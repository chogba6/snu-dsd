/*
* fc_apb.v
*/

module fc_apb
  (
    input wire PCLK,
    input wire PRESETB,        // APB asynchronous reset (0: reset, 1: normal)
    input wire [31:0] PADDR,   // APB address ?—¬ê¸°ì„œ faddr + 0x10 ?´ë©? feature receiving?´ ??‚¬?Œ?„ ?•Œ? ¤ì¤?-> prdataë¡? ?•Œ? ¤ì¤˜ã…‘?•¨  faddr + 0x00, 0xi ë©? ië²ˆì§¸ state?ž„?„ ?•Œ? ¤ì¤?
    input wire PSEL,           // APB select
    input wire PENABLE,        // APB enable
    input wire PWRITE,         // APB write enable
    input wire [31:0] PWDATA,  // APB write data
    output wire [31:0] PRDATA,  // CPU interface out

    input wire [31:0] clk_counter,
    input wire [31:0] max_index,

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports as you need
    //////////////////////////////////////////////////////////////////////////
    output reg fc_start,
    input wire fc_done,
    //output wire [3:0] fc_state, //to fc_module, ?–´?–¤ stateë¥? ?‹œ?ž‘?• ì§?
    input wire [3:0] state_done, //from fc_module
    output wire [31:0] data_size, //to fc_module
    output reg [2:0] COMMAND
//    input wire [31:0] entering_counter0,
//    input wire [31:0] entering_counter1,
//    input wire [31:0] entering_counter2,
//    input wire [31:0] max_regs0,
//    input wire [31:0] max_regs1,
//    input wire [31:0] max_regs2
    
  );

  wire state_enable;
  wire state_enable_pre;
  reg [31:0] prdata_reg;

  
  assign state_enable = PSEL & PENABLE;
  assign state_enable_pre = PSEL & ~PENABLE;
  
  ////////////////////////////////////////////////////////////////////////////
  // TODO : Write your code here
  ////////////////////////////////////////////////////////////////////////////
  reg [31:0] data_size_reg;
  assign data_size = data_size_reg;
  // READ OUTPUT
  always @(posedge PCLK, negedge PRESETB) begin
    if (PRESETB == 1'b0) begin
      prdata_reg <= 32'h00000000;
    end
    else begin
      if (~PWRITE & state_enable_pre) begin
        case ({PADDR[31:2], 2'h0})
          /*READOUT*/
          32'h00000018 : prdata_reg <= clk_counter;
          32'h00000020 : prdata_reg <= max_index;
          32'h00000010 : prdata_reg <= state_done[0]; // state1
          32'h00000014 : prdata_reg <= state_done[1]; // state2
          32'h00000008 : prdata_reg <= state_done[3]; // state4
          32'h0000000c : prdata_reg <= fc_done; // state5
//          32'h00000030 : prdata_reg <= entering_counter0;
//          32'h00000034 : prdata_reg <= entering_counter1;
//          32'h0000003c : prdata_reg <= entering_counter2;
//          32'h00000040 : prdata_reg <= max_regs0;
//          32'h00000044 : prdata_reg <= max_regs1;
//          32'h0000004c : prdata_reg <= max_regs2;
          default: prdata_reg <= 32'h0;
        endcase
      end
      else begin
        prdata_reg <= 32'h0;
      end
    end
  end
  
  assign PRDATA = (~PWRITE & state_enable) ? prdata_reg : 32'h00000000;
  
  // WRITE ACCESS
  always @(posedge PCLK, negedge PRESETB) begin
    if (PRESETB == 1'b0) begin
      /*WRITERES*/
      fc_start <= 0;
     
    end
    else begin
      if (PWRITE & state_enable) begin
        case ({PADDR[31:2], 2'h0})
          /*WRITEIN*/
          32'h00000000 : begin
            if(PWDATA == 1) fc_start <= 1;
            COMMAND <= PWDATA;
          end
          32'h00000004 : begin
            data_size_reg <= PWDATA;
          end
          default: ;
        endcase
      end
    end
  end
endmodule