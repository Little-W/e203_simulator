module accumulator_array #(
    parameter SIZE = 16,
    parameter DATA_WIDTH = 32
) (
    input  wire                         clk,
    input  wire signed [DATA_WIDTH-1:0] data_in              [0:SIZE-1],
    input  wire                         calc_done_i,
    input  wire                         input_valid_i,
    input  wire                         is_init_data_i,
    output wire signed [DATA_WIDTH-1:0] data_out             [0:SIZE-1],
    output wire                         calc_done_o,
    output reg                          tile_calc_over_o,
    output reg                          partial_sum_calc_over
);

    wire [SIZE:0] calc_done_chain;
    wire [SIZE:0] input_valid_chain;
    wire [SIZE:0] is_init_data_chain;

    reg           calc_done_o_d;
    reg           input_valid_chain_d;
    reg           input_valid_i_d;

    assign calc_done_chain[0]    = calc_done_i;
    assign calc_done_o           = calc_done_chain[SIZE];
    assign input_valid_chain[0]  = input_valid_i;
    assign is_init_data_chain[0] = is_init_data_i;

    reg [$clog2(SIZE)-1:0] read_ptr;
    always @(posedge clk) begin
        if (input_valid_i & ~input_valid_i_d) begin  // 捕捉input_valid_i上升沿
            read_ptr <= 0;
        end else if (calc_done_o) begin
            read_ptr <= read_ptr + 1;
        end
        if (tile_calc_over_o) begin
            read_ptr <= 0;
        end
    end

    genvar i;
    generate
        for (i = 0; i < SIZE; i = i + 1) begin : accumulator_gen
            shift_accumulator #(
                .STAGE_NUM (SIZE),
                .DATA_WIDTH(DATA_WIDTH)
            ) acc_inst (
                .clk           (clk),
                .data_in       (data_in[i]),
                .calc_done_i   (calc_done_chain[i]),
                .input_valid_i (input_valid_chain[i]),
                .is_init_data_i(is_init_data_chain[i]),
                .read_ptr_i    (read_ptr),
                .data_out      (data_out[i]),
                .calc_done_o   (calc_done_chain[i+1]),
                .input_valid_o (input_valid_chain[i+1]),
                .is_init_data_o(is_init_data_chain[i+1])
            );
        end
    endgenerate

    always @(posedge clk) begin
        calc_done_o_d <= calc_done_o;
        input_valid_chain_d <= input_valid_chain[SIZE];
        input_valid_i_d <= input_valid_i;
        tile_calc_over_o <= calc_done_o_d & ~calc_done_o;  // 检测下降沿
        partial_sum_calc_over <= input_valid_chain_d & ~input_valid_chain[SIZE]; // 基于 input_valid_chain[SIZE] 的下降沿
    end

endmodule
