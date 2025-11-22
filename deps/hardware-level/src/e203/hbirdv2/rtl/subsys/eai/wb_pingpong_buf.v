

`include "e203_defines.v"

module wb_pingpong_buf #(
    parameter DW = 32  // Data width
) (
    input clk,
    input rst_n,

    // Write side (input from execution unit)
    input                    wr_valid,
    output                   wr_ready,
    input  [DW-1:0]          wr_wb_data, // Write-back data

    // Read side (output to write-back stage)
    output                   rd_valid,
    input                    rd_ready,
    output [DW-1:0]          rd_wb_data  // Read write-back data
);

    // ========================================================================
    // Ping-Pong buffers
    // ========================================================================
    reg [DW-1:0]       wb_data_ping;
    reg [DW-1:0]       wb_data_pong;

    // Buffer status: 0=empty, 1=full
    reg                ping_full;
    reg                pong_full;

    // Current write/read buffer selector: 0=ping, 1=pong
    reg                wr_sel;
    reg                rd_sel;

    // ========================================================================
    // Handshake signals
    // ========================================================================
    wire wr_hsked = wr_valid & wr_ready;
    wire rd_hsked = rd_valid & rd_ready;

    // Write ready: at least one buffer is empty
    assign wr_ready = (wr_sel == 1'b0) ? ~ping_full : ~pong_full;

    // Read valid: at least one buffer is full
    assign rd_valid = (rd_sel == 1'b0) ? ping_full : pong_full;

    // Read wb_data from current read buffer
    assign rd_wb_data = (rd_sel == 1'b0) ? wb_data_ping : wb_data_pong;

    // ========================================================================
    // Write buffer logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_data_ping <= {DW{1'b0}};
            wb_data_pong <= {DW{1'b0}};
        end else begin
            if (wr_hsked) begin
                if (wr_sel == 1'b0) begin
                    wb_data_ping <= wr_wb_data;
                end else begin
                    wb_data_pong <= wr_wb_data;
                end
            end
        end
    end

    // ========================================================================
    // Ping buffer full flag
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ping_full <= 1'b0;
        end else begin
            if (wr_hsked && wr_sel == 1'b0)
                ping_full <= 1'b1;
            else if (rd_hsked && rd_sel == 1'b0)
                ping_full <= 1'b0;
        end
    end

    // ========================================================================
    // Pong buffer full flag
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pong_full <= 1'b0;
        end else begin
            if (wr_hsked && wr_sel == 1'b1)
                pong_full <= 1'b1;
            else if (rd_hsked && rd_sel == 1'b1)
                pong_full <= 1'b0;
        end
    end

    // ========================================================================
    // Write buffer selector
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_sel <= 1'b0;
        end else begin
            if (wr_hsked) begin
                wr_sel <= ~wr_sel;
            end
        end
    end

    // ========================================================================
    // Read buffer selector
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_sel <= 1'b0;
        end else begin
            if (rd_hsked) begin
                rd_sel <= ~rd_sel;
            end
        end
    end

    // ========================================================================
    // Optional: Debug signals
    // ========================================================================
`ifdef DEBUG_WB_PINGPONG
    always @(posedge clk) begin
        if (wr_hsked) begin
            $display("[WB PingPong] Write: wb_data=0x%h, buffer=%s",
                     wr_wb_data, wr_sel ? "PONG" : "PING");
        end
        if (rd_hsked) begin
            $display("[WB PingPong] Read: wb_data=0x%h, buffer=%s",
                     rd_wb_data, rd_sel ? "PONG" : "PING");
        end
    end
`endif

endmodule
