/*
* pool_module.v
*/   
module pool_module 
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

    input pool_start, 
    output reg pool_done,

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports if you need them
    //////////////////////////////////////////////////////////////////////////
    input wire [5:0] input_size,
    input wire [8:0] input_channel_size
  );
  
  reg m_axis_tuser;
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0] m_axis_tdata;
  reg [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] m_axis_tkeep;
  reg m_axis_tlast;
  reg m_axis_tvalid;
  wire s_axis_tready;
  
  assign S_AXIS_TREADY = s_axis_tready;
  assign M_AXIS_TDATA = m_axis_tdata;
  assign M_AXIS_TLAST = m_axis_tlast;
  assign M_AXIS_TVALID = m_axis_tvalid;
  assign M_AXIS_TUSER = 1'b0;
  assign M_AXIS_TKEEP = {(C_S00_AXIS_TDATA_WIDTH/8) {1'b1}};
  
  //////////////////////////////////////////////////////////////////////////
  // TODO : Write your code here
  //////////////////////////////////////////////////////////////////////////
  
  localparam STATE_IDLE = 2'd0,
  STATE_RECEIVE_FEATURE = 2'd1, // Feature ? ?  ?  ?   받는 과정
  STATE_CALCULATE_WRITE = 2'd2, // ?  ?  ?   받 ? feature ? 계산?   ?, SRAM?   ?  ?   과정
  STATE_SEND_RESULT = 2'd3; // count ? target_count까 ? ?  ?  ?  ?   ?   계산 마치 ? 결과 보내?   과정            


  reg [2:0] state;  // state
  reg [31:0] din;
  reg [13:0] addr;
  wire [31:0] dout;
  reg bram_en;
  reg we;
  reg [16:0] count_feature;  // feature  ? 개째 ? 받고 ?  ?   ?.
  reg [7:0] count;  // f_pool_sram?    ? 번째 ? ?  ?  ?   받고 ?  ?   ?
  reg calculate_write_done; // STATE_CALCULATE_WRITE is done.
  reg [127:0] sram_read_reg;  // STATE_CALCULATE_WRITE?  ?   SRAM?  로 ??   16B ? ?   ? ???  ?  ?   reg.
  reg [127:0] sram_buf_reg;   // STATE_CALCULATE_WRITE?  ?   sram_read_reg ? 16B ? 차면 pooling?   ? ?  ?   받아?  ?   buffer
  reg [31:0] result_reg;      // STATE_CALCULATE_WRITE?  ?   pooling?   결과값으 ? r_pool_sram?   ?  ?   ? 결과
  reg [7:0] count_row_done;   // STATE_CALCULATE_WRITE?  ?   feature?   ?   row ? ?  ?  ?   ? ?  ?  ?   ? ?  ?   count.
  reg [10:0] count_row;       // STATE_CALCULATE_WRITE?  ?   sram?   2^12Byte  ?  ? 줄이?   ?  ?  ?   ? count. 
  reg [1:0] toggle;                 // STATE_CALCULATE_WRITE?  ?   sram?  ?   ?  ?  ?   ? ?  ?   ?   ?   ? ?   ? row ? ?  ?  갔다 ?   ? ?  ?   ?  ?  .  reg [1:0] delay;            // STATE_CALCULATE_WRITE     sram  б       2 cycle   ٸ      ?.
  reg sram_read_reg_valid;    // STATE_CALCULATE_WRITE?  ?   sram_read_reg ? valid
  reg sram_buf_reg_valid;     // STATE_CALCULATE_WRITE?  ?   sram_buf_reg ? valid
  reg [12:0] max_save_done; //output count
  reg intermediate_pool_done; // STATE_CALCULATE_WRITE     16B   pooling       4B   result_reg                   .
  reg [15:0] sram_full_row_size;
  reg [15:0] sram_full_row_size2;
  reg [3:0] input_quarter;
  reg row_delay;
  reg [1:0] delay;
  //wire [15:0] sram_row;
  //wire [15:0] SRAM_FULL_ROW_SIZE;
  //assign sram_row = count_row * (input_size >> 2);

  assign s_axis_tready = pool_start && (state == STATE_RECEIVE_FEATURE) && (count_feature != sram_full_row_size);  // Caution 4x4 problem!
  //assign SRAM_FULL_ROW_SIZE = input_size*input_size*(input_channel_size>>2);

  sram_32x8192 f_pool_sram_32x8192( //32x2^13
    .addra(addr),
    .clka(clk),
    .dina(din),
    .douta(dout),
    .ena(bram_en),
    .wea(we)
  );


  // Data Path
  always @(posedge clk) begin
    if(!rstn) begin
        sram_read_reg <= 128'b0;  // STATE_CALCULATE_WRITE     SRAM   κ    16B    а       ϴ  reg.
        result_reg <= 32'b0;      // STATE_CALCULATE_WRITE     pooling             r_pool_sram    ־       
        count_row_done <= 8'b0;   // STATE_CALCULATE_WRITE     feature      row    о      Ȯ   ϱ       count.
        count_row <= 11'b0;
        toggle <= 2'b0;
        delay <= 2'b0;
        sram_read_reg_valid <= 1'b0;
        sram_buf_reg_valid <= 1'b0;
        max_save_done <= 13'b0;
        intermediate_pool_done <= 1'b0;


        addr <= 14'b0;
        bram_en <= 1'b0;
        we <= 1'b0;
        din <= 32'b0;

        count <= 8'b0;
        count_feature <= 17'b0;

        calculate_write_done <= 1'b0;
        m_axis_tvalid <= 1'b0;
        m_axis_tlast <= 1'b0;
        m_axis_tdata <= 32'b0;
        state <= STATE_IDLE;
    /////////////
        pool_done <= 1'b0;
        sram_full_row_size <= 16'b0;//input_size*input_size*(input_channel_size>>2);
        sram_full_row_size2 <= 16'b0;
        input_quarter <= 4'b0;
        row_delay <= 1'b0;
    /////////////
      
      
    end
    else begin
      case (state)
        STATE_IDLE: begin
          // Control
          if(pool_start==0) begin
            sram_read_reg <= 128'b0;  // STATE_CALCULATE_WRITE     SRAM   κ    16B    а       ϴ  reg.
            result_reg <= 32'b0;      // STATE_CALCULATE_WRITE     pooling             r_pool_sram    ־       
            count_row_done <= 8'b0;   // STATE_CALCULATE_WRITE     feature      row    о      Ȯ   ϱ       count.
            count_row <= 11'b0;
            toggle <= 2'b0;
            delay <= 2'b0;
            sram_read_reg_valid <= 1'b0;
            sram_buf_reg_valid <= 1'b0;
            max_save_done <= 13'b0;
            intermediate_pool_done <= 1'b0;


            addr <= 14'b0;
            bram_en <= 1'b0;
            we <= 1'b0;
            din <= 32'b0;

            count <= 8'b0;
            count_feature <= 17'b0;

            calculate_write_done <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            m_axis_tdata <= 32'b0;
            //state <= STATE_IDLE;
    /////////////
            pool_done <= 1'b0;
            row_delay <= 1'b0;         
          end

          else if (pool_start && (pool_done==0)) begin
            if(row_delay == 0) begin
              sram_full_row_size2 <= input_size*input_size*(input_channel_size>>2);
              input_quarter <= (input_size>>2);
              row_delay <= 1'b1;
            end
            else begin
              state <= STATE_RECEIVE_FEATURE;
              sram_full_row_size <= sram_full_row_size2;
              row_delay <= 1'b0;
            end
          end
        end

        STATE_RECEIVE_FEATURE: begin
          // Control
          if (count_feature == sram_full_row_size) begin
            count <= count + 1;
            count_feature <= 17'b0;
            state <= STATE_CALCULATE_WRITE; //feature receive is done
          end
        ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
          // Data
          if (S_AXIS_TVALID) begin
            bram_en <= 1'b1;
            we <= 1'b1;
            addr <= count_feature;
            din <= {S_AXIS_TDATA[7:0], S_AXIS_TDATA[15:8], S_AXIS_TDATA[23:16], S_AXIS_TDATA[31:24]};
            count_feature <= count_feature + 1;
          end
          else begin
            bram_en <= 1'b0;
            we <= 1'b0;
          end
        end


        STATE_CALCULATE_WRITE: begin
          // Control
          if (calculate_write_done) begin //the end
            calculate_write_done <= 1'b0;

            count_row <= 11'b0;
            count_row_done <= 8'b0;
            toggle <= 2'b0;
            delay <= 2'b0;
            //if (count) begin //the end
              state <= STATE_SEND_RESULT;
              //pool_done <= 1'b1;
              //m_axis_tlast <= 1'b1;
            //end
          end
          // Data
          else begin //calculate_write_done is 0

              if(max_save_done==(sram_full_row_size>>2)) begin
                //m_axis_tlast <= 1'b1;
                calculate_write_done <= 1'b1;
                bram_en <= 1'b0;
                delay <= 2'b0;
              end
              else begin
                bram_en <= 1'b1;
                we <= 1'b0;
                case (toggle)
                  2'b00 : begin
                    addr <= count_row * input_quarter + count_row_done;    
                    toggle <= toggle + 1;            
                    if (delay < 2) begin
                      delay <= delay + 1;
                    end
                    else begin
                      sram_read_reg[95:64] <= dout; //third
                    end                
                  end
                  2'b01 : begin
                    addr <= count_row * input_quarter + count_row_done + input_quarter;
                  
                    toggle <= toggle + 1;
                    if (delay < 2) begin
                      delay <= delay + 1;
                    end
                    else begin
                      sram_read_reg[127:96] <= dout; //fourth
                      sram_read_reg_valid <= 1'b1;
                    end
                    if (count_row_done + 1 == input_quarter) begin
                      count_row <= count_row + 2;
                      count_row_done <= 8'b0;
                    end
                    else begin
                      count_row_done <= count_row_done + 1;
                    end                  
                  end
                  2'b10 : begin
                    addr <= count_row * input_quarter + count_row_done;
                    if (sram_read_reg_valid) begin
                      sram_buf_reg <= sram_read_reg;
                      sram_read_reg_valid <= 1'b0;
                      sram_buf_reg_valid <= 1'b1;
                    end
                    sram_read_reg[31:0] <= dout; //first
                    toggle <= toggle + 1;                 
                  end
                  2'b11 : begin
                    addr <= count_row * input_quarter  + count_row_done + input_quarter;
                    sram_read_reg[63:32] <= dout;    //second 
                    toggle <= 2'b00;
                    // sram_buf_reg <= sram_read_reg;
                  
                    if (count_row_done + 1 == input_quarter) begin
                      count_row <= count_row + 2;
                      count_row_done <= 8'b0;
                    end                
                    else begin
                      count_row_done <= count_row_done + 1;
                    end
                  end
                endcase
              end

            // POOLING & SAVING
            if (sram_buf_reg_valid) begin
                if(m_axis_tvalid) begin
                    sram_buf_reg_valid <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                end
                else begin
                if (!intermediate_pool_done) begin
                    if (sram_buf_reg[16 +: 8] > sram_buf_reg[24 +: 8]) begin  // 0 > 1
                      if (sram_buf_reg[16 +: 8] > sram_buf_reg[48 +: 8]) begin // 0 > 2
                        if (sram_buf_reg[16 +: 8] > sram_buf_reg[56 +: 8]) begin // 0 > 3
                          result_reg[24 +:8] <= sram_buf_reg[16 +: 8]; // 0 is max
                        end
                        else begin
                          result_reg[24 +:8] <= sram_buf_reg[56 +: 8]; // 3 is max
                        end
                      end
                      else begin  // 0 < 2
                        if (sram_buf_reg[48 +: 8] > sram_buf_reg[56 +: 8]) begin // 2 > 3
                           result_reg[24 +:8] <= sram_buf_reg[48 +: 8]; // 2 is max
                        end
                        else begin
                          result_reg[24 +:8] <= sram_buf_reg[56 +: 8];  // 3 is max
                        end
                      end
                    end
                    else begin  // 0 < 1
                      if (sram_buf_reg[24 +: 8] > sram_buf_reg[48 +: 8]) begin // 1 > 2
                        if (sram_buf_reg[24 +: 8] > sram_buf_reg[56 +: 8]) begin // 1 > 3
                          result_reg[24 +:8] <= sram_buf_reg[24 +: 8];  // 1 is max
                        end
                        else begin
                          result_reg[24 +:8] <= sram_buf_reg[56 +: 8];  // 3 is max
                        end
                      end
                      else begin  // 1 < 2
                        if (sram_buf_reg[48 +: 8] > sram_buf_reg[56 +: 8]) begin // 2 > 3
                          result_reg[24 +:8] <= sram_buf_reg[48 +: 8];  // 2 is max
                        end
                        else begin
                          result_reg[24 +:8] <= sram_buf_reg[56 +: 8];  // 3 is max
                        end
                      end                   
                    end


                    if (sram_buf_reg[0 +: 8] > sram_buf_reg[ 8 +: 8]) begin  // 0 > 1
                      if (sram_buf_reg[0 +: 8] > sram_buf_reg[32 +: 8]) begin // 0 > 2
                        if (sram_buf_reg[0 +: 8] > sram_buf_reg[40 +: 8]) begin // 0 > 3
                          result_reg[16 +:8] <= sram_buf_reg[0 +: 8]; // 0 is max
                        end
                        else begin
                          result_reg[16 +:8] <= sram_buf_reg[40 +: 8]; // 3 is max
                        end
                      end
                      else begin  // 0 < 2
                        if (sram_buf_reg[32 +: 8] > sram_buf_reg[40 +: 8]) begin // 2 > 3
                          result_reg[16 +:8] <= sram_buf_reg[ 32 +: 8]; // 2 is max
                        end
                        else begin
                          result_reg[16 +:8] <= sram_buf_reg[40 +: 8];  // 3 is max
                        end
                      end
                    end
                    else begin  // 0 < 1
                      if (sram_buf_reg[ 8 +: 8] > sram_buf_reg[ 32 +: 8]) begin // 1 > 2
                        if (sram_buf_reg[ 8 +: 8] > sram_buf_reg[ 40 +: 8]) begin // 1 > 3
                          result_reg[16 +:8] <= sram_buf_reg[ 8 +: 8];  // 1 is max
                        end
                        else begin
                          result_reg[16 +:8] <= sram_buf_reg[40 +: 8];  // 3 is max
                        end
                      end
                      else begin  // 1 < 2
                        if (sram_buf_reg[32 +: 8] > sram_buf_reg[ 40+: 8]) begin // 2 > 3
                          result_reg[16 +:8] <= sram_buf_reg[32 +: 8];  // 2 is max
                        end
                        else begin
                          result_reg[16 +:8] <= sram_buf_reg[ 40+: 8];  // 3 is max
                        end
                      end                   
                    end


                    if (sram_buf_reg[80 +: 8] > sram_buf_reg[88 +: 8]) begin  // 0 > 1
                      if (sram_buf_reg[80+: 8] > sram_buf_reg[112 +: 8]) begin // 0 > 2
                        if (sram_buf_reg[80 +: 8] > sram_buf_reg[120 +: 8]) begin // 0 > 3
                          result_reg[8 +:8] <= sram_buf_reg[80 +: 8]; // 0 is max
                        end
                        else begin
                          result_reg[8 +:8] <= sram_buf_reg[120 +: 8]; // 3 is max
                        end
                      end
                      else begin  // 0 < 2
                        if (sram_buf_reg[112 +: 8] > sram_buf_reg[120 +: 8]) begin // 2 > 3
                          result_reg[8 +:8] <= sram_buf_reg[112 +: 8]; // 2 is max
                        end
                        else begin
                          result_reg[8 +:8] <= sram_buf_reg[120 +: 8];  // 3 is max
                        end
                      end
                    end
                    else begin  // 0 < 1
                      if (sram_buf_reg[88 +: 8] > sram_buf_reg[112 +: 8]) begin // 1 > 2
                        if (sram_buf_reg[88 +: 8] > sram_buf_reg[120 +: 8]) begin // 1 > 3
                          result_reg[8 +:8] <= sram_buf_reg[88 +: 8];  // 1 is max
                        end
                        else begin
                          result_reg[8 +:8] <= sram_buf_reg[120 +: 8];  // 3 is max
                        end
                      end
                      else begin  // 1 < 2
                        if (sram_buf_reg[112 +: 8] > sram_buf_reg[120 +: 8]) begin // 2 > 3
                          result_reg[8 +:8] <= sram_buf_reg[112 +: 8];  // 2 is max
                        end
                        else begin
                          result_reg[8 +:8] <= sram_buf_reg[120+: 8];  // 3 is max
                        end
                      end                   
                    end


                    if (sram_buf_reg[64 +: 8] > sram_buf_reg[72 +: 8]) begin  // 0 > 1
                      if (sram_buf_reg[64 +: 8] > sram_buf_reg[96 +: 8]) begin // 0 > 2
                        if (sram_buf_reg[64 +: 8] > sram_buf_reg[104 +: 8]) begin // 0 > 3
                          result_reg[0 +:8] <= sram_buf_reg[64 +: 8]; // 0 is max
                        end
                        else begin
                          result_reg[0 +:8] <= sram_buf_reg[104 +: 8]; // 3 is max
                        end
                      end
                      else begin  // 0 < 2
                        if (sram_buf_reg[96 +: 8] > sram_buf_reg[104 +: 8]) begin // 2 > 3
                          result_reg[0 +:8] <= sram_buf_reg[96 +: 8]; // 2 is max
                        end
                        else begin
                          result_reg[0 +:8] <= sram_buf_reg[104 +: 8];  // 3 is max
                        end
                      end
                    end
                    else begin  // 0 < 1
                      if (sram_buf_reg[72 +: 8] > sram_buf_reg[96 +: 8]) begin // 1 > 2
                        if (sram_buf_reg[72 +: 8] > sram_buf_reg[104 +: 8]) begin // 1 > 3
                          result_reg[0 +:8] <= sram_buf_reg[72 +: 8];  // 1 is max
                        end
                        else begin
                          result_reg[0 +:8] <= sram_buf_reg[104 +: 8];  // 3 is max
                        end
                      end
                      else begin  // 1 < 2
                        if (sram_buf_reg[96 +: 8] > sram_buf_reg[104 +: 8]) begin // 2 > 3
                          result_reg[0 +:8] <= sram_buf_reg[96 +: 8];  // 2 is max
                        end
                        else begin
                          result_reg[0 +:8] <= sram_buf_reg[104 +: 8];  // 3 is max
                        end
                      end                   
                    end
                  //end
                  
                  intermediate_pool_done <= 1'b1;
                end
                else begin//if (intermediate_pool_done) begin
                // Saving the maximum
                    m_axis_tdata <= {result_reg[7:0], result_reg[15:8], result_reg[23:16], result_reg[31:24]};
                    intermediate_pool_done <= 1'b0;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tkeep <= 4'b1111;
                    m_axis_tuser <= 1'b0;

                    max_save_done <= max_save_done + 1;
                    if(max_save_done == ((sram_full_row_size)>>2)-1) begin
                      m_axis_tlast<=1'b1;
                    end                    
                  //end
                end
              end
            end // sram_buf_reg end
          end //else data end
        end //state end

        STATE_SEND_RESULT: begin
          pool_done <= 1'b1;
          state <= STATE_IDLE;
          /*
          if (pool_done) begin
            state <= STATE_IDLE;
            //pool_done <= 1'b0;
          end
          else begin
            if(m_axis_tlast) pool_done <= 1'b1;
          end*/
        ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
          //pool_done <= 1'b1;
        end
      endcase
    end
  end



endmodule