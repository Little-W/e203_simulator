 //`include "define.svh"
 `include "e203_defines.v"
`include "icb_types.svh"

// MMA(Matrix Multiply Accumulate) Controller
//
// ==== 参数配置规则 ====
// 1. 基地址指针 (base pointers):
//    - lhs_base:  A 矩阵基地址，不允许为 0
//    - rhs_base:  B 矩阵基地址，不允许为 0
//    - dst_base:  C 矩阵基地址，不允许为 0
//    - bias_base: 偏置基地址，允许为 0（表示无偏置）
//
// 2. 矩阵维度 (dimensions):
//    - k: A 矩阵行数 / B 矩阵列数，不允许为 0
//    - n: B 矩阵行数 / C 矩阵行数，不允许为 0
//    - m: B 矩阵列数 / C 矩阵列数，不允许为 0
//
// 3. 行步长 (row strides):
//    - lhs_row_stride_b: A 矩阵行步长（字节），不允许为 0
//    - rhs_col_stride_b: B 矩阵行步长（字节），不允许为 0
//    - dst_row_stride_b: C 矩阵行步长（字节），不允许为 0
//
// 4. 量化参数 (quantization):
//    - 当 use_per_channel = 1 时，q_mult_pt 和 q_shift_pt 不允许为 0
//    - 当 use_per_channel = 0 时，无此限制（per-tensor 模式下可为 0）
//
// 5. 错误码 (err_code):
//    - 2'b00: 正常完成
//    - 2'b01: 无效/不支持的配置（非法参数组合）
//    - 2'b10: 必需资源缺失或指针为 0
//
module mma_controller #(
    parameter int unsigned WEIGHT_WIDTH = 8,   // 权重数据宽度
    parameter int unsigned DATA_WIDTH   = 16,  // IA数据宽度
    parameter int unsigned SIZE         = 16,  // 阵列大小
    parameter int unsigned BUS_WIDTH    = 32,  // 总线宽度
    parameter int unsigned REG_WIDTH    = 32   // 寄存器宽度
) (
    //==== Clock & Control Signals ====
    input  wire clk,            // 时钟
    input  wire rst_n,          // 异步复位，低有效
    input  wire calc_start,     // 计算开始
    input  wire cfg_16bits_ia,  // 使用16位IA数据
    output wire sa_ready,       // 控制器就绪

    //==== Configuration Parameters ====
    // Base pointers
    input logic [REG_WIDTH-1:0] lhs_base,  // A base         (MULT_LHS_PTR)
    input logic [REG_WIDTH-1:0] rhs_base,  // B base (s8)    (MULT_RHS_PTR, N x K row-major)
    input logic [REG_WIDTH-1:0] dst_base,  // C base (s8)    (MULT_DST_PTR)
    input logic [REG_WIDTH-1:0] bias_base, // bias s32 (0=none)   (MULT_BIAS_PTR)

    // Quantization & zero-points
    input logic signed [REG_WIDTH-1:0] q_mult_pt,  // per-tensor mult     (MULT_DST_MULT)
    input logic signed [REG_WIDTH-1:0] q_shift_pt,      // per-tensor rshift   (MULT_DST_SHIFT, +N => >>N)
    input logic use_per_channel,  // 1: per-channel; 0: per-tensor

    // Dimensions
    input logic [REG_WIDTH-1:0] k,  // (MULT_LHS_ROWS)
    input logic [REG_WIDTH-1:0] n,  // (MULT_RHS_ROWS)
    input logic [REG_WIDTH-1:0] m,  // (MULT_RHS_COLS)

    // Row strides (all in BYTES)
    input logic [REG_WIDTH-1:0] lhs_row_stride_b,  // A row stride       (MULT_LHS_COLS_OFFSET)
    input logic [REG_WIDTH-1:0] dst_row_stride_b,  // C row stride       (MULT_ROW_ADDR_OFFSET)
    input logic [REG_WIDTH-1:0] rhs_col_stride_b,  // B row stride       (MULT_RHS_ROW_STRIDE)

    //==== Control Signals ====
    output reg [          2:0] icb_sel,           // ICB多路复用器选择信号
    output reg                 init_cfg_ia,       // IA Loader 配置初始化（单拍）
    output reg                 init_cfg_weight,   // Kernel Loader 配置初始化（单拍）
    output reg                 init_cfg_bias,     // Bias Loader 配置初始化（单拍）
    output reg                 init_cfg_requant,  // Vec Requant 配置初始化（单拍）
    output reg                 init_cfg_oa,       // OA Writer 配置初始化（单拍）
    output reg                 use_16bits,        // 16位数据指示信号

    //==== Compute Core Interface ====
    input wire partial_sum_calc_over,  // 部分和计算结束

    //==== IA Loader Interface ====
    input  wire load_ia_req,      // IA加载请求
    output reg  load_ia_granted,  // IA加载授权
    output reg  send_ia_trigger,  // IA发送触发
    input  wire ia_sending_done,  // IA发送完成
    input  wire ia_data_valid,    // IA数据有效

    //==== Weight Loader Interface ====
    input  wire load_weight_req,      // 权重加载请求
    output reg  load_weight_granted,  // 权重加载授权
    output reg  send_weight_trigger,  // 权重发送触发
    input  wire weight_sending_done,  // 权重发送完成
    input  wire weight_data_valid,    // 权重数据有效

    //==== Bias Loader Interface ====
    input  wire load_bias_req,      // 偏置加载请求
    output reg  load_bias_granted,  // 偏置加载授权
    input  wire bias_valid,         // 偏置数据有效

    // Requantization Interface
    input  wire load_quant_req,      // 申请下一次量化参数访存
    output wire load_quant_granted,  // 量化参数访存授权
    input  wire quant_params_valid,  // 量化参数有效

    //==== FIFO Interface ====
    input wire fifo_full_flag,  // FIFO满信号

    //==== OA Writer Interface ====
    input  wire write_oa_req,      // OA写回请求
    output reg  write_oa_granted,  // OA写回授权
    input  wire write_done,        // 写回完成
    input  wire oa_calc_over,      // OA计算完成

    //==== Writeback Handshake Interface ====
    output reg        wb_valid,  // 写回有效信号
    input  wire       wb_ready,  // 写回就绪信号
    output reg  [1:0] err_code   // 写回状态码: 00=正常, 01=配置错误, 10=资源缺失
);

    // 状态机定义
    typedef enum logic [3:0] {
        IDLE = 4'b0000,
        INIT = 4'b0001,
        WEIGHT_START = 4'b0010,
        IA_START = 4'b0011,
        WAIT_PARTIAL_SUM = 4'b0100,
        WEIGHT_WAIT = 4'b0101,  // 在发送权重触发后等待发送完成
        IA_WAIT = 4'b0110,      // 在发送IA触发后等待发送完成（保证单拍脉冲）
        WAIT_WB = 4'b0111,      // 等待写回握手完成
        ERROR = 4'b1000         // 参数配置错误状态
    } state_t;

    state_t current_state, next_state;
    reg       cfg_16bits_ia_reg;  // 锁存的16位IA配置
    reg       config_error;  // 参数配置错误标志
    reg [1:0] error_type;  // 错误类型: 01=配置错误, 10=资源缺失

    // 参数校验函数
    function automatic logic check_config_valid();
        logic ptr_error;
        logic dim_error;
        logic stride_error;
        logic quant_error;

        // 检查必需指针（bias_base 允许为 0）
        ptr_error = (lhs_base == '0) || (rhs_base == '0) || (dst_base == '0);

        // 检查矩阵维度
        dim_error = (k == '0) || (n == '0) || (m == '0);

        // 检查行步长
        stride_error = (lhs_row_stride_b == '0) || (rhs_col_stride_b == '0) || (dst_row_stride_b == '0);

        // 检查量化参数（仅当 use_per_channel = 1 时）
        quant_error = use_per_channel && (q_mult_pt == '0) && (q_shift_pt == '0);

        return ptr_error || dim_error || stride_error || quant_error;
    endfunction

    // 确定错误类型
    function automatic logic [1:0] get_error_type();
        logic ptr_error;
        logic config_err;

        // 必需资源缺失（指针错误）
        ptr_error = (lhs_base == '0) || (rhs_base == '0) || (dst_base == '0);

        // 配置错误（维度、步长、量化参数）
        config_err = (k == '0) || (n == '0) || (m == '0) ||
                     (lhs_row_stride_b == '0) || (rhs_col_stride_b == '0) || (dst_row_stride_b == '0) ||
                     (use_per_channel && ((q_mult_pt == '0) || (q_shift_pt == '0)));

        if (ptr_error) return 2'b10;  // 资源缺失
        else if (config_err) return 2'b01;  // 配置错误
        else return 2'b00;  // 无错误
    endfunction

    // 状态寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state     <= IDLE;
            cfg_16bits_ia_reg <= 1'b0;
            config_error      <= 1'b0;
            error_type        <= 2'b00;
        end else begin
            current_state <= next_state;
            if (current_state == IDLE && calc_start) begin
                cfg_16bits_ia_reg <= cfg_16bits_ia;
                // 在收到 calc_start 时检查参数配置
                config_error      <= check_config_valid();
                error_type        <= get_error_type();
            end
        end
    end

    // 状态转换逻辑
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (calc_start) begin
                    // 检查参数配置，如果有错误则进入 ERROR 状态
                    if (check_config_valid()) begin
                        next_state = ERROR;
                    end else begin
                        next_state = INIT;
                    end
                end
            end

            INIT: begin
                next_state = WEIGHT_START;
            end

            WEIGHT_START: begin
                if (oa_calc_over) begin
                    // 当计算完成时，检查写回握手
                    if (wb_ready) begin
                        next_state = IDLE;
                    end else begin
                        next_state = WAIT_WB;
                    end
                end else if (weight_data_valid && !weight_sending_done) begin
                    next_state = WEIGHT_WAIT;
                end
            end

            // 新增等待状态：在发出触发后等待 weight_sending_done 完成
            WEIGHT_WAIT: begin
                if (oa_calc_over) begin
                    // 当计算完成时，检查写回握手
                    if (wb_ready) begin
                        next_state = IDLE;
                    end else begin
                        next_state = WAIT_WB;
                    end
                end else if (weight_sending_done) begin
                    next_state = IA_START;
                end
            end

            IA_START: begin
                // 如果满足发送条件，发出一次触发并进入 IA_WAIT（保证触发为单拍）
                if (ia_data_valid && bias_valid && quant_params_valid && 
                         !fifo_full_flag && !ia_sending_done) begin
                    next_state = IA_WAIT;
                end
            end

            // 新增 IA_WAIT：在发出 IA 触发后等待 ia_sending_done 完成
            IA_WAIT: begin
                if (ia_sending_done) begin
                    next_state = WAIT_PARTIAL_SUM;
                end
            end

            WAIT_PARTIAL_SUM: begin
                if (partial_sum_calc_over) begin
                    next_state = WEIGHT_START;
                end
            end

            // 新增 WAIT_WB 状态：等待写回握手完成
            WAIT_WB: begin
                if (wb_ready) begin
                    next_state = IDLE;
                end
            end

            // 新增 ERROR 状态：等待写回握手完成后返回 IDLE
            ERROR: begin
                if (wb_ready) begin
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // 输出逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cfg_ia         <= 1'b0;
            init_cfg_weight     <= 1'b0;
            init_cfg_bias       <= 1'b0;
            init_cfg_requant    <= 1'b0;
            init_cfg_oa         <= 1'b0;
            use_16bits          <= 1'b0;
            send_weight_trigger <= 1'b0;
            send_ia_trigger     <= 1'b0;
            err_code            <= 2'b00;
        end else begin
            // 默认值
            init_cfg_ia         <= 1'b0;
            init_cfg_weight     <= 1'b0;
            init_cfg_bias       <= 1'b0;
            init_cfg_requant    <= 1'b0;
            init_cfg_oa         <= 1'b0;
            send_weight_trigger <= 1'b0;
            send_ia_trigger     <= 1'b0;

            case (current_state)
                IDLE: begin
                    err_code <= 2'b00;  // 清除错误码
                end

                INIT: begin
                    // 初始化所有模块（单拍脉冲）
                    init_cfg_ia      <= 1'b1;
                    init_cfg_weight  <= 1'b1;
                    init_cfg_bias    <= 1'b1;
                    init_cfg_requant <= 1'b1;
                    init_cfg_oa      <= 1'b1;
                    use_16bits       <= cfg_16bits_ia_reg;
                end

                WEIGHT_START: begin
                    // 仅在 WEIGHT_START 一拍内发出发送触发，之后转到 WEIGHT_WAIT 等待完成 -> 保证单拍脉冲
                    if (weight_data_valid && !weight_sending_done) begin
                        send_weight_trigger <= 1'b1;
                    end
                end

                WEIGHT_WAIT: begin
                    // 等待 weight_sending_done 完成，不重复发出触发
                end

                IA_START: begin
                    // 仅在 IA_START 一拍内发出发送触发，之后转到 IA_WAIT 等待完成 -> 保证单拍脉冲
                    if (ia_data_valid && bias_valid && quant_params_valid && 
                        !fifo_full_flag && !ia_sending_done) begin
                        send_ia_trigger <= 1'b1;
                    end
                end

                IA_WAIT: begin
                    // 等待 ia_sending_done 完成，不重复发出触发
                end

                ERROR: begin
                    // 设置错误码
                    err_code <= error_type;
                end

                default: begin
                end
            endcase
        end
    end

    // sa_ready信号
    assign sa_ready = (current_state == IDLE);

    // 写回有效信号
    wire wb_valid_next = oa_calc_over || (current_state == WAIT_WB) || (current_state == ERROR);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_valid <= 1'b0;
        end else begin
            wb_valid <= wb_valid_next;
        end
    end

    // 实例化ICB仲裁器
    icb_arbiter u_icb_arbiter (
        .clk       (clk),
        .rst_n     (rst_n),
        // IA Loader
        .s0_req    (load_ia_req),
        .s0_granted(load_ia_granted),
        .s0_done   (ia_data_valid),
        // Kernel Loader
        .s1_req    (load_weight_req),
        .s1_granted(load_weight_granted),
        .s1_done   (weight_data_valid),
        // Bias Loader
        .s2_req    (load_bias_req),
        .s2_granted(load_bias_granted),
        .s2_done   (bias_valid),
        // Vec Requant
        .s3_req    (load_quant_req),
        .s3_granted(load_quant_granted),
        .s3_done   (quant_params_valid),
        // OA Writer
        .s4_req    (write_oa_req),
        .s4_granted(write_oa_granted),
        .s4_done   (write_done),
        // ICB选择
        .icb_sel   (icb_sel)
    );

endmodule
