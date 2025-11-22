// ICB总线仲裁器
// 设计思路：
// - 总线仲裁器用于管理5个从设备（s0-s4）对ICB总线的访问
// - s4 (oa_writer) 拥有绝对最高优先级，始终优先授权
// - s0-s3 使用动态轮询机制，初始优先级为 s1 > s0 > s3 > s2
// - 每次授权后，被授权设备优先级降到最低，确保公平性
// - 总线空闲时进行仲裁，授权后设置 bus_busy 标志
// - 设备完成操作后释放总线，并更新优先级队列（s4除外）
// - 使用优先级队列数组存储s0-s3的动态优先级顺序
// - arbitrate函数按当前优先级顺序查找有请求的设备
// - calc_updated_priority函数计算授权后的新优先级队列
module icb_arbiter (
    input wire clk,
    input wire rst_n,

    // Slave 0: IA Loader
    input  wire s0_req,
    output reg  s0_granted,
    input  wire s0_done,

    // Slave 1: Kernel Loader
    input  wire s1_req,
    output reg  s1_granted,
    input  wire s1_done,

    // Slave 2: Bias Loader
    input  wire s2_req,
    output reg  s2_granted,
    input  wire s2_done,

    // Slave 3: Vec Requant
    input  wire s3_req,
    output reg  s3_granted,
    input  wire s3_done,

    // Slave 4: OA Writer
    input  wire s4_req,
    output reg  s4_granted,
    input  wire s4_done,

    // ICB选择信号
    output reg [2:0] icb_sel
);

    // 当前授权的主机
    reg [2:0] current_master;
    reg bus_busy;

    // 动态优先级队列：存储s0-s3的优先级顺序
    // priority_queue[0]是最高优先级，priority_queue[3]是最低优先级
    reg [2:0] priority_queue[3:0];
    reg [2:0] next_priority_queue[3:0];

    // 检测当前主机是否完成
    wire current_done = (current_master == 3'd0 && s0_done) ||
                       (current_master == 3'd1 && s1_done) ||
                       (current_master == 3'd2 && s2_done) ||
                       (current_master == 3'd3 && s3_done) ||
                       (current_master == 3'd4 && s4_done);
    // 检测总线是否空闲
    wire bus_idle = !bus_busy || (bus_busy && current_done);



    // 计算更新后的优先级队列：将指定设备移到队尾（最低优先级）
    function automatic void calc_updated_priority(
        input [2:0] granted_device, input [2:0] curr_queue[3:0], output [2:0] new_queue[3:0]);
        integer i, j;

        // 找到被授权设备在队列中的位置并移除
        j = 0;
        for (i = 0; i < 4; i = i + 1) begin
            if (curr_queue[i] != granted_device) begin
                new_queue[j] = curr_queue[i];
                j            = j + 1;
            end
        end

        // 将被授权设备放到队尾
        new_queue[3] = granted_device;
    endfunction

    // 根据优先级队列进行仲裁
    function automatic [2:0] arbitrate();
        integer       i;
        reg     [2:0] device_id;

        // 按优先级顺序检查哪个设备有请求
        for (i = 0; i < 4; i = i + 1) begin
            device_id = priority_queue[i];
            case (device_id)
                3'd0: if (s0_req) return 3'd0;
                3'd1: if (s1_req) return 3'd1;
                3'd2: if (s2_req) return 3'd2;
                3'd3: if (s3_req) return 3'd3;
            endcase
        end

        // 没有设备请求
        return 3'd7;  // 无效值
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_granted        <= 1'b0;
            s1_granted        <= 1'b0;
            s2_granted        <= 1'b0;
            s3_granted        <= 1'b0;
            s4_granted        <= 1'b0;
            icb_sel           <= 3'd0;
            current_master    <= 3'd0;
            bus_busy          <= 1'b0;

            // 初始化优先级队列: s1 > s0 > s3 > s2
            priority_queue[0] <= 3'd1;
            priority_queue[1] <= 3'd0;
            priority_queue[2] <= 3'd3;
            priority_queue[3] <= 3'd2;
        end else begin
            // 如果当前主机完成，释放总线
            if (bus_busy && current_done) begin
                s0_granted <= 1'b0;
                s1_granted <= 1'b0;
                s2_granted <= 1'b0;
                s3_granted <= 1'b0;
                s4_granted <= 1'b0;
                bus_busy   <= 1'b0;

                // 如果完成的不是s4，更新优先级队列
                if (current_master != 3'd4) begin
                    calc_updated_priority(current_master, priority_queue, next_priority_queue);
                    priority_queue[0] <= next_priority_queue[0];
                    priority_queue[1] <= next_priority_queue[1];
                    priority_queue[2] <= next_priority_queue[2];
                    priority_queue[3] <= next_priority_queue[3];
                end
            end

            // 如果总线空闲，按优先级仲裁
            if (bus_idle) begin
                // s4始终拥有最高优先级
                if (s4_req) begin
                    s4_granted     <= 1'b1;
                    icb_sel        <= 3'd4;
                    current_master <= 3'd4;
                    bus_busy       <= 1'b1;
                end else begin
                    // 对于s0-s3，使用动态优先级队列
                    reg [2:0] next_device;
                    next_device = arbitrate();

                    case (next_device)
                        3'd0: begin
                            s0_granted     <= 1'b1;
                            icb_sel        <= 3'd0;
                            current_master <= 3'd0;
                            bus_busy       <= 1'b1;
                        end
                        3'd1: begin
                            s1_granted     <= 1'b1;
                            icb_sel        <= 3'd1;
                            current_master <= 3'd1;
                            bus_busy       <= 1'b1;
                        end
                        3'd2: begin
                            s2_granted     <= 1'b1;
                            icb_sel        <= 3'd2;
                            current_master <= 3'd2;
                            bus_busy       <= 1'b1;
                        end
                        3'd3: begin
                            s3_granted     <= 1'b1;
                            icb_sel        <= 3'd3;
                            current_master <= 3'd3;
                            bus_busy       <= 1'b1;
                        end
                        default: ;  // 无设备请求
                    endcase
                end
            end
        end
    end

endmodule
