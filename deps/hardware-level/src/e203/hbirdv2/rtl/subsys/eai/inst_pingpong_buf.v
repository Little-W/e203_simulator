
`include "e203_defines.v"

module inst_pingpong_buf #(
    parameter DW = 32  // Data width
) (
    input clk,
    input rst_n,

    // Write side (input)
    input           wr_valid,
    output          wr_ready,
    input  [DW-1:0] wr_inst,  // Instruction data
    input  [DW-1:0] wr_rs1,   // rs1 register value (address)
    input  [DW-1:0] wr_rs2,   // rs2 register value (cfg config word)

    // Read side (output)
    output          rd_valid,
    input           rd_ready,
    output [DW-1:0] rd_inst,  // Read instruction data
    output [DW-1:0] rd_rs1,   // Read rs1 value
    output [DW-1:0] rd_rs2    // Read rs2 value
);

    // Ping-Pong buffers
    reg  [DW-1:0] inst_ping;
    reg  [DW-1:0] inst_pong;

    // Ping-Pong buffers for rs1 and rs2
    reg  [DW-1:0] rs1_ping;
    reg  [DW-1:0] rs1_pong;
    reg  [DW-1:0] rs2_ping;
    reg  [DW-1:0] rs2_pong;

    // Buffer status: 0=empty, 1=full
    reg           ping_full;
    reg           pong_full;

    // Current write/read buffer selector: 0=ping, 1=pong
    reg           wr_sel;
    reg           rd_sel;

    // Handshake signals
    wire          wr_hsked = wr_valid & wr_ready;
    wire          rd_hsked = rd_valid & rd_ready;

    // Write ready: at least one buffer is empty
    assign wr_ready = (wr_sel == 1'b0) ? ~ping_full : ~pong_full;

    // Read valid: at least one buffer is full
    assign rd_valid = (rd_sel == 1'b0) ? ping_full : pong_full;

    // Read inst, rs1 and rs2 from current read buffer
    assign rd_inst = (rd_sel == 1'b0) ? inst_ping : inst_pong;
    assign rd_rs1  = (rd_sel == 1'b0) ? rs1_ping : rs1_pong;
    assign rd_rs2  = (rd_sel == 1'b0) ? rs2_ping : rs2_pong;

    // Write buffer logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_ping <= {DW{1'b0}};
            inst_pong <= {DW{1'b0}};
            rs1_ping  <= {DW{1'b0}};
            rs1_pong  <= {DW{1'b0}};
            rs2_ping  <= {DW{1'b0}};
            rs2_pong  <= {DW{1'b0}};
        end else begin
            if (wr_hsked) begin
                if (wr_sel == 1'b0) begin
                    inst_ping <= wr_inst;
                    rs1_ping  <= wr_rs1;
                    rs2_ping  <= wr_rs2;
                end else begin
                    inst_pong <= wr_inst;
                    rs1_pong  <= wr_rs1;
                    rs2_pong  <= wr_rs2;
                end
            end
        end
    end

    // Ping buffer full flag
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ping_full <= 1'b0;
        end else begin
            if (wr_hsked && wr_sel == 1'b0) ping_full <= 1'b1;
            else if (rd_hsked && rd_sel == 1'b0) ping_full <= 1'b0;
        end
    end

    // Pong buffer full flag
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pong_full <= 1'b0;
        end else begin
            if (wr_hsked && wr_sel == 1'b1) pong_full <= 1'b1;
            else if (rd_hsked && rd_sel == 1'b1) pong_full <= 1'b0;
        end
    end

    // Write buffer selector
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_sel <= 1'b0;
        end else begin
            if (wr_hsked) begin
                wr_sel <= ~wr_sel;
            end
        end
    end

    // Read buffer selector
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_sel <= 1'b0;
        end else begin
            if (rd_hsked) begin
                rd_sel <= ~rd_sel;
            end
        end
    end

endmodule
