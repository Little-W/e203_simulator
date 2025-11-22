// shift_accumulator: 基于FIFO的部分和累加器
// 每次输入有效时，将新数据与FIFO指定位置的数据累加（或直接写入），并通过读指针输出任意位置的累加结果。
// 支持初始化数据输入和写指针自动循环，支持写指针在输入无效时复位。

module shift_accumulator #(
    STAGE_NUM  = 16,  // FIFO深度
    DATA_WIDTH = 32   // 数据宽度
) (
    input wire clk,  // 时钟信号
    input wire signed [DATA_WIDTH-1:0] data_in,  // 输入数据
    input wire calc_done_i,  // 输入数据为tile最后一项时拉高
    input wire input_valid_i,  // 输入数据有效信号
    input wire is_init_data_i,  // 初始化数据输入信号（为1时直接写入，不累加）
    input wire [$clog2(STAGE_NUM)-1:0] read_ptr_i,  // 读指针，决定输出数据位置
    output wire signed [DATA_WIDTH-1:0] data_out,  // 输出数据
    output wire calc_done_o,  // 输出：当前数据是否为tile最后一项
    output wire input_valid_o,  // 输出：当前数据是否有效
    output wire is_init_data_o  // 输出：当前数据是否为初始化
);

    // acc_fifo: 用于存储部分和的FIFO
    reg signed [DATA_WIDTH-1:0] acc_fifo[STAGE_NUM];
    // 相关信号寄存器：用于输出时序对齐
    reg is_init_data_reg;  // 记录当前数据是否为初始化
    reg input_valid_reg;  // 记录当前数据是否有效
    reg calc_done_reg;  // 记录当前数据是否为tile最后一项

    // 写指针，指示下次写入/累加的位置
    reg [$clog2(STAGE_NUM)-1:0] write_ptr;
    // 输入有效信号的时序采样，用于检测下降沿
    reg input_valid_i_d;

    // 主时序逻辑：数据累加与信号寄存
    always @(posedge clk) begin
        // 采样input_valid_i用于下降沿检测
        input_valid_i_d  <= input_valid_i;

        // 相关信号每拍寄存
        is_init_data_reg <= is_init_data_i;
        input_valid_reg  <= input_valid_i;
        calc_done_reg    <= calc_done_i;

        if (input_valid_i) begin
            // 若为初始化数据，直接写入FIFO
            if (is_init_data_i) begin
                if (~is_init_data_reg) begin
                    acc_fifo[0] <= data_in;
                    write_ptr   <= 1;
                end
                else begin
                    acc_fifo[write_ptr] <= data_in;
                    write_ptr <= write_ptr + 1;
                end
            end else begin
                // 否则将新数据与FIFO当前位置数据累加，并做饱和限幅
                reg signed [DATA_WIDTH:0] sum;
                sum = acc_fifo[write_ptr] + data_in;
                // 对累加结果 sum 进行饱和处理：
                // 如果 sum 超过 DATA_WIDTH 位有符号数的最大值，则写入最大值；
                // 如果 sum 小于最小值，则写入最小值；
                // 否则，将 sum 的低 DATA_WIDTH 位写入 acc_fifo。
                // 这样可以防止累加器溢出，保证输出始终在有效范围内。
                if (sum > ((1 << (DATA_WIDTH - 1)) - 1)) begin
                    acc_fifo[write_ptr] <= ((1 << (DATA_WIDTH - 1)) - 1);
                end else if (sum < -(1 << (DATA_WIDTH - 1))) begin
                    acc_fifo[write_ptr] <= -(1 << (DATA_WIDTH - 1));
                end else begin
                    acc_fifo[write_ptr] <= sum[DATA_WIDTH-1:0];
                end
                write_ptr <= write_ptr + 1;
            end

        end
        // 输入有效信号下降沿时，写指针复位
        if (~input_valid_i && input_valid_i_d) begin
            write_ptr <= 0;
        end
    end

    // 输出：由读指针索引FIFO，相关信号为寄存器输出
    assign data_out       = acc_fifo[read_ptr_i];
    assign calc_done_o    = calc_done_reg;
    assign input_valid_o  = input_valid_reg;
    assign is_init_data_o = is_init_data_reg;

endmodule
