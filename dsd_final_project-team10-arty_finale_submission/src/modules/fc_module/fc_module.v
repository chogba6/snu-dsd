/*
* fc_module.v
*/

module fc_module 
  #(
    parameter integer C_S00_AXIS_TDATA_WIDTH = 32
  )
  (
    input wire clk,
    input wire rstn,

    output wire S_AXIS_TREADY,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] S_AXIS_TDATA,
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] S_AXIS_TKEEP, 
    input wire S_AXIS_TUSER, 
    input wire S_AXIS_TLAST, 
    input wire S_AXIS_TVALID, //valid?   ?   ??? master ???      ִ  tdata ??? ?  ?  ?  

    input wire M_AXIS_TREADY, 
    output wire M_AXIS_TUSER, 
    output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] M_AXIS_TDATA, 
    output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] M_AXIS_TKEEP, 
    output wire M_AXIS_TLAST, 
    output wire M_AXIS_TVALID,

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports as you need
    //////////////////////////////////////////////////////////////////////////
    output wire [3:0] state_done,
    input wire fc_start,
    output reg fc_done,
    //input wire [3:0] fc_state,
    input wire [31:0] data_size,
    input wire [2:0] COMMAND,
    output reg [31:0] max_index
  ); 

  localparam STATE_IDLE = 4'd0,
  STATE_RECEIVE_FEATURE = 4'd1,
  STATE_RECEIVE_BIAS = 4'd2,
  STATE_RECEIVE_WEIGHT_AND_READ_FEATURE = 4'd3,
  //STATE_READ_BIAS = 4'd4,
  STATE_RECEIVE_WEIGHT = 4'd4,
  STATE_COMPUTE = 4'd5,
  STATE_PSUM = 4'd6,
  STATE_ADD_BIAS = 4'd7,
  STATE_WRITE_RESULT = 4'd7,
  STATE_SEND_RESULT = 4'd8,
  PARAM_FEATURE_SIZE = 9'd64; // Set this value to 64, if FPGA test .. 256 if tb test
  
  reg [3:0] state;
  
  reg m_axis_tuser;
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0] m_axis_tdata;
  reg [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] m_axis_tkeep;
  reg m_axis_tlast;
  reg m_axis_tvalid;
  wire s_axis_tready;
 
  
  assign S_AXIS_TREADY = s_axis_tready;
  //assign M_AXIS_TDATA = m_axis_tdata;
  assign M_AXIS_TLAST = m_axis_tlast;
  assign M_AXIS_TVALID = m_axis_tvalid;
  assign M_AXIS_TUSER = 1'b0;
  assign M_AXIS_TKEEP = {(C_S00_AXIS_TDATA_WIDTH/8) {1'b1}};

  ////////////////////////////////////////////////////////////////////////////
  // TODO : Write your code here
  ////////////////////////////////////////////////////////////////////////////

  // variable for receive feature and bias
  reg [3:0] state_done_reg;
  assign state_done = state_done_reg; 
  reg tlast; 
  reg [1:0] cal_counter;

  //variable for feature, bias sram
  reg [31:0] din;
  reg [8:0] addr;
  reg [8:0] in1;
  wire [31:0] dout;
  reg bram_en;
  reg we;
  reg [8:0] feature_start_address;
  reg [8:0] bias_start_address;
  
  sram_32x512 u_fc_sram_32x512( //sram ?       32bit?   ?  ?   ?   ?  ?  
    .addra(addr),
    .clka(clk),
    .dina(din),
    .douta(dout),
    .ena(bram_en),
    .wea(we)
  );
  
  // variable for receive weight and calculate
  integer i, j;
  reg [20:0] input_size;
  reg [20:0] output_size;
  reg signed [31:0] temp [0:1];
  reg signed [31:0] result_buffer_pre [0:3];
  wire signed [7:0] result_buffer [0:3];
  reg signed [7:0] bias_buffer [0:3];
  reg pe_rstn;
  reg [1:0] total_counter;
  reg [31:0] data_counter;
  reg [10:0] feature_counter;
  reg [8:0] bias_counter;
  reg [1:0] sram_wait_counter;
  assign result_buffer[0] = (result_buffer_pre[0][31]) ? ((input_size == PARAM_FEATURE_SIZE) ? ((result_buffer_pre[0][30:13] != 18'h3ffff) ? 8'b1000_0000 : ({1'b1, result_buffer_pre[0][12:6]}+1'b1)) : 8'b0 )
  : ((result_buffer_pre[0][30:13] != 18'b0) ? 8'b0111_1111 : {1'b0, result_buffer_pre[0][12:6]});
  assign result_buffer[1] = (result_buffer_pre[1][31]) ? ((input_size == PARAM_FEATURE_SIZE) ? ((result_buffer_pre[1][30:13] != 18'h3ffff) ? 8'b1000_0000 : ({1'b1, result_buffer_pre[1][12:6]}+1'b1)) : 8'b0 )
  : ((result_buffer_pre[1][30:13] != 18'b0) ? 8'b0111_1111 : {1'b0, result_buffer_pre[1][12:6]});
  assign result_buffer[2] = (result_buffer_pre[2][31]) ? ((input_size == PARAM_FEATURE_SIZE) ? ((result_buffer_pre[2][30:13] != 18'h3ffff) ? 8'b1000_0000 : ({1'b1, result_buffer_pre[2][12:6]}+1'b1)) : 8'b0 )
  : ((result_buffer_pre[2][30:13] != 18'b0) ? 8'b0111_1111 : {1'b0, result_buffer_pre[2][12:6]});
  assign result_buffer[3] = (result_buffer_pre[3][31]) ? ((input_size == PARAM_FEATURE_SIZE) ? ((result_buffer_pre[3][30:13] != 18'h3ffff) ? 8'b1000_0000 : ({1'b1, result_buffer_pre[3][12:6]}+1'b1)) : 8'b0 )
  : ((result_buffer_pre[3][30:13] != 18'b0) ? 8'b0111_1111 : {1'b0, result_buffer_pre[3][12:6]});

  assign M_AXIS_TDATA = {result_buffer[3], result_buffer[2], result_buffer[1], result_buffer[0]};

  
  // variable for pe module;
  genvar t;
  reg signed [7:0] in_a [0:3];
  reg signed [7:0] in_b [0:3];
  wire signed [31:0] out_c [0:3];
  generate
    for(t = 0; t < 4; t = t + 1) begin : pe_set
      pe u_pe(clk, pe_rstn, S_AXIS_TVALID, S_AXIS_TLAST, in_a[t], in_b[t], out_c[t]);
    end
  endgenerate
  //assign s_axis_tready = 1;
  assign s_axis_tready = (state == STATE_RECEIVE_FEATURE || state == STATE_RECEIVE_WEIGHT || state == STATE_RECEIVE_BIAS) && (~tlast) && (~w_wait); //potential problem : data miss


  // control path
  always @(posedge clk) begin
    if (!rstn) begin
      state <= STATE_IDLE;
      tlast <= 0;
      data_counter <= 0;
      
    end
    else begin
      //state <= fc_state;
      case (state)
        STATE_IDLE: begin
          if(fc_done) begin
            if(idle_counter == 0) begin
                
            end
            else if(idle_counter == 1) begin
                data_counter <= 0;
                input_size <= 0;
                tlast <= 0;
                output_size <= 0;
            end
          end
          if(fc_start &&(COMMAND == 1)) begin 
            state <= STATE_RECEIVE_FEATURE;
          end
        end
        STATE_RECEIVE_FEATURE: begin
          if (tlast) begin
            
          end
          else begin
            if (S_AXIS_TVALID && s_axis_tready) begin
              data_counter <= data_counter + 1;
              if(data_counter == 0) input_size <= data_size;
              if (S_AXIS_TLAST) tlast <= 1'b1;
            end
          end
          
          if(COMMAND == 2) begin
            state <= STATE_RECEIVE_BIAS;
            tlast <= 0;
            data_counter <= 0;
          end
        end
        STATE_RECEIVE_BIAS: begin
          if (tlast) begin
            
          end
          else begin
            if (S_AXIS_TVALID && s_axis_tready) begin
              if (S_AXIS_TLAST) tlast <= 1'b1; 
              data_counter <= data_counter + 1;
              if(!data_counter) output_size <= data_size;
            end
          end
          
          if(COMMAND == 4) begin
            state <= STATE_RECEIVE_WEIGHT;
            tlast <= 0;
          end
        end
        STATE_RECEIVE_WEIGHT_AND_READ_FEATURE: begin
          
        end
        STATE_RECEIVE_WEIGHT: begin           //in fact, we concurrently receive weight and calculate result here         
          if(sram_wait_counter == 2) begin
            if(tlast) begin              
              if (cal_counter == 3) begin                
                tlast <= 0;  
                if(bias_counter == output_size - 1) begin
                    
                end              
              end
            end
            else if (S_AXIS_TVALID && s_axis_tready) begin                          
              if((feature_counter == (input_size >> 2) - 1) || S_AXIS_TLAST) begin
                tlast <= 1;    
              end        
            end
          end
          if(COMMAND == 5) state <= STATE_COMPUTE;
        end
        STATE_COMPUTE: begin                  //in fact, we send our result(write our result) to vdma(?)
          if(COMMAND == 0) state <= STATE_IDLE;
        end
        STATE_WRITE_RESULT: begin
          
        end
        STATE_SEND_RESULT: begin
          
        end
      endcase
    end
  end

  reg signed [31:0] max_buffer;
  reg w_wait;
  reg [31:0] low_valid_counter;
  reg [31:0] omit_data;
  reg [2:0] idle_counter;
  // data path
  always @(posedge clk) begin
    if (!rstn) begin      
      state_done_reg <= 0;
      for(j = 0; j <4; j = j + 1) begin
        in_a[j] <= 0;
        in_b[j] <= 0;
      end
      din <= 32'b0;
      addr <= 8'b0;
      in1 <= 8'b0;
      bram_en <= 1'b0;
      we <= 1'b0;
      sram_wait_counter <= 0;
      w_wait <= 0;
      feature_counter <= 0;
      bias_counter <= 0;
      cal_counter <= 0;
      total_counter <= 0;
      low_valid_counter <= 0;
      pe_rstn <= 0;
      idle_counter <= 0;
      fc_done <= 0;
      bias_start_address  <= 0;
      feature_start_address <= 0;
      m_axis_tvalid <= 0;
      m_axis_tlast <= 0;
      result_buffer_pre[0] <= 32'b0;
      result_buffer_pre[1] <= 32'b0;
      result_buffer_pre[2] <= 32'b0;
      result_buffer_pre[3] <= 32'b0;
      bias_buffer[0] <= 8'b0;
      bias_buffer[1] <= 8'b0;
      bias_buffer[2] <= 8'b0;
      bias_buffer[3] <= 8'b0;
      max_buffer <= 32'h8000_0000;
      max_index <= 0;
    end
    else begin
      case (state)
        STATE_IDLE: begin
          if(fc_done) begin
            if(idle_counter == 0) begin
                idle_counter <= 1;
                m_axis_tlast  <= 0;
                m_axis_tvalid <= 0;
            end
            else if(idle_counter == 1) begin
                state_done_reg <= 0;
                for(j = 0; j <4; j = j + 1) begin
                    in_a[j] <= 0;
                    in_b[j] <= 0;
                end
                din <= 32'b0;
                addr <= 8'b0;
                in1 <= 8'b0;
                bram_en <= 1'b0;
                we <= 1'b0;
                sram_wait_counter <= 0;
                w_wait <= 0;
                feature_counter <= 0;
                bias_counter <= 0;
                cal_counter <= 0;
                total_counter <= 0;
                low_valid_counter <= 0;
                pe_rstn <= 0;
                idle_counter <= 0;
                bias_start_address  <= 0;
                feature_start_address <= 0;
                m_axis_tvalid <= 0;
                m_axis_tlast <= 0;
                result_buffer_pre[0] <= 32'b0;
                result_buffer_pre[1] <= 32'b0;
                result_buffer_pre[2] <= 32'b0;
                result_buffer_pre[3] <= 32'b0;
                bias_buffer[0] <= 8'b0;
                bias_buffer[1] <= 8'b0;
                bias_buffer[2] <= 8'b0;
                bias_buffer[3] <= 8'b0;
                max_buffer <= 32'h8000_0000;
            end
          end
        end
        STATE_RECEIVE_FEATURE: begin
          if (tlast) begin
            state_done_reg[0] <= 1'b1;
            bram_en <= 1'b0;
            we <= 1'b0;
            bias_start_address <= in1;
            feature_start_address <= 0;
          end
          else begin
            if (S_AXIS_TVALID && s_axis_tready) begin
              fc_done <= 0;
              max_index <= 0;
              din <= S_AXIS_TDATA;
              addr <= in1;
              in1 <= in1 + 1;
              bram_en <= 1'b1;
              we <= 1'b1;
            end
          end
        end
        STATE_RECEIVE_BIAS: begin
          if (tlast) begin
            state_done_reg[1] <= 1'b1;
            bram_en <= 1'b0;
            we <= 1'b0;
            w_wait <= 1'b1;
            in1 <= feature_start_address;
          end
          else begin
            if (S_AXIS_TVALID && s_axis_tready) begin
              din <= S_AXIS_TDATA;
              addr <= in1;
              in1 <= in1 + 1;
              bram_en <= 1'b1;
              we <= 1'b1;
            end
          end
        end
        STATE_RECEIVE_WEIGHT: begin //RECEIVE WEIGHT AND CALCULATION
          if(sram_wait_counter == 0) begin
            sram_wait_counter <= 1;
            bram_en <= 1;
            we <= 0;
            addr <= in1;
            in1 <= feature_start_address + 1;
          end
          else if(sram_wait_counter == 1) begin
            sram_wait_counter <= 2;
            bram_en <= 1;
            we <= 0;
            addr <= in1;
            in1 <= in1 + 1;
            w_wait <= 1'b0;
          end
          else if(sram_wait_counter == 2) begin
            if(tlast) begin
              cal_counter <= cal_counter + 1;
              if(cal_counter == 0) begin
                bram_en <= 1;
                we <= 0;
                addr <= bias_start_address + (bias_counter >> 2);
              end
              else if(cal_counter == 1) begin                
                in1 <= 0;
              end
              else if(cal_counter == 2) begin            
                temp[0] <= $signed(out_c[0]) + $signed(out_c[1]);
                temp[1] <= $signed(out_c[2]) + $signed(out_c[3]);
                bram_en <= 1;
                we <= 0;
                addr <= in1;
                in1 <= in1 + 1;
                bias_buffer[0] <= dout[7:0];
                bias_buffer[1] <= dout[15:8];
                bias_buffer[2] <= dout[23:16];
                bias_buffer[3] <= dout[31:24];
              end
              else if (cal_counter == 3) begin
                result_buffer_pre[total_counter] <= $signed(temp[0]) + $signed(temp[1]) + $signed({{18{bias_buffer[total_counter][7]}}, bias_buffer[total_counter], 6'b0});
                if(input_size == PARAM_FEATURE_SIZE && $signed(temp[0]) + $signed(temp[1]) + $signed({{18{bias_buffer[total_counter][7]}}, bias_buffer[total_counter], 6'b0}) >= max_buffer) begin 
                  max_index <= bias_counter;
                  max_buffer <= $signed(temp[0]) + $signed(temp[1]) + $signed({{18{bias_buffer[total_counter][7]}}, bias_buffer[total_counter], 6'b0});
                end
                
                total_counter <= total_counter + 1;
                bias_counter <= bias_counter + 1;
                pe_rstn <= 1'b0;
                feature_counter <= 0;
                w_wait <= 0;
                bram_en <= 1;
                we <= 0;
                addr <= in1;
                in1 <= in1 + 1;
                if(total_counter == 3) begin //total_counter : vdma uses 32bit so checking whether we make 4 output feature
                  m_axis_tvalid <= 1;
                end
                if(bias_counter == output_size - 1) begin
                  m_axis_tvalid <= 1;
                  state_done_reg[3] <= 1'b1;
                  m_axis_tlast <= 1;
                end
              end
            end
            else if (S_AXIS_TVALID && s_axis_tready) begin              
              feature_counter <= feature_counter + 1;
              m_axis_tvalid <= 0;
              m_axis_tlast <= 0;
              pe_rstn <= 1'b1;
              in_b[0] <= S_AXIS_TDATA[7:0];
              in_b[1] <= S_AXIS_TDATA[15:8];
              in_b[2] <= S_AXIS_TDATA[23:16];
              in_b[3] <= S_AXIS_TDATA[31:24];

              if(low_valid_counter != 0) begin
                in_a[0] <= omit_data[7:0];
                in_a[1] <= omit_data[15:8];
                in_a[2] <= omit_data[23:16];
                in_a[3] <= omit_data[31:24];
                low_valid_counter <= 0;
              end
              else begin
                in_a[0] <= dout[7:0];
                in_a[1] <= dout[15:8];
                in_a[2] <= dout[23:16];
                in_a[3] <= dout[31:24];
              end

              if(feature_counter < (input_size >> 2) - 1) begin
                bram_en <= 1'b1;
                we <= 0;
                addr <= in1;
                in1 <= in1 + 1;
              end
              else if((feature_counter == (input_size >> 2) - 1) || S_AXIS_TLAST) begin
                bram_en <= 1;
                w_wait <= 1'b1;
                cal_counter <= 0;    
              end        
            end
            else begin
              m_axis_tvalid <= 0;
              m_axis_tlast <= 0;
              low_valid_counter <= low_valid_counter + 1;
              if(!low_valid_counter) omit_data <= dout;
            end
          end
        end
        STATE_COMPUTE: begin
          fc_done <= 1;
        end/*
        STATE_ACCUM: begin
          
        end
        STATE_WRITE_RESULT: begin
          
        end
        STATE_SEND_RESULT: begin
          
        end*/
      endcase
    end
  end
endmodule
module pe(clk, rstn, S_AXIS_TVALID, S_AXIS_TLAST, in_a, in_b, out_c);
  input wire clk, rstn, S_AXIS_TVALID, S_AXIS_TLAST;
  input wire signed [7:0] in_a, in_b;
  output reg signed [31:0] out_c;

  reg signed [31:0] temp1;
  
  always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      out_c <= 0;
      temp1 <= 0;
    end
    else begin
      if(!S_AXIS_TVALID && !S_AXIS_TLAST) begin
        out_c <= out_c;
        temp1 <= temp1;
      end
      else begin
        temp1 <= in_a * in_b;
        out_c <= $signed(out_c) + temp1;
      end
    end
  end
endmodule