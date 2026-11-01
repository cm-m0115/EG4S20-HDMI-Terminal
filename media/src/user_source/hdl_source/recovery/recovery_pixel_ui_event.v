`default_nettype none
`timescale 1ns/1ps
// Reliable held event from FINAL output pixel to the 100MHz application.
// Request/ACK are synchronized; the 20-bit identity bus is stable while busy.
// Cancel invalidates eligibility but still drains an old outstanding event.
module recovery_pixel_ui_event #(parameter integer ID_WIDTH=20)(
 input wire pixel_clk,pixel_rst,pixel_valid,pixel_marker,input wire [ID_WIDTH-1:0] pixel_identity,
 input wire app_clk,app_rst,input wire app_enable,
 output wire event_valid,output reg [ID_WIDTH-1:0] event_identity,input wire event_ready
);

reg req,ack;
reg [ID_WIDTH-1:0] hold_event,last_identity;
reg seen;
(* ASYNC_REG="TRUE" *)reg ack1,ack2,req1,req2;
// Continuous values retain the original net initializer expressions.


 
 
 // Capture the bundled payload before the second request synchronizer is
 // consumed. The pixel owner holds it until ACK returns. Only this register
 // is the CDC payload endpoint; identity comparisons are now synchronous.
 always @(posedge app_clk)event_identity<=hold_event;
 assign event_valid=app_enable&&req2!=ack;
 always @(posedge pixel_clk or posedge pixel_rst)begin
  if(pixel_rst)begin req<=0;ack1<=0;ack2<=0;hold_event<=0;last_identity<=0;seen<=0;end
  else begin
   ack1<=ack;ack2<=ack1;
   if(!pixel_valid)seen<=0;
   else if(pixel_marker&&req==ack2&&(!seen||pixel_identity!=last_identity))begin
    hold_event<=pixel_identity;last_identity<=pixel_identity;seen<=1;req<=~req;
   end
  end
 end
 always @(posedge app_clk or posedge app_rst)begin
  if(app_rst)begin ack<=0;req1<=0;req2<=0;end
  else begin
   req1<=req;req2<=req1;
   // A no-pending transfer already has req2==ack, so assigning req2 then
   // is identical to holding ack. Remove that redundant feedback compare
   // from the acceptance/disabled-drain D cone; no extra handshake cycle.
   ack <= (app_enable && !event_ready) ? ack : req2;
  end
 end
endmodule

`default_nettype wire
