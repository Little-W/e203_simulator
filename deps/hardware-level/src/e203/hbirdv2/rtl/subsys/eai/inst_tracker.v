`include "e203_defines.v"

module inst_tracker (
    input wire clk,
    input wire rst_n,

    // MMA 指令启动信号
    input  wire calc_start,        // MMA 指令开始执行

    // MMA 写回握手信号
    input  wire mma_wb_valid,      // MMA 写回有效
    input  wire mma_wb_ready,      // MMA 写回就绪

    // 输出控制信号
    output reg  nice_mem_holdup    // 内存暂停信号（指令未退休时拉高）
);

    // ========================================================================
    // 内部状态机
    // ========================================================================
    // 状态定义
    localparam IDLE     = 1'b0;  // 空闲状态，无未退休指令
    localparam PENDING  = 1'b1;  // 有未退休的 MMA 指令

    reg state;

    // 写回握手成功
    wire wb_handshake = mma_wb_valid && mma_wb_ready;

    // ========================================================================
    // 状态机逻辑
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    // 检测到 MMA 指令启动，进入 PENDING 状态
                    if (calc_start) begin
                        state <= PENDING;
                    end
                end

                PENDING: begin
                    // 写回握手成功，指令退休，返回 IDLE
                    if (wb_handshake) begin
                        state <= IDLE;
                    end
                    // 注意：如果在 PENDING 状态又来新的 calc_start，
                    // 保持 PENDING（简化设计，假设单发射）
                end
            endcase
        end
    end

    // ========================================================================
    // nice_mem_holdup 信号生成
    // ========================================================================
    // 当有未退休的 MMA 指令时（PENDING 状态），拉高 mem_holdup
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nice_mem_holdup <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    // IDLE 状态下，如果有新指令启动，立即拉高 holdup
                    if (calc_start) begin
                        nice_mem_holdup <= 1'b1;
                    end else begin
                        nice_mem_holdup <= 1'b0;
                    end
                end

                PENDING: begin
                    // PENDING 状态下，保持 holdup 直到写回成功
                    if (wb_handshake) begin
                        nice_mem_holdup <= 1'b0;
                    end else begin
                        nice_mem_holdup <= 1'b1;
                    end
                end
            endcase
        end
    end

    // ========================================================================
    // Optional: Debug signals
    // ========================================================================
`ifdef DEBUG_RETIRE_TRACKER
    always @(posedge clk) begin
        if (calc_start) begin
            $display("[Retire Tracker] MMA instruction started, mem_holdup asserted");
        end
        if (wb_handshake) begin
            $display("[Retire Tracker] MMA instruction retired, mem_holdup deasserted");
        end
    end
`endif

endmodule
