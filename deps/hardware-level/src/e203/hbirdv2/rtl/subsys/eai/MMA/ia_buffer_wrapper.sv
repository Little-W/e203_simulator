/*
 * ia_buffer_wrapper - 输入激活缓冲区包装器
 * 模拟 32位宽 × 128位深 的 Memory Compiler 生成的 SRAM 时序
 * 
 * 特性：
 * - 单端口读写（不支持同时读写）
 * - 写使能控制的同步写入
 * - 读取有1周期延迟（寄存器输出）
 * - 字节写使能支持
 */

module ia_buffer_wrapper #(
    parameter int unsigned DATA_WIDTH = 32,   // 数据宽度
    parameter int unsigned DEPTH = 128,       // 深度
    parameter int unsigned ADDR_WIDTH = $clog2(DEPTH)
) (
    input  wire                      clk,
    input  wire                      rst_n,
    
    // 写接口
    input  wire                      wr_en,
    input  wire [ADDR_WIDTH-1:0]     wr_addr,
    input  wire [DATA_WIDTH-1:0]     wr_data,
    input  wire [DATA_WIDTH/8-1:0]   wr_mask,  // 字节写使能
    
    // 读接口
    input  wire                      rd_en,
    input  wire [ADDR_WIDTH-1:0]     rd_addr,
    output reg  [DATA_WIDTH-1:0]     rd_data
);

    // 内部存储阵列
    reg [DATA_WIDTH-1:0] mem [DEPTH];
    
    // 读数据寄存器（模拟1周期延迟）
    reg [DATA_WIDTH-1:0] rd_data_reg;
    
    // 写操作（同步）
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= '0;
            end
        end else if (wr_en) begin
            for (int i = 0; i < DATA_WIDTH/8; i++) begin
                if (wr_mask[i]) begin
                    mem[wr_addr][i*8 +: 8] <= wr_data[i*8 +: 8];
                end
            end
        end
    end
    
    // 读操作（1周期延迟，模拟SRAM时序）
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data_reg <= '0;
        end else if (rd_en) begin
            rd_data_reg <= mem[rd_addr];
        end
    end
    
    assign rd_data = rd_data_reg;

endmodule
