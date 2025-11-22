/*
 * ia_loader 输入激活加载控制器设计说明（自主访存版本）
 * ------------------------------------------------------------
 * 功能概述:
 *  本模块负责面向分块矩阵运算，从外部存储器自主读取输入激活（IA），并按行输出到脉动阵列。
 *  模块内部完全控制IA Tile的访存与行tile循环访存逻辑
 *  设计目标：在满足时序和功能的前提下，实现高效的（最短周期的）输入激活加载。
 *
 * 分块访存策略（简要）:
 *  使用常见的Tile化矩阵乘法策略：OA[k*m] = IA[k*n] × Kernel[n*m]
 *  - IA矩阵(A): k行n列（输入激活）
 *  - Weight矩阵(B): n行m列（权重）
 *  - OA矩阵(C): k行m列（输出）
 *
 *  术语:
 *   - SIZE: 脉动阵列的行/列宽度（通常为16），模块参数 SIZE 即脉动阵列规格
 *   - IA Tile: 尺寸为 SIZE 行 × SIZE 列 的输入子块，对于IA_loader,每一行有row_tile_num=n/ SIZE(向上取整）  个tile
 *   - Weight Tile: 尺寸为 SIZE 行 × SIZE 列
 *   - OA Tile: 尺寸为 SIZE 行 × SIZE 列
 *
 *  重要推导:
 *   - row_tile_num = ceil(n/ SIZE)          // 每个OA行的IA Tile数//实际计算时需要使用移位和加法来替代原有的除法和取整，以保证时序通过
 *   - row_tile_rem = ceil(n/ SIZE) - n           // 最后一个IA Tile的无效的列数（考虑矩阵边界）
 *   - 每行IA Tile 会被重复使用loop_row_num=ceil(m/ SIZE) 次（与不同列的Weight Tile相乘）//实际计算时需要使用移位和加法来替代原有的除法和取整，以保证时序通过
 *   - col_tile_num = ceil(k / SIZE)          // 列方向需要的IA Tile个数，需使用移位加法替代除法以满足时序
 *   - col_tile_rem = (col_tile_num * SIZE) - k // 最后一列方向Tile的无效行数，计算同样采用移位加法避免乘除
 *
 * 工作流程（高层）：
 *  0) 空闲阶段（IDLE）
      上一次GEMM完成后（IA矩阵完全加载完毕后）或者模块刚上电时，模块处于IDLE状态，等待init_cfg信号拉高进入配置阶段
    1) 配置阶段（init_cfg）   
       IDLE阶段被 init_cfg 单拍拉高触发，模块进入配置状态
 *     - 锁存所有需要的寄存器：k、n、m、lhs_base、lhs_row_stride_b、lhs_zp、use_16bits
 *     - 根据 k、SIZE、N 等计算 row_tile_num 与 loop_row_num row_tile_rem等访存参数并保存
 *
 *  2) 自主Load阶段（模块内部驱动 ICB）
     配置阶段计算且寄存完成之后 或者 上一个IA Tile的逐行发送完成且整个IA矩阵没有加载完成时，模块进入Load状态
 *     读请求通道：
 *     - 根据当前 IA Tile 索引计算基地址（cfg_lhs_base + tile_row * lhs_row_stride_b + col_offset）//实际实现中tile_row * lhs_row_stride_b不能用乘法，需要用一个寄存器寄存上一行的地址，然后加上STRIDE
        col_offset = (tile_col_idx * SIZE * (use_16bits ? 16 : 8)) //实际实现中col_offset不能用乘法，需要用一个寄存器寄存上一个tile的列的地址，然后加上SIZE*(use_16bits ? 2 : 1)
 *     - 维护 tile_row_idx、tile_col_idx、loop_row_cnt 等状态变量，
 -  计数当前tile在当前行的cnt，并计算计算当前 Tile 的实际列数（考虑矩阵边界）如果在row_tile_num 内，icb_ext_cmd_m_t.len始终是 SIZE * (use_16bits ? 16 : 8)/`E203_XLEN，如果刚好等于row_tile_num ，这里的读请求得注意，有效行数为=SIZE-row_tile_rem，所以burst len只需要访问有效的这些数据，而如果32字节里面有些数据是无效的，那么读出来之后也不用管，因为在kernel loader那里会把对应的weight置为0
 *   同理，最后一行的tile的无效的行不用发送读请求读  
 - 每一个tile的地址和实际长度算好后就发一次读请求，一个tile读完之后，tile_col_idx++，如果tile_col_idx==row_tile_num,说明这一行的tile读完了，就把tile_col_idx清0，loop_row_cnt++，如果loop_row_cnt==loop_row_num,说明这一行的tile循环读完了，就把基地址加上tile_col_idx還有stride的这些，再把相关的idx清0，继续读下一行tile,tile_row_idx++
        *  
 *    读响应通道
 *     - 将读取的数据缓存到内部行缓冲或Tile缓冲中；当完整Tile可用时置 ia_data_valid=1
 *
 *  3) Send阶段（外部通过 send_ia_trigger 启动逐行发送）
 *     - 当 ia_data_valid=1 且收到 send_ia_trigger 后，模块进入发送阶段（SEND）
 *     - 每个时钟周期输出一行 IA 数据到 ia_out，同时将 ia_row_valid 置1 表示该周期数据有效
 *     - 发送持续 tile 内的行数（最多 SIZE 行，实际行数由矩阵边界决定）tile按行输出。无效的行不输出；无效的列不管，照常输出，因为后面wa（kernel）置为0；
 *     - ia_calc_done: 指示该行为生成最终OA所需的最后一次部分和（用于阵列控制决定是否写回）
 *     - ia_sending_done: 在发送完整个 IA Tile 后置1
 *
 *
 *
 * 信号语义与时序（关键）:
 *  - ia_out [SIZE]: 并行输出的一整行 IA 数据（signed [DATA_WIDTH-1:0]）
 *      * 在 ia_row_valid=1 的周期内，ia_out 上的数据为有效，并可被脉动阵列采样
 *      * 对于未有效元素（矩阵边界处），应由模块在输出时填充0或保持定义的填充值
 *  - ia_row_valid: 与 ia_out 同步的有效指示信号
 *      * 在SEND状态且当模块在某周期输出一行有效数据时置1
 *      * 非发送周期（IDLE/LOAD/行间空闲）保持0，接收方不得采样 ia_out
 *  - ia_data_valid: 指示内部已经完成当前 IA Tile 的全部行读取并可用于发送（Load->Send 的条件）
 *      * ia_data_valid 与 ia_calc_done 保持一致：当 ia_data_valid 为高时，ia_calc_done 同步为高，且两者在相同周期范围内持续输出
 *      * 接收方或上层控制逻辑可使用该组合信号确认当前Tile可用于参与最终OA的部分和累加
 *  - ia_is_init_data: 指示当前Tile是否为该OA累加序列中的第一个IA Tile（用于累加器清零判断），对本模块来说 当前行数据为第一个Tile的数据//与ia_out同步第一个tile一直拉高
 *      * 当为第一个IA Tile时，在该Tile的整个数据有效周期内（与 ia_data_valid 相同）输出高电平，接收阵列可据此清零或初始化累加器
 *      * 该信号应与 ia_data_valid/ia_row_valid 同步输出，以避免采样竞态
 *  - ia_sending_done: 指示当前 IA Tile 的逐行发送已全部完成（SEND 完结）//脉冲拉高一拍
 *  - ia_calc_done: 与 ia_data_valid 同步（见上），用于标记当前Tile在计算流程中的特殊语义（例如表明该Tile为最后一次用于某输出元素的部分和）
 *
 * 重加载逻辑（Reloading）：
 *  - 当一个 IA Tile 的逐行发送完成并且 ia_sending_done 置1 时，模块应自动驱动 load_ia_req=1，申请下一次访存授权。
 *  - 在收到外部调度器的 load_ia_granted 授权后，模块计算下一个 IA Tile 的基地址（基于 cfg_lhs_base 与 tile 索引、cfg_lhs_row_stride_b 等）并进入 LOAD 状态发起读请求。
 * - 当整个 IA 矩阵（k 行 n 列）全部加载完毕后，模块应保持在 IDLE 状态，等待下一次 init_cfg 触发。
 *
 * 边界数据处理（Zero-padding 与 Skip）：
 *  - 在矩阵边界处，某些 Tile 的实际有效行或列可能少于 SIZE 。模块必须在访存与输出时兼顾效率与正确性：
 *    * 跳过完全无效的行/列：对于完全超出原矩阵范围的行/列，模块必须跳过对应的访存操作以节省带宽与延迟。
 *    * 局部读取不用补零：对于部分有效的列 例如最后一个tile只含部分列），不用对剩余位置填充0，因为kernel会将这些位置的权重置为0。
 *    * 
 *  - 在跳过访存的场景下，需保证 ia_data_valid、ia_sending_done 时序仍然正确，避免上层误判数据准备或发送完成。
 */

`include "e203_defines.v"
`include "icb_types.svh"
// //TODO: 零点偏移没有验证  ia_is_init_data,
//  ia_calc_done,  也需要再看看 
// 输入激活加载控制器，双缓冲区交替向脉动阵列加载输入数据
module ia_loader #(
    parameter int unsigned DATA_WIDTH = 16,  // 单个输入数据宽度
    parameter int unsigned SIZE       = 16,  // 输入阵列大小（每行元素数）
    parameter int unsigned BUS_WIDTH  = 32,  // 总线位宽（用于 ICB 数据宽度）
    parameter int unsigned REG_WIDTH  = 32   // 配置寄存器宽度（地址/偏移/零点）
) (
    // 时钟与复位
    input logic clk,   // 时钟信号
    input logic rst_n, // 异步复位，低有效

    // 配置控制接口
    input logic init_cfg,  // 触发配置参数锁存//单拍触发

    // Load/Send 控制接口
    output reg load_ia_req,  // 申请下一次访存授权（输出到外部控制器）//握手
    input logic load_ia_granted,  // 外部控制器授权下一次访存（握手信号）
    input logic send_ia_trigger,  // 触发发送输入激活到脉动阵列//脉冲

    // 矩阵尺寸配置（在 init_cfg 时被锁存）
    input  logic [REG_WIDTH-1:0]        k,                 // 输入激活矩阵行数（RHS_ROWS）// init_cfg高时保证稳定
    input logic [REG_WIDTH-1:0] n,  // 输入激活矩阵列数（RHS_COLS）
    input  logic [REG_WIDTH-1:0]        m,                 // 输出矩阵列数（LHS_COLS），用于计算行的循环次数
    //也就是说对于IA_loader,每一行有row_tile_num=n/ 16向上取整个tile,然后这一行row_tile_num个tile发完后又循环这一行，循环次数为loop_row_num=m/ 16向上取整个tile

    // 配置寄存器（在 init_cfg 时锁存）
    input  logic signed [REG_WIDTH-1:0] lhs_zp,            // 输入激活零点偏移（s32）这个不是地址偏移，是数据偏移，把读到的每个数据加上这个就行，如果上溢就是最大值，下溢就是最小值
    input  logic [REG_WIDTH-1:0]        lhs_row_stride_b,  // 矩阵每两行之间的地址间距（以调用方约定的单位）
    input logic [REG_WIDTH-1:0] lhs_base,  // 读取基地址（第一个分块）
    input  logic                        use_16bits,        // 输入数据类型指示，1为s16，0为s8;对于ia来说，数据可能是s8或者s16,在读取后，如果是s8要拓展符号位先变为signed16再计算后输出

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
    output logic ia_sending_done,  // trigger后，一整个tile已经输出完毕//脉冲
    output logic ia_row_valid,  // 当前行数据有效//与ia_out同步
    output logic                         ia_is_init_data,    // 当前行数据为第一个Tile的数据//与ia_out同步第一个tile一直拉高
    output logic                         ia_calc_done,      // 当前输入的行已经是最后一个tile，部分和将累加得到最终结果//与ia_out同步最后一个tile一直拉高
    output logic signed [DATA_WIDTH-1:0] ia_out [SIZE],      // 输出到脉动阵列的输入数据//tile按行输出。无效的行不输出；无效的列不管，照常输出，因为后面wa（kernel）置为0；

    // 新增输出：当完成所有行读取时指示数据已准备好
    output logic                         ia_data_valid      // 所有行数据已读取完毕并可用于发送，和 send_ia_trigger握手//在LOAD完拉高，LOAD->SEND转换时拉低
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
  reg signed [REG_WIDTH-1:0] cfg_lhs_zp;
  reg [REG_WIDTH-1:0] cfg_lhs_row_stride_b, cfg_lhs_base;
  reg cfg_use_16bits;

  // =========================================================================
  // Tile计算参数
  // =========================================================================
  reg [REG_WIDTH-1:0] row_tile_num;  // 每行tile数量 = ceil(n/SIZE)
  reg [REG_WIDTH-1:0] col_tile_num;  // 列方向tile数量 = ceil(k/SIZE)
  reg [REG_WIDTH-1:0] loop_row_num;  // 行循环次数 = ceil(m/SIZE)
  reg [REG_WIDTH-1:0] row_tile_rem;  // 最后一个行tile无效列数
  reg [REG_WIDTH-1:0] col_tile_rem;  // 最后一个列tile无效行数

  // =========================================================================
  // Tile索引和地址
  // =========================================================================
  reg [REG_WIDTH-1:0] tile_row_idx;  // 当前tile行索引
  reg [REG_WIDTH-1:0] tile_col_idx;  // 当前tile列索引
  reg [REG_WIDTH-1:0] loop_row_cnt;  // 当前行循环计数
  reg [REG_WIDTH-1:0] current_row_base;  // 当前行基地址
  reg [REG_WIDTH-1:0] current_tile_addr;  // 当前tile起始地址

  // =========================================================================
  // 读取控制
  // =========================================================================
  reg [REG_WIDTH-1:0] rows_to_read;  // 当前tile需读取的行数
  reg [REG_WIDTH-1:0] current_read_row;  // 当前读取的行号
  reg [REG_WIDTH-1:0] read_burst_length;  // 读取burst长度
  reg [REG_WIDTH-1:0] current_row_addr;  // 当前读取行的地址（累加寄存器）

  // =========================================================================
  // Tile缓冲区
  // =========================================================================
  reg signed [DATA_WIDTH-1:0] tile_buffer[SIZE][SIZE];
  reg [REG_WIDTH-1:0] valid_rows;  // 缓冲区有效行数
  reg [REG_WIDTH-1:0] valid_cols;  // 缓冲区有效列数

  // =========================================================================
  // 发送控制
  // =========================================================================
  reg [REG_WIDTH-1:0] send_row_idx;
  //reg ia_data_valid;

  // =========================================================================
  // ICB响应接收控制
  // =========================================================================
  reg [REG_WIDTH-1:0] rsp_row_cnt;  // 响应行计数
  reg [REG_WIDTH-1:0] rsp_beat_cnt;  // 响应beat计数

  // 响应通道独立维护的tile参数（在INIT时计算好）
  reg [REG_WIDTH-1:0] rsp_rows_per_tile;  // 每个完整tile的行数 = SIZE
  reg [REG_WIDTH-1:0] rsp_rows_last_tile;  // 最后一个tile的行数 = SIZE - col_tile_rem
  reg [REG_WIDTH-1:0] rsp_beats_per_row_normal;  // 正常tile每行的beat数
  reg [REG_WIDTH-1:0] rsp_beats_per_row_last;  // 最后一列tile每行的beat数

  // 响应通道的tile追踪
  reg [REG_WIDTH-1:0] rsp_tile_row_idx;  // 当前响应的tile行索引
  reg [REG_WIDTH-1:0] rsp_tile_col_idx;  // 当前响应的tile列索引
  reg [REG_WIDTH-1:0] rsp_loop_row_cnt;  // 当前响应的循环计数

  // =========================================================================
  // 辅助信号
  // =========================================================================

  //  wire is_last_col_tile = (tile_col_idx == row_tile_num - 1);
  //  wire is_last_row_tile = (tile_row_idx == col_tile_num - 1);
  // wire is_last_col_tile = (tile_col_idx == col_tile_num - 1);
  // wire is_last_row_tile = (tile_row_idx == row_tile_num - 1);
  // 正确的判断逻辑：!!!!!!
  // tile_col_idx 是列方向索引，应该与 row_tile_num 比较（一行有多少个tile）
  // tile_row_idx 是行方向索引，应该与 col_tile_num 比较（一列有多少个tile）
  wire is_last_col_tile = (tile_col_idx == row_tile_num - 1);
  wire is_last_row_tile = (tile_row_idx == col_tile_num - 1);


  wire is_last_loop = (loop_row_cnt == loop_row_num - 1);
  wire is_first_tile = (tile_col_idx == 0);
  wire cmd_hs = icb_cmd_valid && icb_cmd_ready;
  wire rsp_hs = icb_rsp_valid && icb_rsp_ready;

  localparam int BYTE_PER_BEAT = BUS_WIDTH / 8;

  // =========================================================================
  // 单段式状态机 - 现态更新与次态逻辑合并
  // =========================================================================
  logic is_last_row_tile_dff;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      is_last_row_tile_dff <= 0;
    end else begin
      is_last_row_tile_dff <= is_last_row_tile;
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
          if (load_ia_granted) state <= LOAD;
        end

        LOAD: begin
          // 当所有响应接收完毕时转到SEND
          if (ia_data_valid) state <= SEND;
        end

        SEND: begin
          //if (is_last_row_tile && is_last_col_tile && is_last_loop)
          //if (is_last_row_tile && (tile_col_idx == col_tile_num ) && is_last_loop)
          if (!is_last_row_tile && is_last_row_tile_dff)  // is_last_loop的下降沿
            state <= IDLE;
          else if (load_ia_granted)
            // 等待授权后才进入下一个LOAD
            state <= LOAD;
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
      cfg_lhs_zp <= '0;
      cfg_lhs_row_stride_b <= '0;
      cfg_lhs_base <= '0;
      cfg_use_16bits <= '0;
      row_tile_num <= '0;
      col_tile_num <= '0;
      loop_row_num <= '0;
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
      cfg_lhs_zp <= lhs_zp;
      cfg_lhs_row_stride_b <= lhs_row_stride_b;
      cfg_lhs_base <= lhs_base;
      cfg_use_16bits <= use_16bits;

      // 使用移位和加法替代除法: ceil(n/SIZE) = (n + SIZE - 1) >> log2(SIZE)
      row_tile_num <= (n + SIZE - 1) >> $clog2(SIZE);  // 每行tile数量
      col_tile_num <= (k + SIZE - 1) >> $clog2(SIZE);  // 列方向tile数量
      loop_row_num <= (m + SIZE - 1) >> $clog2(SIZE);  // 行循环次数

      // row_tile_rem = (ceil(n/SIZE) * SIZE) - n
      // 计算最后一个行tile的无效列数
      row_tile_rem <= (((n + SIZE - 1) >> $clog2(SIZE)) << $clog2(SIZE)) - n;
      // 计算最后一个列tile的无效行数
      col_tile_rem <= (((k + SIZE - 1) >> $clog2(SIZE)) << $clog2(SIZE)) - k;

      // =====================================================
      // 响应通道专用参数计算（完全独立于请求通道）
      // =====================================================
      rsp_rows_per_tile <= SIZE;  // 完整tile的行数
      // 最后一个行tile的有效行数 = SIZE - col_tile_rem
      rsp_rows_last_tile <= SIZE - ((((k + SIZE - 1) >> $clog2(SIZE)) << $clog2(SIZE)) - k);

      // 计算每行需要的beat数（正常tile）
      // beats = ceil(SIZE * bytes_per_element / BYTE_PER_BEAT)
      rsp_beats_per_row_normal <= ((SIZE << (use_16bits ? 1 : 0)) + BYTE_PER_BEAT - 1) >> $clog2(
          BYTE_PER_BEAT
      );

      // 计算每行需要的beat数（最后一列tile，可能列数不足）
      // beats = ceil((SIZE - row_tile_rem) * bytes_per_element / BYTE_PER_BEAT)
      rsp_beats_per_row_last <= (((SIZE - (((n + SIZE - 1) >> $clog2(
          SIZE
      )) << $clog2(
          SIZE
      )) + n) << (use_16bits ? 1 : 0)) + BYTE_PER_BEAT - 1) >> $clog2(
          BYTE_PER_BEAT
      );
    end
  end

  // =========================================================================
  // Tile索引管理
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tile_row_idx <= '0;
      tile_col_idx <= '0;
      loop_row_cnt <= '0;
      current_row_base <= '0;
    end else begin
      case (state)
        INIT: begin
          tile_row_idx <= '0;
          tile_col_idx <= '0;
          loop_row_cnt <= '0;
          current_row_base <= cfg_lhs_base;
        end

        SEND: begin
          if (ia_sending_done) begin
            if (is_last_loop && is_last_col_tile) begin
              // 移到下一行tile
              tile_row_idx <= tile_row_idx + 1;
              tile_col_idx <= '0;
              loop_row_cnt <= '0;
              // 更新当前行的基地址，加上一个tile行的地址偏移量
              // cfg_lhs_row_stride_b 是配置的行间距（单位：字节），表示矩阵中相邻两行之间的地址间隔
              // 由于一个 tile 包含 SIZE 行，所以需要跳过 SIZE 行的地址偏移
              // 通过左移 $clog2(SIZE) 位实现乘以 SIZE 的效果（避免使用乘法器以满足时序要求）
              // 例如：SIZE=16 时，$clog2(16)=4，左移4位相当于乘以16
              // 最终地址偏移 = cfg_lhs_row_stride_b * S
              current_row_base <= current_row_base + (cfg_lhs_row_stride_b << $clog2(SIZE));
            end else if (is_last_col_tile) begin
              // 同一行重新开始
              tile_col_idx <= '0;
              loop_row_cnt <= loop_row_cnt + 1;
            end else begin
              // 同一行下一个tile
              tile_col_idx <= tile_col_idx + 1;
            end
          end
        end
      endcase
    end
  end

  // =========================================================================
  // 地址计算
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_tile_addr <= '0;
    end else if (state == INIT) begin
      current_tile_addr <= cfg_lhs_base;
    end else if (state == SEND && ia_sending_done) begin
      // tile发送完成后更新到下一个tile的起始地址
      if (is_last_col_tile && is_last_loop) begin
        // 当前行的所有tile循环都完成了，移到下一行tile的第一个//与384行等价，这里是先把要拿去访存的地址先更新了，384行是先寄存着，方便后续跳回。
        // 下一tile行的地址 = 当前tile行基地址 + SIZE × stride
        current_tile_addr <= current_row_base + (cfg_lhs_row_stride_b << $clog2(SIZE));
      end else if (is_last_col_tile) begin
        // 当前行的tile发完，重新循环这一行，回到第一个tile
        current_tile_addr <= current_row_base;//384行是先寄存着，方便后续跳回。这样不用再减一次，少用一个加法器和移位器
      end else begin
        // 移到同一tile行的下一个tile（列方向）
        // 下一个tile地址 = 当前tile地址 + SIZE个元素的字节数
        current_tile_addr <= current_tile_addr + (SIZE << (cfg_use_16bits ? 1 : 0));
      end
    end
  end

  // =========================================================================
  // 有效行列数计算
  // =========================================================================
  logic [REG_WIDTH-1:0] next_tile_col_idx;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rows_to_read <= '0;
      valid_rows   <= '0;
      valid_cols   <= '0;
    end else if (state == INIT) begin
      // INIT状态就计算好第一个tile的有效行列
      valid_rows   <= (col_tile_num == 1) ? (SIZE - col_tile_rem) : SIZE;
      valid_cols   <= (row_tile_num == 1) ? (SIZE - row_tile_rem) : SIZE;
      rows_to_read <= (col_tile_num == 1) ? (SIZE - col_tile_rem) : SIZE;
    end else if (state == SEND && ia_sending_done) begin
      // SEND完成后，为下一个tile计算有效行列
      // 判断下一个tile的行索引
      logic [REG_WIDTH-1:0] next_tile_row_idx;
      if (is_last_loop && is_last_col_tile) next_tile_row_idx = tile_row_idx + 1;
      else next_tile_row_idx = tile_row_idx;

      // 根据下一个tile的行索引判断是否是最后一行tile
      if (next_tile_row_idx == col_tile_num - 1) begin
        valid_rows   <= SIZE - col_tile_rem;
        rows_to_read <= SIZE - col_tile_rem;
      end else begin
        valid_rows   <= SIZE;
        rows_to_read <= SIZE;
      end

      // 列方向类似
      if (is_last_col_tile) next_tile_col_idx = 0;
      else next_tile_col_idx = tile_col_idx + 1;

      if (next_tile_col_idx == row_tile_num - 1) valid_cols <= SIZE - row_tile_rem;
      else valid_cols <= SIZE;
    end
  end

  assign icb_cmd_len = read_burst_length - 1;
  // =========================================================================
  // ICB读请求发送
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_read_row <= '0;
      read_burst_length <= '1;
      icb_cmd_valid <= '0;
      icb_cmd_read <= '0;
      icb_cmd_addr <= '0;
      current_row_addr <= '0;
    end else begin
      case (state)
        LOAD: begin
          // 当前tile还有行需要读取
          if (current_read_row < rows_to_read) begin
            // 等待上一次请求握手完成或首次发送
            if (!icb_cmd_valid || cmd_hs) begin
              icb_cmd_valid <= 1'b1;
              icb_cmd_read  <= 1'b1;

              // 使用累加寄存器计算地址（避免乘法）
              if (current_read_row == 0) begin
                // 第一行：使用tile基地址
                icb_cmd_addr <= current_tile_addr;
                current_row_addr <= current_tile_addr + cfg_lhs_row_stride_b;
              end else begin
                // 后续行：使用累加的地址
                icb_cmd_addr <= current_row_addr;
                current_row_addr <= current_row_addr + cfg_lhs_row_stride_b;
              end

              current_read_row <= current_read_row + 1;

              // 计算burst长度
              if (is_last_col_tile) begin
                read_burst_length <= (((SIZE - row_tile_rem) << (cfg_use_16bits ? 1 : 0)) + BYTE_PER_BEAT - 1) >> $clog2(
                    BYTE_PER_BEAT);
              end else begin
                read_burst_length <= ((SIZE << (cfg_use_16bits ? 1 : 0)) + BYTE_PER_BEAT - 1) >> $clog2(
                    BYTE_PER_BEAT);
              end
            end
          end else begin
            // 当前tile所有行已发送完读请求
            if (cmd_hs) begin // 等待最后一个请求握手完成
              icb_cmd_valid <= 1'b0;
            end
          end
        end

        default: begin
          current_read_row <= '0;
          icb_cmd_valid <= 1'b0;
          icb_cmd_read <= 1'b0;
          current_row_addr <= '0;
        end
      endcase
    end
  end



  // =========================================================================
  // ICB读响应接收（完全独立的通道）
  // =========================================================================
  // 数据宽度相关参数
  localparam int ELEMENTS_PER_BEAT_S8 = BYTE_PER_BEAT;  // 每个beat包含的s8元素数 (4或8)
  localparam int ELEMENTS_PER_BEAT_S16 = BYTE_PER_BEAT >> 1; // 每个beat包含的s16元素数 (2或4)

  // 列索引计算
  logic [$clog2(SIZE)-1:0] base_col_idx;  // 当前beat对应的起始列索引
  logic [$clog2(SIZE)-1:0] col_idx;
  assign col_idx = cfg_use_16bits ? (rsp_beat_cnt << $clog2(
      ELEMENTS_PER_BEAT_S16
  )) : (rsp_beat_cnt << $clog2(
      ELEMENTS_PER_BEAT_S8
  ));

  // 响应通道辅助信号（根据响应通道自己的tile索引计算）
  wire rsp_is_last_col_tile = (rsp_tile_col_idx == row_tile_num - 1);  // 是否最后一列tile
  wire rsp_is_last_row_tile = (rsp_tile_row_idx == col_tile_num - 1);  // 是否最后一行tile
  wire [REG_WIDTH-1:0] rsp_current_rows = rsp_is_last_row_tile ? rsp_rows_last_tile : rsp_rows_per_tile;      // 当前tile的行数
  wire [REG_WIDTH-1:0] rsp_current_beats = rsp_is_last_col_tile ? rsp_beats_per_row_last : rsp_beats_per_row_normal;  // 当前行的beat数

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_row_cnt <= '0;
      rsp_beat_cnt <= '0;
      icb_rsp_ready <= '0;
      base_col_idx <= '0;

      // 响应通道tile追踪
      rsp_tile_row_idx <= '0;
      rsp_tile_col_idx <= '0;
      rsp_loop_row_cnt <= '0;

      // 初始化tile缓冲区
      for (int i = 0; i < SIZE; i++) begin
        for (int j = 0; j < SIZE; j++) begin
          tile_buffer[i][j] <= '0;
        end
      end
    end else begin
      case (state)
        INIT: begin
          // 响应通道初始化
          rsp_tile_row_idx <= '0;
          rsp_tile_col_idx <= '0;
          rsp_loop_row_cnt <= '0;
          rsp_row_cnt <= '0;
          rsp_beat_cnt <= '0;
        end

        LOAD: begin
          icb_rsp_ready <= 1'b1;

          if (rsp_hs) begin
            // =====================================================
            // 数据解析与存储（修复：先计算列索引，然后再存储）
            // =====================================================
            // 计算当前beat对应的列索引

            // 数据解析与存储
            if (cfg_use_16bits) begin
              // 16位数据模式
              if (BYTE_PER_BEAT == 4) begin
                // 32位总线：每个beat包含2个s16元素
                if (col_idx < SIZE)
                  tile_buffer[rsp_row_cnt][col_idx] <= $signed(
                      icb_rsp_rdata[15:0]
                  ) + cfg_lhs_zp[15:0];
                if (col_idx + 1 < SIZE)
                  tile_buffer[rsp_row_cnt][col_idx+1] <= $signed(
                      icb_rsp_rdata[31:16]
                  ) + cfg_lhs_zp[15:0];
              end
              //  else begin
              //     // 64位总线：每个beat包含4个s16元素
              //     if (col_idx < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx] <= $signed(icb_rsp_rdata[15:0]) + cfg_lhs_zp[15:0];
              //     if (col_idx + 1 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 1] <= $signed(icb_rsp_rdata[31:16]) + cfg_lhs_zp[15:0];
              //     if (col_idx + 2 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 2] <= $signed(icb_rsp_rdata[47:32]) + cfg_lhs_zp[15:0];
              //     if (col_idx + 3 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 3] <= $signed(icb_rsp_rdata[63:48]) + cfg_lhs_zp[15:0];
              // end
            end else begin
              // 8位数据模式（需符号扩展到16位）
              if (BYTE_PER_BEAT == 4) begin
                // 32位总线：每个beat包含4个s8元素
                if (col_idx < SIZE)
                  tile_buffer[rsp_row_cnt][col_idx] <= $signed(
                      {{8{icb_rsp_rdata[7]}}, icb_rsp_rdata[7:0]}
                  ) + cfg_lhs_zp[15:0];
                if (col_idx + 1 < SIZE)
                  tile_buffer[rsp_row_cnt][col_idx+1] <= $signed(
                      {{8{icb_rsp_rdata[15]}}, icb_rsp_rdata[15:8]}
                  ) + cfg_lhs_zp[15:0];
                if (col_idx + 2 < SIZE)
                  tile_buffer[rsp_row_cnt][col_idx+2] <= $signed(
                      {{8{icb_rsp_rdata[23]}}, icb_rsp_rdata[23:16]}
                  ) + cfg_lhs_zp[15:0];
                if (col_idx + 3 < SIZE)
                  tile_buffer[rsp_row_cnt][col_idx+3] <= $signed(
                      {{8{icb_rsp_rdata[31]}}, icb_rsp_rdata[31:24]}
                  ) + cfg_lhs_zp[15:0];
              end
              // else begin
              //     // 64位总线：每个beat包含8个s8元素
              //     if (col_idx < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx] <= $signed({{8{icb_rsp_rdata[7]}}, icb_rsp_rdata[7:0]}) + cfg_lhs_zp[15:0];
              //     if (col_idx + 1 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 1] <= $signed({{8{icb_rsp_rdata[15]}}, icb_rsp_rdata[15:8]}) + cfg_lhs_zp[15:0];
              //     if (col_idx + 2 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 2] <= $signed({{8{icb_rsp_rdata[23]}}, icb_rsp_rdata[23:16]}) + cfg_lhs_zp[15:0];
              //     if (col_idx + 3 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 3] <= $signed({{8{icb_rsp_rdata[31]}}, icb_rsp_rdata[31:24]}) + cfg_lhs_zp[15:0];
              //     if (col_idx + 4 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 4] <= $signed({{8{icb_rsp_rdata[39]}}, icb_rsp_rdata[39:32]}) + cfg_lhs_zp[15:0];
              //     if (col_idx + 5 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 5] <= $signed({{8{icb_rsp_rdata[47]}}, icb_rsp_rdata[47:40]}) + cfg_lhs_zp[15:0];
              //     if (col_idx + 6 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 6] <= $signed({{8{icb_rsp_rdata[55]}}, icb_rsp_rdata[55:48]}) + cfg_lhs_zp[15:0];
              //     if (col_idx + 7 < SIZE)
              //         tile_buffer[rsp_row_cnt][col_idx + 7] <= $signed({{8{icb_rsp_rdata[63]}}, icb_rsp_rdata[63:56]}) + cfg_lhs_zp[15:0];
              // end
            end

            // =====================================================
            // 响应计数器更新
            // =====================================================
            if (rsp_beat_cnt == rsp_current_beats - 1) begin
              rsp_beat_cnt <= '0;

              if (rsp_row_cnt == rsp_current_rows - 1) begin
                // 当前tile的所有行接收完毕
                rsp_row_cnt <= '0;

                if (rsp_tile_col_idx == row_tile_num - 1) begin
                  // 当前行的所有tile接收完
                  rsp_tile_col_idx <= '0;

                  if (rsp_loop_row_cnt == loop_row_num - 1) begin
                    // 当前行循环完成，移到下一行tile
                    rsp_loop_row_cnt <= '0;
                    rsp_tile_row_idx <= rsp_tile_row_idx + 1;
                  end else begin
                    // 继续循环当前行的tile
                    rsp_loop_row_cnt <= rsp_loop_row_cnt + 1;
                  end
                end else begin
                  // 移到当前行的下一个tile
                  rsp_tile_col_idx <= rsp_tile_col_idx + 1;
                end
              end else begin
                // 移到当前tile的下一行
                rsp_row_cnt <= rsp_row_cnt + 1;
              end
            end else begin
              // 继续当前行的下一个beat
              rsp_beat_cnt <= rsp_beat_cnt + 1;
            end
          end
        end

        default: begin
          rsp_row_cnt   <= '0;
          rsp_beat_cnt  <= '0;
          icb_rsp_ready <= '0;
          base_col_idx  <= '0;
        end
      endcase
    end
  end

  // =========================================================================
  // ia_data_valid生成
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ia_data_valid <= '0;
    end else begin
      case (state)
        LOAD: begin
          // 当前tile的最后一个beat接收完成时拉高
          if (rsp_hs && rsp_beat_cnt == rsp_current_beats - 1 && rsp_row_cnt == rsp_current_rows - 1)
            ia_data_valid <= 1'b1;
        end

        SEND: begin
          // 开始发送时拉低
          if (send_ia_trigger || send_row_idx > 0) ia_data_valid <= 1'b0;
        end

        default: ia_data_valid <= '0;
      endcase
    end
  end

  // =========================================================================
  // 发送控制
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      send_row_idx <= '0;
      ia_sending_done <= '0;
    end else begin
      case (state)
        SEND: begin
          //if (send_ia_trigger || (send_row_idx > 0 && send_row_idx < valid_rows)) begin
          //    if (send_row_idx == valid_rows - 1) begin
          if (send_ia_trigger || (send_row_idx > 0 && send_row_idx <= valid_rows)) begin
            if (send_row_idx == valid_rows) begin
              ia_sending_done <= 1'b1;
              send_row_idx <= '0;
            end else begin
              send_row_idx <= send_row_idx + 1;
              ia_sending_done <= 1'b0;
            end
          end else begin
            ia_sending_done <= 1'b0;
          end
        end

        default: begin
          send_row_idx <= '0;
          ia_sending_done <= '0;
        end
      endcase
    end
  end

  // =========================================================================
  // load_ia_req生成
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      load_ia_req <= '0;
    end else begin
      // INIT状态拉高load_ia_req，申请第一个tile的访存授权
      if (state == INIT && !load_ia_req) begin
        load_ia_req <= 1'b1;
      end  // SEND状态发送完成后，如果不是最后一个tile，需要申请下一个tile
      else if (state == SEND && ia_sending_done && 
                 !(is_last_row_tile && is_last_col_tile && is_last_loop) && !load_ia_req) begin
        load_ia_req <= 1'b1;
      end  // 收到授权后拉低
      else if (load_ia_granted) begin
        load_ia_req <= 1'b0;
      end
    end
  end
  // =========================================================================
  // ia_out输出赋值 
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ia_row_valid <= 1'b0;
    end else begin
      if (state == SEND && send_ia_trigger) begin
        ia_row_valid <= 1'b1;
      end  //else if (state == SEND && send_row_idx== valid_rows - 1) begin
      else if (state == SEND && send_row_idx == valid_rows) begin
        ia_row_valid <= 1'b0;
      end
    end
  end
  // =========================================================================
  // 输出赋值
  // =========================================================================
  //assign ia_data_valid = ia_data_valid;
  //assign ia_sending_done = ia_sending_done;
  //assign ia_row_valid = (state == SEND) && (send_row_idx > 0 || send_ia_trigger);
  //assign ia_row_valid = (state == SEND) && (send_row_idx > 0);// || send_ia_trigger);
  assign ia_is_init_data = is_first_tile && (state == SEND);
  assign ia_calc_done = (is_last_col_tile) && (state == SEND) && ia_row_valid;

  generate
    for (genvar i = 0; i < SIZE; i++) begin : gen_ia_out
      assign ia_out[i] = (send_row_idx > 0) ? tile_buffer[send_row_idx - 1][i] : 
                                send_ia_trigger ? tile_buffer[0][i] : '0;
    end
  endgenerate



endmodule
