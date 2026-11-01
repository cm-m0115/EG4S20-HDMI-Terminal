`default_nettype none
`timescale 1ns/1ps
// 8N1 UART with midpoint sampling and stop-bit validation.
module recovery_uart_byte #(parameter integer CLK_HZ=100000000,BAUD=115200)(
 input wire clk,rst,input wire rx,output reg tx,
 input wire tx_valid,input wire [7:0] tx_data,output wire tx_ready,
 output reg rx_valid,output reg [7:0] rx_data
);

localparam integer DIV=(CLK_HZ+BAUD/2)/BAUD;
reg [1:0] rx_sync;
reg [15:0] tx_count,rx_count;
reg [3:0] tx_bit,rx_bit;
reg [9:0] tx_shift;
reg [7:0] rx_shift;
reg tx_busy,rx_busy;
// Continuous values retain the original net initializer expressions.


 
  /* fehdl async_reg=1 */
 
 
 
 
 
 assign tx_ready=!tx_busy;
 always @(posedge clk or posedge rst)begin
  if(rst)begin rx_sync<=3;tx<=1;tx_count<=0;tx_bit<=0;tx_shift<=1023;tx_busy<=0;end
  else begin
   rx_sync<={rx_sync[0],rx};
   if(!tx_busy)begin
    tx<=1;
    if(tx_valid)begin tx_shift<={1'b1,tx_data,1'b0};tx<=0;tx_busy<=1;tx_bit<=0;tx_count<=DIV-1;end
   end else if(tx_count!=0)tx_count<=tx_count-1'b1;
   else if(tx_bit==9)begin tx<=1;tx_busy<=0;end
   else begin tx_shift<={1'b1,tx_shift[9:1]};tx<=tx_shift[1];tx_bit<=tx_bit+1'b1;tx_count<=DIV-1;end
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin rx_count<=0;rx_bit<=0;rx_shift<=0;rx_valid<=0;rx_data<=0;rx_busy<=0;end
  else begin
   rx_valid<=0;
   if(!rx_busy)begin
    if(!rx_sync[1])begin rx_busy<=1;rx_bit<=0;rx_count<=DIV/2;end
   end else if(rx_count!=0)rx_count<=rx_count-1'b1;
   else if(rx_bit==0)begin
    if(rx_sync[1])rx_busy<=0;
    else begin rx_bit<=1;rx_count<=DIV-1;end
   end else if(rx_bit<=8)begin
    rx_shift[rx_bit-1]<=rx_sync[1];rx_bit<=rx_bit+1'b1;rx_count<=DIV-1;
   end else begin
    rx_busy<=0;
    if(rx_sync[1])begin rx_data<=rx_shift;rx_valid<=1;end
   end
  end
 end
endmodule

`default_nettype wire
