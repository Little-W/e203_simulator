`include "e203_defines.v"

module csr_unit #(
    parameter REG_WIDTH = 32
) (
    input wire clk,
    input wire rst_n,

    // CSR 读写接口
    input  wire                 csr_req,      // CSR 请求
    input  wire                 is_csr_read,  // 1=读, 0=写
    input  wire [         11:0] csr_addr,     // CSR 地址
    input  wire [REG_WIDTH-1:0] csr_wdata,    // 写数据
    output reg                  csr_ready,    // 就绪信号
    output reg  [REG_WIDTH-1:0] csr_rdata,    // 读数据

    // CSR 写回接口（用于 CSR 读操作的响应）
    output reg                  csr_wb_valid,  // 写回有效
    input  wire                 csr_wb_ready,  // 写回就绪
    output reg  [REG_WIDTH-1:0] csr_wb_data,   // 写回数据

    // ========================================================================
    // CSR 输出值（供执行单元使用）
    // ========================================================================

    // --- Base Pointers ---
    output wire [REG_WIDTH-1:0] lhs_base,  // A base (MULT_LHS_PTR)
    output wire [REG_WIDTH-1:0] rhs_base,  // B base (MULT_RHS_PTR)
    output wire [REG_WIDTH-1:0] dst_base,  // C base (MULT_DST_PTR)
    output wire [REG_WIDTH-1:0] bias_base, // bias (MULT_BIAS_PTR)

    // --- Quantization & Zero-points ---
    output wire signed [REG_WIDTH-1:0] lhs_zp,     // A zero-point (MULT_LHS_OFFSET)
    output wire signed [REG_WIDTH-1:0] rhs_zp,     // B zero-point (MULT_RHS_OFFSET)
    output wire signed [REG_WIDTH-1:0] dst_zp,     // C zero-point (MULT_DST_OFFSET)
    output wire signed [REG_WIDTH-1:0] q_mult_pt,  // per-tensor mult (MULT_DST_MULT)
    output wire signed [REG_WIDTH-1:0] q_shift_pt, // per-tensor shift (MULT_DST_SHIFT)

    // --- Dimensions ---
    output wire [REG_WIDTH-1:0] m,  // M (MULT_LHS_ROWS)
    output wire [REG_WIDTH-1:0] k,  // K (MULT_RHS_COLS)
    output wire [REG_WIDTH-1:0] n,  // N (MULT_RHS_ROWS)

    // --- Row Strides (in BYTES) ---
    output wire [REG_WIDTH-1:0] lhs_row_stride_b,  // A row stride (MULT_LHS_ROW_STRIDE)
    output wire [REG_WIDTH-1:0] dst_row_stride_b,  // C row stride (MULT_DST_ROW_STRIDE)
    output wire [REG_WIDTH-1:0] rhs_col_stride_b,  // B col stride (MULT_RHS_COL_STRIDE)

    // --- Activation Clamp ---
    output wire signed [REG_WIDTH-1:0] act_min,  // MULT_ACT_MIN
    output wire signed [REG_WIDTH-1:0] act_max   // MULT_ACT_MAX
);

    // ========================================================================
    // CSR 地址定义（MULT 组）
    // ========================================================================
    // --- Pointer CSRs ---
    localparam MULT_LHS_PTR = 12'h7C0;
    localparam MULT_RHS_PTR = 12'h7C1;
    localparam MULT_DST_PTR = 12'h7C2;
    localparam MULT_BIAS_PTR = 12'h7C3;

    // --- Dimension/Stride CSRs ---
    localparam MULT_LHS_ROWS = 12'h7C4;        // K (A 的行数)
    localparam MULT_RHS_COLS = 12'h7C5;        // N (B 的行数/内积长度)
    localparam MULT_RHS_ROWS = 12'h7C6;        // M (B 的列数/输出通道数)
    localparam MULT_DST_ROW_STRIDE = 12'h7C7; // C 行步长
    localparam MULT_LHS_ROW_STRIDE = 12'h7C8; // A 行步长
    localparam MULT_RHS_COL_STRIDE = 12'h7C9; // B 列步长

    // --- Quantization/Activation CSRs ---
    localparam MULT_LHS_OFFSET = 12'h7CA;  // A 零点偏移
    localparam MULT_RHS_OFFSET = 12'h7CB;  // B 零点偏移
    localparam MULT_DST_OFFSET = 12'h7CC;  // 输出零点
    localparam MULT_DST_MULT = 12'h7CD;    // per-tensor mult 或 per-channel mult 指针
    localparam MULT_DST_SHIFT = 12'h7CE;   // per-tensor shift 或 per-channel shift 指针
    localparam MULT_ACT_MIN = 12'h7CF;     // 激活下限
    localparam MULT_ACT_MAX = 12'h7D0;     // 激活上限

    // ========================================================================
    // CSR 寄存器定义
    // ========================================================================
    // --- Pointers ---
    reg        [REG_WIDTH-1:0] csr_lhs_base;
    reg        [REG_WIDTH-1:0] csr_rhs_base;
    reg        [REG_WIDTH-1:0] csr_dst_base;
    reg        [REG_WIDTH-1:0] csr_bias_base;

    // --- Dimensions ---
    reg        [REG_WIDTH-1:0] csr_k;  // K (A 的行数)
    reg        [REG_WIDTH-1:0] csr_n;  // N (B 的行数/内积长度)
    reg        [REG_WIDTH-1:0] csr_m;  // M (B 的列数/输出通道数)

    // --- Strides ---
    reg        [REG_WIDTH-1:0] csr_dst_row_stride_b;  // MULT_DST_ROW_STRIDE
    reg        [REG_WIDTH-1:0] csr_lhs_row_stride_b;  // MULT_LHS_ROW_STRIDE
    reg        [REG_WIDTH-1:0] csr_rhs_col_stride_b;  // MULT_RHS_COL_STRIDE

    // --- Quantization ---
    reg signed [REG_WIDTH-1:0] csr_lhs_zp;      // MULT_LHS_OFFSET
    reg signed [REG_WIDTH-1:0] csr_rhs_zp;      // MULT_RHS_OFFSET
    reg signed [REG_WIDTH-1:0] csr_dst_zp;      // MULT_DST_OFFSET
    reg signed [REG_WIDTH-1:0] csr_q_mult_pt;   // MULT_DST_MULT
    reg signed [REG_WIDTH-1:0] csr_q_shift_pt;  // MULT_DST_SHIFT

    // --- Activation ---
    reg signed [REG_WIDTH-1:0] csr_act_min;  // MULT_ACT_MIN
    reg signed [REG_WIDTH-1:0] csr_act_max;  // MULT_ACT_MAX

    // ========================================================================
    // 输出连接
    // ========================================================================
    assign lhs_base         = csr_lhs_base;
    assign rhs_base         = csr_rhs_base;
    assign dst_base         = csr_dst_base;
    assign bias_base        = csr_bias_base;

    assign k                = csr_k;  // K (A 的行数)
    assign n                = csr_n;  // N (B 的行数/内积长度)
    assign m                = csr_m;  // M (B 的列数/输出通道数)

    assign lhs_row_stride_b = csr_lhs_row_stride_b;
    assign dst_row_stride_b = csr_dst_row_stride_b;
    assign rhs_col_stride_b = csr_rhs_col_stride_b;

    assign lhs_zp           = csr_lhs_zp;
    assign rhs_zp           = csr_rhs_zp;
    assign dst_zp           = csr_dst_zp;
    assign q_mult_pt        = csr_q_mult_pt;
    assign q_shift_pt       = csr_q_shift_pt;

    assign act_min          = csr_act_min;
    assign act_max          = csr_act_max;

    // ========================================================================
    // CSR 写操作
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all CSRs to 0
            csr_lhs_base         <= {REG_WIDTH{1'b0}};
            csr_rhs_base         <= {REG_WIDTH{1'b0}};
            csr_dst_base         <= {REG_WIDTH{1'b0}};
            csr_bias_base        <= {REG_WIDTH{1'b0}};
            csr_k                <= {REG_WIDTH{1'b0}};
            csr_n                <= {REG_WIDTH{1'b0}};
            csr_m                <= {REG_WIDTH{1'b0}};
            csr_lhs_row_stride_b <= {REG_WIDTH{1'b0}};
            csr_dst_row_stride_b <= {REG_WIDTH{1'b0}};
            csr_rhs_col_stride_b <= {REG_WIDTH{1'b0}};
            // Cast resets to signed to avoid unsigned->signed warnings in DC
            csr_lhs_zp           <= $signed({REG_WIDTH{1'b0}});
            csr_rhs_zp           <= $signed({REG_WIDTH{1'b0}});
            csr_dst_zp           <= $signed({REG_WIDTH{1'b0}});
            csr_q_mult_pt        <= $signed({REG_WIDTH{1'b0}});
            csr_q_shift_pt       <= $signed({REG_WIDTH{1'b0}});
            csr_act_min          <= $signed({REG_WIDTH{1'b0}});
            csr_act_max          <= $signed({REG_WIDTH{1'b0}});
        end else if (csr_req && !is_csr_read) begin
            // Write operation
            case (csr_addr)
                MULT_LHS_PTR:  csr_lhs_base <= csr_wdata;
                MULT_RHS_PTR:  csr_rhs_base <= csr_wdata;
                MULT_DST_PTR:  csr_dst_base <= csr_wdata;
                MULT_BIAS_PTR: csr_bias_base <= csr_wdata;

                MULT_LHS_ROWS:        csr_k <= csr_wdata;  // K
                MULT_RHS_COLS:        csr_n <= csr_wdata;  // N
                MULT_RHS_ROWS:        csr_m <= csr_wdata;  // M
                MULT_DST_ROW_STRIDE: csr_dst_row_stride_b <= csr_wdata;
                MULT_LHS_ROW_STRIDE: csr_lhs_row_stride_b <= csr_wdata;
                MULT_RHS_COL_STRIDE: csr_rhs_col_stride_b <= csr_wdata;

                MULT_LHS_OFFSET: csr_lhs_zp <= $signed(csr_wdata);
                MULT_RHS_OFFSET: csr_rhs_zp <= $signed(csr_wdata);
                MULT_DST_OFFSET: csr_dst_zp <= $signed(csr_wdata);
                MULT_DST_MULT:   csr_q_mult_pt <= $signed(csr_wdata);
                MULT_DST_SHIFT:  csr_q_shift_pt <= $signed(csr_wdata);
                MULT_ACT_MIN:    csr_act_min <= $signed(csr_wdata);
                MULT_ACT_MAX:    csr_act_max <= $signed(csr_wdata);

                default: ;  // Ignore writes to unimplemented CSRs
            endcase
        end
    end

    // ========================================================================
    // CSR 读操作
    // ========================================================================
    always @(*) begin
        if (csr_req && is_csr_read) begin
            case (csr_addr)
                MULT_LHS_PTR:  csr_rdata = csr_lhs_base;
                MULT_RHS_PTR:  csr_rdata = csr_rhs_base;
                MULT_DST_PTR:  csr_rdata = csr_dst_base;
                MULT_BIAS_PTR: csr_rdata = csr_bias_base;

                MULT_LHS_ROWS:        csr_rdata = csr_k;   // K
                MULT_RHS_COLS:        csr_rdata = csr_n;   // N
                MULT_RHS_ROWS:        csr_rdata = csr_m;   // M
                MULT_DST_ROW_STRIDE: csr_rdata = csr_dst_row_stride_b;
                MULT_LHS_ROW_STRIDE: csr_rdata = csr_lhs_row_stride_b;
                MULT_RHS_COL_STRIDE: csr_rdata = csr_rhs_col_stride_b;

                // Cast signed CSRs to unsigned bus width for readback
                MULT_LHS_OFFSET: csr_rdata = $unsigned(csr_lhs_zp);
                MULT_RHS_OFFSET: csr_rdata = $unsigned(csr_rhs_zp);
                MULT_DST_OFFSET: csr_rdata = $unsigned(csr_dst_zp);
                MULT_DST_MULT:   csr_rdata = $unsigned(csr_q_mult_pt);
                MULT_DST_SHIFT:  csr_rdata = $unsigned(csr_q_shift_pt);
                MULT_ACT_MIN:    csr_rdata = $unsigned(csr_act_min);
                MULT_ACT_MAX:    csr_rdata = $unsigned(csr_act_max);

                default: csr_rdata = {REG_WIDTH{1'b0}};  // Unimplemented CSRs return 0
            endcase
        end else begin
            csr_rdata = {REG_WIDTH{1'b0}};
        end
    end

    // ========================================================================
    // CSR Ready 信号（单周期响应）
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_ready <= 1'b1;
        end else begin
            // CSR 访问单周期完成，始终 ready
            csr_ready <= 1'b1;
        end
    end

    // ========================================================================
    // CSR 写回逻辑（读写操作都返回响应）
    // ========================================================================
    always @(*) begin
        csr_wb_valid = csr_req;
        csr_wb_data = is_csr_read ? csr_rdata : {REG_WIDTH{1'b0}};
    end

    // ========================================================================
    // Optional: Debug signals
    // ========================================================================
`ifdef DEBUG_CSR
    always @(posedge clk) begin
        if (csr_req && !is_csr_read) begin
            $display("[CSR] Write: addr=0x%h, data=0x%h", csr_addr, csr_wdata);
        end
        if (csr_req && is_csr_read) begin
            $display("[CSR] Read: addr=0x%h, data=0x%h", csr_addr, csr_rdata);
        end
    end
`endif

endmodule
