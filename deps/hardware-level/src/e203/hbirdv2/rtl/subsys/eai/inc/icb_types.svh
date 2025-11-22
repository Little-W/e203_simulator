`ifndef __ICB_TYPES_SVH__
`define __ICB_TYPES_SVH__
`timescale 1ns/1ps

// ICB 类型定义（打包）
`include "eai_define.svh"
`include "e203_defines.v"

// 为了解决端口方向性问题，将命令/响应拆分为方向化的打包结构
// Master -> Slave: 命令有效载荷（master 驱动）
typedef struct packed {
    logic                       valid;                       // master 输出
    logic [`E203_ADDR_SIZE-1:0] addr;                        // master 输出
    logic                       read;                        // master 输出
    logic [`E203_XLEN-1:0]      wdata;                       // master 输出
    logic [`E203_XLEN_MW-1:0]   wmask;                       // master 输出
    logic [1:0]                 size;                        // master 输出
} icb_cmd_m_t;

// Slave -> Master: 命令返回的就绪信号（slave 驱动）
typedef struct packed {
    logic                       ready;                       // slave 输出
} icb_cmd_s_t;

// Slave -> Master: 响应有效载荷（slave 驱动）
typedef struct packed {
    logic                       rsp_valid;                   // slave 输出
    logic [`E203_XLEN-1:0]      rsp_rdata;                   // slave 输出
    logic                       rsp_err;                     // slave 输出
} icb_rsp_s_t;

// Master -> Slave: 响应就绪信号（master 驱动）
typedef struct packed {
    logic                       rsp_ready;                   // master 输出
} icb_rsp_m_t;

// Burst/非对齐/16 outstanding能力的 ICB pack 结构体定义
// 上游CMD请求通道
typedef struct packed {
    logic                       valid;                       // master 输出
    logic [`E203_ADDR_SIZE-1:0] addr;                        // master 输出
    logic                       read;                        // master 输出
    logic [`ICB_LEN_W-1:0]      len;                         // master 输出，突发长度，0表示1个数据
} icb_ext_cmd_m_t;

// 上游写数据通道
typedef struct packed {
    logic                       w_valid;                     // master 输出
    logic [`E203_XLEN-1:0]      wdata;                       // master 输出
    logic [3:0]                 wmask;                       // master 输出
} icb_ext_wr_m_t;

// 上游CMD就绪
typedef struct packed {
    logic                       ready;                       // slave 输出
} icb_ext_cmd_s_t;

// 上游写数据就绪
typedef struct packed {
    logic                       w_ready;                    // slave 输出
} icb_ext_wr_s_t;

// 上游响应通道
typedef struct packed {
    logic                       rsp_valid;                   // slave 输出
    logic [`E203_XLEN-1:0]      rsp_rdata;                   // slave 输出
    logic                       rsp_err;                     // slave 输出
} icb_ext_rsp_s_t;

// 上游响应就绪
typedef struct packed {
    logic                       rsp_ready;                   // master 输出
} icb_ext_rsp_m_t;
`endif // __ICB_TYPES_SVH__

