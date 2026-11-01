`default_nettype none
`timescale 1ns/1ps
// B's monotonic timestamp owns the 1000ms wait and key decision.
// GPIO marks the local boundary; reliable UART confirms its identity later.
// Store candidate press/release while confirmation is pending (never infer
// optical light timing). An earlier held press cannot become a valid answer.
module recovery_practice_cue #(parameter integer CLK_HZ=100000000,WAIT_MS=1000,SHORT_MS=3000)(
 input wire clk,rst,enable,input wire [31:0] now_cycles,
 input wire presented,confirmed,input wire [31:0] presented_cycles,input wire press_l,press_r,release_l,release_r,
 input wire [31:0] press_l_time,press_r_time,release_l_time,release_r_time,
 input wire sync_l,sync_r,
 output reg green_request,output reg pass_event,fail_event,output reg answer_right
);

localparam [31:0] WAIT_CYCLES=(CLK_HZ/1000)*WAIT_MS;
localparam [31:0] SHORT_CYCLES=(CLK_HZ/1000)*SHORT_MS;
reg active,finished,gpio_seen,identity_seen,press_seen,release_seen,invalid;
reg [31:0] wait_start,gpio_time,press_time,release_time;
// Continuous values retain the original net initializer expressions.


 
 
 
 
 always @(posedge clk or posedge rst)begin
  if(rst)begin active<=0;finished<=0;gpio_seen<=0;identity_seen<=0;press_seen<=0;release_seen<=0;invalid<=0;
   wait_start<=0;gpio_time<=0;press_time<=0;release_time<=0;green_request<=0;pass_event<=0;fail_event<=0;answer_right<=0;
  end else begin
   pass_event<=0;fail_event<=0;
   if(!enable)begin active<=0;finished<=0;green_request<=0;gpio_seen<=0;identity_seen<=0;press_seen<=0;release_seen<=0;invalid<=0;end
   else if(!active)begin active<=1;wait_start<=now_cycles;end
   else if(!finished)begin
    if(!green_request)begin
     if(press_l||press_r||sync_l||sync_r)begin fail_event<=1;finished<=1;end
     else if(now_cycles-wait_start>=WAIT_CYCLES)green_request<=1;
    end else begin
     if(presented&&!gpio_seen)begin gpio_seen<=1;gpio_time<=presented_cycles;end
     if(confirmed)identity_seen<=1;
     if(sync_l&&sync_r)invalid<=1;
     if(press_l||press_r)begin
      if(press_seen||press_l&&press_r)invalid<=1;
      else begin press_seen<=1;answer_right<=press_r;press_time<=press_r?press_r_time:press_l_time;end
     end
     if(release_l||release_r)begin
      if(press_seen&&(answer_right?release_r:release_l))begin release_seen<=1;release_time<=answer_right?release_r_time:release_l_time;end
      else invalid<=1;
     end
     if(gpio_seen&&identity_seen&&press_seen)begin
      if(invalid||$signed(press_time-gpio_time)<0)begin fail_event<=1;finished<=1;end
      else if(release_seen)begin
       if(release_time-press_time>=SHORT_CYCLES)fail_event<=1;else pass_event<=1;
       finished<=1;
      end
     end
    end
   end
  end
 end
endmodule

`default_nettype wire
