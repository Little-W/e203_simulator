module compute_core #(
    parameter int unsigned SIZE = 16,
    parameter int unsigned DATA_WIDTH = 16
) (
    input  wire                           clk,
    // 权重与数据输入
    input  wire                           store_weight_req,
    input  wire signed [7:0]              weight_in   [SIZE],
    input  wire signed [DATA_WIDTH-1:0]   ia_vec_in   [SIZE],
    input  wire                           ia_row_valid,
    input  wire                           ia_calc_done,
    input  wire                           ia_is_init_data,
    input  wire signed [31:0]             bias_in     [SIZE],
    // 输出到后级
    output wire signed [31:0]             acc_data_out[SIZE],
    output wire                           acc_data_valid,
    output wire                           tile_calc_over,
    output wire                           partial_sum_calc_over
);

    // Data Setup (数据对齐)
    wire signed [DATA_WIDTH-1:0] data_setup_out        [SIZE];
    wire                         data_setup_input_valid;
    wire                         data_setup_calc_done;
    wire                         data_setup_is_init_data;

    // Systolic Array
    wire signed [31:0]           sa_sum_out            [SIZE];

    data_setup #(
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_NUM  (SIZE)
    ) u_data_setup (
        .clk           (clk),
        .data_in       (ia_vec_in),
        .data_out      (data_setup_out),
        .input_valid_i (ia_row_valid),
        .calc_done_i   (ia_calc_done),
        .is_init_data_i(ia_is_init_data),
        .input_valid_o (data_setup_input_valid),
        .calc_done_o   (data_setup_calc_done),
        .is_init_data_o(data_setup_is_init_data)
    );

    ws_systolic_array #(
        .SIZE(SIZE)
    ) u_systolic_array (
        .clk             (clk),
        .store_weight_req(store_weight_req),
        .weight_in       (weight_in),
        .data_in         (data_setup_out),
        .sum_in          (bias_in),
        .sum_out         (sa_sum_out)
    );

    accumulator_array #(
        .SIZE      (SIZE),
        .DATA_WIDTH(32)
    ) u_accumulator_array (
        .clk                  (clk),
        .data_in              (sa_sum_out),
        .calc_done_i          (data_setup_calc_done),
        .input_valid_i        (data_setup_input_valid),
        .is_init_data_i       (data_setup_is_init_data),
        .data_out             (acc_data_out),
        .calc_done_o          (acc_data_valid),
        .partial_sum_calc_over(partial_sum_calc_over),
        .tile_calc_over_o     (tile_calc_over)
    );

endmodule
