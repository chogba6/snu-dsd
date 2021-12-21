/*
* conv_module.v
*/

module conv_module 
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
    input wire S_AXIS_TVALID, 

    input wire M_AXIS_TREADY, 
    output wire M_AXIS_TUSER, 
    output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] M_AXIS_TDATA, 
    output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] M_AXIS_TKEEP, 
    output wire M_AXIS_TLAST, 
    output wire M_AXIS_TVALID, 

    input conv_start, 
    output reg conv_done,

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports if you need them
    input [2:0] COMMAND,    // IDLE : 3'b000  //    Feature receive, 3'b001  // Bias receive :   3'b010 // Calculation start  3'b011 // Data Transmit 3'b100 //
    input [8:0] InCh,        // Number of Input Channel -> Maximum : 256
    input [8:0] OutCh,       // Number of Output Channel -> Maximum : 256
    input [5:0] FLength,  // Columb Size of Input Feature Map -> Maximum : 32

    output reg F_writedone,
    output reg B_writedone,
    output reg W_writedone
//    output reg transmit_done

    //output reg rdy_to_transmit
    //input  F_writedone_respond,
    //input  B_writedone_respond,
    //input  W_writedone_respond,
    //input  transmit_done_respond
    //////////////////////////////////////////////////////////////////////////

  );
  
  reg                                           m_axis_tuser;
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0]            m_axis_tdata;
  reg [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        m_axis_tkeep;
  reg                                           m_axis_tlast;
  reg                                           m_axis_tvalid;
  wire                                          s_axis_tready;
  
  assign S_AXIS_TREADY = s_axis_tready;
 // assign M_AXIS_TDATA = m_axis_tdata;
  assign M_AXIS_TLAST = m_axis_tlast;
  assign M_AXIS_TVALID = m_axis_tvalid;
  assign M_AXIS_TUSER = 1'b0;
  assign M_AXIS_TKEEP = {(C_S00_AXIS_TDATA_WIDTH/8) {1'b1}};

  ////////////////////////////////////////////////////////////////////////////
  // TODO : Write your code here
  localparam STATE_IDLE = 3'b000,
  STATE_RECEIVE_FEATURE = 3'b001, // Feature into SRAM
  STATE_RECEIVE_BIAS = 3'b010,    // Bias into reg
  STATE_RECEIVE_WEIGHT = 3'b011,  // Calculation & Sending is also done in this state
  STATE_SEND_RESULT = 3'b100,     // Kind of a dummy state
  ////////////////
  STATE_WEIGHT_SETTING = 4'b0101,   // Resetting the weight_reg & feature_reg.
  STATE_FEATURE_SETTING = 4'b0110,  // [1st state] Setting the weight_reg & feature_reg. (PE is currently inactive)
  STATE_BIAS_SETTING = 4'b0111,     // Setting the bias
  STATE_PE_CALCULATING = 4'b1000,  // PE is currently active
  STATE_DATA_SENDING = 4'b1001;    // PE partial data is sent through M_AXIS_TDATA

  /////////////////////////////// VARIABLES //////////////////////////////////
  // variables in general
  reg [2:0] state;
  reg [3:0] sub_state;
  reg tready;   // whether it is ready to get more from VDMA.
  reg [8:0] output_channel_counter; // output channel from which we are reading feature and weight
  reg [8:0] channel_counter;      // channel from which we are reading feature and weight !! in STATE_REG_SETTING starts from 0, in STATE_CALCULATING starts from 1
  // variables for STATE_IDLE

  
  // variables for STATE_RECEIVE_FEATURE
  reg [12:0] feature_receive_counter;   // counter for plugging feature into SRAM (maybe 2)
  


  // variables for STATE_RECEIVE_BIAS
  reg [12:0] bias_receive_counter;

  // varaibles for STATE_RECEIVE_WEIGHT
  


  //////////////////////////////////// WEIGHT RELATED ////////////////////////////////////////////////////////////////
  reg [127:0] weight_reg;   // lower 72bits are weights that are currently used in calculation
  reg [7:0] weight_reg_counter; // How many bits are in the weight_reg
  wire weight_reg_suff;          // If weight_reg_counter > 72, it is turned on
  assign weight_reg_suff = (weight_reg_counter >=72); // equal?
  //wire weight_reg_full;          // If weight_reg_counter > 96, it is full (it cannot get 32 bits)
  //assign weight_reg_full = (weight_reg_counter > 96);
  reg weight_reg_set_done;      // If weight_reg is ready to calculate, it is on
  reg weight_reg_resetting_completed; // 1 if shfting the weight_reg (>>72), (i.e. remove weight that is already used)
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


  //////////////////////////////////// FEATURE RELATED ///////////////////////////////////////////////////////////////
  reg [271:0] feature_reg [2:0];    // register for feature
  reg feature_reg_set_done;         // If zero-padded data is inserted to feature_reg completely
  reg [5:0] feature_row_counter;
  reg [6:0] feature_reg_delay;      // For reading SRAM.
  reg [11:0] feature_sram_counter;  // # of line that we are reading from the SRAM
  reg [5:0] sram_feature_read_counter;
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  /////////////////////////////////////// BIAS RELATED ///////////////////////////////////////////////////////////////
  reg [31:0] bias_reg;    // lower 8 bits are bias that is currently used in calculation
  reg bias_reg_set_done; 
  reg [3:0] bias_reg_delay;

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  reg [2:0] weight_delay;


  reg transmit_done;
  reg [11:0] flen_square;





  // variables for STATE_SEND_RESULT
  

  // assignments
  assign s_axis_tready = ((state == STATE_RECEIVE_WEIGHT) && tready) || ((state == STATE_RECEIVE_FEATURE)&& tready) || ((state == STATE_RECEIVE_BIAS) && tready);


  // 2 SRAM to save features.

  reg [31:0] din [2:0];
  reg [10:0] addr [2:0];
  wire [31:0] dout [2:0];
  reg [2:0] bram_en;
  reg [2:0] we;

  sram_32x2048 f_conv1_sram_32x2048( // sram for temporalily saving features. (2^12 bytes)
    .addra(addr[0]),
    .clka(clk),
    .dina(din[0]),
    .douta(dout[0]),
    .ena(bram_en[0]),
    .wea(we[0])
  );

  sram_32x64 b_conv_sram_32x64( // sram for temporalily saving bias (2^8 Bytes top)
    .addra(addr[1]),
    .clka(clk),
    .dina(din[1]),
    .douta(dout[1]),
    .ena(bram_en[1]),
    .wea(we[1])
  );

    sram_32x1024 p_conv_sram_32x1024 ( // sram for partial_sum
    .addra(addr[2]),
    .clka(clk),
    .dina(din[2]),
    .douta(dout[2]),
    .ena(bram_en[2]),
    .wea(we[2])
  );

  //PE MODULE
  reg signed [7:0] in_a;
  reg signed [7:0] in_b;
  reg signed [31:0] in_sum;
  reg in_sum_en;
  wire signed [31:0] out_c;
  conv_pe conv_u_pe(clk, in_a, in_b, in_sum, in_sum_en, out_c);

  //counter for PE
  //reg [3:0] in_counter; // count 9 times, replaced by pe_sram_delay;
  reg [5:0] out_counter; // count flen times
  reg [4:0] pe_sram_delay; // counting delay when getting partial sum from sram
  reg [10:0] pe_addr; //partial_sum address, max = 32 x 32k
  reg cal_done; // signal for finishing 3*34 feature
  reg [5:0] inch_1_counter;
  reg [9:0] inch_all_counter;
  reg [9:0] outch_all_counter;
  reg inch_all_done;
  reg outch_all_done;
  

  //variable for data_send
  reg [10:0] delay_in_sending;
  reg signed [31:0] result_exact [0:3];
  reg signed [7:0] result_quantized [0:3];
  reg [9:0] send_counter;
  reg send_done;
    
  ////////////////////////////////////////////////////////////////////////////
  
  
  /////////////////////////////// DATA PATH //////////////////////////////////
  always @(posedge clk) begin
    if(!rstn) begin
      in_a <= 0;
      in_b <= 0;
      in_sum <= 0;
      in_sum_en <= 1;
      
      out_counter <= 0;
      pe_sram_delay <= 0;
      pe_addr <= 0;
      cal_done <= 0;
      inch_1_counter <= 0;
      inch_all_counter <= 0;
      outch_all_counter <= 0;
      inch_all_done <= 0;
      outch_all_done <= 0;
      delay_in_sending <= 0;
      send_counter <= 0;
      send_done <= 0;

      F_writedone <= 1'b0;
      B_writedone <= 1'b0;
      W_writedone <= 1'b0;
      transmit_done <= 1'b0;
      conv_done <= 1'b0;

      m_axis_tvalid <= 1'b0;
      m_axis_tlast <= 1'b0;
      m_axis_tdata <= 32'b0;

      // BRAM
      bram_en <= 3'b0;
      we <= 3'b0;
      addr[0] <= 11'b0;
      addr[1] <= 11'b0;
      addr[2] <= 11'b0;
      din[0] <= 32'b0;
      din[1] <= 32'b0;
      din[2] <= 32'b0;
      

      // variables in general
      state <= STATE_IDLE;
      sub_state <= STATE_WEIGHT_SETTING;
      tready <= 1'b0;
      output_channel_counter <= 9'b0;
      channel_counter <= 9'b0;
      
      // variables for STATE_RECEIVE_FEATURE
      feature_receive_counter <= 13'b0;

      // variables for STATE_RECEIVE_BIAS
      bias_receive_counter <= 13'b0;

      // variables for STATE_RECEIVE_WEIGHT

      //////////////////////////////////// WEIGHT RELATED ////////////////////////////////////////////////////////////////
      weight_reg <= 128'b0;
      weight_reg_counter <= 8'b0;
      weight_reg_set_done <= 1'b0;
      weight_reg_resetting_completed <= 1'b1;
      
      //////////////////////////////////// FEATURE RELATED ///////////////////////////////////////////////////////////////
      feature_reg[0] <= 272'b0;
      feature_reg[1] <= 272'b0;
      feature_reg[2] <= 272'b0;
      feature_reg_set_done <= 1'b0;
      feature_row_counter <= 6'b0;
      feature_reg_delay <= 7'b0;
      feature_sram_counter <= 12'b0;
      sram_feature_read_counter <= 6'b0;

      /////////////////////////////////////// BIAS RELATED ///////////////////////////////////////////////////////////////
      bias_reg <= 32'b0;
      bias_reg_set_done <= 1'b0;
      bias_reg_delay <= 4'b0;

      

      weight_delay <= 0;
    end
    else begin
      case(state)
        STATE_IDLE: begin
          if (COMMAND == 3'b001) begin
            state <= STATE_RECEIVE_FEATURE;
            tready <= 1'b1;
            flen_square <= FLength * FLength;
          end
          else if (conv_done) begin
            // We don't set conv_done as 0 here.
            in_a <= 0;
            in_b <= 0;
            in_sum <= 0;
            in_sum_en <= 1;
          
            out_counter <= 0;
            pe_sram_delay <= 0;
            pe_addr <= 0;
            cal_done <= 0;
            inch_1_counter <= 0;
            inch_all_counter <= 0;
            outch_all_counter <= 0;
            inch_all_done <= 0;
            outch_all_done <= 0;
            delay_in_sending <= 0;
            send_counter <= 0;
            send_done <= 0;

            F_writedone <= 1'b0;
            B_writedone <= 1'b0;
            //W_writedone <= 1'b0;
            transmit_done <= 1'b0;

            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            m_axis_tdata <= 32'b0;

            // BRAM
            bram_en <= 3'b0;
            we <= 3'b0;
            addr[0] <= 11'b0;
            addr[1] <= 11'b0;
            addr[2] <= 11'b0;
            din[0] <= 32'b0;
            din[1] <= 32'b0;
            din[2] <= 32'b0;
          

            // variables in general
            state <= STATE_IDLE;
            sub_state <= STATE_WEIGHT_SETTING;
            tready <= 1'b0;
            output_channel_counter <= 9'b0;
            channel_counter <= 9'b0;
          
            // variables for STATE_RECEIVE_FEATURE
            feature_receive_counter <= 13'b0;

            // variables for STATE_RECEIVE_BIAS
            bias_receive_counter <= 13'b0;

            // variables for STATE_RECEIVE_WEIGHT

            //////////////////////////////////// WEIGHT RELATED ////////////////////////////////////////////////////////////////
            weight_reg <= 128'b0;
            weight_reg_counter <= 8'b0;
            weight_reg_set_done <= 1'b0;
            weight_reg_resetting_completed <= 1'b1;
          
            //////////////////////////////////// FEATURE RELATED ///////////////////////////////////////////////////////////////
            feature_reg[0] <= 272'b0;
            feature_reg[1] <= 272'b0;
            feature_reg[2] <= 272'b0;
            feature_reg_set_done <= 1'b0;
            feature_row_counter <= 6'b0;
            feature_reg_delay <= 7'b0;
            feature_sram_counter <= 12'b0;
            sram_feature_read_counter <= 6'b0;

            /////////////////////////////////////// BIAS RELATED ///////////////////////////////////////////////////////////////
            bias_reg <= 32'b0;
            bias_reg_set_done <= 1'b0;
            bias_reg_delay <= 4'b0;

            weight_delay <= 0;
            result_exact[0] <= 32'b0;
            result_exact[1] <= 32'b0;
            result_exact[2] <= 32'b0;
            result_exact[3] <= 32'b0;
            result_quantized[0] <= 8'b0;
            result_quantized[1] <= 8'b0;
            result_quantized[2] <= 8'b0;
            result_quantized[3] <= 8'b0;
          end
          
          ///////////////////////////////////////Control path/////////////////////////////////////////////////                
          
        end
        STATE_RECEIVE_FEATURE: begin      
          if (F_writedone) begin // F_writedone needed?
            if (COMMAND == 3'b010) begin
              state <= STATE_RECEIVE_BIAS; 
              F_writedone <= 1'b0;
              ///////////////////
              conv_done <= 1'b0;
              W_writedone <= 1'b0;
              ///////////////////
              tready <= 1'b1; //preset
            end
            else begin
              bram_en[0] <= 1'b0; //caution
              din[0] <= 32'b0;
              addr[0] <= 11'b0;
              tready <= 1'b0;
            end   
          end         
          ///////////////////////////////////////Control path/////////////////////////////////////////////////       


          if (S_AXIS_TVALID && s_axis_tready) begin
            bram_en[0] <= 1'b1;
            we[0] <= 1'b1;
            addr[0] <= feature_receive_counter;
            din[0] <= S_AXIS_TDATA;//{S_AXIS_TDATA[7:0], S_AXIS_TDATA[15:8], S_AXIS_TDATA[23:16], S_AXIS_TDATA[31:24]};
            feature_receive_counter <= feature_receive_counter + 1;
          end
          if (S_AXIS_TLAST) begin
            F_writedone <= 1'b1;
          end
        end
        STATE_RECEIVE_BIAS: begin
          if (B_writedone) begin
            if (COMMAND == 3'b011) begin
              state <= STATE_RECEIVE_WEIGHT;
              B_writedone <= 1'b0;
            end
            bram_en[1] <= 1'b0;
            din[1] <= 32'b0;
            addr[1] <= 11'b0;
            tready <= 1'b0;
          end
          ///////////////////////////////////////Control path/////////////////////////////////////////////////       


          if (S_AXIS_TVALID && s_axis_tready) begin
            bram_en[1] <= 1'b1;
            we[1] <= 1'b1;
            addr[1] <= bias_receive_counter;
            din[1] <= {S_AXIS_TDATA[7:0], S_AXIS_TDATA[15:8], S_AXIS_TDATA[23:16], S_AXIS_TDATA[31:24]};
            bias_receive_counter <= bias_receive_counter + 1;
          end
          if (S_AXIS_TLAST) begin
            B_writedone <= 1'b1;
          end
        end
        STATE_RECEIVE_WEIGHT: begin
          if (COMMAND == 3'b100 && W_writedone) begin //        
            state <= STATE_SEND_RESULT;
            //W_writedone <= 1'b0;
          end
          ///////////////////////////////////////Control path/////////////////////////////////////////////////   

          case (sub_state)
            STATE_WEIGHT_SETTING: begin
              if (weight_reg_set_done) begin
                sub_state <= STATE_FEATURE_SETTING;
              end
              ///////////////////////////////////////Control path/////////////////////////////////////////////////                 
              if (!weight_reg_resetting_completed) begin
                weight_reg <= (weight_reg >> 72);
                weight_reg_counter <= weight_reg_counter - 72; //holding #
                weight_reg_resetting_completed <= 1'b1;
                weight_reg_set_done <= 0;
              end
              else if (!weight_reg_set_done) begin
                if (!weight_reg_suff) begin
                  tready <= 1'b1;
                  if (weight_delay < 1) begin
                    weight_delay <= weight_delay + 1;
                  end
                  else begin
                    weight_reg[weight_reg_counter +:32] <= S_AXIS_TDATA; //double flip
                    weight_reg_counter <= weight_reg_counter + 32;
                    if (weight_reg_counter + 32 >= 72) begin
                      tready <= 1'b0;
                    end
                  end
                end
                else begin //SUFFICIENT
                  tready <= 1'b0; // unnecessary
                  weight_reg_set_done <= 1'b1;
                  weight_delay <= 0;
                end 
              end
            end 
            STATE_FEATURE_SETTING: begin
              if (feature_reg_set_done) begin
                sub_state <= STATE_BIAS_SETTING;
              end
              ///////////////////////////////////////Control path/////////////////////////////////////////////////  

              if (!feature_reg_set_done) begin
                // output_channel_counter, channel_counter, feature_row_counter, feature_col_counter
                //////////////// full zero-padding needed row //////////////////////////
                if (feature_row_counter == 0) begin 
                  bram_en[0] <= 1'b1;
                  we[0] <= 1'b0;
                  // addr[0] <= ((channel_counter * (FLength) * (FLength)) >> 2) + ((feature_row_counter + internal_feature_row_counter) * FLength >> 2) + (feature_col_counter >> 2) + sram_feature_read_counter;
                  addr[0] <= channel_counter * (flen_square >> 2) + sram_feature_read_counter;
                  sram_feature_read_counter <= sram_feature_read_counter + 1;
                  if (feature_reg_delay < 2) begin
                    feature_reg_delay <= feature_reg_delay + 1;
                    // feature_reg[0] <= 64'b0;  // reset should be already done in transition from STATE_CALCULATING
                  end
                  else begin
                    feature_reg_delay <= feature_reg_delay + 1;
                    if (feature_reg_delay < 2 + (FLength>>2) * 2) begin
                      if (feature_reg_delay < 2 + (FLength>>2)) begin // Reading the first row
                        feature_reg[1] <= feature_reg[1] | (dout[0] << (8 + 32 * (feature_reg_delay - 2)));
                      end
                      else begin    // Reading the second row
                        feature_reg[2] <= feature_reg[2] | (dout[0] << (8 + 32 * (feature_reg_delay - 2 - (FLength>>2))));
                      end
                    end
                    else begin
                      feature_reg_set_done <= 1'b1;
                      bram_en[0] <= 1'b0;
                      addr[0] <= 12'b0;
                      sram_feature_read_counter <= 0;
                      feature_row_counter <= feature_row_counter + 2;
                      feature_reg_delay <= 3'b0; //caution
                    end
                  end
                end

                else if (feature_row_counter < FLength) begin  // Till just before the last row 
                  bram_en[0] <= 1'b1;
                  we[0] <= 1'b0;
                  addr[0] <= channel_counter * (flen_square >> 2) + feature_row_counter * (FLength>>2) + sram_feature_read_counter;
                  sram_feature_read_counter <= sram_feature_read_counter + 1;
                  if (feature_reg_delay < 2) begin
                    feature_reg_delay <= feature_reg_delay + 1;
                    if (feature_reg_delay == 1) begin
                      feature_reg[0] <= feature_reg[1];
                      feature_reg[1] <= feature_reg[2];
                      feature_reg[2] <= 0;
                    end
                  end
                  else begin
                    feature_reg_delay <= feature_reg_delay + 1;
                    if (feature_reg_delay < 2 + (FLength>>2)) begin
                      feature_reg[2] <= feature_reg[2] | (dout[0] << (8 + 32 * (feature_reg_delay - 2)));
                    end
                    else begin //마지막인데 여기로 들어감
                      feature_reg_set_done <= 1'b1;
                      bram_en[0] <= 1'b0; //맞나?
                      addr[0] <= 12'b0;
                      sram_feature_read_counter <= 0;
                      feature_row_counter <= feature_row_counter + 1;
                      feature_reg_delay <= 3'b0;
                    end
                  end
                end
                
                else begin // end of channel. 안된듯
                  feature_reg[0] <= feature_reg[1];
                  feature_reg[1] <= feature_reg[2];
                  feature_reg[2] <= 0;
                  feature_reg_set_done <= 1'b1;
                  feature_row_counter <= feature_row_counter + 1;
                  bram_en[0] <= 1'b0;
                end
              end

            end
            STATE_BIAS_SETTING: begin
              if (bias_reg_set_done) begin
                sub_state <= STATE_PE_CALCULATING;
              end
              ///////////////////////////////////////Control path/////////////////////////////////////////////////  

              if (output_channel_counter[1:0] == 2'b00) begin
                bram_en[1] <= 1'b1;
                we[1] <= 1'b0;
                addr[1] <= (output_channel_counter >> 2);
                if (bias_reg_delay < 2) begin
                  bias_reg_delay <= bias_reg_delay + 1;
                end
                else begin
                  bias_reg <= {dout[1][7:0], dout[1][15:8], dout[1][23:16], dout[1][31:24]};  // DEBUG
                  bias_reg_delay <= 4'b0;
                  bram_en[1] <= 1'b0;
                  //addr[1] <= 11'b0;
                  bias_reg_set_done <= 1'b1;
                end               
              end
              else if (!bias_reg_set_done) begin
                bias_reg <= (bias_reg >> 8);
                bias_reg_set_done <= 1'b1;
                bias_reg_delay <= 4'b0;
              end
            end           
            STATE_PE_CALCULATING: begin

              if (inch_all_done) begin
                sub_state <= STATE_DATA_SENDING;
              end
              else if (cal_done) begin
                cal_done <= 0;  
                /*if (output_channel_counter == OutCh) begin //Dangerous
                  state <= STATE_SEND_RESULT;
                end*/ // we turn W_writedone in the data_sending

                sub_state <= STATE_WEIGHT_SETTING;
                feature_reg_set_done <= 1'b0;
                
                if (feature_row_counter == FLength+1) begin
                  feature_reg[0] <= 272'b0;
                  feature_reg[1] <= 272'b0; // timing caution
                  feature_reg[2] <= 272'b0;
                  feature_row_counter <= 0;
                  if (channel_counter == InCh-1) begin  // Hmm.. modified!
                    output_channel_counter <= output_channel_counter + 1;
                    channel_counter <= 0;
                    bias_reg_set_done <= 1'b0; //only this?
                  end
                  else begin
                    channel_counter <= channel_counter + 1;
                  end

                  weight_reg_set_done <= 1'b0;
                  weight_reg_resetting_completed <= 1'b0;
                end
              end
              ///////////////////////////////////////Control path/////////////////////////////////////////////////  
              
              // After completing calculation, turn off weight_reg_set_done, weight_reg_reseeting_completed
              // make exception when done is high
              if((inch_all_done || cal_done) == 0) begin
                if(out_counter < FLength) begin
                  if(pe_sram_delay == 0) begin
                    bram_en[2] <= 1;
                    we[2] <= 0;
                    addr[2] <= pe_addr;
                    pe_sram_delay <= 1;
                  end
                  else if(pe_sram_delay == 1) begin
                    bram_en[2] <= 0;
                    addr[2] <= 0;
                    pe_sram_delay <= 2;
                  end
                  else if(pe_sram_delay == 2) begin
                    if(inch_all_counter == 0) begin
                      in_sum <= 0;
                      in_sum_en <= 1;
                      pe_sram_delay  <= pe_sram_delay + 1;
                    end
                    else begin
                      in_sum <= dout[2];
                      in_sum_en <= 1;
                      pe_sram_delay <= pe_sram_delay + 1;
                    end
                  end
                  else if(pe_sram_delay <= 5) begin
                    in_sum_en <= 0;
                    in_sum <= 0;
                    in_a <= feature_reg[0][(out_counter << 3) + ((pe_sram_delay - 3) << 3) +: 8];
                    in_b <= weight_reg[(pe_sram_delay - 3) << 3 +: 8];
                    pe_sram_delay <= pe_sram_delay + 1; 
                  end
                  else if(pe_sram_delay <= 8) begin
                    in_sum_en <= 0;
                    in_sum <= 0;
                    in_a <= feature_reg[1][(out_counter << 3) + ((pe_sram_delay - 6) << 3) +: 8];
                    in_b <= weight_reg[((pe_sram_delay - 3) << 3) +: 8];
                    pe_sram_delay <= pe_sram_delay + 1;
                  end
                  else if(pe_sram_delay <= 11) begin
                    in_sum_en <= 0;
                    in_sum <= 0;
                    in_a <= feature_reg[2][(out_counter << 3) + ((pe_sram_delay - 9) << 3) +: 8];
                    in_b <= weight_reg[((pe_sram_delay - 3) << 3) +: 8];
                    pe_sram_delay <= pe_sram_delay + 1;                
                  end
                  else if(pe_sram_delay == 12) begin
                    in_a <= 0;
                    in_b <= 0;
                    in_sum_en <= 0;
                    in_sum <= 0;
                    pe_sram_delay <= pe_sram_delay + 1;
                  end
                  else if(pe_sram_delay == 13) begin
                    pe_sram_delay <= pe_sram_delay + 1;
                  end
                  else if(pe_sram_delay == 14) begin
                    bram_en[2] <= 1;
                    we[2] <= 1;
                    addr[2] <= pe_addr;
                    din[2] <= out_c;
                    pe_sram_delay <= pe_sram_delay + 1;
                  end
                  else if(pe_sram_delay == 15) begin
                    bram_en[2] <= 0;
                    we[2] <= 0;
                    pe_addr <= pe_addr + 1;
                    pe_sram_delay <= 0;
                    out_counter <= out_counter + 1;
                  end
                end
                else if(out_counter == FLength) begin
                  if((inch_all_counter == InCh - 1) && (inch_1_counter == FLength - 1)) begin
                    inch_all_counter <= 0;
                    inch_all_done <= 1;
                    cal_done <= 1;
                    inch_1_counter <= 0;
                    pe_addr <= 0;
                    out_counter <= 0;
                    //when inch_all_done signal is high, we move to state_Data_sending and do quantization at STATE_DATA_SENDING, we need to initialze sram
                    //this can be done when pe_sram_delay == 2 && inch_all_counter == 0 with making in_sum = 0 and in_sum_en = 1 -- solved!

                  end
                  else if(inch_1_counter == FLength - 1) begin
                    inch_all_counter <= inch_all_counter + 1;
                    inch_1_counter <= 0;
                    cal_done <= 1;
                    pe_addr <= 0;
                    out_counter <= 0;
                  end
                  else begin
                    inch_1_counter <= inch_1_counter + 1; 
                    cal_done <= 1;
                    out_counter <= 0;
                  end
                end
              end
            end
            STATE_DATA_SENDING: begin
              if (send_done) begin
                send_done <= 0;
                sub_state <= STATE_PE_CALCULATING;
                delay_in_sending <= 0;
                inch_all_done <= 0;
              end
              ///////////////////////////////////////Control path/////////////////////////////////////////////////  

              // addr range of flen * flen is filled with exact_result
              if(delay_in_sending <= 1) begin
                bram_en[2] <= 1;
                we[2] <= 0;
                addr[2] <= pe_addr;
                pe_addr <= pe_addr + 1;
                delay_in_sending <= delay_in_sending + 1;
              end
              else if(delay_in_sending == 2) begin
                bram_en[2] <= 1;
                we[2] <= 0;
                addr[2] <= pe_addr;
                pe_addr <= pe_addr + 1;
                delay_in_sending <= 3;
                result_exact[0] <= dout[2];
              end
              else if(delay_in_sending == 3) begin
                bram_en[2] <= 1;
                we[2] <= 0;
                addr[2] <= pe_addr;
                pe_addr <= pe_addr + 1;
                delay_in_sending <= 4;
                result_exact[1] <= dout[2];
              end
              else if(delay_in_sending <= 5) begin
                bram_en[2] <= 0;
                addr[2] <= 0;
                delay_in_sending <= delay_in_sending + 1;
                result_exact[delay_in_sending - 2] <= dout[2];
              end
              else if(delay_in_sending == 6) begin
                result_exact[0] <= $signed(result_exact[0]) + {{18{bias_reg[7]}}, bias_reg[0 +: 8], 6'b0};
                result_exact[1] <= $signed(result_exact[1]) + {{18{bias_reg[7]}}, bias_reg[0 +: 8], 6'b0};
                result_exact[2] <= $signed(result_exact[2]) + {{18{bias_reg[7]}}, bias_reg[0 +: 8], 6'b0};
                result_exact[3] <= $signed(result_exact[3]) + {{18{bias_reg[7]}}, bias_reg[0 +: 8], 6'b0};
                delay_in_sending <= 7;
              end
              else if(delay_in_sending == 7) begin
                if(result_exact[0][31]) begin
                  result_quantized[0] <=0;
                end
                else begin
                  if(result_exact[0][30:13] != 18'b0) result_quantized[0] <= 8'b0111_1111;
                  else result_quantized[0] <= {1'b0, result_exact[0][12:6]};
                end

                if(result_exact[1][31]) begin
                  result_quantized[1] <=0;
                end
                else begin
                  if(result_exact[1][30:13] != 18'b0) result_quantized[1] <= 8'b0111_1111;
                  else result_quantized[1] <= {1'b0, result_exact[1][12:6]};
                end

                if(result_exact[2][31]) begin
                  result_quantized[2] <=0;
                end
                else begin
                  if(result_exact[2][30:13] != 18'b0) result_quantized[2] <= 8'b0111_1111;
                  else result_quantized[2] <= {1'b0, result_exact[2][12:6]};
                end

                if(result_exact[3][31]) begin
                  result_quantized[3] <=0;
                end
                else begin
                  if(result_exact[3][30:13] != 18'b0) result_quantized[3] <= 8'b0111_1111;
                  else result_quantized[3] <= {1'b0, result_exact[3][12:6]};
                end
                delay_in_sending <= 8;
                m_axis_tvalid <= 1;
                /////////////////
                if(send_counter >= (flen_square >> 2) - 1 && outch_all_counter == OutCh - 1) begin
                  m_axis_tlast <= 1'b1;
                end
                /////////////////
              end
              else if(delay_in_sending == 8) begin
                m_axis_tvalid <= 0;
                if(send_counter < (flen_square >> 2) - 1) begin
                  send_counter <= send_counter + 1;
                  delay_in_sending <= 0;
                end
                else begin
                  delay_in_sending <= 9;
                  send_done <= 1;
                  send_counter <= 0;
                  pe_addr <= 0;
                  if(outch_all_counter == OutCh - 1) begin
                    W_writedone <= 1; // caution !!
                  end
                  else outch_all_counter <= outch_all_counter + 1;
                end
              end
            end
          endcase
        end

        STATE_SEND_RESULT: begin
          transmit_done <= 1'b1;
          conv_done <= 1'b1;
          if (transmit_done) begin
            state <= STATE_IDLE;
            transmit_done <= 1'b0;
          end
          ///////////////////////////////////////Control path/////////////////////////////////////////////////          
        end
      endcase
    end
  end
  assign M_AXIS_TDATA = {result_quantized[3], result_quantized[2], result_quantized[1], result_quantized[0]};



  ////////////////////////////////////////////////////////////////////////////


  ////////////////////////////////////////////////////////////////////////////
  
endmodule

module conv_pe(clk, in_a, in_b, in_sum, in_sum_en, out_c);
  input wire clk;
  input wire signed [7:0] in_a, in_b;
  input wire signed [31:0] in_sum;
  input wire in_sum_en;
  output reg signed [31:0] out_c;

  reg signed [31:0] temp1;
  
  always @(posedge clk) begin    
      if(in_sum_en) begin
        out_c <= in_sum;
        temp1 <= 0;
      end
      else begin
        temp1 <= in_a * in_b;
        out_c <= $signed(out_c) + temp1;
      end    
  end
endmodule