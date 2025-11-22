
`include "icb_types.svh"

module icb_ext_flat_adapter #(
  parameter int WIDTH  = 32,
  parameter int ADDR_W = 19,
  parameter int LEN_W  = 3,
  parameter int MW     = (WIDTH/8)
)(
  input  logic clk,
  input  logic rst_n,

  // ICB ext 打包信号输入（从 master 来）
  input  icb_ext_cmd_m_t        icb_cmd_m,
  input  icb_ext_wr_m_t         icb_wr_m,
  output icb_ext_cmd_s_t        icb_cmd_s,
  output icb_ext_wr_s_t         icb_wr_s,
  output icb_ext_rsp_s_t        icb_rsp_s,
  input  icb_ext_rsp_m_t        icb_rsp_m,

  // 扁平 ICB (接 top_sram_icb_bridge)
  output logic                  sa_icb_cmd_valid,
  input  logic                  sa_icb_cmd_ready,
  output logic [ADDR_W-1:0]     sa_icb_cmd_addr,
  output logic                  sa_icb_cmd_read,
  output logic [LEN_W-1:0]      sa_icb_cmd_len,
  output logic [WIDTH-1:0]      sa_icb_cmd_wdata,
  output logic [MW-1:0]         sa_icb_cmd_wmask,
  output logic                  sa_icb_w_valid,
  input  logic                  sa_icb_w_ready,
  input  logic                  sa_icb_rsp_valid,
  output logic                  sa_icb_rsp_ready,
  input  logic [WIDTH-1:0]      sa_icb_rsp_rdata,
  input  logic                  sa_icb_rsp_err
);
  // master -> bridge (命令通道)
  assign sa_icb_cmd_valid = icb_cmd_m.valid;
  assign sa_icb_cmd_addr  = icb_cmd_m.addr[ADDR_W-1:0];
  assign sa_icb_cmd_read  = icb_cmd_m.read;
  assign sa_icb_cmd_len   = icb_cmd_m.len[LEN_W-1:0];

  // master -> bridge (写数据通道)
  assign sa_icb_cmd_wdata = icb_wr_m.wdata;
  assign sa_icb_cmd_wmask = icb_wr_m.wmask;
  assign sa_icb_w_valid   = icb_wr_m.w_valid;

  // bridge -> master (就绪信号)
  assign icb_cmd_s.ready  = sa_icb_cmd_ready;
  assign icb_wr_s.w_ready = sa_icb_w_ready;

  // bridge -> master (响应通道)
  assign icb_rsp_s = '{
    rsp_valid: sa_icb_rsp_valid,
    rsp_rdata: sa_icb_rsp_rdata,
    rsp_err  : sa_icb_rsp_err
  };

  // master -> bridge (响应就绪)
  assign sa_icb_rsp_ready = icb_rsp_m.rsp_ready;

endmodule
