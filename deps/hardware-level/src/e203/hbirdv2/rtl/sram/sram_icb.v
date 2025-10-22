module sram_icb #(
  parameter DW = 32,
  parameter MW = 4,
  parameter AW = 19,
  parameter AW_LSB = 2,
  parameter USR_W = 1,
  parameter DP = 131072,
  parameter FORCE_X2ZERO = 1
)(
  input                   clk,
  input                   rst_n,
  input                   i_icb_cmd_valid,
  output                  i_icb_cmd_ready,
  input                   i_icb_cmd_read,
  input  [AW-1:0]         i_icb_cmd_addr,
  input  [DW-1:0]         i_icb_cmd_wdata,
  input  [MW-1:0]         i_icb_cmd_wmask,
  input  [USR_W-1:0]      i_icb_cmd_usr,
  output                  i_icb_rsp_valid,
  input                   i_icb_rsp_ready,
  output [DW-1:0]         i_icb_rsp_rdata,
  output [USR_W-1:0]      i_icb_rsp_usr,
  input                   tcm_cgstop,
  input                   test_mode
);

  wire sram_ctrl_active;
  wire ram_cs;
  wire ram_we;
  wire [AW-AW_LSB-1:0] ram_addr;
  wire [MW-1:0] ram_wem;
  wire [DW-1:0] ram_din;
  wire [DW-1:0] ram_dout;
  wire clk_ram;

  sram_icb_ctrl #(
    .DW(DW),
    .MW(MW),
    .AW(AW),
    .AW_LSB(AW_LSB),
    .USR_W(USR_W)
  ) u_sram_icb_ctrl (
    .sram_ctrl_active(sram_ctrl_active),
    .tcm_cgstop      (tcm_cgstop),
    .i_icb_cmd_valid (i_icb_cmd_valid),
    .i_icb_cmd_ready (i_icb_cmd_ready),
    .i_icb_cmd_read  (i_icb_cmd_read),
    .i_icb_cmd_addr  (i_icb_cmd_addr),
    .i_icb_cmd_wdata (i_icb_cmd_wdata),
    .i_icb_cmd_wmask (i_icb_cmd_wmask),
    .i_icb_cmd_usr   (i_icb_cmd_usr),
    .i_icb_rsp_valid (i_icb_rsp_valid),
    .i_icb_rsp_ready (i_icb_rsp_ready),
    .i_icb_rsp_rdata (i_icb_rsp_rdata),
    .i_icb_rsp_usr   (i_icb_rsp_usr),
    .ram_cs   (ram_cs),
    .ram_we   (ram_we),
    .ram_addr (ram_addr),
    .ram_wem  (ram_wem),
    .ram_din  (ram_din),
    .ram_dout (ram_dout),
    .clk_ram  (clk_ram),
    .test_mode(test_mode),
    .clk      (clk),
    .rst_n    (rst_n)
  );

  sirv_gnrl_ram #(
    .DP(DP),
    .FORCE_X2ZERO(FORCE_X2ZERO),
    .DW(DW),
    .MW(MW),
    .AW(AW-AW_LSB),
    .MEM_PATH(`E203_CFG_EXTRAM_INIT_PATH),    // 新增
    .INIT_EN(`E203_CFG_EXTRAM_INIT_EN)        // 新增
  ) u_sram (
    .sd  (  ),
    .ds  (  ),
    .ls  (  ),
    .clk  (clk_ram),
    .rst_n(rst_n),
    .din  (ram_din),
    .addr (ram_addr),
    .cs   (ram_cs),
    .we   (ram_we),
    .wem  (ram_wem),
    .dout (ram_dout)
  );

endmodule