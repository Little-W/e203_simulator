// =============================================
// vec_s8_to_fifo: s8向量打包?2位并输出的FIFO模块
// ---------------------------------------------
// 设计思路?
//   1. 双区FIFO设计（Ping-Pong Buffer）：
//      - 每区为方形存储：VLEN×VLEN，存储VLEN个完整向?
//      - 写满一区后自动切换到另一区，实现连续数据流处?
//      - 读写分离：写区域和读区域可以不同，提高吞吐率
//
//   2. 数据流控制：
//      - 输入阶段：连续接收s8向量，检测in_valid下降沿作为批次结束标?
//      - 输出阶段?2位打包输出，?个s8字节组成一?2位数?
//      - 状态机控制：IDLE->REQ->OUTPUT三态切?
//
//   3. 握手协议设计?
//      - 双重握手：先请求-确认获取有效字节数，再数?就绪传输
//      - 避免数据丢失：确保有效字节数与数据同步传?
//
// ---------------------------------------------
// 时序要求?
//   输入时序?
//     - in_valid高电平期间连续输入向量数?
//     - in_valid下降沿标志当前批次结束，触发区域切换
//     - 写指针在每个in_valid上升沿递增
//
//   输出握手时序?
//     1. 模块检测到有数据时拉高oa_fifo_req
//     2. 主机在下一周期或延后几周期拉高req_ack，同时提供vec_valid_num_col
//     3. 模块锁存vec_valid_num_col，开始数据输出流?
//     4. output_valid/output_ready标准握手，每次传?6位数?
//     5. 传输完成后自动切换读区域并重置状?
//
//   关键约束?
//     - req_ack必须与vec_valid_num_col同时有效
//     - output_ptr?递增?VLEN/4-1)，对应VLEN个字节的32位打?
//     - 区域切换仅在批次结束（is_last_vec）或读完成时发生
//
// ---------------------------------------------
// 接口说明?
//   clk, rstn              -- 时钟与复?
//   in_valid               -- 输入数据有效（连续高电平输入，下降沿标志批次结束?
//   in_vec_s8[VLEN]        -- 输入s8向量数组
//   oa_fifo_req             -- 请求输出信号（模?>主机，有数据待输出时为高?
//   req_ack                -- 主机确认信号（主?>模块，确认接收请求）
//   vec_valid_num_col      -- 主机给出的有效字节数（与req_ack同时有效?
//   output_valid           -- FIFO输出数据有效（标准握手信号）
//   output_ready           -- 外部请求弹出数据（标准握手信号）
//   output_row_switch      --输出每行向量最?字节标志
//   output_mask            -- 输出数据有效性掩码（?位）
//   output_data            -- 输出数据（低32位）
//   fifo_full_flag         -- 两块FIFO都被占用时为高（背压信号?
//
// 数据格式?
//   - 输入：每次输入VLEN个signed [7:0]数据
//   - 输出?6?4位mask+32位数据，mask[i]对应data[8*i+7:8*i]字节有效?
//   - mask编码?'b1111=全部有效?'b0111=?字节有效，依此类?
// =============================================

module vec_s8_to_fifo #(
    parameter integer VLEN = 16
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 in_valid,
    input  wire [   VLEN*8-1:0] in_vec_s8,
    output reg                  oa_fifo_req,
    input  wire [(VLEN>>2)-1:0] vec_valid_num_col,
    output wire                 output_valid,
    input  wire                 output_ready,
    output wire                 output_row_switch,
    output reg  [          3:0] output_mask,
    output reg  [         31:0] output_data,
    output reg                  fifo_full_flag
);

  reg [VLEN*8-1:0] fifo_mem0[0:VLEN-1];
  reg [VLEN*8-1:0] fifo_mem1[0:VLEN-1];

  localparam PTR_WIDTH = $clog2(VLEN);
  reg [PTR_WIDTH-1:0] fifo_wptr0, fifo_wptr1;
  reg [PTR_WIDTH-1:0] fifo_count0, fifo_count1;
  reg [PTR_WIDTH-1:0] output_ptr0, output_ptr1;

  reg fifo_sel;
  reg stream_active;
  reg fifo_read_sel;
  reg in_valid_q;
  wire [(VLEN-1):0] stored_valid_col;
  reg [(VLEN>>2)-1:0] vec_valid_num_col_tmp;
  reg fifo_occupy0, fifo_occupy1;

  localparam ROW_CNT_WIDTH = $clog2(VLEN / 4);
  reg [ROW_CNT_WIDTH-1:0] cnt_each_row;

  assign output_valid = stream_active;


  wire is_last_vec = in_valid_q & ~in_valid;

  // check negedge of in_valid
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) in_valid_q <= 1'b0;
    else in_valid_q <= in_valid;
  end

  // check state of fifo
  always @(*) begin
    if (!rst_n) begin
      fifo_occupy0 <= 1'b0;
      fifo_occupy1 <= 1'b0;
    end else begin
      fifo_occupy0 <= (fifo_count0 != 0);
      fifo_occupy1 <= (fifo_count1 != 0);
    end
  end

  // generate occupy state of fifo
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) fifo_full_flag <= 1'b0;
    else fifo_full_flag <= (fifo_occupy0 != 0) && (fifo_occupy1 != 0);
  end

  // choose fifo to write
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) fifo_sel <= 1'b0;
    else if (is_last_vec) begin
      if (!fifo_occupy0) fifo_sel <= 1'b0;
      else if (!fifo_occupy1) fifo_sel <= 1'b1;
      else fifo_sel <= ~fifo_sel;
    end
  end

  // choose fifo to read
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) fifo_read_sel <= 1'b0;
    else begin
      if (fifo_occupy0 && !fifo_occupy1) fifo_read_sel <= 1'b0;
      else if (!fifo_occupy0 && fifo_occupy1) fifo_read_sel <= 1'b1;
      else if (fifo_occupy0 && fifo_occupy1) fifo_read_sel <= fifo_read_sel;
      else fifo_read_sel <= fifo_read_sel;
    end
  end

  // change fifo_wptr0, fifo_wptr1
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fifo_wptr0 <= 'b0;
      fifo_wptr1 <= 'b0;
    end else if (in_valid) begin
      if (fifo_sel == 1'b0) begin
        if (is_last_vec) fifo_wptr0 <= 'b0;
        else fifo_wptr0 <= fifo_wptr0 + 1'b1;
      end else begin
        if (is_last_vec) fifo_wptr1 <= 'b0;
        else fifo_wptr1 <= fifo_wptr1 + 1'b1;
      end
    end
  end
  //fifo_wptr1 <= (fifo_wptr1 == VLEN-1) ? 0 : fifo_wptr1 + 1'b1;
  // change output_ptr0, output_ptr1
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      output_ptr0 <= 'b0;
      output_ptr1 <= 'b0;
    end else begin
      if (stream_active && output_ready && cnt_each_row == (vec_valid_num_col_tmp / 4)) begin
        if (fifo_read_sel == 1'b0) begin
          output_ptr0 <= ((stream_active && output_ready) ? (output_ptr0 + 1'b1) : output_ptr0);
        end else begin
          output_ptr1 <= ((stream_active && output_ready) ? (output_ptr1 + 1'b1) : output_ptr1);
        end
      end
    end
  end

  // generate mask
  assign stored_valid_col = {VLEN{1'b1}} << (VLEN - vec_valid_num_col_tmp - 1);

  // generate request for number of valid column
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      oa_fifo_req <= 1'b0;
      vec_valid_num_col_tmp <= 'b0;
    end else begin
      if ((fifo_occupy0 || fifo_occupy1) && !stream_active) begin
        oa_fifo_req <= 1'b1;
        vec_valid_num_col_tmp <= vec_valid_num_col;
      end else begin
        oa_fifo_req <= 1'b0;
      end
    end
  end

  // generate output_row_switch
  assign output_row_switch = (cnt_each_row == (vec_valid_num_col_tmp/4)) && stream_active && output_ready;

  // generage fifo_count0, fifo_count1
  always @(*) begin
    if (!rst_n) begin
      fifo_count0 = 'b0;
      fifo_count1 = 'b0;
    end else begin
      if (fifo_wptr0 >= output_ptr0) fifo_count0 = fifo_wptr0 - output_ptr0;
      else fifo_count0 = VLEN - output_ptr0 + fifo_wptr0;
      if (fifo_wptr1 >= output_ptr1) fifo_count1 = fifo_wptr1 - output_ptr1;
      else fifo_count1 = VLEN - output_ptr1 + fifo_wptr1;
    end
  end

  // generate stream_active
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) stream_active <= 1'b0;
    else begin
      if (oa_fifo_req && !stream_active) begin
        if ((fifo_read_sel == 1'b0 && fifo_count0 > 0) || 
                    (fifo_read_sel == 1'b1 && fifo_count1 > 0)) begin
          stream_active <= 1'b1;
        end
      end
            else if (stream_active && output_ready && cnt_each_row == (vec_valid_num_col_tmp/4)) begin
        if ((fifo_read_sel == 1'b0 && fifo_count0 <= 1) || 
                    (fifo_read_sel == 1'b1 && fifo_count1 <= 1)) begin
          stream_active <= 1'b0;
        end
      end
    end
  end

  // generate cnt_each_row
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) cnt_each_row <= 'b0;
    else if (stream_active && output_ready) begin
      if (cnt_each_row == (vec_valid_num_col_tmp / 4)) cnt_each_row <= 'b0;
      else cnt_each_row <= cnt_each_row + 1'b1;
    end
  end

  // storage input data
  always @(posedge clk) begin
    if (in_valid && fifo_sel == 1'b0) begin
      fifo_mem0[fifo_wptr0] <= in_vec_s8;
    end
    if (in_valid && fifo_sel == 1'b1) begin
      fifo_mem1[fifo_wptr1] <= in_vec_s8;
    end
  end

  // generate output_data
  always @(*) begin
    output_data = 32'b0;
    output_mask = 4'b0;
    if (stream_active) begin
      if (fifo_read_sel == 1'b0) begin
        output_data = fifo_mem0[output_ptr0][(cnt_each_row)*32+:32];
        output_mask = stored_valid_col[(3-cnt_each_row)*4+:4];
      end else begin
        output_data = fifo_mem1[output_ptr1][(cnt_each_row)*32+:32];
        output_mask = stored_valid_col[(3-cnt_each_row)*4+:4];
      end
    end
  end

endmodule









