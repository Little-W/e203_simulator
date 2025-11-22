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
// Designer   : AI Assistant
//
// Description:
//  Dummy MMA Top Module for early verification
//  Provides simple handshake and timing behavior without actual computation
//
// ====================================================================
`include "e203_defines.v"

module dummy_mma_top #(
    parameter int unsigned WEIGHT_WIDTH = 8,
    parameter int unsigned DATA_WIDTH   = 16,
    parameter int unsigned SIZE         = 16,
    parameter int unsigned BUS_WIDTH    = 32,
    parameter int unsigned REG_WIDTH    = 32,
    parameter int unsigned ADDR_WIDTH   = 32,
    parameter int unsigned LEN_WIDTH    = 3
) (
    //==== 时钟与复位 ====
    input wire clk,
    input wire rst_n,

    //==== 外部控制接口 ====
    input  wire calc_start,
    input  wire cfg_16bits_ia,
    output wire sa_ready,

    //==== 写回握手接口 ====
    output wire       wb_valid,
    input  wire       wb_ready,
    output wire [1:0] err_code,

    //==== CSR 配置输入（仅用于验证，不实际使用）====
    input logic [REG_WIDTH-1:0] lhs_base,
    input logic [REG_WIDTH-1:0] rhs_base,
    input logic [REG_WIDTH-1:0] dst_base,
    input logic [REG_WIDTH-1:0] bias_base,
    input logic signed [REG_WIDTH-1:0] lhs_zp,
    input logic signed [REG_WIDTH-1:0] rhs_zp,
    input logic signed [REG_WIDTH-1:0] dst_zp,
    input logic signed [REG_WIDTH-1:0] q_mult_pt,
    input logic signed [REG_WIDTH-1:0] q_shift_pt,
    input logic                        use_per_channel,
    input logic [REG_WIDTH-1:0] k,
    input logic [REG_WIDTH-1:0] n,
    input logic [REG_WIDTH-1:0] m,
    input logic [REG_WIDTH-1:0] lhs_row_stride_b,
    input logic [REG_WIDTH-1:0] dst_row_stride_b,
    input logic [REG_WIDTH-1:0] rhs_col_stride_b,
    input logic signed [REG_WIDTH-1:0] act_min,
    input logic signed [REG_WIDTH-1:0] act_max,

    //==== ICB 接口（全部悬空，不产生访存）====
    output logic                      sa_icb_cmd_valid,
    input  logic                      sa_icb_cmd_ready,
    output logic [ADDR_WIDTH-1:0]     sa_icb_cmd_addr,
    output logic                      sa_icb_cmd_read,
    output logic [LEN_WIDTH-1:0]      sa_icb_cmd_len,
    output logic [BUS_WIDTH-1:0]      sa_icb_cmd_wdata,
    output logic [BUS_WIDTH/8-1:0]    sa_icb_cmd_wmask,
    output logic                      sa_icb_w_valid,
    input  logic                      sa_icb_w_ready,
    input  logic                      sa_icb_rsp_valid,
    output logic                      sa_icb_rsp_ready,
    input  logic [BUS_WIDTH-1:0]      sa_icb_rsp_rdata,
    input  logic                      sa_icb_rsp_err
);

    // ========================================================================
    // 内部状态机
    // ========================================================================
    localparam IDLE       = 2'b00;
    localparam COMPUTING  = 2'b01;
    localparam DONE       = 2'b10;

    reg [1:0] state;
    reg [7:0] cycle_cnt;  // 模拟计算周期计数器

    // 模拟计算延迟（可配置）
    localparam COMPUTE_CYCLES = 8'd10;

    // ========================================================================
    // 状态机逻辑
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            cycle_cnt <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (calc_start) begin
                        state     <= COMPUTING;
                        cycle_cnt <= 8'd0;
                    end
                end

                COMPUTING: begin
                    if (cycle_cnt >= COMPUTE_CYCLES - 1) begin
                        state     <= DONE;
                        cycle_cnt <= 8'd0;
                    end else begin
                        cycle_cnt <= cycle_cnt + 1'b1;
                    end
                end

                DONE: begin
                    // 等待写回握手完成
                    if (wb_valid && wb_ready) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // ========================================================================
    // 输出信号生成
    // ========================================================================
    // sa_ready: 空闲时为高
    assign sa_ready = (state == IDLE);

    // wb_valid: DONE 状态时拉高
    assign wb_valid = (state == DONE);

    // err_code: 固定返回成功（0x00）
    assign err_code = 2'b00;

    // ========================================================================
    // ICB 接口（全部悬空）
    // ========================================================================
    assign sa_icb_cmd_valid = 1'b0;
    assign sa_icb_cmd_addr  = {ADDR_WIDTH{1'b0}};
    assign sa_icb_cmd_read  = 1'b0;
    assign sa_icb_cmd_len   = {LEN_WIDTH{1'b0}};
    assign sa_icb_cmd_wdata = {BUS_WIDTH{1'b0}};
    assign sa_icb_cmd_wmask = {(BUS_WIDTH/8){1'b0}};
    assign sa_icb_w_valid   = 1'b0;
    assign sa_icb_rsp_ready = 1'b1;

    // ========================================================================
    // Optional: Debug signals
    // ========================================================================
`ifdef DEBUG_DUMMY_MMA
    always @(posedge clk) begin
        if (calc_start) begin
            $display("[Dummy MMA] Computation started");
        end
        if (state == COMPUTING && cycle_cnt == COMPUTE_CYCLES - 1) begin
            $display("[Dummy MMA] Computation completed after %0d cycles", COMPUTE_CYCLES);
        end
        if (wb_valid && wb_ready) begin
            $display("[Dummy MMA] Write-back handshake completed, err_code=0x%h", err_code);
        end
    end
`endif

endmodule
