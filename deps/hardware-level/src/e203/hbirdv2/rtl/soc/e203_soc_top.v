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
                                                                         
                                                                         
                                                                         
module e203_soc_top(
  /* 
  端口命名约定说明（简要）：
  - <name>_o_oval : "output outVALue" - 表示要驱动到芯片封装/IO pad 的逻辑电平值。
      * 当对应的输出被使能（见下）时，驱动器会把该值驱动到引脚。
  - <name>_o_oe   : "output outEnablE" - 输出使能信号（通常为 1 表示驱动，0 表示三态/不驱动）。
      * 当 _o_oe == 1 时，IO 驱动器把 _o_oval 的值驱动到 pad。
      * 当 _o_oe == 0 时，IO 驱动器释放总线（高阻），外部电路/输入路径可以读取 pad 值。
  - <name>_i_ival : "input inVALue" - 从 pad 采样到的输入电平值（当 pad 由外部或内部 pull-up/pull-down 决定时有效）。
  例：
    io_pads_gpioA_o_oval = 1; io_pads_gpioA_o_oe = 1  -> 引脚输出高电平
    io_pads_gpioA_o_oe  = 0                                -> 引脚为高阻，可作为输入读取 io_pads_gpioA_i_ival
  注意：具体 pad 上的上拉（pue）、下拉、驱动强度（ds）等由对应的 *_o_pue/_o_ds 等端口控制或由底层 IO 单元实现。
  */

  // This clock should comes from the crystal pad generated high speed clock (16MHz)
  input  hfextclk,
  output hfxoscen,// The signal to enable the crystal pad generated clock

  // This clock should comes from the crystal pad generated low speed clock (32.768KHz)
  input  lfextclk,
  output lfxoscen,// The signal to enable the crystal pad generated clock


  // The JTAG TCK is input, need to be pull-up
  input   io_pads_jtag_TCK_i_ival,

  // The JTAG TMS is input, need to be pull-up
  input   io_pads_jtag_TMS_i_ival,

  // The JTAG TDI is input, need to be pull-up
  input   io_pads_jtag_TDI_i_ival,

  // The JTAG TDO is output have enable
  output  io_pads_jtag_TDO_o_oval,
  output  io_pads_jtag_TDO_o_oe,

  // The GPIO are all bidir pad have enables
  input  [32-1:0] io_pads_gpioA_i_ival,
  output [32-1:0] io_pads_gpioA_o_oval,
  output [32-1:0] io_pads_gpioA_o_oe,

  input  [32-1:0] io_pads_gpioB_i_ival,
  output [32-1:0] io_pads_gpioB_o_oval,
  output [32-1:0] io_pads_gpioB_o_oe,

  //QSPI0 SCK and CS is output without enable
  output  io_pads_qspi0_sck_o_oval,
  output  io_pads_qspi0_cs_0_o_oval,

  //QSPI0 DQ is bidir I/O with enable, and need pull-up enable
  input   io_pads_qspi0_dq_0_i_ival,
  output  io_pads_qspi0_dq_0_o_oval,
  output  io_pads_qspi0_dq_0_o_oe,
  input   io_pads_qspi0_dq_1_i_ival,
  output  io_pads_qspi0_dq_1_o_oval,
  output  io_pads_qspi0_dq_1_o_oe,
  input   io_pads_qspi0_dq_2_i_ival,
  output  io_pads_qspi0_dq_2_o_oval,
  output  io_pads_qspi0_dq_2_o_oe,
  input   io_pads_qspi0_dq_3_i_ival,
  output  io_pads_qspi0_dq_3_o_oval,
  output  io_pads_qspi0_dq_3_o_oe,
  


  // Erst is input need to be pull-up by default
  input   io_pads_aon_erst_n_i_ival,

  // dbgmode are inputs need to be pull-up by default
  input  io_pads_dbgmode0_n_i_ival,
  input  io_pads_dbgmode1_n_i_ival,
  input  io_pads_dbgmode2_n_i_ival,

  // BootRom is input need to be pull-up by default
  input  io_pads_bootrom_n_i_ival,


  // dwakeup is input need to be pull-up by default
  input  io_pads_aon_pmu_dwakeup_n_i_ival,

      // PMU output is just output without enable
  output io_pads_aon_pmu_padrst_o_oval,
  output io_pads_aon_pmu_vddpaden_o_oval 
);


 
 wire sysper_icb_cmd_valid;
 wire sysper_icb_cmd_ready;

 wire sysfio_icb_cmd_valid;
 wire sysfio_icb_cmd_ready;

 wire sysmem_icb_cmd_valid;
 wire sysmem_icb_cmd_ready;

 wire sram_icb_cmd_valid;
 wire sram_icb_cmd_ready;
 wire [31:0] sram_icb_cmd_addr;
 wire sram_icb_cmd_read;
 wire [`E203_XLEN-1:0] sram_icb_cmd_wdata;
 wire [`E203_XLEN/8-1:0] sram_icb_cmd_wmask;
 wire sram_icb_rsp_valid;
 wire sram_icb_rsp_ready;
 wire [`E203_XLEN-1:0] sram_icb_rsp_rdata;

 wire hfclk;
 wire hfclkrst;

 // Add intermediate wires for OE signals
wire jtag_TDO_o_oe_int;
wire [31:0] gpioA_o_oe_int;
wire [31:0] gpioB_o_oe_int;
wire qspi0_dq_0_o_oe_int;
wire qspi0_dq_1_o_oe_int;
wire qspi0_dq_2_o_oe_int;
wire qspi0_dq_3_o_oe_int;

 e203_subsys_top u_e203_subsys_top(
    .core_mhartid      (1'b0),
  



  `ifdef E203_HAS_ITCM_EXTITF //{
    .ext2itcm_icb_cmd_valid  (1'b0),
    .ext2itcm_icb_cmd_ready  (),
    .ext2itcm_icb_cmd_addr   (`E203_ITCM_ADDR_WIDTH'b0 ),
    .ext2itcm_icb_cmd_read   (1'b0 ),
    .ext2itcm_icb_cmd_wdata  (32'b0),
    .ext2itcm_icb_cmd_wmask  (4'b0),
    
    .ext2itcm_icb_rsp_valid  (),
    .ext2itcm_icb_rsp_ready  (1'b0),
    .ext2itcm_icb_rsp_err    (),
    .ext2itcm_icb_rsp_rdata  (),
  `endif//}

  `ifdef E203_HAS_DTCM_EXTITF //{
    .ext2dtcm_icb_cmd_valid  (1'b0),
    .ext2dtcm_icb_cmd_ready  (),
    .ext2dtcm_icb_cmd_addr   (`E203_DTCM_ADDR_WIDTH'b0 ),
    .ext2dtcm_icb_cmd_read   (1'b0 ),
    .ext2dtcm_icb_cmd_wdata  (32'b0),
    .ext2dtcm_icb_cmd_wmask  (4'b0),
    
    .ext2dtcm_icb_rsp_valid  (),
    .ext2dtcm_icb_rsp_ready  (1'b0),
    .ext2dtcm_icb_rsp_err    (),
    .ext2dtcm_icb_rsp_rdata  (),
  `endif//}

  .sysper_icb_cmd_valid (sysper_icb_cmd_valid),
  .sysper_icb_cmd_ready (sysper_icb_cmd_ready),
  .sysper_icb_cmd_read  (), 
  .sysper_icb_cmd_addr  (), 
  .sysper_icb_cmd_wdata (), 
  .sysper_icb_cmd_wmask (), 
  
  .sysper_icb_rsp_valid (sysper_icb_cmd_valid),
  .sysper_icb_rsp_ready (sysper_icb_cmd_ready),
  .sysper_icb_rsp_err   (1'b0  ),
  .sysper_icb_rsp_rdata (32'b0),


  .sysfio_icb_cmd_valid(sysfio_icb_cmd_valid),
  .sysfio_icb_cmd_ready(sysfio_icb_cmd_ready),
  .sysfio_icb_cmd_read (), 
  .sysfio_icb_cmd_addr (), 
  .sysfio_icb_cmd_wdata(), 
  .sysfio_icb_cmd_wmask(), 
   
  .sysfio_icb_rsp_valid(sysfio_icb_cmd_valid),
  .sysfio_icb_rsp_ready(sysfio_icb_cmd_ready),
  .sysfio_icb_rsp_err  (1'b0  ),
  .sysfio_icb_rsp_rdata(32'b0),

  .sysmem_icb_cmd_valid(sysmem_icb_cmd_valid),
  .sysmem_icb_cmd_ready(sysmem_icb_cmd_ready),
  .sysmem_icb_cmd_read (), 
  .sysmem_icb_cmd_addr (), 
  .sysmem_icb_cmd_wdata(), 
  .sysmem_icb_cmd_wmask(), 

  .sysmem_icb_rsp_valid(sysmem_icb_cmd_valid),
  .sysmem_icb_rsp_ready(sysmem_icb_cmd_ready),
  .sysmem_icb_rsp_err  (1'b0  ),
  .sysmem_icb_rsp_rdata(32'b0),

  .io_pads_jtag_TCK_i_ival    (io_pads_jtag_TCK_i_ival    ),
  .io_pads_jtag_TCK_o_oval    (),
  .io_pads_jtag_TCK_o_oe      (),
  .io_pads_jtag_TCK_o_ie      (),
  .io_pads_jtag_TCK_o_pue     (),
  .io_pads_jtag_TCK_o_ds      (),

  .io_pads_jtag_TMS_i_ival    (io_pads_jtag_TMS_i_ival    ),
  .io_pads_jtag_TMS_o_oval    (),
  .io_pads_jtag_TMS_o_oe      (),
  .io_pads_jtag_TMS_o_ie      (),
  .io_pads_jtag_TMS_o_pue     (),
  .io_pads_jtag_TMS_o_ds      (),

  .io_pads_jtag_TDI_i_ival    (io_pads_jtag_TDI_i_ival    ),
  .io_pads_jtag_TDI_o_oval    (),
  .io_pads_jtag_TDI_o_oe      (),
  .io_pads_jtag_TDI_o_ie      (),
  .io_pads_jtag_TDI_o_pue     (),
  .io_pads_jtag_TDI_o_ds      (),

  .io_pads_jtag_TDO_i_ival    (1'b1    ),
  .io_pads_jtag_TDO_o_oval    (io_pads_jtag_TDO_o_oval    ),
  .io_pads_jtag_TDO_o_oe      (jtag_TDO_o_oe_int      ),
  .io_pads_jtag_TDO_o_ie      (),
  .io_pads_jtag_TDO_o_pue     (),
  .io_pads_jtag_TDO_o_ds      (),

  .io_pads_jtag_TRST_n_i_ival (1'b1 ),
  .io_pads_jtag_TRST_n_o_oval (),
  .io_pads_jtag_TRST_n_o_oe   (),
  .io_pads_jtag_TRST_n_o_ie   (),
  .io_pads_jtag_TRST_n_o_pue  (),
  .io_pads_jtag_TRST_n_o_ds   (),

  .test_mode(1'b0),
  .test_iso_override(1'b0),

  .io_pads_gpioA_i_ival       (io_pads_gpioA_i_ival),
  .io_pads_gpioA_o_oval       (io_pads_gpioA_o_oval),
  .io_pads_gpioA_o_oe         (gpioA_o_oe_int), 

  .io_pads_gpioB_i_ival       (io_pads_gpioB_i_ival),
  .io_pads_gpioB_o_oval       (io_pads_gpioB_o_oval),
  .io_pads_gpioB_o_oe         (gpioB_o_oe_int), 

  .io_pads_qspi0_sck_i_ival   (1'b1),
  .io_pads_qspi0_sck_o_oval   (io_pads_qspi0_sck_o_oval),
  .io_pads_qspi0_sck_o_oe     (),
  .io_pads_qspi0_dq_0_i_ival  (io_pads_qspi0_dq_0_i_ival),
  .io_pads_qspi0_dq_0_o_oval  (io_pads_qspi0_dq_0_o_oval),
  .io_pads_qspi0_dq_0_o_oe    (qspi0_dq_0_o_oe_int),
  .io_pads_qspi0_dq_1_i_ival  (io_pads_qspi0_dq_1_i_ival),
  .io_pads_qspi0_dq_1_o_oval  (io_pads_qspi0_dq_1_o_oval),
  .io_pads_qspi0_dq_1_o_oe    (qspi0_dq_1_o_oe_int),
  .io_pads_qspi0_dq_2_i_ival  (io_pads_qspi0_dq_2_i_ival),
  .io_pads_qspi0_dq_2_o_oval  (io_pads_qspi0_dq_2_o_oval),
  .io_pads_qspi0_dq_2_o_oe    (qspi0_dq_2_o_oe_int),
  .io_pads_qspi0_dq_3_i_ival  (io_pads_qspi0_dq_3_i_ival),
  .io_pads_qspi0_dq_3_o_oval  (io_pads_qspi0_dq_3_o_oval),
  .io_pads_qspi0_dq_3_o_oe    (qspi0_dq_3_o_oe_int),
  .io_pads_qspi0_cs_0_i_ival  (1'b1),
  .io_pads_qspi0_cs_0_o_oval  (io_pads_qspi0_cs_0_o_oval),
  .io_pads_qspi0_cs_0_o_oe    (), 

    .hfextclk        (hfextclk),
    .hfxoscen        (hfxoscen),
    .lfextclk        (lfextclk),
    .lfxoscen        (lfxoscen),
    .hfclk           (hfclk),
    .hfclkrst       (hfclkrst),

  .io_pads_aon_erst_n_i_ival        (io_pads_aon_erst_n_i_ival       ), 
  .io_pads_aon_erst_n_o_oval        (),
  .io_pads_aon_erst_n_o_oe          (),
  .io_pads_aon_erst_n_o_ie          (),
  .io_pads_aon_erst_n_o_pue         (),
  .io_pads_aon_erst_n_o_ds          (),
  .io_pads_aon_pmu_dwakeup_n_i_ival (io_pads_aon_pmu_dwakeup_n_i_ival),
  .io_pads_aon_pmu_dwakeup_n_o_oval (),
  .io_pads_aon_pmu_dwakeup_n_o_oe   (),
  .io_pads_aon_pmu_dwakeup_n_o_ie   (),
  .io_pads_aon_pmu_dwakeup_n_o_pue  (),
  .io_pads_aon_pmu_dwakeup_n_o_ds   (),
  .io_pads_aon_pmu_vddpaden_i_ival  (1'b1 ),
  .io_pads_aon_pmu_vddpaden_o_oval  (io_pads_aon_pmu_vddpaden_o_oval ),
  .io_pads_aon_pmu_vddpaden_o_oe    (),
  .io_pads_aon_pmu_vddpaden_o_ie    (),
  .io_pads_aon_pmu_vddpaden_o_pue   (),
  .io_pads_aon_pmu_vddpaden_o_ds    (),

  
    .io_pads_aon_pmu_padrst_i_ival    (1'b1 ),
    .io_pads_aon_pmu_padrst_o_oval    (io_pads_aon_pmu_padrst_o_oval ),
    .io_pads_aon_pmu_padrst_o_oe      (),
    .io_pads_aon_pmu_padrst_o_ie      (),
    .io_pads_aon_pmu_padrst_o_pue     (),
    .io_pads_aon_pmu_padrst_o_ds      (),

    .io_pads_bootrom_n_i_ival       (io_pads_bootrom_n_i_ival),
    .io_pads_bootrom_n_o_oval       (),
    .io_pads_bootrom_n_o_oe         (),
    .io_pads_bootrom_n_o_ie         (),
    .io_pads_bootrom_n_o_pue        (),
    .io_pads_bootrom_n_o_ds         (),

    .io_pads_dbgmode0_n_i_ival       (io_pads_dbgmode0_n_i_ival),

    .io_pads_dbgmode1_n_i_ival       (io_pads_dbgmode1_n_i_ival),

    .io_pads_dbgmode2_n_i_ival       (io_pads_dbgmode2_n_i_ival),

    .sram_icb_cmd_valid  (sram_icb_cmd_valid),
    .sram_icb_cmd_ready  (sram_icb_cmd_ready),
    .sram_icb_cmd_addr   (sram_icb_cmd_addr ),
    .sram_icb_cmd_read   (sram_icb_cmd_read ),
    .sram_icb_cmd_wdata  (sram_icb_cmd_wdata),
    .sram_icb_cmd_wmask  (sram_icb_cmd_wmask),
    .sram_icb_rsp_valid  (sram_icb_rsp_valid),
    .sram_icb_rsp_ready  (sram_icb_rsp_ready),
    .sram_icb_rsp_rdata  (sram_icb_rsp_rdata)

  );

   sram_icb #(
     .DW(`E203_XLEN),
     .MW(`E203_XLEN/8),
     .AW(19),
     .AW_LSB(2), // 字节寻址
     .USR_W(1),
     .DP(131072),
     .FORCE_X2ZERO(1)
   ) u_sram_icb (
      .clk(hfclk),
      .rst_n(~hfclkrst),
      .i_icb_cmd_valid(sram_icb_cmd_valid),
      .i_icb_cmd_ready(sram_icb_cmd_ready),
      .i_icb_cmd_read(sram_icb_cmd_read),
      .i_icb_cmd_addr(sram_icb_cmd_addr[18:0]),
      .i_icb_cmd_wdata(sram_icb_cmd_wdata),
      .i_icb_cmd_wmask(sram_icb_cmd_wmask),
      .i_icb_cmd_usr(1'b0),
      .i_icb_rsp_valid(sram_icb_rsp_valid),
      .i_icb_rsp_ready(sram_icb_rsp_ready),
      .i_icb_rsp_rdata(sram_icb_rsp_rdata),
      .i_icb_rsp_usr(),
      .tcm_cgstop(1'b0),
      .test_mode(1'b0)
  );

`ifdef FPGA_SOURCE
assign io_pads_jtag_TDO_o_oe = ~jtag_TDO_o_oe_int;
assign io_pads_gpioA_o_oe = ~gpioA_o_oe_int;
assign io_pads_gpioB_o_oe = ~gpioB_o_oe_int;
assign io_pads_qspi0_dq_0_o_oe = ~qspi0_dq_0_o_oe_int;
assign io_pads_qspi0_dq_1_o_oe = ~qspi0_dq_1_o_oe_int;
assign io_pads_qspi0_dq_2_o_oe = ~qspi0_dq_2_o_oe_int;
assign io_pads_qspi0_dq_3_o_oe = ~qspi0_dq_3_o_oe_int;
`else
assign io_pads_jtag_TDO_o_oe = jtag_TDO_o_oe_int;
assign io_pads_gpioA_o_oe = gpioA_o_oe_int;
assign io_pads_gpioB_o_oe = gpioB_o_oe_int;
assign io_pads_qspi0_dq_0_o_oe = qspi0_dq_0_o_oe_int;
assign io_pads_qspi0_dq_1_o_oe = qspi0_dq_1_o_oe_int;
assign io_pads_qspi0_dq_2_o_oe = qspi0_dq_2_o_oe_int;
assign io_pads_qspi0_dq_3_o_oe = qspi0_dq_3_o_oe_int;
`endif

endmodule
