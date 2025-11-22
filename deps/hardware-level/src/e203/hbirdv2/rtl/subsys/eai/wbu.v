/* verilator lint_off TIMESCALEMOD */

/* verilator lint_on TIMESCALEMOD */

`include "e203_defines.v"

module wbu #(
    parameter DW = 32  // Data width
) (
    input clk,
    input rst_n,

    // 来自 CSR 单元的写回数据接口
    input           csr_wb_valid,
    output          csr_wb_ready,
    input  [DW-1:0] csr_wb_data,

    // 来自 MMA 执行单元的写回数据接口
    input           mma_wb_valid,
    output          mma_wb_ready,
    input  [DW-1:0] mma_wb_data,

    // NICE 响应接口（连接到 nice_rsp_*）
    output          nice_rsp_valid,
    input           nice_rsp_ready,
    output [DW-1:0] nice_rsp_rdat,
    output          nice_rsp_err     // 错误标志（当前始终为 0）
);

    // ========================================================================
    // 内部信号定义
    // ========================================================================
    // CSR Ping-Pong Buffer 信号
    wire          csr_buf_rd_valid;
    wire          csr_buf_rd_ready;
    wire [DW-1:0] csr_buf_rd_data;

    // MMA Ping-Pong Buffer 信号
    wire          mma_buf_rd_valid;
    wire          mma_buf_rd_ready;
    wire [DW-1:0] mma_buf_rd_data;

    // ========================================================================
    // CSR Ping-Pong Buffer 实例化
    // ========================================================================
    wb_pingpong_buf #(
        .DW(DW)
    ) u_csr_wb_pingpong_buf (
        .clk       (clk),
        .rst_n     (rst_n),

        // 写入侧（来自 CSR 单元）
        .wr_valid  (csr_wb_valid),
        .wr_ready  (csr_wb_ready),
        .wr_wb_data(csr_wb_data),

        // 读出侧（连接到仲裁逻辑）
        .rd_valid  (csr_buf_rd_valid),
        .rd_ready  (csr_buf_rd_ready),
        .rd_wb_data(csr_buf_rd_data)
    );

    // ========================================================================
    // MMA Ping-Pong Buffer 实例化
    // ========================================================================
    wb_pingpong_buf #(
        .DW(DW)
    ) u_mma_wb_pingpong_buf (
        .clk       (clk),
        .rst_n     (rst_n),

        // 写入侧（来自 MMA 执行单元）
        .wr_valid  (mma_wb_valid),
        .wr_ready  (mma_wb_ready),
        .wr_wb_data(mma_wb_data),

        // 读出侧（连接到仲裁逻辑）
        .rd_valid  (mma_buf_rd_valid),
        .rd_ready  (mma_buf_rd_ready),
        .rd_wb_data(mma_buf_rd_data)
    );

    // ========================================================================
    // 仲裁逻辑：MMA 优先级高于 CSR
    // ========================================================================
    // 优先级选择：MMA > CSR
    wire sel_mma = mma_buf_rd_valid;
    wire sel_csr = csr_buf_rd_valid && !mma_buf_rd_valid;

    // 输出多路选择
    assign nice_rsp_valid = mma_buf_rd_valid || csr_buf_rd_valid;
    assign nice_rsp_rdat  = sel_mma ? mma_buf_rd_data : csr_buf_rd_data;

    // 反压分配：只有被选中的缓冲才能接收 ready 信号
    assign mma_buf_rd_ready = sel_mma && nice_rsp_ready;
    assign csr_buf_rd_ready = sel_csr && nice_rsp_ready;

    // ========================================================================
    // 错误信号（当前始终为 0）
    // ========================================================================
    assign nice_rsp_err = 1'b0;

    // ========================================================================
    // Optional: Debug signals
    // ========================================================================
`ifdef DEBUG_WBU
    always @(posedge clk) begin
        if (csr_wb_valid && csr_wb_ready) begin
            $display("[WBU] CSR Write-back: wb_data=0x%h", csr_wb_data);
        end
        if (mma_wb_valid && mma_wb_ready) begin
            $display("[WBU] MMA Write-back: wb_data=0x%h", mma_wb_data);
        end
        if (nice_rsp_valid && nice_rsp_ready) begin
            $display("[WBU] Response: rsp_rdat=0x%h, source=%s", 
                     nice_rsp_rdat, sel_mma ? "MMA" : "CSR");
        end
    end
`endif

endmodule
