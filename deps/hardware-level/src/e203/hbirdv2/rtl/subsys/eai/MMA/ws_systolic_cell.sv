// filepath: /home/etc/FPGA/tflm_ai_dsa/basic/ws_systolic_cell.sv
module ws_systolic_cell #(
    parameter int unsigned DATA_IN_WIDTH = 16,  // s16 输入数据
    parameter int unsigned WEIGHT_WIDTH  = 8,   // s8  权重
    parameter int unsigned ACC_WIDTH     = 32   // 累加/输出位宽，默认32位
) (
    input  wire                            clk,
    input  wire                            store_weight_req,  // 置位时加载新权重
    input  wire signed [ WEIGHT_WIDTH-1:0] weight_in,
    input  wire signed [DATA_IN_WIDTH-1:0] data_in,
    input  wire signed [    ACC_WIDTH-1:0] sum_in,
    output wire signed [DATA_IN_WIDTH-1:0] data_out,
    output wire signed [ WEIGHT_WIDTH-1:0] weight_out,
    output wire signed [    ACC_WIDTH-1:0] sum_out
);

    // 寄存保持：权重驻留（WS），数据流水透传
    reg signed  [DATA_IN_WIDTH-1:0] data_reg;
    reg signed  [ WEIGHT_WIDTH-1:0] weight_reg;
    reg signed  [    ACC_WIDTH-1:0] sum_reg;

    wire signed [    ACC_WIDTH-1:0] mult_result;  // s16*s8 -> s24
    wire signed [      ACC_WIDTH:0] sum_ext;  // 扩一位用于饱和判断

    assign mult_result = data_reg * weight_reg;
    // 显式符号扩展后相加，避免表达式宽度截断
    assign sum_ext = $signed(
        {sum_reg[ACC_WIDTH-1], sum_reg}
    ) + $signed(
        {mult_result[ACC_WIDTH-1], mult_result}
    );

    always_ff @(posedge clk) begin
        if (store_weight_req) begin
            weight_reg <= weight_in;
            sum_reg    <= '0;
            data_reg   <= '0;
        end else begin
            data_reg <= data_in;
            sum_reg  <= sum_in;
        end
    end

    // 输出透传到相邻单元
    assign data_out = data_reg;
    assign weight_out = weight_reg;

    // 饱和到 ACC_WIDTH 位（改为连续赋值以兼容 iverilog 对 always_* 的限制）
    assign sum_out = (sum_ext > $signed(
        {1'b0, {(ACC_WIDTH - 1) {1'b1}}}
    )) ? $signed(
        {1'b0, {(ACC_WIDTH - 1) {1'b1}}}
    ) : (sum_ext < $signed(
        {1'b1, {(ACC_WIDTH - 1) {1'b0}}}
    )) ? $signed(
        {1'b1, {(ACC_WIDTH - 1) {1'b0}}}
    ) : sum_ext[ACC_WIDTH-1:0];

endmodule
