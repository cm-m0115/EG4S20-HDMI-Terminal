`default_nettype none
`timescale 1ns/1ps
// history BMPs use the existing media owner and cancellation/drain path.
// No extra SD reader, frame store, clock, or frozen-core connection.
module recovery_history_media_bridge(
 input wire clk,rst,enable,detail_valid,input wire [5:0] detail_scene,
 input wire app_valid,input wire [5:0] app_scene,input wire [1:0] app_effect,input wire app_cancel,
 input wire media_ready,input wire recover, // link/fault recovery invalidates queued scene ownership
 output wire cmd_valid,output wire [5:0] cmd_scene,output wire [1:0] cmd_effect,
 output wire cancel,output wire app_ready,output wire history_exit
);

reg prev_enable,prev_detail_valid,requested;
reg [5:0] prev_detail_scene;
wire changed;
// Continuous values retain the original net initializer expressions.
assign changed = (enable!=prev_enable)||
  (enable&&((detail_valid!=prev_detail_valid)||
   (detail_valid&&detail_scene!=prev_detail_scene)));

 
 
 
 assign cancel=app_cancel||changed;
 assign cmd_valid=!cancel&&!(recover===1'b1)&&(enable?(detail_valid&&!requested):app_valid);
 assign cmd_scene=enable?detail_scene:app_scene;
 assign cmd_effect=enable?2'd0:app_effect;
 assign app_ready=!enable&&!cancel&&media_ready;
 assign history_exit=prev_enable&&!enable;
 always @(posedge clk or posedge rst)begin
  if(rst)begin prev_enable<=0;prev_detail_valid<=0;prev_detail_scene<=0;requested<=0;end
  else begin
   prev_enable<=enable;prev_detail_valid<=detail_valid;prev_detail_scene<=detail_scene;
   if(changed||app_cancel||(recover===1'b1))requested<=0;
   else if(enable&&cmd_valid&&media_ready)requested<=1;
  end
 end
endmodule

`default_nettype wire
