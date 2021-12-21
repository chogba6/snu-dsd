/*
* conv_top.v
*/

`timescale 1ns / 1ps

module conv_top 
  #(
    parameter integer C_S00_AXIS_TDATA_WIDTH = 32
  )
  (
    input wire CLK,
    input wire RESETN,

    // AXIS protocol
    output wire S_AXIS_TREADY,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] S_AXIS_TDATA,
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
    input wire PSEL, 
    input wire PENABLE, 
    input wire PWRITE, 
    input wire [31:0] PWDATA, 
    output wire PSLVERR, 
    output wire PREADY, 
    output wire [31:0] PRDATA
  );
  
  // For CONV control path
  wire          conv_start;   // you can use respond of this signal for handshaking
  wire          conv_done;    // you can use respond of this signal for handshaking
  wire [31:0]   clk_counter;
  assign PREADY = 1'b1;
  assign PSLVERR = 1'b0;

  // Wiring for module & apb connecting.
  wire [2:0] COMMAND;    // IDLE : 3'b000  //    Feature receive, 3'b001  // Bias receive :   3'b010 // Calculation start  3'b011 // Data Transmit 3'b100 //
  wire [8:0] InCh;        // Number of Input Channel -> Maximum : 256
  wire [8:0] OutCh;       // Number of Output Channel -> Maximum : 256
  wire [5:0] FLength;  // Columb Size of Input Feature Map -> Maximum : 32

  wire F_writedone;
  wire B_writedone;
  wire W_writedone;
//  wire transmit_done;

  
  clk_counter_conv u_clk_counter(
    .clk   (CLK),
    .rstn  (RESETN),
    .start (conv_start),
    .done  (conv_done),

    .clk_counter (clk_counter)
  );
  
  conv_module  #(.C_S00_AXIS_TDATA_WIDTH(C_S00_AXIS_TDATA_WIDTH)) 
  u_conv_module
  (
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

    .conv_start (conv_start),
    .conv_done  (conv_done),

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports if you need them
      .COMMAND(COMMAND),
      .InCh(InCh),
      .OutCh(OutCh),
      .FLength(FLength),
      .F_writedone(F_writedone),
      .B_writedone(B_writedone),
      .W_writedone(W_writedone)
      //.transmit_done(transmit_done)
    //////////////////////////////////////////////////////////////////////////

  );
  
  conv_apb u_conv_apb(
    .PCLK    (CLK),
    .PRESETB (RESETN),
    .PADDR   ({16'd0,PADDR[15:0]}),
    .PSEL    (PSEL),
    .PENABLE (PENABLE),
    .PWRITE  (PWRITE),
    .PWDATA  (PWDATA),
    .PRDATA  (PRDATA),

    .clk_counter (clk_counter),
    .conv_done   (conv_done),
    .conv_start  (conv_start),

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports if you need them
      .COMMAND(COMMAND),
      .InCh(InCh),
      .OutCh(OutCh),
      .FLength(FLength),
      .F_writedone(F_writedone),
      .B_writedone(B_writedone),
      .W_writedone(W_writedone)
      //.transmit_done(transmit_done)
    //////////////////////////////////////////////////////////////////////////
  );
  
endmodule
