`default_nettype none
`timescale 1ns/1ps
// frame: A5 5A type sessionLE32 seqLE16 length8 payload CRC16LE.
// CRC-16/CCITT-FALSE (1021, FFFF), covering type through payload.
// Parser never publishes partially received or bad-CRC payloads.
module recovery_uart_packet #(parameter integer CLK_HZ=100000000,BAUD=115200,MAX_BYTES=168,TX_INPUT_STABLE=0)(
 input wire clk,rst,input wire uart_rx,output wire uart_tx,
 input wire tx_valid,output wire tx_ready,input wire [7:0] tx_type,
 input wire [31:0] tx_session,input wire [15:0] tx_seq,input wire [7:0] tx_length,
 input wire [MAX_BYTES*8-1:0] tx_data,
 output reg rx_valid,output reg [7:0] rx_type,
 output reg [31:0] rx_session,output reg [15:0] rx_seq,
 output reg [7:0] rx_length,
 // payload bytes go to the link's bank RAM. A DATA payload
 // byte is written only while rx_store_enable is high; rx_dropped reports that
 // some payload byte of the frame was not stored (no free bank).
 input wire rx_store_enable,output reg rx_wr_en,output reg [7:0] rx_wr_addr,
 output reg [7:0] rx_wr_data,output reg rx_dropped
);

localparam integer FRAME_IDLE=CLK_HZ/20;
wire byte_ready,byte_rx_valid;
wire [7:0] byte_rx_data;
reg tx_active;
reg [8:0] tx_index;
reg [7:0] held_type,held_length;
reg [31:0] held_session;
reg [15:0] held_seq,tx_crc;
wire [MAX_BYTES*8-1:0] held_data;
reg [7:0] byte_tx_data;
reg [7:0] payload_byte;
reg [1:0] rx_state;
reg [8:0] rx_index;
reg [15:0] rx_crc;
reg [7:0] crc_low;
reg [8:0] rx_payload_end;
reg [31:0] rx_idle;
// Continuous values retain the original net initializer expressions.


 function [15:0] crc_byte;input [15:0] c;input [7:0] d;integer k;reg [15:0] v;
 begin v=c^{d,8'd0};for(k=0;k<8;k=k+1)v=v[15]?(v<<1)^16'h1021:v<<1;crc_byte=v;end endfunction
 
 
 
 
 generate if(TX_INPUT_STABLE!=0)begin:g_stable_tx
  assign held_data=tx_data;
 end else begin:g_captured_tx
  reg [MAX_BYTES*8-1:0] payload;
  assign held_data=payload;
  always @(posedge clk or posedge rst)begin
   if(rst)payload<=0;
   else if(!tx_active&&tx_valid&&tx_length<=MAX_BYTES)payload<=tx_data;
  end
 end endgenerate
 
 // Preselect the wide payload while the byte UART is busy. Each UART byte
 // occupies at least ten clocks (DIV >= 1), so this settles before ready.
 // Packet acceptance, bit timing, headers, CRC and receiver stay unchanged.
 
 always @(posedge clk or posedge rst)begin
  if(rst)payload_byte<=0;
  else if(tx_active&&tx_index>=10&&tx_index<10+held_length)
   payload_byte<=held_data[(tx_index-10)*8+:8];
 end
 assign tx_ready=!tx_active;
 always @*begin
  byte_tx_data=0;
  case(tx_index)
   0:byte_tx_data=8'ha5;1:byte_tx_data=8'h5a;2:byte_tx_data=held_type;
   3:byte_tx_data=held_session[7:0];4:byte_tx_data=held_session[15:8];
   5:byte_tx_data=held_session[23:16];6:byte_tx_data=held_session[31:24];
   7:byte_tx_data=held_seq[7:0];8:byte_tx_data=held_seq[15:8];9:byte_tx_data=held_length;
   default:begin
    if(tx_index<10+held_length)byte_tx_data=payload_byte;
    else if(tx_index==10+held_length)byte_tx_data=tx_crc[7:0];
    else byte_tx_data=tx_crc[15:8];
   end
  endcase
 end
 recovery_uart_byte #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_byte(
  .clk(clk),.rst(rst),.rx(uart_rx),.tx(uart_tx),
  .tx_valid(tx_active),.tx_data(byte_tx_data),.tx_ready(byte_ready),
  .rx_valid(byte_rx_valid),.rx_data(byte_rx_data));
 always @(posedge clk or posedge rst)begin
  if(rst)begin tx_active<=0;tx_index<=0;held_type<=0;held_length<=0;
   held_session<=0;held_seq<=0;tx_crc<=16'hffff;end
  else if(!tx_active)begin
   if(tx_valid&&tx_length<=MAX_BYTES)begin
    tx_active<=1;tx_index<=0;held_type<=tx_type;held_length<=tx_length;
    held_session<=tx_session;held_seq<=tx_seq;tx_crc<=16'hffff;
   end
  end else if(byte_ready)begin
   if(tx_index>=2&&tx_index<10+held_length)tx_crc<=crc_byte(tx_crc,byte_tx_data);
   if(tx_index==11+held_length)tx_active<=0;
   else tx_index<=tx_index+1'b1;
  end
 end
 
 
 
 
 // Registered single byte write port (replaces 1408 payload registers and 176
 // per-slot enables). Address is the payload index 0..MAX_BYTES-1.
 always @(posedge clk or posedge rst)begin
  if(rst)begin rx_wr_en<=0;rx_wr_addr<=0;rx_wr_data<=0;end
  else begin
   rx_wr_en<=byte_rx_valid&&rx_state==2&&rx_index>=8&&rx_index<rx_payload_end&&rx_store_enable&&!rx_dropped;
   rx_wr_addr<=rx_index[7:0]-8'd8;rx_wr_data<=byte_rx_data;
  end
 end


 always @(posedge clk or posedge rst)begin
  if(rst)begin rx_state<=0;rx_index<=0;rx_crc<=16'hffff;rx_type<=0;
   rx_session<=0;rx_seq<=0;rx_length<=0;rx_valid<=0;crc_low<=0;rx_idle<=0;rx_payload_end<=9'd8;rx_dropped<=0;end
  else begin
   rx_valid<=0;
   if(byte_rx_valid)rx_idle<=0;
   else if(rx_state!=0)begin
    if(rx_idle>=FRAME_IDLE)begin rx_state<=0;rx_idle<=0;end
    else rx_idle<=rx_idle+1'b1;
   end
   if(byte_rx_valid)case(rx_state)
    0:if(byte_rx_data==8'ha5)rx_state<=1;
    1:begin
     if(byte_rx_data==8'h5a)begin rx_state<=2;rx_index<=0;rx_crc<=16'hffff;rx_dropped<=0;end
     else if(byte_rx_data!=8'ha5)rx_state<=0;
    end
    2:begin
     if(rx_index<rx_payload_end||rx_index<8)rx_crc<=crc_byte(rx_crc,byte_rx_data);
     case(rx_index)
      0:rx_type<=byte_rx_data;
      1:rx_session[7:0]<=byte_rx_data;2:rx_session[15:8]<=byte_rx_data;
      3:rx_session[23:16]<=byte_rx_data;4:rx_session[31:24]<=byte_rx_data;
      5:rx_seq[7:0]<=byte_rx_data;6:rx_seq[15:8]<=byte_rx_data;
      7:begin rx_length<=byte_rx_data;rx_payload_end<={1'b0,byte_rx_data}+9'd8;if(byte_rx_data>MAX_BYTES)rx_state<=0;end
      default:begin
       if(rx_index<rx_payload_end)begin if(!rx_store_enable)rx_dropped<=1;end
       else if(rx_index==rx_payload_end)crc_low<=byte_rx_data;
       else begin
        rx_valid<=({byte_rx_data,crc_low}==rx_crc);rx_state<=0;
       end
      end
     endcase
     rx_index<=rx_index+1'b1;
    end
    default:rx_state<=0;
   endcase
  end
 end
endmodule

`default_nettype wire
