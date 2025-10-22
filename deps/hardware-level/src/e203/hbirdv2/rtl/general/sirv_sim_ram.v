/*                                                                      
 Copyright 2018-2020 Nuclei System Technology, Inc.                
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
  Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */                                                                      
                                                                         
                                                                         
                                                                         
//=====================================================================
//
// Designer   : Bob Hu
//
// Description:
//  The simulation model of SRAM
//
// ====================================================================
module sirv_sim_ram 
#(parameter DP = 512,
  parameter FORCE_X2ZERO = 0,
  parameter DW = 32,
  parameter MW = 4,
  parameter AW = 32,
  parameter MEM_PATH = "",      // 新增：内存初始化文件路径
  parameter INIT_EN = 0         // 新增：初始化使能
)
(
  input             clk, 
  input  [DW-1  :0] din, 
  (*mark_debug = "true"*)input  [AW-1  :0] addr,
  input             cs,
  input             we,
  input  [MW-1:0]   wem,
  (*mark_debug = "true"*)output [DW-1:0]   dout
);

    // reg [DW-1:0] mem_r [0:DP-1];  // 移至非综合分支
    // reg [AW-1:0] addr_r;          // 移至非综合分支
    wire [MW-1:0] wen;
    wire ren;

    assign ren = cs & (~we);
    assign wen = ({MW{cs & we}} & wem);

    // 统一出口：综合/仿真均驱动到 dout_pre，再经过 FORCE_X2ZERO 逻辑
    wire [DW-1:0] dout_pre;

    // 地址与 XPM 参数
    localparam ADDR_BITS = (DP <= 1) ? 1 : $clog2(DP);
    localparam integer BYTEW = (DW/MW);
    localparam integer MEM_BITS = DP*DW;
    wire [ADDR_BITS-1:0] addra = addr[ADDR_BITS-1:0];

    genvar i;

`ifdef SYNTHESIS
  `ifdef USE_XPM
    // 在综合下用 XPM 单端口 RAM
    // 若需初始化，请保证：
    // - INIT_EN = 1
    // - MEM_PATH 为合法 .mem 文件或 "none"
    xpm_memory_spram #(
      .ADDR_WIDTH_A        (ADDR_BITS),
      .AUTO_SLEEP_TIME     (0),
      .BYTE_WRITE_WIDTH_A  (BYTEW),        // 例如 8 bit
      .ECC_MODE            ("no_ecc"),
      .MEMORY_INIT_FILE    (MEM_PATH),     // 为空时请改为 "none"
      .MEMORY_INIT_PARAM   ("0"),
      .MEMORY_OPTIMIZATION ("true"),
      .MEMORY_PRIMITIVE    ("block"),
      .MEMORY_SIZE         (MEM_BITS),
      .MESSAGE_CONTROL     (0),
      .READ_DATA_WIDTH_A   (DW),
      .READ_LATENCY_A      (1),            // 输出寄存 1 拍
      .READ_RESET_VALUE_A  ("0"),
      .RST_MODE_A          ("SYNC"),
      .SIM_ASSERT_CHK      (0),
      .USE_MEM_INIT        (INIT_EN),
      .WRITE_DATA_WIDTH_A  (DW),
      .WRITE_MODE_A        ("read_first")
    ) u_xpm_spram (
      .douta               (dout_pre),
      .addra               (addra),
      .clka                (clk),
      .ena                 (1'b1),         // 读由 regcea 控制，写由 wea 控制
      .rsta                (1'b0),
      .regcea              (ren),          // 仅在读有效时更新输出
      .sleep               (1'b0),
      .wea                 (wen),          // 宽度 MW，按字节写
      .dina                (din),
      .injectdbiterra      (1'b0),
      .injectsbiterra      (1'b0)
    );
  `else
    // 非xpm综合分支：行为级RAM模型，仅支持DW为8的整数倍
    initial begin
      if (DW % 8 != 0) begin
        $error("sirv_sim_ram: DW must be a multiple of 8 in non-xpm synthesis mode!");
      end
    end

    reg [DW-1:0] mem_r [0:DP-1];
    reg [AW-1:0] addr_r;
    reg [DW-1:0] dout_reg;

    // 内存初始化
    initial begin
      if (INIT_EN && MEM_PATH != "") begin
        $display("sirv_sim_ram: loading memory from %s", MEM_PATH);
        $readmemh(MEM_PATH, mem_r);
      end
    end

    // 写入逻辑：用generate展开，避免变量位选取
    genvar k;
    generate
      for (k = 0; k < MW; k = k + 1) begin : ram_write
        always @(posedge clk) begin
          if (cs && we && wem[k]) begin
            mem_r[addr][8*k+7:8*k] <= din[8*k+7:8*k];
          end
        end
      end
    endgenerate

    // 读出逻辑
    always @(posedge clk) begin
      if (cs && !we) begin
        addr_r <= addr;
        dout_reg <= mem_r[addr];
      end
    end

    assign dout_pre = dout_reg;
  `endif
`else
    // 非综合（仿真）保持原有行为级模型
    (* ram_style="block" *) reg [DW-1:0] mem_r [0:DP-1];//DP个DW位宽的存储单元
    reg [AW-1:0] addr_r;

    // 内存初始化逻辑
    initial begin
        if (INIT_EN && MEM_PATH != "") begin
            $display("sirv_sim_ram: loading memory from %s", MEM_PATH);
            $readmemh(MEM_PATH, mem_r);
        end
    end

    always @(posedge clk) begin
        if (ren) begin
            addr_r <= addr;
        end
    end

    generate
      for (i = 0; i < MW; i = i+1) begin : mem
        if((8*i+8) > DW ) begin: last
          always @(posedge clk) begin
            if (wen[i]) begin
               mem_r[addr][DW-1:8*i] <= din[DW-1:8*i];
            end
          end
        end
        else begin: non_last
          always @(posedge clk) begin
            if (wen[i]) begin
               mem_r[addr][8*i+7:8*i] <= din[8*i+7:8*i];
            end
          end
        end
      end
    endgenerate

    assign dout_pre = mem_r[addr_r];
`endif

    // 原有 FORCE_X2ZERO 输出处理保持不变
    generate
     if(FORCE_X2ZERO == 1) begin: force_x_to_zero
        for (i = 0; i < DW; i = i+1) begin:force_x_gen 
            `ifndef SYNTHESIS//{
            assign dout[i] = (dout_pre[i] === 1'bx) ? 1'b0 : dout_pre[i];
            `else//}{
            assign dout[i] = dout_pre[i];
            `endif//}
        end
     end
     else begin:no_force_x_to_zero
       assign dout = dout_pre;
     end
    endgenerate

endmodule
