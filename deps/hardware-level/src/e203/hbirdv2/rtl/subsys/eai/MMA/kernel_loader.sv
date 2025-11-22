/*
 * kernel_loader 权重加载控制器设计说明（自主访存版本）
  *与ia_loader区别：
 1.所有数据都是int8，没有16bit选项，而且输出也都是8位宽，不需要符号扩展。
 2.不需要输出 ia_is_init_data、ia_calc_done 这两个表征是第一个Tile还是最后一个tile的信号
 3.weight矩阵是列展平存储在内存中的，而且访问的时候是一列tile一列tile的访问。所以其实也是连续访存，和ia_loader基本一样。
 4.对于IA_loader,每一行有row_tile_num个tile,然后这一行row_tile_num个tile发完后又循环这一行，循环次数为 loop_row_num=m/ 16向上取整个tile
    而对于kernel_loader,每一列的col_tile_num个tile发完之后并不循环发送这一列，而是将所有列的tile都发送完毕后，再从第一列开始重新发送。
5.weight矩阵是列展平存储在内存中的，所以缓存在tile buffer中的时候也一列一列存的，但是发weight_out的时候是一行一行发的（先输出最后一行，最后输出第一行，和ia loader相反的）
6.weight_out输出到脉动阵列的权重（按行输出），行倒序输出，先输出最后一行，最后输出第一行。
7.tile按行输出。无效的行输出0；无效的列置为0，和ia loader不一样，因为weight tile是“压入”ws systolic array里的，所以无效的行也必须输入。而且由于ia没有处理，所以他无效的行和列都应该置为0。
 * ------------------------------------------------------------
 * 功能概述:
 *  本模块负责面向分块矩阵运算，从外部存储器自主读取权重数据（RHS），并按行输出到脉动阵列。
 *  模块内部负责计算每个权重分块（Weight Tile）的访存地址、发起 ICB 读请求、缓存并按需输出权重。
 *  设计目标：完成一次权重Tile的发送后自动申请并加载下一批权重，以保证计算流水的连续性 *  设计目标：在满足时序和功能的前提下，实现高效的（最短周期的）输入激活加载。

 * 分块访存策略（简要）:
 *  使用常见的Tile化矩阵乘法策略：OA[k*m] = IA[k*n] × Kernel[n*m]
 *  - IA矩阵(A): k行n列（输入激活）
 *  - Weight矩阵(B): n行m列（权重）
 *  - OA矩阵(C): k行m列（输出）
  *  术语:
 *   - SIZE: 脉动阵列的行/列宽度（通常为16），模块参数 SIZE 即脉动阵列规格
 *   - weight Tile: 尺寸为 SIZE 行 × SIZE 列 的输入子块，对于kernel_loader,每一行有row_tile_num=n/ SIZE(向上取整）  个tile
 *   - Weight Tile: 尺寸为 SIZE 行 × SIZE 列
 *   - OA Tile: 尺寸为 SIZE 行 × SIZE 列*
  *  重要推导:
 *   - row_tile_num = ceil(n/ SIZE)          // 每个行的Tile数//实际计算时需要使用移位和加法来替代原有的除法和取整，以保证时序通过
 *   - row_tile_rem = ceil(n/ SIZE) - n           // 最后一个 Tile的无效的列数（考虑矩阵边界）
 *   - 一共m列tile构成的一整组 weight Tile 会被重复使用loop_allTile_num=ceil(k/ SIZE) 次（与不同行的IA Tile相乘）//实际计算时需要使用移位和加法来替代原有的除法和取整，以保证时序通过
 *   - col_tile_num = ceil(k / SIZE)          // 列方向需要的 Tile个数，需使用移位加法替代除法以满足时序
 *   - col_tile_rem = (col_tile_num * SIZE) - k // 最后一列方向Tile的无效行数，计算同样采用移位加法避免乘除

 *  访存与地址生成策略（列主序考虑）：
 *  - 模块在 init_cfg 时锁存基地址（cfg_rhs_base）、行/列间距（cfg_rhs_row_stride_b）和分块尺寸
 *  - 对于列主序存储，计算每个 Weight Tile 的访存地址时需要以列为主的偏移步长：
 *      tile_base = cfg_rhs_base + tile_col * cfg_rhs_col_stride + tile_row * cfg_rhs_row_stride (按实现约定)
 *  - 实现上可以按列逐列读取 tile（每次读取 k 个连续元素），或按块化读取后在缓冲区内做重排
 *  - 读取完成后模块将数据重排为按行格式，然后置 weight_data_valid=1，表示当前 Tile 已准备好发送

 * 工作流程（高层）：
 *  0) 空闲阶段（IDLE）
      上一次GEMM完成后（weight矩阵完全加载完毕后）或者模块刚上电时，模块处于IDLE状态，等待init_cfg信号拉高进入配置阶段
    1) 配置阶段（init_cfg）   
       IDLE阶段被 init_cfg 单拍拉高触发，模块进入配置状态
 *     - 锁存所有需要的寄存器：k、n、m、rhs_base、rhs_col_stride_b、rhs_zp、use_16bits
 *     - 根据 k、SIZE、N 等计算 row_tile_num 与 loop_allTile_num row_tile_rem等访存参数并保存
 *
 *  2) 自主Load阶段（模块内部驱动 ICB）
     配置阶段计算且寄存完成之后 或者 上一个weight Tile的逐行发送完成且整个weight矩阵没有加载完成时，模块进入Load状态
 *     读请求通道：
 *     - 根据当前 Tile 索引计算基地址（cfg_rhs_base + tile_col * rhs_col_stride_b + row_offset）//实际实现中不能用乘法，需要用一个寄存器寄存上一行的地址，然后加上STRIDE
 *     - 维护 tile_row_idx、tile_col_idx、loop_row_cnt 等状态变量，
 *   同理，最后一行的tile的无效的行不用发送读请求读  
        *  
 *    读响应通道
 *     - 将读取的数据缓存到内部行缓冲或Tile缓冲中；当完整Tile可用时置 data_valid=1
 *
 *  3) Send阶段（外部通过 send_weight_trigger 启动逐行发送）
 *     - 当 data_valid=1 且收到 send_weight_trigger 后，模块进入发送阶段（SEND）
 *     - 每个时钟周期输出一列权重数据到 weight_out，同时将 weight_row_valid 置1 表示该周期数据有效
 *     - 发送持续 tile 内的行数tile按行输出.tile按行输出。无效的行输出0；无效的列置为0，和ia loader不一样，因为weight tile是“压入”ws systolic array里的，所以无效的行也必须输入。而且由于ia没有处理，所以他无效的行和列都应该置为0。
 *     - sending_done: 在发送完整个 Tile 后置1
 *
 **

 */

`include "e203_defines.v"
`include "icb_types.svh"

module kernel_loader #(
    parameter int unsigned DATA_WIDTH = 8,   // 权重数据宽度
    parameter int unsigned SIZE       = 16,  // 阵列大小
    parameter int unsigned BUS_WIDTH  = 32,  // 总线宽度
    parameter int unsigned REG_WIDTH  = 32   // 配置寄存器宽度
) (
    // 时钟与复位
    input wire clk,   // 时钟信号
    input wire rst_n, // 异步复位，低有效

    // 配置控制接口
    input wire init_cfg,  // 触发配置参数锁存

    // 自动重触发控制接口
    output reg  load_weight_req,      // 申请下一次访存授权（输出到外部控制器）
    input  wire load_weight_granted,  // 外部控制器授权下一次访存（握手信号）
    input  wire send_weight_trigger,  // 触发发送权重到脉动阵列（单拍触发）

    // 矩阵尺寸与分块配置（在 init_cfg 时被锁存）
    input wire [REG_WIDTH-1:0] k,  // 输入激活矩阵行数（RHS_ROWS）
    input  wire [REG_WIDTH-1:0]        n,                 // 输入激活矩阵列数（RHS_COLS）//也就是权重矩阵的行数
    input  wire [REG_WIDTH-1:0]        m,                 // 输出矩阵列数（LHS_COLS），用于计算是否为最后一个tile//也就是权重矩阵的列数

    // 配置寄存器（在 init_cfg 时锁存）
    input wire signed [REG_WIDTH-1:0] rhs_zp,  // 权重零点（s32）
    input wire [REG_WIDTH-1:0] rhs_col_stride_b,  // 权重列间地址间距
    input wire [REG_WIDTH-1:0] rhs_base,  // 权重数据基地址（第一个分块）


    // ICB 主接口（模块作为 Master，展开信号）
    // 命令通道
    output reg                   icb_cmd_valid,  // 命令有效
    input  logic                 icb_cmd_ready,  // 命令就绪
    output reg                   icb_cmd_read,   // 读操作标志
    output reg   [REG_WIDTH-1:0] icb_cmd_addr,   // 命令地址
    output logic [          3:0] icb_cmd_len,    // Burst长度-1
    // 响应通道
    input  logic                 icb_rsp_valid,  // 响应有效
    output reg                   icb_rsp_ready,  // 响应就绪
    input  logic [BUS_WIDTH-1:0] icb_rsp_rdata,  // 读数据
    input  logic                 icb_rsp_err,    // 错误标志

    // 输出信号到脉动阵列
    output reg weight_sending_done,  // 权重发送完成//脉冲一拍
    output reg weight_row_valid,  // 控制脉动阵列权重加载//与weight_out同步
    output reg signed [DATA_WIDTH-1:0] weight_out[SIZE],   // 输出到脉动阵列的权重（按行输出）//tile按行输出。无效的行输出0；无效的列置为0；行倒序输出，先输出最后一行，最后输出第一行

    // 新增输出：当完成所有权重读取时指示数据已准备好
    output reg                         weight_data_valid   // 所有权重数据已读取完毕并可用于发送//和send_weight_trigger握手
);

  // 状态定义
  typedef enum logic [1:0] {
    IDLE = 2'b00,  // 空闲状态
    INIT = 2'b11,  // 初始化状态，锁存配置参数
    LOAD = 2'b01,  // 读取数据状态
    SEND = 2'b10   // 发送数据状态
  } state_t;

  state_t state;

  // =========================================================================
  // 配置寄存器
  // =========================================================================
  reg [REG_WIDTH-1:0] cfg_k, cfg_n, cfg_m;
  reg signed [REG_WIDTH-1:0] cfg_rhs_zp;
  reg [REG_WIDTH-1:0] cfg_rhs_col_stride_b, cfg_rhs_base;

  // =========================================================================
  // Tile计算参数
  // =========================================================================
  reg [REG_WIDTH-1:0] row_tile_num;  // 每行tile数量 = ceil(m/SIZE)
  reg [REG_WIDTH-1:0] col_tile_num;  // 列方向tile数量 = ceil(n/SIZE) - weight矩阵的列数
  reg [REG_WIDTH-1:0] loop_col_num;  // 列循环次数 = ceil(k/SIZE) - 重复使用次数
  reg [REG_WIDTH-1:0] row_tile_rem;  // 最后一个行tile无效列数
  reg [REG_WIDTH-1:0] col_tile_rem;  // 最后一个列tile无效行数

  // =========================================================================
  // Tile索引和地址
  // =========================================================================
  reg [REG_WIDTH-1:0] tile_row_idx;  // 当前tile行索引（对应m方向）
  reg [REG_WIDTH-1:0] tile_col_idx;  // 当前tile列索引（对应n方向）
  reg [REG_WIDTH-1:0] loop_col_cnt;  // 当前列循环计数
  //reg [REG_WIDTH-1:0] current_col_base; // 当前列基地址
  reg [REG_WIDTH-1:0] current_tile_addr;  // 当前tile起始地址

  // =========================================================================
  // 读取控制
  // =========================================================================
  //reg [REG_WIDTH-1:0] cols_to_read;     // 当前tile需读取的列数
  reg [REG_WIDTH-1:0] current_read_col;  // 当前读取的列号
  reg [REG_WIDTH-1:0] read_burst_length;  // 读取burst长度
  reg [REG_WIDTH-1:0] current_col_addr;  // 当前读取列的地址（累加寄存器）

  // =========================================================================
  // Tile缓冲区
  // =========================================================================
  reg signed [DATA_WIDTH-1:0] tile_buffer[SIZE][SIZE];
  wire [REG_WIDTH-1:0] valid_rows;  // 缓冲区有效行数
  wire [REG_WIDTH-1:0] valid_cols;  // 缓冲区有效列数

  // =========================================================================
  // 发送控制
  // =========================================================================
  reg [REG_WIDTH-1:0] send_row_idx;

  // =========================================================================
  // ICB响应接收控制
  // =========================================================================
  reg [REG_WIDTH-1:0] rsp_col_cnt;  // 响应计数
  reg [REG_WIDTH-1:0] rsp_beat_cnt;  // 响应beat计数

  // 响应通道独立维护的tile参数（在INIT时计算好）
  reg [REG_WIDTH-1:0] rsp_rows_per_tile;  // 每个完整tile的行数 = SIZE
  reg [REG_WIDTH-1:0] rsp_rows_last_tile;  // 最后一个tile的行数 = SIZE - row_tile_rem
  reg [REG_WIDTH-1:0] rsp_beats_per_row_normal;  // 正常tile每行的beat数
  reg [REG_WIDTH-1:0] rsp_beats_per_row_last;  // 最后一列tile每行的beat数

  // 响应通道的tile追踪
  reg [REG_WIDTH-1:0] rsp_tile_row_idx;  // 当前响应的tile行索引
  reg [REG_WIDTH-1:0] rsp_tile_col_idx;  // 当前响应的tile列索引
  reg [REG_WIDTH-1:0] rsp_loop_col_cnt;  // 当前响应的循环计数

  // =========================================================================
  // 辅助信号
  // =========================================================================
  wire is_last_col_tile = (tile_col_idx == col_tile_num - 1);  //FIXME:row_tile_num???
  wire is_last_row_tile = (tile_row_idx == row_tile_num - 1);
  wire is_last_loop = (loop_col_cnt == loop_col_num - 1);
  wire cmd_hs = icb_cmd_valid && icb_cmd_ready;
  wire rsp_hs = icb_rsp_valid && icb_rsp_ready;

  localparam int BYTE_PER_BEAT = BUS_WIDTH / 8;

  // =========================================================================
  // 单段式状态机 - 现态更新与次态逻辑合并
  // =========================================================================
  logic is_last_col_tile_dff;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      is_last_col_tile_dff <= 0;
    end else begin
      is_last_col_tile_dff <= is_last_col_tile;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
    end else begin
      case (state)
        IDLE: begin
          if (init_cfg) state <= INIT;
        end

        INIT: begin
          // 等待load授权后才进入LOAD状态
          if (load_weight_granted) state <= LOAD;
        end

        LOAD: begin
          // 当所有响应接收完毕时转到SEND
          if (weight_data_valid) state <= SEND;
        end

        SEND: begin
          // 当本次 tile 的行逐行发送完成（weight_sending_done）时，判断是否为整个权重矩阵的最后一个 tile
          // 只有在：当前为最后一行 tile、最后一列 tile，并且完成了最后一轮循环时，才真正结束并回到 IDLE
          if (weight_sending_done && is_last_row_tile && is_last_col_tile && is_last_loop) begin
            state <= IDLE;
          end else if (weight_sending_done) begin
            // 等待授权后才进入下一个LOAD
            state <= LOAD;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

  // =========================================================================
  // 配置参数锁存与计算
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg_k <= '0;
      cfg_n <= '0;
      cfg_m <= '0;
      cfg_rhs_zp <= '0;
      cfg_rhs_col_stride_b <= '0;
      cfg_rhs_base <= '0;
      row_tile_num <= '0;
      col_tile_num <= '0;
      loop_col_num <= '0;
      row_tile_rem <= '0;
      col_tile_rem <= '0;

      // 响应通道参数初始化
      rsp_rows_per_tile <= '0;
      rsp_rows_last_tile <= '0;
      rsp_beats_per_row_normal <= '0;
      rsp_beats_per_row_last <= '0;

    end else if (state == IDLE && init_cfg) begin
      // 锁存基本配置参数
      cfg_k <= k;
      cfg_n <= n;
      cfg_m <= m;
      cfg_rhs_zp <= rhs_zp;
      cfg_rhs_col_stride_b <= rhs_col_stride_b;
      cfg_rhs_base <= rhs_base;

      // 使用移位和加法替代除法: ceil(n/SIZE) = (n + SIZE - 1) >> $clog2(SIZE)
      col_tile_num <= (m + SIZE - 1) >> $clog2(SIZE);  // 每行tile数量（n方向）
      row_tile_num <= (n + SIZE - 1) >> $clog2(SIZE);  // 列方向tile数量（m方向）
      loop_col_num <= (k + SIZE - 1) >> $clog2(SIZE);  // 列循环次数

      // row_tile_rem = (ceil(n/SIZE) * SIZE) - n
      // 计算最后一个行tile的无效列数//FIXME:这里好两个好像反了
      col_tile_rem <= (((m + SIZE - 1) >> $clog2(SIZE)) << $clog2(SIZE)) - m;
      // col_tile_rem = (ceil(m/SIZE) * SIZE) - m
      row_tile_rem <= (((n + SIZE - 1) >> $clog2(SIZE)) << $clog2(SIZE)) - n;

      // =====================================================
      // 响应通道专用参数计算（完全独立于请求通道）
      // =====================================================
      rsp_rows_per_tile <= SIZE;  // 完整tile的行数
      // 最后一个行tile的有效列数 = SIZE - row_tile_remFIXME:同上
      rsp_rows_last_tile <= SIZE - ((((m + SIZE - 1) >> $clog2(SIZE)) << $clog2(SIZE)) - m);

      // 计算每行需要的beat数（正常tile，int8固定）
      // beats = ceil(SIZE / BYTE_PER_BEAT)
      rsp_beats_per_row_normal <= (SIZE + BYTE_PER_BEAT - 1) >> $clog2(BYTE_PER_BEAT);

      // 计算每行需要的beat数（最后一行tile）//FIXME:感觉不对
      // beats = ceil((SIZE - col_tile_rem) / BYTE_PER_BEAT)
      rsp_beats_per_row_last <= ((SIZE - ((((n + SIZE - 1) >> $clog2(
          SIZE
      )) << $clog2(
          SIZE
      )) - n)) + BYTE_PER_BEAT - 1) >> $clog2(
          BYTE_PER_BEAT
      );
    end
  end

  // =========================================================================
  // Tile索引管理 - 列主序访存
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tile_row_idx <= '0;
      tile_col_idx <= '0;
      loop_col_cnt <= '0;
      //current_col_base <= '0;//FIXME:这个应该不需要了
    end else begin
      case (state)
        INIT: begin
          tile_row_idx <= '0;
          tile_col_idx <= '0;
          loop_col_cnt <= '0;
          //current_col_base <= cfg_rhs_base;
        end

        SEND: begin
          if (weight_sending_done) begin
            // 遍历顺序：在同一行内列索引先增加 (col 方向为内层)，
            // 当列到末尾则列归0并行索引增加；当行也到末尾则行归0并 loop_col_cnt++。
            if (tile_row_idx < row_tile_num - 1) begin
              // 同一行的下一个列 tile
              tile_row_idx <= tile_row_idx + 1;
            end else begin
              // 当前行的列已到末尾，回到该行的第 0 列
              tile_row_idx <= '0;
              if (tile_col_idx < col_tile_num - 1) begin
                // 移到下一行，同列从0开始
                tile_col_idx <= tile_col_idx + 1;
              end else begin
                // 行也到末尾：回到第0行，并推进 loop 计数
                tile_col_idx <= '0;
                if (loop_col_cnt < loop_col_num - 1) begin
                  loop_col_cnt <= loop_col_cnt + 1;
                end else begin
                  // 所有 loop 完成，回到初始位置
                  loop_col_cnt <= '0;
                end
              end
            end
          end
        end
      endcase
    end
  end

  // =========================================================================
  // 地址计算 - 列主序
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_tile_addr <= '0;
    end else if (state == INIT) begin
      current_tile_addr <= cfg_rhs_base;
    end else if (state == SEND && weight_sending_done) begin
      if (is_last_col_tile && is_last_row_tile && is_last_loop)
        // 所有tile发送完成，地址回到初始位置
        current_tile_addr <= '0;
      // tile发送完成后更新到下一个tile的起始地址
      else if (is_last_col_tile && is_last_row_tile) begin
        // 当前列的所有tile循环都完成了，移到下一列tile的第一个
        current_tile_addr <= cfg_rhs_base;
      end else if (is_last_row_tile) begin
        // 当前列的tile发完，重新循环这一列，回到第一个tile/FIXME:循环逻辑修改：发完所有列tile后才重新开始（不是单列循环）
        current_tile_addr <= cfg_rhs_base + (cfg_rhs_col_stride_b << $clog2(
            SIZE
        )) * rsp_tile_col_idx;
        //current_tile_addr <= cfg_rhs_base;
      end else begin
        current_tile_addr <= current_tile_addr + SIZE;  // int8每个元素1字节
      end

    end
  end

  // =========================================================================
  // 有效行列数计算
  // =========================================================================
  logic [REG_WIDTH-1:0] next_tile_row_idx ;//FIXME:循环逻辑修改：发完所有列tile后才重新开始（不是单列循环）
  // 列方向
  logic [REG_WIDTH-1:0] next_tile_col_idx;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      //  valid_rows <= '0;
      //  valid_cols <= '0;
      next_tile_row_idx <= 'b0;
      next_tile_col_idx <= 'b0;
      //  end else if (state == INIT) begin
      //      // INIT状态就计算好第一个tile的有效行列
      //      valid_rows <= (row_tile_num == 1) ? (SIZE - row_tile_rem) : SIZE;
      //      valid_cols <= (col_tile_num == 1) ? (SIZE - col_tile_rem) : SIZE;
    end else if (state == SEND && weight_sending_done) begin
      // SEND完成后，为下一个tile计算有效行列
      // 判断下一个tile的行索引
      if (is_last_row_tile && is_last_col_tile && is_last_loop) next_tile_row_idx <= 0;
      else if (is_last_row_tile && is_last_col_tile) next_tile_row_idx <= 0;
      else if (is_last_row_tile) next_tile_row_idx <= 0;
      else next_tile_row_idx <= tile_row_idx + 1;


      // 根据下一个tile的行索引判断是否是最后一行tile
      //  if (next_tile_row_idx == row_tile_num - 1) 
      //      valid_rows <= SIZE - row_tile_rem;
      //   else 
      //      valid_rows <= SIZE;


      if (is_last_row_tile && is_last_col_tile && is_last_loop) next_tile_col_idx <= 0;
      else if (is_last_row_tile && is_last_col_tile) next_tile_col_idx <= 0;
      else if (is_last_row_tile) next_tile_col_idx <= tile_col_idx + 1;



      //  if (next_tile_col_idx == col_tile_num - 1)
      //      valid_cols <= SIZE - col_tile_rem;
      //  else
      //      valid_cols <= SIZE;
    end
  end

  assign icb_cmd_len = read_burst_length - 1;
  assign valid_cols = (col_tile_num == 0) ? '0 : (tile_col_idx == col_tile_num - 1) ? (SIZE - col_tile_rem) : SIZE;
  assign valid_rows = (row_tile_num == 0) ? '0 : (tile_row_idx == row_tile_num - 1) ? (SIZE - row_tile_rem) : SIZE;
  // =========================================================================
  // ICB读请求发送 - 列主序
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_read_col <= '0;
      read_burst_length <= '1;
      icb_cmd_valid <= '0;
      icb_cmd_read <= '0;
      icb_cmd_addr <= '0;
      current_col_addr <= '0;
    end else begin
      case (state)
        LOAD: begin
          // 当前tile还有列需要读取
          if (current_read_col < valid_cols) begin
            // 等待上一次请求握手完成或首次发送
            if (!icb_cmd_valid || cmd_hs) begin
              icb_cmd_valid <= 1'b1;
              icb_cmd_read  <= 1'b1;

              // 使用累加寄存器计算地址（避免乘法）
              if (current_read_col == 0) begin
                // 第一列：使用tile基地址/FIXME:循环逻辑修改：strided名字修改
                icb_cmd_addr <= current_tile_addr;
                current_col_addr <= current_tile_addr + cfg_rhs_col_stride_b;
              end else begin
                // 后续列：使用累加的地址
                icb_cmd_addr <= current_col_addr;
                current_col_addr <= current_col_addr + cfg_rhs_col_stride_b;
              end

              current_read_col <= current_read_col + 1;

              // 计算burst长度（int8固定）
              if (is_last_row_tile) begin
                read_burst_length <= ((SIZE - row_tile_rem) + BYTE_PER_BEAT - 1) >>
                    $clog2(BYTE_PER_BEAT);
              end else begin
                read_burst_length <= (SIZE + BYTE_PER_BEAT - 1) >> $clog2(BYTE_PER_BEAT);
              end
            end
          end else begin
            // 当前tile所有行已发送完读请求
            if (cmd_hs) begin // 等待最后一次握手完成
              icb_cmd_valid <= '0;
            end
          end
        end

        default: begin
          current_read_col <= '0;
          icb_cmd_valid <= 1'b0;
          icb_cmd_read <= 1'b0;
          current_col_addr <= '0;
        end
      endcase
    end
  end

  // =========================================================================
  // ICB读响应接收 - int8固定
  // =========================================================================
  localparam int ELEMENTS_PER_BEAT_S8 = BYTE_PER_BEAT;

  logic [$clog2(SIZE)-1:0] col_idx;
  assign col_idx = rsp_beat_cnt << $clog2(ELEMENTS_PER_BEAT_S8);

  wire rsp_is_last_col_tile = (rsp_tile_col_idx == col_tile_num - 1);
  wire rsp_is_last_row_tile = (rsp_tile_row_idx == row_tile_num - 1);
  wire [REG_WIDTH-1:0] rsp_current_cols = rsp_is_last_col_tile ? rsp_rows_last_tile : rsp_rows_per_tile;
  wire [REG_WIDTH-1:0] rsp_current_beats = rsp_is_last_row_tile ? rsp_beats_per_row_last : rsp_beats_per_row_normal;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_col_cnt <= '0;
      rsp_beat_cnt <= '0;
      icb_rsp_ready <= '0;

      rsp_tile_row_idx <= '0;
      rsp_tile_col_idx <= '0;
      rsp_loop_col_cnt <= '0;

      // 初始化tile缓冲区
      for (int i = 0; i < SIZE; i++) begin
        for (int j = 0; j < SIZE; j++) begin
          tile_buffer[i][j] <= '0;
        end
      end
    end else begin
      case (state)
        INIT: begin
          rsp_tile_row_idx <= '0;
          rsp_tile_col_idx <= '0;
          rsp_loop_col_cnt <= '0;
          rsp_col_cnt <= '0;
          rsp_beat_cnt <= '0;
        end

        LOAD: begin
          icb_rsp_ready <= 1'b1;

          if (rsp_hs) begin
            // int8数据解析（加零点）
            if (BYTE_PER_BEAT == 4) begin
              // 32位总线：4个s8元素
              if (col_idx < SIZE)
                tile_buffer[rsp_col_cnt][col_idx] <= $signed(icb_rsp_rdata[7:0]) + cfg_rhs_zp[7:0];
              if (col_idx + 1 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+1] <= $signed(
                    icb_rsp_rdata[15:8]
                ) + cfg_rhs_zp[7:0];
              if (col_idx + 2 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+2] <= $signed(
                    icb_rsp_rdata[23:16]
                ) + cfg_rhs_zp[7:0];
              if (col_idx + 3 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+3] <= $signed(
                    icb_rsp_rdata[31:24]
                ) + cfg_rhs_zp[7:0];
            end else begin
              // 64位总线：8个s8元素
              if (col_idx < SIZE)
                tile_buffer[rsp_col_cnt][col_idx] <= $signed(icb_rsp_rdata[7:0]) + cfg_rhs_zp[7:0];
              if (col_idx + 1 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+1] <= $signed(
                    icb_rsp_rdata[15:8]
                ) + cfg_rhs_zp[7:0];
              if (col_idx + 2 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+2] <= $signed(
                    icb_rsp_rdata[23:16]
                ) + cfg_rhs_zp[7:0];
              if (col_idx + 3 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+3] <= $signed(
                    icb_rsp_rdata[31:24]
                ) + cfg_rhs_zp[7:0];
              if (col_idx + 4 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+4] <= $signed(
                    icb_rsp_rdata[39:32]
                ) + cfg_rhs_zp[7:0];
              if (col_idx + 5 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+5] <= $signed(
                    icb_rsp_rdata[47:40]
                ) + cfg_rhs_zp[7:0];
              if (col_idx + 6 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+6] <= $signed(
                    icb_rsp_rdata[55:48]
                ) + cfg_rhs_zp[7:0];
              if (col_idx + 7 < SIZE)
                tile_buffer[rsp_col_cnt][col_idx+7] <= $signed(
                    icb_rsp_rdata[63:56]
                ) + cfg_rhs_zp[7:0];
            end

            // =====================================================
            // 响应计数器更新：
            // 内层：beat 计数完整后，表示当前行的一个 beat 接收完毕；
            // 当 beat 达到本行需要的 beat 数后，行计数 +1；
            // 当行计数达到本 tile 的行数后，表示当前 tile 接收完毕，
            // 此时按 列->行->loop 的顺序推进 tile 索引（列为内层）。
            // =====================================================
            if (rsp_beat_cnt == rsp_current_beats - 1) begin
              // 本行的最后一个 beat 已接收
              rsp_beat_cnt <= '0;

              if (rsp_col_cnt == rsp_current_cols - 1) begin
                // 当前 tile 的所有行已接收完毕
                rsp_col_cnt <= '0;

                // 先推进 tile 的列索引（列为内层）
                if (rsp_tile_row_idx < row_tile_num - 1) begin
                  rsp_tile_row_idx <= rsp_tile_row_idx + 1;
                end else begin
                  // 列到末尾，列归0并推进行索引
                  rsp_tile_row_idx <= '0;

                  if (rsp_tile_col_idx < col_tile_num - 1) begin
                    rsp_tile_col_idx <= rsp_tile_col_idx + 1;
                  end else begin
                    // 行也到末尾，行归0并推进 loop 计数
                    rsp_tile_col_idx <= '0;
                    if (rsp_loop_col_cnt < loop_col_num - 1) begin
                      rsp_loop_col_cnt <= rsp_loop_col_cnt + 1;
                    end else begin
                      // 所有循环完成，回到初始
                      rsp_loop_col_cnt <= '0;
                    end
                  end
                end
              end else begin
                // 当前 tile 未完成，推进到 tile 的下一行
                rsp_col_cnt <= rsp_col_cnt + 1;
              end
            end else begin
              // 继续当前行的下一个 beat
              rsp_beat_cnt <= rsp_beat_cnt + 1;
            end
          end
        end

        default: begin
          rsp_col_cnt   <= '0;
          rsp_beat_cnt  <= '0;
          icb_rsp_ready <= '0;
          // base_col_idx <= '0;
        end
      endcase
    end
  end

  // =========================================================================
  // weight_data_valid生成
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_data_valid <= '0;
    end else begin
      case (state)
        LOAD: begin
          if (rsp_hs && rsp_beat_cnt == (rsp_current_beats - 1) && rsp_col_cnt == rsp_current_cols - 1)
            weight_data_valid <= 1'b1;
        end

        SEND: begin
          if (send_weight_trigger || send_row_idx < 15) weight_data_valid <= 1'b0;
        end

        default: weight_data_valid <= '0;
      endcase
    end
  end

  // =========================================================================
  // 发送控制 - 行倒序输出，包括无效行
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      send_row_idx <= SIZE - 1;  // 初始值为最后一行索引
      weight_sending_done <= '0;
    end else begin
      case (state)
        INIT: begin
          send_row_idx <= SIZE - 1;  // 每次INIT重新初始化
        end

        SEND: begin
          // 发送SIZE行（包括无效行），从最后一行开始递减
          if (send_weight_trigger) begin
            // trigger时发送当前行，然后递减
            //send_row_idx <= send_row_idx - 1;
            weight_sending_done <= (send_row_idx == 0) ? 1'b1 : 1'b0;
          end else if (weight_row_valid) begin
            // 继续发送剩余行
            if (send_row_idx == 0) begin
              weight_sending_done <= 1'b1;
              send_row_idx <= SIZE - 1;  // 为下一个tile准备
            end else begin
              send_row_idx <= send_row_idx - 1;
              weight_sending_done <= 1'b0;
            end
          end else begin
            weight_sending_done <= 1'b0;
          end
        end

        default: begin
          send_row_idx <= SIZE - 1;
          weight_sending_done <= '0;
        end
      endcase
    end
  end

  // =========================================================================
  // load_weight_req生成
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      load_weight_req <= '0;
    end else begin
      if (state == IDLE && !load_weight_req && init_cfg) begin
        load_weight_req <= 1'b1;
      end 
             else if (state == SEND && weight_sending_done && 
                 !(is_last_row_tile && is_last_col_tile && is_last_loop) && !load_weight_req) begin
        load_weight_req <= 1'b1;
      end else if (load_weight_granted) begin
        load_weight_req <= 1'b0;
      end
    end
  end

  // =========================================================================
  // weight_row_valid输出
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_row_valid <= 1'b0;
    end else begin
      if (state == SEND && send_weight_trigger) begin
        weight_row_valid <= 1'b1;
      end else if (state == SEND && send_row_idx == 0 && weight_row_valid) begin
        weight_row_valid <= 1'b0;
      end
    end
  end

  // =========================================================================
  // weight_out输出赋值 - 直接使用send_row_idx，无效行/列输出0
  // =========================================================================
  generate
    for (genvar i = 0; i < SIZE; i++) begin : gen_weight_out
      always_comb begin
        if (weight_row_valid) begin
          // 检查是否为有效行和有效列
          if (send_row_idx < valid_rows && i < valid_cols) begin
            weight_out[i] = tile_buffer[i][send_row_idx];
          end else begin
            weight_out[i] = '0;  // 无效行或无效列输出0
          end
        end else begin
          weight_out[i] = '0;
        end
      end
    end
  endgenerate

endmodule
