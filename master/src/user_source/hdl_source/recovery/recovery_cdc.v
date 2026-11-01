`default_nettype none
`timescale 1ns/1ps
// Async assertion, domain-local synchronous deassertion for new reset paths.
module recovery_reset_sync(input wire clk,input wire arst,output wire rst);

(* ASYNC_REG="TRUE" *) reg [1:0] sync;
// Continuous values retain the original net initializer expressions.


 
 always @(posedge clk or posedge arst)if(arst)sync<=2'b11;else sync<={sync[0],1'b0};
 assign rst=sync[1];
endmodule

// A report transaction freezes type, outcome, validity and all patient fields
// together. Ordinary prompts/countdown never overwrite a retained report.
module recovery_report_snapshot(
 input wire clk,rst,capture,input wire [1:0] report_mode,input wire [7:0] report_epoch,
 input wire [5:0] started,input wire [2:0] outcome,input wire [3:0] fault,
 input wire [1:0] t1_unanswered,t2_unanswered,input wire [69:0] fields,
 output reg [31:0] metadata,output reg [69:0] snapshot_fields
);

reg [3:0] report_seq;
// Continuous values retain the original net initializer expressions.


 
 always @(posedge clk or posedge rst)begin
  if(rst)begin report_seq<=0;metadata<=0;snapshot_fields<=0;end
  else if(capture)begin
   report_seq<=report_seq+1'b1;
   metadata<={1'b1,report_mode,report_epoch,started,outcome,fault,
     t1_unanswered,t2_unanswered,report_seq+4'd1};
   snapshot_fields<=fields;
  end
 end
endmodule
// Stable source payload until destination acknowledge. Receiver captures only
// at its requested frame boundary, so displayed status is a coherent snapshot.
module recovery_status_mailbox #(parameter WIDTH=128)(
 input wire src_clk,src_rst,input wire [WIDTH-1:0] src_data,
 input wire dst_clk,dst_rst,input wire frame_boundary,output reg [WIDTH-1:0] dst_data,
 // Source-side observation only. A matching echo with settled high means
 // that entire held packet has already been accepted at a frame boundary.
 output wire src_settled,output wire [WIDTH-1:0] src_echo
);

reg req,ack;
reg [WIDTH-1:0] hold_data;
(* ASYNC_REG="TRUE" *)reg ack1,ack2,req1,req2;
// Continuous values retain the original net initializer expressions.


 
 
 assign src_settled=req==ack2;
 assign src_echo=hold_data;
 always @(posedge src_clk or posedge src_rst)begin
  if(src_rst)begin req<=0;hold_data<=0;ack1<=0;ack2<=0;end
  else begin ack1<=ack;ack2<=ack1;if(req==ack2)begin hold_data<=src_data;req<=~req;end end
 end
 always @(posedge dst_clk or posedge dst_rst)begin
  if(dst_rst)begin ack<=0;req1<=0;req2<=0;dst_data<=0;end
  else begin req1<=req;req2<=req1;if(frame_boundary&&req2!=ack)begin dst_data<=hold_data;ack<=req2;end end
 end
endmodule

`default_nettype wire
