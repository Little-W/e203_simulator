module ws_systolic_array #(
    parameter int unsigned SIZE = 16
) (
    input  wire                              clk,
    input  wire                              store_weight_req,    // 权重加载请求，单个信号控制所有行
    input  wire signed [7:0]                 weight_in          [SIZE],
    input  wire signed [15:0]                data_in            [SIZE],
    input  wire signed [31:0]                sum_in             [SIZE],  // 累加器反馈输入
    output wire signed [31:0]                sum_out            [SIZE]
);

    // // 中间信号
    // wire signed [15:0] data_pipe   [SIZE][SIZE];
    // wire signed [7:0]  weight_pipe [SIZE][SIZE];
    // wire signed [31:0] sum_pipe    [SIZE][SIZE];

    // genvar row, col;
    // generate
    //     for (row = 0; row < SIZE; row++) begin : gen_row
    //         for (col = 0; col < SIZE; col++) begin : gen_col
    //             ws_systolic_cell ws_cell (
    //                 .clk(clk),
    //                 .store_weight_req(store_weight_req),
    //                 .weight_in(row == 0 ? weight_in[col] : weight_pipe[row-1][col]),
    //                 .data_in(col == 0 ? data_in[row] : data_pipe[row][col-1]),
    //                 .sum_in(row == 0 ? sum_in[col] : sum_pipe[row-1][col]),
    //                 .data_out(data_pipe[row][col]),
    //                 .weight_out(weight_pipe[row][col]),
    //                 .sum_out(sum_pipe[row][col])
    //             );
    //         end
    //     end

    //     // 修复 VARHIDDEN 警告，避免 genvar col 重复声明
    //     for (genvar sum_col = 0; sum_col < SIZE; sum_col++) begin : gen_sum_out
    //         assign sum_out[sum_col] = sum_pipe[SIZE-1][sum_col];
    //     end
    // endgenerate

// 中间信号
wire signed [15:0] data_pipe   [SIZE][SIZE];
wire signed [7:0]  weight_pipe [SIZE][SIZE];
wire signed [31:0] sum_pipe    [SIZE][SIZE];

genvar row, col;
generate
    for (row = 0; row < SIZE; row++) begin : gen_row
        for (col = 0; col < SIZE; col++) begin : gen_col
            if (row == 0 && col == 0) begin : cell_corner
                ws_systolic_cell ws_cell (
                    .clk(clk),
                    .store_weight_req(store_weight_req),
                    .weight_in(weight_in[col]),
                    .data_in(data_in[row]),
                    .sum_in(sum_in[col]),
                    .data_out(data_pipe[row][col]),
                    .weight_out(weight_pipe[row][col]),
                    .sum_out(sum_pipe[row][col])
                );
            end else if (row == 0) begin : cell_top_row
                ws_systolic_cell ws_cell (
                    .clk(clk),
                    .store_weight_req(store_weight_req),
                    .weight_in(weight_in[col]),
                    .data_in(data_pipe[row][col-1]),
                    .sum_in(sum_in[col]),
                    .data_out(data_pipe[row][col]),
                    .weight_out(weight_pipe[row][col]),
                    .sum_out(sum_pipe[row][col])
                );
            end else if (col == 0) begin : cell_left_col
                ws_systolic_cell ws_cell (
                    .clk(clk),
                    .store_weight_req(store_weight_req),
                    .weight_in(weight_pipe[row-1][col]),
                    .data_in(data_in[row]),
                    .sum_in(sum_pipe[row-1][col]),
                    .data_out(data_pipe[row][col]),
                    .weight_out(weight_pipe[row][col]),
                    .sum_out(sum_pipe[row][col])
                );
            end else begin : cell_inner
                ws_systolic_cell ws_cell (
                    .clk(clk),
                    .store_weight_req(store_weight_req),
                    .weight_in(weight_pipe[row-1][col]),
                    .data_in(data_pipe[row][col-1]),
                    .sum_in(sum_pipe[row-1][col]),
                    .data_out(data_pipe[row][col]),
                    .weight_out(weight_pipe[row][col]),
                    .sum_out(sum_pipe[row][col])
                );
            end
        end
    end

    for (genvar sum_col = 0; sum_col < SIZE; sum_col++) begin : gen_sum_out
        assign sum_out[sum_col] = sum_pipe[SIZE-1][sum_col];
    end
endgenerate

endmodule
