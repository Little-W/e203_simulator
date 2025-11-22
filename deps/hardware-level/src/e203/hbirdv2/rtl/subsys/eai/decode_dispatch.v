/*
 * AI-DSA Instruction Decoder and Dispatcher
 * 
 * 功能：
 * - 解码 AI-DSA 自定义指令（CUSTOM_1/CUSTOM_3）
 * - 提取配置字段并生成控制信号
 * - 实现指令握手和执行启动逻辑
 */

`include "e203_defines.v"

module decode_dispatch #(
    parameter int unsigned REG_WIDTH = 32
) (
    input wire clk,
    input wire rst_n,

    // 指令输入接口
    input  wire                 decode_inst_valid,
    output wire                 decode_inst_ready,
    input  wire [REG_WIDTH-1:0] instruction,        // 完整指令字
    input  wire [REG_WIDTH-1:0] rs1_val,            // rs1 寄存器值（地址）
    input  wire [REG_WIDTH-1:0] rs2_val,            // rs2 寄存器值（cfg配置字）

    // 执行单元反压信号
    input wire sa_ready,  // 系统就绪信号

    // CSR 单元反压信号
    input wire csr_ready,  // CSR 单元就绪信号

    // WB 单元 stall 信号
    input wire id_stall,  // WB 单元 stall 信号（高电平表示需要暂停）

    // 控制信号输出（计算类指令）
    output reg                 calc_start,       // 计算开始信号（单周期脉冲）
    output reg                 cfg_16bits_ia,    // 使用16位IA数据
    output reg                 use_per_channel,  // 使用per-channel量化
    output reg [REG_WIDTH-1:0] dst_base,         // 输出地址

    // CSR 单元输出接口
    output reg [REG_WIDTH-1:0] csr_wdata,    // CSR 写数据
    output reg                 csr_req,      // CSR 请求信号（单周期脉冲）
    output reg                 is_csr_read,  // CSR 读操作标志
    output reg [         11:0] csr_addr      // CSR 地址（imm[11:0]）
);

    // ========================================================================
    // 指令字段定义
    // ========================================================================
    localparam OPCODE_CUSTOM_1 = 7'b0101011;  // CUSTOM_1
    localparam OPCODE_CUSTOM_3 = 7'b1111011;  // CUSTOM_3

    localparam FUNCT7_MAT_MULT_T = 7'b0000001;
    localparam FUNCT3_RD_RS1_RS2 = 3'b111;
    localparam FUNCT3_CSR_WR = 3'b010;
    localparam FUNCT3_CSR_RD = 3'b100;

    // 指令字段提取
    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];
    wire [11:0] imm12 = instruction[31:20];  // I-type 立即数（CSR地址）

    // ========================================================================
    // cfg 配置字段解析（来自 rs2）
    // ========================================================================
    wire [2:0] cfg_out_w = rs2_val[2:0];  // 输出位宽
    wire [1:0] cfg_bias_w = rs2_val[4:3];  // bias位宽
    wire [1:0] cfg_b_w = rs2_val[6:5];  // 右乘数B位宽
    wire [1:0] cfg_a_w = rs2_val[8:7];  // 左乘数A位宽
    wire cfg_per_ch = rs2_val[9];  // 量化模式：0=per-tensor，1=per-channel

    // A_W 编码：00=s4, 01=s8, 10=s16
    wire is_a_16bits = (cfg_a_w == 2'b10);

    // ========================================================================
    // 指令识别
    // ========================================================================
    wire is_mat_mult_t = (opcode == OPCODE_CUSTOM_1) && 
                         (funct7 == FUNCT7_MAT_MULT_T) && 
                         (funct3 == FUNCT3_RD_RS1_RS2);

    wire is_csr_wr = (opcode == OPCODE_CUSTOM_3) && (funct3 == FUNCT3_CSR_WR);
    wire is_csr_rd = (opcode == OPCODE_CUSTOM_3) && (funct3 == FUNCT3_CSR_RD);

    wire is_valid_inst = is_mat_mult_t || is_csr_wr || is_csr_rd;

    // CSR 指令标志
    wire is_csr_inst = is_csr_wr || is_csr_rd;

    // ========================================================================
    // 握手协议（考虑不同指令类型的反压和全局 stall）
    // ========================================================================
    // 根据指令类型选择对应的 ready 信号
    // - 计算类指令：等待 sa_ready
    // - CSR 指令：等待 csr_ready
    wire target_ready = is_csr_inst ? csr_ready : sa_ready;

    // decode_inst_ready 同时考虑指令类型反压和全局 stall
    assign decode_inst_ready = target_ready && !id_stall;

    // 握手成功条件
    wire inst_handshake = decode_inst_valid && decode_inst_ready && is_valid_inst;

    // ========================================================================
    // 时序逻辑：生成控制信号
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calc_start      <= 1'b0;
            cfg_16bits_ia   <= 1'b0;
            use_per_channel <= 1'b0;
            dst_base        <= {REG_WIDTH{1'b0}};
            csr_wdata       <= {REG_WIDTH{1'b0}};
            csr_req         <= 1'b0;
            is_csr_read     <= 1'b0;
            csr_addr        <= 12'b0;
        end else begin
            // 默认单周期脉冲信号复位
            calc_start <= 1'b0;
            csr_req    <= 1'b0;

            // 指令握手成功时
            if (inst_handshake) begin
                if (is_mat_mult_t) begin
                    // 拉高 calc_start 一个周期
                    calc_start      <= 1'b1;

                    // 提取配置
                    cfg_16bits_ia   <= is_a_16bits;
                    use_per_channel <= cfg_per_ch;
                    dst_base        <= rs1_val;  // rs1 为输出起始地址
                end else if (is_csr_wr) begin
                    // CSR 写操作：csrwr rs1, imm12
                    // CSR[imm12] ← rs1
                    csr_req     <= 1'b1;
                    is_csr_read <= 1'b0;
                    csr_addr    <= imm12;
                    csr_wdata   <= rs1_val;
                end else if (is_csr_rd) begin
                    // CSR 读操作：csrrd rd, imm12
                    // rd ← CSR[imm12]
                    csr_req     <= 1'b1;
                    is_csr_read <= 1'b1;
                    csr_addr    <= imm12;
                    csr_wdata   <= {REG_WIDTH{1'b0}};  // 读操作不使用wdata
                end
            end
        end
    end

    // ========================================================================
    // 可选：调试信号
    // ========================================================================
`ifdef DEBUG_DECODER
    always @(posedge clk) begin
        if (inst_handshake) begin
            if (is_mat_mult_t) begin
                $display("[Decoder] mat_mult_t: dst_base=0x%h, A_W=%0d, cfg_16bits_ia=%0d, per_ch=%0d",
                         rs1_val, cfg_a_w, is_a_16bits, cfg_per_ch);
            end else if (is_csr_wr) begin
                $display("[Decoder] csrwr: CSR[0x%h] <- 0x%h", imm12, rs1_val);
            end else if (is_csr_rd) begin
                $display("[Decoder] csrrd: rd <- CSR[0x%h]", imm12);
            end
        end
    end
`endif

endmodule
