//`include "define.svh"
`include "e203_defines.v"
`include "icb_types.svh"

module vec_requant #(
    parameter int VLEN      = 16,
    parameter int REG_WIDTH = 32
) (
    input logic clk,
    input logic rst_n,

    // 配置
    input logic               init_cfg,
    input logic               cfg_per_channel,
    input logic signed [31:0] activation_min_in,
    input logic signed [31:0] activation_max_in,
    input logic signed [31:0] dst_offset_in,
    // per-tensor 常量；per-channel 下这两个做为“基地址”使用
    input logic signed [31:0] multiplier_in,
    input logic signed [31:0] shift_in,
    input logic        [31:0] k,                  // 行数
    input logic        [31:0] m,                  // 列数

    // 量化参数装载握手（外部可用；TB里通常 grant=req）
    output logic load_quant_req,
    input  logic load_quant_granted,
    output logic quant_params_valid,

    // ICB
    output    icb_ext_cmd_m_t icb_cmd_m,
    output    icb_ext_wr_m_t  icb_wr_m,
    input var icb_ext_cmd_s_t icb_cmd_s,
    input var icb_ext_wr_s_t  icb_wr_s,
    input var icb_ext_rsp_s_t icb_rsp_s,
    output    icb_ext_rsp_m_t icb_rsp_m,

    // 数据口
    input  logic               in_valid,
    input  logic signed [31:0] in_vec_s32[VLEN],
    output logic               out_valid,
    output logic signed [ 7:0] out_vec_s8[VLEN]
);

  // ----------------------------
  // 常量与类型
  // ----------------------------
  localparam int BYTES_PER_WORD = `E203_XLEN / 8;  // 32位=4
  typedef logic [`ICB_LEN_W-1:0] icb_len_t;

  // ----------------------------
  // 状态机与游标
  // ----------------------------
  typedef enum logic [1:0] {
    IDLE,
    LOAD,
    COMPUTE,
    TILE_COMPLETE
  } state_e;
  state_e state, state_n;

  // 只保留 4 个状态名，LOAD 内部用 phase 区分 mul/shift
  typedef enum logic [0:0] {
    PH_MUL   = 1'b0,
    PH_SHIFT = 1'b1
  } phase_e;
  phase_e          load_phase;  // 当前子阶段（先 mul 后 shift）

  logic     [31:0] tile_col;  // 当前列 tile 号
  logic     [ 4:0] row_in_tile_cnt;  // 0..15：本 tile 已完成的行数
  logic     [31:0] lane_need_cur;  // 本 tile 需要的列数（尾块可能 < VLEN）
  logic     [31:0] tile_row;  // 当前行 tile 号
  logic     [31:0] rows_need_cur;  // 当前行 tile 需要的行数（最后一块为余数）
  logic     [31:0] lane_need_q;  // 锁存，用于计算/屏蔽无效 lane
  icb_len_t        burst_len_cur;  // = lane_need_cur - 1

  // per-channel：mul/shift 两次突发的采样计数
  logic     [ 5:0] rd_beats_cnt;
  logic     [ 5:0] beats_expect;
  logic            cmd_busy;

  // track number of tiles & finished flag
  logic     [31:0] num_row_tiles;
  logic     [31:0] num_col_tiles;
  logic            all_tiles_done;

  // ----------------------------
  // 配置寄存
  // ----------------------------
  logic signed [31:0] activation_min_r, activation_max_r, dst_offset_r;
  logic signed [31:0] pt_multiplier_r, pt_shift_r;  // per-tensor 常量
  logic [31:0] k_r, m_r;  // 锁存的尺寸
  logic [31:0] mul_base_r, sh_base_r;  // per-channel 基地址


  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      activation_min_r <= '0;
      activation_max_r <= '0;
      dst_offset_r     <= '0;
      pt_multiplier_r  <= '0;
      pt_shift_r       <= '0;
      k_r              <= '0;
      m_r              <= '0;
      mul_base_r       <= '0;
      sh_base_r        <= '0;
    end else if (init_cfg) begin
      activation_min_r <= activation_min_in;
      activation_max_r <= activation_max_in;
      dst_offset_r     <= dst_offset_in;
      pt_multiplier_r  <= multiplier_in;
      pt_shift_r       <= shift_in;
      k_r              <= k;
      m_r              <= m;
      // per-channel 基地址（接口复用 multiplier_in/shift_in）
      mul_base_r       <= multiplier_in;
      sh_base_r        <= shift_in;
    end
  end

  // compute number of tiles (rows/cols)
  always_comb begin
    // safe ceil_div: (n + VLEN -1) / VLEN
    num_row_tiles = (k_r == 0) ? 0 : ((k_r + VLEN - 1) / VLEN);
    num_col_tiles = (m_r == 0) ? 0 : ((m_r + VLEN - 1) / VLEN);
  end

  // ----------------------------
  // tile 列需要多少 lane（尾块）
  // ----------------------------
  function automatic [31:0] f_lane_need(input [31:0] cols, input [31:0] vlen, input [31:0] tcol);
    reg [31:0] remain;
    begin
      remain = (cols > (tcol * vlen)) ? (cols - tcol * vlen) : 32'd0;
      f_lane_need = (remain >= vlen) ? vlen : remain;
    end
  endfunction

  function automatic [31:0] f_rows_need(input [31:0] rows, input [31:0] vlen, input [31:0] trow);
    reg [31:0] remain;
    begin
      remain = (rows > (trow * vlen)) ? (rows - trow * vlen) : 32'd0;
      f_rows_need = (remain >= vlen) ? vlen : remain;
    end
  endfunction

  // 每次进入 LOAD 前计算 lane_need\row_need
  always_comb begin
    lane_need_cur = f_lane_need(m_r, VLEN, tile_col);
  end

  always_comb begin
    rows_need_cur = f_rows_need(k_r, VLEN, tile_row);
  end

  // 参数就绪拍锁存（供计算屏蔽尾块）
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lane_need_q <= '0;
    end else begin
      // per-tensor 模式下：所有 lane 都有效
      if (!cfg_per_channel) begin
        lane_need_q <= f_lane_need(m, VLEN, 32'd0);  // 或 32'(VLEN) ，lane_need_q 是 32 位
      end  // per-channel 模式下：在 quant_params_valid 时锁存当前需要的 lanes
      else if (quant_params_valid) begin
        lane_need_q <= lane_need_cur;
      end
    end
  end


  // ICB len = 需要拍数-1（0 表示 1 拍）
  always_comb begin
    burst_len_cur = icb_len_t'((lane_need_cur > 0) ? (lane_need_cur - 1) : 0);
  end

  // ----------------------------
  // ICB 命令/响应
  // ----------------------------
  icb_ext_cmd_m_t icb_cmd_m_reg, icb_cmd_m_wire;
  icb_ext_rsp_m_t icb_rsp_m_wire;

  wire cmd_hskd = icb_cmd_m_reg.valid && icb_cmd_s.ready;
  wire rsp_hskd = icb_rsp_s.rsp_valid && icb_rsp_m.rsp_ready;

  // master 侧：响应 ready 常 1；不使用写通道
  assign icb_wr_m  = '{default: '0};
  assign icb_rsp_m = '{rsp_ready: 1'b1};
  assign icb_cmd_m = icb_cmd_m_wire;
  always_comb icb_cmd_m_wire = icb_cmd_m_reg;


  // ----------------------------
  // per-channel 参数缓冲
  // ----------------------------
  logic signed [31:0] ch_multiplier_r[VLEN];
  logic signed [31:0] ch_shift_r     [VLEN];


  // ----------------------------
  // 主状态机（只保留 4 个状态名）
  // ----------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // reset all sequential state
      state              <= IDLE;
      load_phase         <= PH_MUL;
      quant_params_valid <= 1'b0;
      row_in_tile_cnt    <= 5'd0;
      rd_beats_cnt       <= 6'd0;
      beats_expect       <= 6'd0;
      cmd_busy           <= 1'b0;
      load_quant_req     <= 1'b0;
      tile_col           <= 32'd0;
      tile_row           <= 32'd0;
      icb_cmd_m_reg      <= '{default: '0};
      all_tiles_done     <= 1'b0;
    end else begin
      // default per-cycle de-asserts (will be overridden in branches)
      icb_cmd_m_reg.valid <= 1'b0;
      icb_cmd_m_reg.read  <= 1'b0;
      //load_quant_req      <= 1'b0;  
      // note: do NOT clear quant_params_valid/lane_need_q here (they are cleared when tile completes)

      // handle init_cfg (single-cycle reset of per-tile counters)
      if (init_cfg) begin
        state              <= IDLE;
        quant_params_valid <= (cfg_per_channel ? 1'b0 : 1'b1);
        row_in_tile_cnt    <= 5'd0;
        rd_beats_cnt       <= 6'd0;
        cmd_busy           <= 1'b0;
        tile_col           <= 32'd0;
        tile_row           <= 32'd0;
        all_tiles_done     <= 1'b0;  // clear done on re-config
      end else begin

        case (state)
          // ----------------------
          IDLE: begin
            rd_beats_cnt    <= 6'd0;
            cmd_busy        <= 1'b0;
            row_in_tile_cnt <= 5'd0;

            // 如果所有 tile 都做完了 -> stay IDLE 等待 init_cfg 清除
            if (all_tiles_done) begin
              load_quant_req <= 1'b0;
              // remain idle
            end else begin
              // 保持请求直到 grant（避免单拍丢失）
              if (cfg_per_channel && !quant_params_valid && (lane_need_cur != 0)) begin
                load_quant_req <= 1'b1;
                if (load_quant_granted) begin
                  load_quant_req <= 1'b0;
                  load_phase     <= PH_MUL;
                  state          <= LOAD;
                  // do not clear load_quant_req here; default loop will clear next cycle if needed
                end
              end

              // per-tensor 或 已有参数: 直接响应输入
              if (!cfg_per_channel || quant_params_valid) begin
                if (in_valid) begin
                  // start compute for this tile/row-stream
                  state <= COMPUTE;
                  // ensure counter starts at 0 when entering a fresh compute
                  // row_in_tile_cnt will be incremented on out_valid
                  // do not clear quant_params_valid here (should remain valid during compute)
                end
              end
            end
          end

          // ----------------------
          LOAD: begin
            if (load_quant_granted) load_quant_req <= 1'b0;
            row_in_tile_cnt <= 5'd0;
            // 1) 若当前没有在途命令，则按 phase 发一条读命令（valid/ready handshake）
            if (!cmd_busy) begin
              icb_cmd_m_reg.valid <= 1'b1;
              icb_cmd_m_reg.read <= 1'b1;
              icb_cmd_m_reg.addr  <= (load_phase==PH_MUL)
                                    ? (mul_base_r + tile_col*VLEN*BYTES_PER_WORD)
                                    : (sh_base_r  + tile_col*VLEN*BYTES_PER_WORD);
              icb_cmd_m_reg.len <= burst_len_cur;  // len = lane_need_cur - 1

              if (cmd_hskd) begin
                // 命令已被对端接受，本次突发开始
                cmd_busy     <= 1'b1;
                icb_cmd_m_reg.valid <= 1'b0;  // 下拍取消 valid
                rd_beats_cnt <= 6'd0;
                beats_expect <= lane_need_cur[5:0];  // 需要收的拍数
              end
            end

            // 2) 接收响应拍：mul/shift 缓冲写入
            if (icb_rsp_s.rsp_valid && icb_rsp_m.rsp_ready && cmd_busy) begin
              // 防护断言（仿真）
`ifndef SYNTHESIS
              if (beats_expect > VLEN) begin
                $display("[%0t] ERROR: beats_expect (%0d) > VLEN", $time, beats_expect);
                $fatal;
              end
              if (rd_beats_cnt >= VLEN) begin
                $display("[%0t] ERROR: rd_beats_cnt (%0d) >= VLEN", $time, rd_beats_cnt);
                $fatal;
              end
`endif

              if (load_phase == PH_MUL) ch_multiplier_r[rd_beats_cnt] <= icb_rsp_s.rsp_rdata;
              else ch_shift_r[rd_beats_cnt] <= icb_rsp_s.rsp_rdata;

              rd_beats_cnt <= rd_beats_cnt + 1;

              // 3) 本次突发收满：决定是切 phase 还是完成 LOAD
              if ((rd_beats_cnt + 1) == beats_expect) begin
                cmd_busy <= 1'b0;  // 本突发结束
                if (load_phase == PH_MUL) begin
                  // mul 收满 -> 切到 shift，下一拍会去发 shift 的命令
                  load_phase <= PH_SHIFT;
                end else begin
                  // shift 也收满，参数就绪：同时锁存 lane_need，并根据当拍 in_valid 决定是否直接进 COMPUTE
                  quant_params_valid <= 1'b1;
                  //lane_need_q        <= lane_need_cur;   // <-- 把 lane_need 在参数就绪时锁存

                  if (in_valid) begin
                    state <= COMPUTE; // 允许在同一时钟周期观察到 in_valid 并直接进入 COMPUTE
                  end else begin
                    state <= IDLE;
                  end
                end
              end
            end
          end

          // ----------------------
          COMPUTE: begin
            // 现在 COMPUTE 负责一整块 tile 的所有行：
            // 在 out_valid 的上升周期计数；当计数达到 rows_need_cur 时转到 TILE_COMPLETE
            load_phase <= PH_MUL;

            if (out_valid) begin
              if (row_in_tile_cnt == rows_need_cur[4:0] - 1) begin
                // 本 tile 行数已全部处理完毕 -> 执行收尾
                if (cfg_per_channel) begin
                  load_quant_req <= 1'b1;
                  quant_params_valid <= 1'b0;
                end
                state <= TILE_COMPLETE;
                row_in_tile_cnt <= 5'd0;
              end else begin
                // 继续在 COMPUTE 等下一行的输入
                row_in_tile_cnt <= row_in_tile_cnt + 1;
                // 继续在 COMPUTE 等下一行的输入
                state <= COMPUTE;
              end
            end
            if ((tile_col + 1 == num_col_tiles) && (tile_row + 1 == num_row_tiles) && row_in_tile_cnt == rows_need_cur[4:0]-1)
              all_tiles_done <= 1'b1;
            // 否则保持在 COMPUTE，等待 out_valid（或者下一次 in_valid 进入流水线）
          end

          // ----------------------
          TILE_COMPLETE: begin

            // 到这里意味着本 tile 的所有行已经计算完（由 COMPUTE 决定）
            // 做收尾工作：清参数就绪、推进 tile 坐标。
            row_in_tile_cnt <= row_in_tile_cnt + 1;
            //quant_params_valid <= 1'b0;
            all_tiles_done  <= 1'b0;
            // 推进 tile_row/tile_col，并根据是否已完成全部 tile 设定 all_tiles_done
            if ((tile_col + 1) >= num_col_tiles) begin
              // 当前列已经是最后一列 -> 列回 0，并推进行
              tile_col <= 32'd0;
              if ((tile_row + 1) >= num_row_tiles) begin
                // 行也到末尾 -> 所有 tile 完成
                tile_row <= 32'd0;

                //quant_params_valid <= 1'b0;
              end else begin
                tile_row <= tile_row + 1;
              end
            end else begin
              // 还没到最后列 -> 仅推进列
              tile_col <= tile_col + 1;
            end

            if (all_tiles_done && !cfg_per_channel) begin
              quant_params_valid <= 1'b0;
            end


            if ((tile_col + 1 == num_col_tiles) && (tile_row + 1 == num_row_tiles)) begin
              state <= IDLE;
            end else if (!cfg_per_channel) state <= COMPUTE;
            else state <= LOAD;

            // 仿真断言：超出范围直接暴露
`ifndef SYNTHESIS
            if (row_in_tile_cnt > VLEN) begin
              $display("[%0t] ERROR: row_in_tile_cnt (%0d) > VLEN", $time, row_in_tile_cnt);
              $fatal;
            end
`endif
          end

          // ----------------------
          default: begin
            // 保底：防止卡死
            state <= IDLE;
          end

        endcase
      end  // !init_cfg
    end  // !rst_n
  end


  // ----------------------------
  // 数据通路（1 拍管线：in_valid -> out_valid）
  // ----------------------------
  logic out_valid_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid_q <= 1'b0;
    end else begin
      out_valid_q <= in_valid && ((!cfg_per_channel) || quant_params_valid);
    end
  end

  assign out_valid = (!cfg_per_channel) ? out_valid_q : (out_valid_q && quant_params_valid);

  // 用 CMSIS-NN 风格重写重量化函数
  function automatic signed [31:0] cmsis_nn_requantize(input signed [31:0] acc,
                                                       input signed [31:0] multiplier,
                                                       input signed [31:0] shift_s);
    reg signed [63:0] prod;
    reg signed [63:0] rounded;
    reg [5:0] shift_amt;
    reg signed [31:0] neg_shift;
    begin
      prod = acc * multiplier;
      if (shift_s > 0) begin
        shift_amt = shift_s[5:0];
        rounded = prod + (64'sd1 <<< (shift_amt - 1));
        cmsis_nn_requantize = rounded >>> shift_amt;
      end else if (shift_s < 0) begin
        neg_shift = -shift_s;
        shift_amt = neg_shift[5:0];
        prod = prod <<< shift_amt;
        cmsis_nn_requantize = prod[31:0];
      end else begin
        cmsis_nn_requantize = prod[31:0];
      end
    end
  endfunction

  // 做一行（16 lane），尾块屏蔽
  genvar j;
  for (j = 0; j < VLEN; j++) begin : LANE
    // 局部变量声明放最前
    logic lane_en;
    logic signed [31:0] cur_m, cur_s;
    logic signed [31:0] rq_tmp;

    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        out_vec_s8[j] <= '0;
      end else if (in_valid) begin
        // 选择 per-channel 缓冲或 per-tensor 常量
        cur_m     = cfg_per_channel ? ch_multiplier_r[j] : pt_multiplier_r;
        cur_s     = cfg_per_channel ? ch_shift_r[j] : pt_shift_r;

        rq_tmp    = cmsis_nn_requantize(in_vec_s32[j], cur_m, cur_s);
        rq_tmp    = rq_tmp + dst_offset_r;

        if (rq_tmp < activation_min_r) rq_tmp = activation_min_r;
        if (rq_tmp > activation_max_r) rq_tmp = activation_max_r;

        lane_en = (j < lane_need_q);

        if (lane_en) begin
          if (rq_tmp > 32'sd127) out_vec_s8[j] <= 8'sd127;
          else if (rq_tmp < -32'sd128) out_vec_s8[j] <= -32'sd128;
          else out_vec_s8[j] <= rq_tmp[7:0];
        end else begin
          out_vec_s8[j] <= 8'sd0;
        end
      end
    end
  end

endmodule
