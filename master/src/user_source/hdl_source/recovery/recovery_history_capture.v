`default_nettype none
`timescale 1ns/1ps
// Freeze raw report and timestamp on the
// capture edge, then register its score BEFORE the history RAM write. Full
// throughput is one report per clock; no acceptance/score/record is dropped.
module recovery_history_capture(
 input wire clk,rst,capture,input wire [159:0] status,input wire [23:0] timestamp,
 output reg saved_capture,output reg [159:0] saved_status,output reg [23:0] saved_timestamp
);

reg pending;
reg [159:0] raw_status;
reg [23:0] raw_timestamp;
wire [6:0] captured_score;
// Continuous values retain the original net initializer expressions.


 
 
 recovery_ward_score u_score(.report_fields(raw_status[127:0]),.total_score(captured_score));
 always @(posedge clk or posedge rst)begin
  if(rst)begin pending<=0;raw_status<=0;raw_timestamp<=0;saved_capture<=0;saved_status<=0;saved_timestamp<=0;end
  else begin
   pending<=capture;saved_capture<=pending;
   if(capture)begin raw_status<=status;raw_timestamp<=timestamp;end
   if(pending)begin
    saved_status<=raw_status;saved_timestamp<=raw_timestamp;
    if(raw_status[158:157]==2)begin saved_status[121:115]<=captured_score;saved_status[122]<=1;end
   end
  end
 end
endmodule

`default_nettype wire
