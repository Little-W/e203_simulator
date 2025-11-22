//`include "define.svh"
`include "e203_defines.v"
`include "icb_types.svh"

module bias_loader #(
    parameter int unsigned SIZE       = 16,  // VLEN
    parameter int          VLEN       = 16,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned REG_WIDTH  = 32
) (
    input wire clk,
    input wire rst_n,

    // 配置
    input wire                 init_cfg,
    input wire [REG_WIDTH-1:0] bias_base,  // 偏置基地址（按列 tile 递增）
    input wire [REG_WIDTH-1:0] k,          // 预留
    input wire [REG_WIDTH-1:0] m,          // 总列数（决定尾块）

    // ICB（三通道，读为主）
    output icb_ext_cmd_m_t icb_cmd_m,
    output icb_ext_wr_m_t  icb_wr_m,
    input  icb_ext_cmd_s_t icb_cmd_s,
    input  icb_ext_wr_s_t  icb_wr_s,
    input  icb_ext_rsp_s_t icb_rsp_s,
    output icb_ext_rsp_m_t icb_rsp_m,

    // 计算时序标志
    input  wire                   partial_sum_calc_over, // 第一次部分和结束后会为1（电平/脉冲均可）
    input wire tile_calc_over,  // 本 OA tile 结束

    // 访存握手
    output reg  load_bias_req,
    input  wire load_bias_granted,

    // 偏置是否可用（保持到 tile_calc_over）
    output reg bias_valid,

    // 输出偏置向量（第一次部分和输出偏置，其余时间输出0）
    output wire [DATA_WIDTH-1:0] data_out[SIZE]
);

  // ---------------------------
  // 常量 / 类型
  // ---------------------------
  localparam int BYTES_PER_WORD = `E203_XLEN / 8;  // 一般为4字节
  typedef logic [`ICB_LEN_W-1:0] icb_len_t;

  // ---------------------------
  // 配置寄存
  // ---------------------------
  reg   [REG_WIDTH-1:0] cfg_bias_base;
  reg   [REG_WIDTH-1:0] cfg_m;
  reg   [REG_WIDTH-1:0] cfg_k;
  reg                   cfg_need_bias;
  logic [         31:0] tile_col;
  logic [         31:0] tile_row;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg_bias_base <= '0;
      cfg_m         <= '0;
      cfg_k         <= '0;
      cfg_need_bias <= 1'b0;
    end else if (init_cfg) begin
      cfg_bias_base <= bias_base;
      cfg_m         <= m;
      cfg_k         <= k;
      cfg_need_bias <= (bias_base != '0);  // 基地址为0认为不需要偏置
    end
  end

  // ---------------------------
  // 列 tile 计算（尾块）
  // ---------------------------
  function automatic [31:0] f_cols_need(input [31:0] total_cols, input [31:0] vlen, input [31:0] t);
    reg [31:0] remain;
    begin
      remain      = (total_cols > (t * vlen)) ? (total_cols - t * vlen) : 32'd0;
      f_cols_need = (remain >= vlen) ? vlen : remain;
    end
  endfunction

  reg  [31:0] next_tile_idx;     // 将要读取的列tile索引
  wire [31:0] cols_need_next = f_cols_need(cfg_m, SIZE, next_tile_idx);
  wire [31:0] byte_off_next  = next_tile_idx * SIZE * BYTES_PER_WORD;

  // ---------------------------
  // 第一次部分和结束标志（电平）
  // 说明：不做边沿检测；一旦为1就表示“本 tile 以后都不该再输出偏置”
  //      只在 init_cfg 或 tile_calc_over 时清零。
  // ---------------------------
  reg first_ps_done;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      first_ps_done <= 1'b0;
    end else if (init_cfg || tile_calc_over) begin
      first_ps_done <= 1'b0;  // 新 tile 开始前清零
    end else if (!first_ps_done && partial_sum_calc_over) begin
      first_ps_done <= 1'b1;  // 只允许第一次把它置 1
    end
  end


  // ---------------------------
  // 预取意图（tile结束后为下一 tile 预取）
  // ---------------------------
  // reg prefetch_pending;
  // always_ff @(posedge clk or negedge rst_n) begin
  //   if (!rst_n) begin
  //     prefetch_pending <= 1'b0;
  //   end else begin
  //     if (init_cfg)         prefetch_pending <= 1'b1;   // 第0块也要预取
  //     else if (tile_calc_over) prefetch_pending <= 1'b1;   // 当前tile结束，准备下一块
  //     else if (load_bias_req && load_bias_granted) prefetch_pending <= 1'b0; // 成交后清除
  //   end
  // end

  // ---------------------------
  // ICB 命令通道寄存
  // ---------------------------
  reg                       icb_cmd_valid_q;
  reg                       icb_cmd_read_q;
  reg       [REG_WIDTH-1:0] icb_cmd_addr_q;
  icb_len_t                 icb_cmd_len_q;

  assign icb_cmd_m.valid  = icb_cmd_valid_q;
  assign icb_cmd_m.read   = icb_cmd_read_q;
  assign icb_cmd_m.addr   = icb_cmd_addr_q;
  assign icb_cmd_m.len    = icb_cmd_len_q;

  assign icb_wr_m.w_valid = 1'b0;
  assign icb_wr_m.wdata   = '0;
  assign icb_wr_m.wmask   = '0;

  assign icb_rsp_m        = '{rsp_ready: 1'b1};

  // ---------------------------
  // 偏置缓冲
  // ---------------------------
  reg [DATA_WIDTH-1:0] bias_buffer[SIZE];
  logic [31:0] num_row_tiles;
  logic [31:0] num_col_tiles;

  always_comb begin
    // safe ceil_div: (n + VLEN -1) / VLEN
    num_row_tiles = (cfg_k == 0) ? 0 : ((cfg_k + VLEN - 1) / VLEN);
    num_col_tiles = (cfg_m == 0) ? 0 : ((cfg_m + VLEN - 1) / VLEN);
  end
  // ---------------------------
  // FSM
  // ---------------------------
  typedef enum logic [1:0] {
    IDLE = 2'd0,
    LOAD = 2'd1,
    OUT  = 2'd2
  } fsm_e;
  fsm_e       state;

  reg   [5:0] rd_beats_cnt;
  reg   [5:0] beats_expect;  // = cols_need_next


  logic       all_tiles_done;
  // 输出使用逻辑：仅“第一次部分和结束前”使用偏置
  wire        use_bias_now = (bias_valid && !first_ps_done);

  // 组合输出（如需打一拍可改成寄存）

  genvar gi;
  generate
    for (gi = 0; gi < SIZE; gi = gi + 1) begin : G_OUT
      // Drive explicit width zero to avoid signed/unsigned warnings in DC
      assign data_out[gi] = use_bias_now ? bias_buffer[gi] : {DATA_WIDTH{1'b0}};
    end
  endgenerate

  // ---------------------------
  // 主时序
  // ---------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state           <= IDLE;
      load_bias_req   <= 1'b0;
      bias_valid      <= 1'b0;

      icb_cmd_valid_q <= 1'b0;
      icb_cmd_read_q  <= 1'b0;
      icb_cmd_addr_q  <= '0;
      icb_cmd_len_q   <= icb_len_t'(0);
      all_tiles_done  <= 1'b0;
      rd_beats_cnt    <= 6'd0;
      beats_expect    <= 6'd0;
      next_tile_idx   <= 32'd0;
      tile_col        <= 32'd0;
      tile_row        <= 32'd0;

      for (int unsigned i = 0; i < SIZE; i++) begin
        bias_buffer[i] <= {DATA_WIDTH{1'b0}};
      end

    end else begin
      // 缺省拉低命令
      icb_cmd_valid_q <= 1'b0;
      icb_cmd_read_q  <= 1'b0;

      // init 时做一次同步清零
      if (init_cfg) begin
        state          <= IDLE;
        load_bias_req  <= 1'b0;
        bias_valid     <= 1'b0;
        rd_beats_cnt   <= 6'd0;
        beats_expect   <= 6'd0;
        next_tile_idx  <= 32'd0;
        all_tiles_done <= 1'b0;
        tile_col       <= 32'd0;
        tile_row       <= 32'd0;

      end else begin
        case (state)
          // -------------------------
          IDLE: begin
            // 只在 tile 完成后清 bias_valid（满足你的需求）
            if (tile_calc_over) bias_valid <= 1'b0;
            if (all_tiles_done) begin
              load_bias_req <= 1'b0;
              // remain idle
            end else begin
              // 拉起预取
              if (cfg_need_bias && !bias_valid && (cols_need_next != 0)) begin
                load_bias_req <= 1'b1;
                if (load_bias_granted) begin
                  load_bias_req   <= 1'b0;
                  rd_beats_cnt    <= 6'd0;
                  beats_expect    <= cols_need_next[5:0];

                  // 发 ICB 读命令（len = need-1）
                  icb_cmd_valid_q <= 1'b1;
                  icb_cmd_read_q  <= 1'b1;
                  icb_cmd_addr_q  <= cfg_bias_base + byte_off_next;
                  icb_cmd_len_q   <= icb_len_t'((cols_need_next > 0) ? (cols_need_next - 1) : 0);

                  state           <= LOAD;
                end
              end else begin
                load_bias_req <= 1'b0;
              end

              // 若外部已放入有效（理论上不会发生），也可以进入 OUT
              if (bias_valid) state <= OUT;
            end
          end

          // -------------------------
          LOAD: begin
            // 命令阶段：若尚未被 ready 接受，继续保持 valid

            if (!icb_cmd_s.ready) begin
              icb_cmd_valid_q <= 1'b1;
              icb_cmd_read_q  <= 1'b1;
              icb_cmd_addr_q  <= cfg_bias_base + byte_off_next;
              icb_cmd_len_q   <= icb_len_t'((beats_expect > 0) ? (beats_expect - 1) : 0);
            end

            // 接收响应拍
            if (icb_rsp_s.rsp_valid) begin
              if (rd_beats_cnt < SIZE[5:0]) begin
                bias_buffer[rd_beats_cnt] <= icb_rsp_s.rsp_rdata;
              end
              rd_beats_cnt <= rd_beats_cnt + 1;

              if ((rd_beats_cnt + 1) == beats_expect) begin
                // 尾部补0
                for (int unsigned f = 0; f < SIZE; f++) begin
                  if (f >= beats_expect) begin
                    bias_buffer[f] <= {DATA_WIDTH{1'b0}};
                  end
                end
                // 读完即“bias_valid=1”，保持到 tile_calc_over 才清 0
                bias_valid    <= 1'b1;

                // 下一个 tile 的偏移
                next_tile_idx <= next_tile_idx + 1;


                // 进入 OUT：由 use_bias_now 决定是否输出偏置
                state         <= OUT;
              end
            end
          end

          // -------------------------
          OUT: begin
            // 只在 tile 结束时清 bias_valid（符合你的要求）
            if (tile_calc_over) begin
              bias_valid <= 1'b0;
              if ((tile_col + 1) >= num_col_tiles) begin
                // 当前列已经是最后一列 -> 列回 0，并推进行
                tile_col <= 32'd0;
                next_tile_idx <= 0;
                load_bias_req <= 1'b1;
                if ((tile_row + 1) >= num_row_tiles) begin
                  // 行也到末尾 -> 所有 tile 完成
                  tile_row       <= 32'd0;
                  all_tiles_done <= 1'b1;
                  //quant_params_valid <= 1'b0;
                end else tile_row <= tile_row + 1;
              end else
                // 还没到最后列 -> 仅推进列
                tile_col <= tile_col + 1;
            end
            //if (load_bias_granted) load_bias_req <= 1'b0;
            // OUT 态也允许在 tile_over 后拉起下一块的预取
            if (cfg_need_bias && tile_calc_over && (cols_need_next != 0)) begin
              load_bias_req <= 1'b1;
            end

            if (load_bias_granted && load_bias_req) begin
              load_bias_req   <= 1'b0;
              rd_beats_cnt    <= 6'd0;
              beats_expect    <= cols_need_next[5:0];

              icb_cmd_valid_q <= 1'b1;
              icb_cmd_read_q  <= 1'b1;
              icb_cmd_addr_q  <= cfg_bias_base + byte_off_next;
              icb_cmd_len_q   <= icb_len_t'((cols_need_next > 0) ? (cols_need_next - 1) : 0);

              state           <= LOAD;
            end

            if ((tile_col + 1 == num_col_tiles) && (tile_row + 1 == num_row_tiles) && tile_calc_over) begin
              state <= IDLE;
            end
          end

          default: state <= IDLE;
        endcase
        if(!cfg_need_bias) begin
          bias_valid <= 1'b1;
        end
      end
    end
  end

endmodule
