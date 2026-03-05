/* 
* fc_top.v
*/

`timescale 1ns / 1ps

module fc_top 
  #(
    parameter integer C_S00_AXIS_TDATA_WIDTH = 32
  )
  (
    input wire CLK,
    input wire RESETN,

    // AXIS protocol
    output wire S_AXIS_TREADY, //  fc module?´ ë°›ì„ì¤?ë¹„ê??˜?—ˆ?‹¤.
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] S_AXIS_TDATA, //
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] S_AXIS_TKEEP, 
    input wire S_AXIS_TUSER, 
    input wire S_AXIS_TLAST, 
    input wire S_AXIS_TVALID, 

    input wire M_AXIS_TREADY, 
    output wire M_AXIS_TUSER, 
    output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] M_AXIS_TDATA, 
    output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] M_AXIS_TKEEP, 
    output wire M_AXIS_TLAST, 
    output wire M_AXIS_TVALID, 

    // APB protocol
    input wire [31:0] PADDR, 
    input wire PENABLE, 
    input wire PSEL, 
    input wire PWRITE, 
    input wire [31:0] PWDATA, 
    output wire [31:0] PRDATA, 
    output wire PREADY, 
    output wire PSLVERR
  );
  
  // For FC control path
  wire fc_start;
  wire fc_done;
  wire [31:0] clk_counter;
  wire [31:0] max_index;
  assign PREADY = 1'b1;
  assign PSLVERR = 1'b0;

  wire [3:0] state_done;
  wire [31:0] data_size;
  wire [2:0] COMMAND;

//  wire [31:0] entering_counter0;
//  wire [31:0] entering_counter1;
//  wire [31:0] entering_counter2;
//  wire [31:0] max_regs0;
//  wire [31:0] max_regs1;
//  wire [31:0] max_regs2;
  
  clk_counter_fc u_clk_counter(
    .clk   (CLK),
    .rstn  (RESETN),
    .start (fc_start),
    .done  (fc_done),

    .clk_counter (clk_counter)
  );
  
  fc_apb u_fc_apb(
    .PCLK    (CLK),
    .PRESETB (RESETN),
    .PADDR   ({16'd0,PADDR[15:0]}),
    .PSEL    (PSEL),
    .PENABLE (PENABLE),
    .PWRITE  (PWRITE),
    .PWDATA  (PWDATA),
    .PRDATA  (PRDATA),

    .clk_counter (clk_counter),
    .max_index   (max_index),

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports as you need
    //////////////////////////////////////////////////////////////////////////
    .fc_start(fc_start),
    .fc_done(fc_done),
    .state_done(state_done),
    .COMMAND(COMMAND),
    .data_size(data_size)
//    .entering_counter0(entering_counter0),
//    .entering_counter1(entering_counter1),
//    .entering_counter2(entering_counter2),
//    .max_regs0(max_regs0),
//    .max_regs1(max_regs1),
//    .max_regs2(max_regs2)
  );
  
  fc_module u_fc_module(
    .clk  (CLK),
    .rstn (RESETN),

    .S_AXIS_TREADY (S_AXIS_TREADY),
    .S_AXIS_TDATA  (S_AXIS_TDATA),
    .S_AXIS_TKEEP  (S_AXIS_TKEEP),
    .S_AXIS_TUSER  (S_AXIS_TUSER),
    .S_AXIS_TLAST  (S_AXIS_TLAST),
    .S_AXIS_TVALID (S_AXIS_TVALID),

    .M_AXIS_TREADY (M_AXIS_TREADY),
    .M_AXIS_TUSER  (M_AXIS_TUSER),
    .M_AXIS_TDATA  (M_AXIS_TDATA),
    .M_AXIS_TKEEP  (M_AXIS_TKEEP),
    .M_AXIS_TLAST  (M_AXIS_TLAST),
    .M_AXIS_TVALID (M_AXIS_TVALID),

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports as you need
    //////////////////////////////////////////////////////////////////////////
    .fc_start(fc_start),
    .fc_done(fc_done),
    .state_done(state_done),
    .COMMAND(COMMAND),
    .data_size(data_size),
    .max_index(max_index)
//    .entering_counter0(entering_counter0),
//    .entering_counter1(entering_counter1),
//    .entering_counter2(entering_counter2),
//    .max_regs0(max_regs0),
//    .max_regs1(max_regs1),
//    .max_regs2(max_regs2)

  );
  
endmodule