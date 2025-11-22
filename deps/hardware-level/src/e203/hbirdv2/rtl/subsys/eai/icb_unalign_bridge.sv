// ICB Unalign Bridge Module
// 功能：将非四字节对齐的ICB访问转换为对齐访问，支持burst和outstanding管理

module icb_unalign_bridge #(
  parameter WIDTH       = 32,           // 数据位宽
  parameter ADDR_W      = 32,           // 地址位宽  
  parameter OUTS_DEPTH  = 16,           // 上游outstanding深度
  parameter ICB_LEN_W   = 3,            // burst长度位宽
  parameter DW          = WIDTH/8       // 数据字节数
)(
  input  wire                   clk,
  input  wire                   rst_n,

  // 上游ICB从接口
  //cmd请求通道
  input  wire                   sa_icb_cmd_valid,
  output wire                   sa_icb_cmd_ready,
  input  wire [ADDR_W-1:0]      sa_icb_cmd_addr,
  input  wire                   sa_icb_cmd_read,
  input  wire [ICB_LEN_W-1:0]   sa_icb_cmd_len,
  //cmd写数据通道
  input  wire [WIDTH-1:0]       sa_icb_cmd_wdata,
  input  wire [DW-1:0]          sa_icb_cmd_wmask, 
  input  wire                   sa_icb_w_valid,
  output wire                   sa_icb_w_ready,
 //rsp读数据写响应通道
  output wire                   sa_icb_rsp_valid,
  input  wire                   sa_icb_rsp_ready,
  output wire [WIDTH-1:0]       sa_icb_rsp_rdata,
  output wire                   sa_icb_rsp_err,

  // 下游ICB主接口

   //cmd通道
  output wire                   m_icb_cmd_valid,
  input  wire                   m_icb_cmd_ready,
  output wire [ADDR_W-1:0]      m_icb_cmd_addr,
  output wire                   m_icb_cmd_read,
  output wire [WIDTH-1:0]       m_icb_cmd_wdata,
  output wire [DW-1:0]          m_icb_cmd_wmask,

  //rsp读数据写响应通道
  input  wire                   m_icb_rsp_valid,
  output wire                   m_icb_rsp_ready,
  input  wire [WIDTH-1:0]       m_icb_rsp_rdata,
  input  wire                   m_icb_rsp_err
);

  // ========================================
  // 参数和常量定义
  // ========================================
  localparam FIFO_DEPTH = 2**($clog2(OUTS_DEPTH));
  localparam PTR_W = $clog2(FIFO_DEPTH);
  
  // ========================================
  // 信号声明
  // ========================================
  
  // Outstanding FIFO相关信号
  logic                        cmd_fifo_wen;
  logic                        cmd_fifo_ren;
  logic                        cmd_fifo_full;
  logic                        cmd_fifo_empty;
  logic [ADDR_W+ICB_LEN_W:0]   cmd_fifo_wdata;
  logic [ADDR_W+ICB_LEN_W:0]   cmd_fifo_rdata;
  logic [PTR_W:0]              cmd_fifo_wptr;
  logic [PTR_W:0]              cmd_fifo_rptr;
  logic [ADDR_W+ICB_LEN_W:0]   cmd_fifo_mem[FIFO_DEPTH];
  
  // 解析后的请求信息 - 部分信号来自寄存器
  logic [ICB_LEN_W:0]          burst_cycle_1start;
  logic [1:0]                  cur_offset;
  logic [ADDR_W-1:0]           cur_base_addr;
  logic                        cur_cross_boundary;
  logic [ICB_LEN_W:0]          cur_burst_cnt;
  logic [ICB_LEN_W:0]          burst_cnt_nxt;
  
  // 从FIFO读取的临时信号
  logic                        fifo_is_read;
  logic [ADDR_W-1:0]           fifo_addr;
  logic [ICB_LEN_W-1:0]        fifo_len;
  
  // 当前请求信息寄存器
  logic                        cur_is_read;
  logic [ADDR_W-1:0]           cur_addr;
  logic [ICB_LEN_W-1:0]        cur_len_0start;
  
  // 响应通道独立的计数器
  logic [ICB_LEN_W:0]          rsp_burst_cnt;
  logic [ICB_LEN_W:0]          rsp_burst_cnt_nxt;
  
  // 写数据缓存
  logic [WIDTH-1:0]            wdata_buf;
  logic [DW-1:0]               wmask_buf;
  logic                        wdata_buf_valid;
  logic [WIDTH-1:0]            wdata_aligned;
  logic [DW-1:0]               wmask_aligned;
  
  // 读数据缓存
  logic [WIDTH-1:0]            rdata_buf;
  logic                        rdata_buf_valid;
  logic [WIDTH-1:0]            rdata_aligned;
  

  
  // 状态机
  typedef enum logic [1:0] {
    IDLE    = 2'b00,
    FIRST   = 2'b01,
    LAST  = 2'b10,
    BURST   = 2'b11
  } state_t;
  
  state_t                      cmd_state;
  state_t                      cmd_state_nxt;
  state_t                      rsp_state;
  state_t                      rsp_state_nxt;
  
  // 控制信号
  logic                        cmd_fire;
  logic                        rsp_fire;
  logic                        is_last_burst;      // cmd通道的最后burst标志
  logic                        rd_last_burst;     // rsp通道独立的最后burst标志
  logic                        last_beat_sent;
  

  
  // ========================================
  // Outstanding命令FIFO
  // ========================================
  
  // FIFO写入控制
  assign cmd_fifo_wen = sa_icb_cmd_valid & sa_icb_cmd_ready;
  assign cmd_fifo_wdata = {sa_icb_cmd_read, sa_icb_cmd_len, sa_icb_cmd_addr};
  
  // FIFO读取控制 - cmd完成且rsp到最后一拍并fire才能处理下一个请求
  // 初始状态：cmd和rsp都IDLE时可以开始
  // 后续状态：cmd完成且rsp最后一拍fire时才能开始下一个
  assign cmd_fifo_ren = !cmd_fifo_empty && 
                        ((cmd_state == IDLE && rsp_state == IDLE) ||
                         (rd_last_burst && rsp_fire));
  assign {fifo_is_read, fifo_len, fifo_addr} = cmd_fifo_rdata;

  // FIFO满空标志
  assign cmd_fifo_full = (cmd_fifo_wptr[PTR_W] != cmd_fifo_rptr[PTR_W]) & 
                         (cmd_fifo_wptr[PTR_W-1:0] == cmd_fifo_rptr[PTR_W-1:0]);
  assign cmd_fifo_empty = (cmd_fifo_wptr == cmd_fifo_rptr);
  
  // FIFO指针更新
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cmd_fifo_wptr <= '0;
      cmd_fifo_rptr <= '0;
    end else begin
      if (cmd_fifo_wen)
        cmd_fifo_wptr <= cmd_fifo_wptr + 1'b1;
      if (cmd_fifo_ren)
        cmd_fifo_rptr <= cmd_fifo_rptr + 1'b1;
    end
  end
  
  // FIFO存储器
  always_ff @(posedge clk) begin
    if (cmd_fifo_wen)
      cmd_fifo_mem[cmd_fifo_wptr[PTR_W-1:0]] <= cmd_fifo_wdata;
  end
  assign cmd_fifo_rdata = cmd_fifo_mem[cmd_fifo_rptr[PTR_W-1:0]];

  
  // ========================================
  // 地址对齐计算
  // ========================================
  
  // 当前请求信息组合逻辑 - 第一拍直接用FIFO，后续用寄存器
  logic cur_is_read_comb;
  logic [ADDR_W-1:0] cur_addr_comb;
  logic [ICB_LEN_W-1:0] cur_len_0start_comb;
  assign cur_offset = cur_addr_comb[1:0];
  assign cur_base_addr = {cur_addr_comb[ADDR_W-1:2], 2'b00};
  
  
  // 判断是否跨越4字节边界 - 当地址非对齐时才可能跨界
  assign cur_cross_boundary = (cur_offset != 2'b00);
  assign burst_cycle_1start = cur_len_0start_comb + 1'b1 + cur_cross_boundary;
  
  // 响应通道需要使用寄存器锁定的值，而不是组合逻辑值
  logic rsp_cross_boundary;
  logic [ICB_LEN_W:0] rsp_burst_cycle_1start;
  assign rsp_cross_boundary = (cur_addr[1:0] != 2'b00);
  assign rsp_burst_cycle_1start = cur_len_0start + 1'b1 + rsp_cross_boundary;
  // ========================================
  // 当前请求信息寄存器 - 只在burst期间保存
  // ========================================
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cur_is_read <= 1'b0;
      cur_addr <= '0;
      cur_len_0start <= '0;
    end else begin
      // 在读取FIFO时就锁定当前请求信息，直到rsp完成才更新下一个
      if (cmd_fifo_ren) begin
        cur_is_read <= fifo_is_read;
        cur_addr <= fifo_addr;
        cur_len_0start <= fifo_len;
      end
    end
  end
  
  
  // 当FIFO读取时使用FIFO数据，其他时候使用寄存器数据
  assign cur_is_read_comb = rd_last_burst?
                            cur_is_read : 
                            (  cmd_fifo_ren ? fifo_is_read : cur_is_read );
  assign cur_addr_comb = cmd_fifo_ren ? fifo_addr : cur_addr;
  assign cur_len_0start_comb = cmd_fifo_ren ? fifo_len : cur_len_0start;
  
  // ========================================
  // 命令发送状态机
  // ========================================
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cmd_state <= IDLE;
      cur_burst_cnt <= '0;
      last_beat_sent <= 1'b0;
    end else begin
      cmd_state <= cmd_state_nxt;
      cur_burst_cnt <= burst_cnt_nxt;
      
      case (cmd_state_nxt)
        IDLE: last_beat_sent <= 1'b0;
        FIRST: begin
          if (cmd_fire && cur_cross_boundary)
            last_beat_sent <= 1'b0;
        end
        LAST: begin
          if (cmd_fire)
            last_beat_sent <= 1'b1;
        end
        default: ;
      endcase
    end
  end
  
  // 状态机下一状态逻辑
  always_comb begin
    cmd_state_nxt = cmd_state;
    burst_cnt_nxt = cur_burst_cnt;
    
    case (cmd_state)
      IDLE: begin
        if (cmd_fifo_ren) begin
          cmd_state_nxt = FIRST;
          burst_cnt_nxt = '0;
        end
      end
      
      FIRST: begin
        if (cmd_fire) begin
          if (cur_burst_cnt == burst_cycle_1start-1) begin
            // if(cmd_fifo_ren) // 连续请求
            //   cmd_state_nxt = FIRST;
            // else
            cmd_state_nxt = IDLE;
          end else begin
            cmd_state_nxt = BURST;
            burst_cnt_nxt = cur_burst_cnt + 1'b1;
            end
          end
      end
      

      BURST: begin
        if (cmd_fire) begin
          if (cur_burst_cnt == burst_cycle_1start-1) begin
            cmd_state_nxt = IDLE;
            burst_cnt_nxt = '0;
          end else begin
            burst_cnt_nxt = cur_burst_cnt + 1'b1;
          end
        end
      end
      
      // LAST: begin
      //   if (cmd_fire) begin
      //     if (is_last_burst) begin
      //       cmd_state_nxt = IDLE;
      //     end else begin
      //       cmd_state_nxt = BURST;
      //       burst_cnt_nxt = cur_burst_cnt + 1'b1;
      //     end
      //   end
      // end
      

    endcase
  end
  
  assign is_last_burst = (cur_burst_cnt == burst_cycle_1start-1);
  
  // ========================================
  // 响应burst计数器和rd_last_burst逻辑
  // ========================================
  
  // 响应burst计数器
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_burst_cnt <= '0;
    end else begin
      rsp_burst_cnt <= rsp_burst_cnt_nxt;
    end
  end
  
  // 响应burst计数器下一状态逻辑
  always_comb begin
    rsp_burst_cnt_nxt = rsp_burst_cnt;
    
    if (rsp_fire) begin
      if (rd_last_burst) begin
        rsp_burst_cnt_nxt = '0;  // 一个完整的响应完成，重置计数器
      end else begin
        rsp_burst_cnt_nxt = rsp_burst_cnt + 1'b1;  // 继续计数
      end
    end
  end
  
  // 响应通道独立的最后burst标志 - 不依赖cmd_state
  //assign rd_last_burst = (rsp_burst_cnt == burst_cycle_1start-1) ;//&& (rsp_state != IDLE);
  assign rd_last_burst = (rsp_burst_cnt == rsp_burst_cycle_1start-1) ;//&& (rsp_state != IDLE);
  
  // 写请求和读请求的cmd_fire逻辑不同
  logic cmd_fire_write, cmd_fire_read, cmd_fire_write_last;
  // 写操作常规拍：需要w_valid & w_ready & cmd_valid & cmd_ready
  assign cmd_fire_write = (!cur_is_read_comb) & sa_icb_w_valid & sa_icb_w_ready & m_icb_cmd_valid & m_icb_cmd_ready;
  // 写操作最后拍：只需要cmd_valid & cmd_ready（使用缓存数据，不需要新的w_valid）
  assign cmd_fire_write_last = (!cur_is_read_comb) & wdata_buf_valid & is_last_burst  
                                //&!sa_icb_w_valid 
                                & m_icb_cmd_valid & m_icb_cmd_ready;
  // 读操作：需要cmd_valid & cmd_ready
  assign cmd_fire_read = cur_is_read_comb & m_icb_cmd_valid & m_icb_cmd_ready;
  assign cmd_fire = cmd_fire_write | cmd_fire_write_last | cmd_fire_read;
  // sa_icb_w_ready逻辑：写请求通道还有burst的余额，且下游已经准备好接收
  // 因为写通道没有FIFO缓冲，要保证下游已经传完这一拍准备继续传输
  //assign sa_icb_w_ready = (!cur_is_read_comb) & (cmd_state != IDLE) & m_icb_cmd_ready;
  assign sa_icb_w_ready = (!cur_is_read_comb) && (cmd_state != IDLE) &&
                          (  (!is_last_burst || !cur_cross_boundary) ) && 
                          m_icb_cmd_ready;
  
  // ========================================
  // cmd对齐处理（写数据与写请求）
  // ========================================
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wdata_buf <= '0;
      wmask_buf <= '0;
      wdata_buf_valid <= 1'b0;
    end else begin
      // 对于连续的写burst传输，需要缓存上一拍的非对齐wdata
      if (cmd_fire ) begin
          if(!cur_is_read_comb) begin
            if ((cmd_state == FIRST || cmd_state == BURST) && !is_last_burst) begin
              // 缓存跨界的高位部分，用于下一拍拼接
              wdata_buf <= sa_icb_cmd_wdata >> ((DW - cur_offset) * 8);
              wmask_buf <= sa_icb_cmd_wmask >> (DW - cur_offset);
              wdata_buf_valid <= 1'b1;
            end else if (is_last_burst) begin
              wdata_buf_valid <= 1'b0;
              wdata_buf <= '0;
              wmask_buf <= '0;
            end
          end
    end

    end
  end
  logic [4:0] cur_offsetX8;
  assign cur_offsetX8 = cur_offset << 3; // 优化乘法为移位
  // 生成对齐的写数据和掩码
  always_comb begin
    wdata_aligned = '0;
    wmask_aligned = '0;
    
    if (cmd_state == FIRST && !cur_is_read_comb) begin
        wdata_aligned = sa_icb_cmd_wdata << cur_offsetX8;  // 优化乘法为移位
        wmask_aligned = sa_icb_cmd_wmask << cur_offset;
      // end else begin
      //   // 不跨界
      //   wdata_aligned = sa_icb_cmd_wdata << cur_offsetX8;
      //   wmask_aligned = sa_icb_cmd_wmask << cur_offset;
      // end
    end else if (cmd_state == BURST && !cur_is_read_comb) begin
      // 对于连续burst，需要拼接上一拍缓存的数据和当前数据
      if (!is_last_burst) begin
        // 拼接：当前数据的低位部分 + 上一拍缓存的高位部分
        wdata_aligned = (sa_icb_cmd_wdata << cur_offsetX8) | wdata_buf;
        wmask_aligned = (sa_icb_cmd_wmask << cur_offset) | wmask_buf;
      end else begin
        // 最后一个burst，使用缓存数据
        if(cur_cross_boundary)
        begin
          wdata_aligned = wdata_buf;
          wmask_aligned = wmask_buf;
        end
        else
          begin
          wdata_aligned = sa_icb_cmd_wdata ;
          wmask_aligned = sa_icb_cmd_wmask;
          end
      end
    end 
    // else if (cmd_state == LAST) begin
    //   // 跨界最后一拍：缓存的高位部分或拼接数据
    //   if (wdata_buf_valid) begin
    //     wdata_aligned = wdata_buf | (sa_icb_cmd_wdata << cur_offsetX8);
    //     wmask_aligned = wmask_buf | (sa_icb_cmd_wmask << cur_offset);
    //   end else begin
    //     wdata_aligned = sa_icb_cmd_wdata << cur_offsetX8;
    //     wmask_aligned = sa_icb_cmd_wmask << cur_offset;
    //   end
    // end
  end
  
  // ========================================
  // 读数据对齐处理
  // ========================================
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rdata_buf <= '0;
      rdata_buf_valid <= 1'b0;
    end else begin
      // 读响应通道：对于连续的读burst传输，需要缓存上一拍的非对齐rdata
      if (rsp_fire && cur_is_read_comb) begin
        // 对于连续的读burst传输，需要缓存上一拍的非对齐rdata
        if (!rd_last_burst) begin
          // 缓存跨界的高位部分，用于下一拍拼接
          rdata_buf <= m_icb_rsp_rdata >> cur_offsetX8;  // 优化乘法为移位
          rdata_buf_valid <= 1'b1;
        end else if (rd_last_burst || rsp_state == LAST) begin
          rdata_buf_valid <= 1'b0;
        end
      end
    end
  end
  
  // 生成对齐的读数据
  always_comb begin
    rdata_aligned = '0;
    
    if (cur_is_read_comb) begin
      if (rsp_state == IDLE) begin
        if (rsp_cross_boundary) begin
          // 跨界第一拍：仅取低位部分
          rdata_aligned = 'b0;
        end else begin
          // 不跨界
          rdata_aligned = m_icb_rsp_rdata ;
        end
      end else if (rsp_state == BURST) begin
                      
                      // 对于连续burst，需要拼接上一拍缓存的数据和当前数据
                      if (rdata_buf_valid && rsp_cross_boundary) begin
                      //if (!rd_last_burst && rsp_cross_boundary) begin
                        // 拼接：当前数据的高位部分 + 上一拍缓存的低位部分
                        rdata_aligned = (m_icb_rsp_rdata << ((DW - cur_addr[1:0]) << 3)) | rdata_buf;
                      end else begin
                        // 不跨界或第一个burst
                        rdata_aligned = m_icb_rsp_rdata >> (cur_addr[1:0] << 3);
                      end
      end
    end
  end
  

  
  // ========================================
  // 响应处理状态转移
  // ========================================
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_state <= IDLE;
    end else begin
      rsp_state <= rsp_state_nxt;
    end
  end
  // ========================================
  // 响应处理下一状态
  // ========================================
  always_comb begin
    rsp_state_nxt = rsp_state;
    
    case (rsp_state)
      IDLE: begin
        //if (rsp_fire&&!rd_last_burst)
        if (m_icb_rsp_ready && m_icb_rsp_valid &&!rd_last_burst)
          rsp_state_nxt = BURST;
      end
      
      
      BURST: begin
        if (rsp_fire) begin
            if (rd_last_burst)
            rsp_state_nxt = IDLE;
        end
      end
    endcase
  end
  
  // rsp_fire只有在有效响应且上游能接收时才为真
  // 直连响应信号 - 不经过FIFO
  logic sa_rsp_valid_comb;
  logic sa_rsp_ready_comb;
  //assign rsp_fire = sa_rsp_valid_comb & sa_icb_rsp_ready;
  assign rsp_fire = m_icb_rsp_ready & m_icb_rsp_valid;
  

  
  // ========================================
  // 接口信号连接
  // ========================================
  
  // ========================================
  // 接口信号连接 - 直连方式
  // ========================================
  
  // 上游接口
  assign sa_icb_cmd_ready = !cmd_fifo_full;
  
  // 响应valid条件：响应逻辑与cmd_state无关，只看rsp_state和请求类型
  assign sa_rsp_valid_comb = m_icb_rsp_valid && (
    // 读响应：在rsp_state=IDLE或后续状态都可以传输
    (cur_is_read && (
      (rsp_state == IDLE && !rsp_cross_boundary) ||                        // 第一次响应启动

      (rsp_state == BURST)
    )) ||
    // 写响应：只在最后一拍
    (!cur_is_read && rd_last_burst)
  );
  
  assign sa_icb_rsp_valid = sa_rsp_valid_comb;
  assign sa_icb_rsp_rdata = cur_is_read_comb ? rdata_aligned : {WIDTH{1'b0}};
  assign sa_icb_rsp_err = m_icb_rsp_err;
  
  // 下游接口 - 合并读写请求通道逻辑
  // 读操作：cmd_valid在整个burst期间有效
  // 写操作：1. 有新的SA端数据(sa_icb_w_valid)，或
  //         2. 最后一拍需要发送缓存数据(wdata_buf_valid && is_last_burst)
  assign m_icb_cmd_valid = (cmd_state != IDLE) && (
    cur_is_read_comb || 
    sa_icb_w_valid || 
    (!cur_is_read_comb && wdata_buf_valid && is_last_burst  && cur_cross_boundary)
  );
  // burst时地址每次自增4字节
  assign m_icb_cmd_addr = cur_base_addr + (cur_burst_cnt << 2); // 每次自增4
  assign m_icb_cmd_read = cur_is_read_comb;
  assign m_icb_cmd_wdata = wdata_aligned;
  assign m_icb_cmd_wmask = wmask_aligned;
  
  // 反压逻辑：上游不ready时，下游也不ready
  assign m_icb_rsp_ready = sa_rsp_valid_comb ? sa_icb_rsp_ready : 1'b1;

endmodule