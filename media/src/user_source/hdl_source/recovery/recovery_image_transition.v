`default_nettype none
`timescale 1ns/1ps
// single-read-port fade-out / legal bank switch / fade-in.
// Reference: lesson 10 video_fade_transition.v (frame-held ramp only).
// This implementation uses the project's real pre-active frame boundary and
// existing pixel-domain commit mailbox; it adds no clock-domain crossings.
// start: complete candidate image has met the existing commit prerequisites.
// fetched: this command's new bank SOF was actually accepted by HDMI.
// done: a whole new-image frame at exact full gain was accepted by HDMI.
// Legal FADE_FRAMES is 1..32; either direction takes exactly that many frame
// boundaries. RGB gain changes only at frame_boundary (or asynchronous reset).
module recovery_image_transition #(
    parameter integer FADE_FRAMES = 16,
    parameter integer FRAME_PIXELS = 307200,
    parameter integer EFFECT_SELECT_ENABLE = 0,
    parameter integer WIPE_WIDTH = 640,
    parameter integer EASING_ENABLE = 0,
    parameter integer DIRECTION_ENABLE = 0
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire abort,
    input wire frame_boundary,
    input wire fetched,
    input wire axis_user,
    input wire axis_valid,
    input wire axis_ready,
    input wire [1:0] effect,
    input wire [1:0] direction,
    output reg [8:0] gain,
    output reg [9:0] reveal_width,
    output reg wipe_active,
    output reg [1:0] active_direction,
    output wire allow_switch,
    output wire busy,
    output reg done,
    output reg error
);

localparam integer N = (FADE_FRAMES < 1) ? 1 :
                           ((FADE_FRAMES > 32) ? 32 : FADE_FRAMES);
localparam integer PIXELS = (FRAME_PIXELS < 1) ? 1 : FRAME_PIXELS;
localparam integer PIXEL_COUNT_WIDTH = (PIXELS <= 1) ? 1 : $clog2(PIXELS+1);
localparam [2:0] S_IDLE=0, S_OUT=1, S_BLACK=2, S_IN=3,
                     S_VERIFY=4, S_RECOVER=5, S_W_ARM=6, S_W_BLACK=7;
reg [2:0] state;
reg [5:0] step;
reg short_profile;
wire [6:0] next_unclamped;
wire [5:0] next_step;
reg [1:0] direction_hold;
reg verifying_frame;
reg [PIXEL_COUNT_WIDTH-1:0] accepted_pixels;
wire accept_pixel ;
// Continuous values retain the original net initializer expressions.
assign next_unclamped = {1'b0,step}+(short_profile?7'd2:7'd1);
assign next_step = next_unclamped>=N?N:next_unclamped[5:0];
assign accept_pixel =  axis_valid && axis_ready;

    // Clamp invalid parameters to a bounded circuit. Integration must select
    // the documented range; the simulation guard catches invalid builds.
    
    
    
    
    
    
    
    
    
    
    
    
    
    assign busy = (state != S_IDLE);
    assign allow_switch = !abort && (((state == S_BLACK) && (gain == 9'd0)) ||
        state == S_W_BLACK || (state == S_W_ARM && frame_boundary));

    // Constant-divisor integer arithmetic gives a monotonic exact-endpoint
    // ramp for EVERY supported N, including N values that do not divide 256.
    // Smoothstep is evaluated only for the small frame counter, never for
    // individual pixels. Constant N permits constant-folding into a small LUT.
    function [8:0] ramp;
        input [5:0] next_step;
        begin case(next_step)
            6'd0:ramp=EASING_ENABLE!=0?(((256*0/N)*(256*0/N)*(768-2*(256*0/N))+32768)/65536):(256*0/N);
            6'd1:ramp=EASING_ENABLE!=0?(((256*1/N)*(256*1/N)*(768-2*(256*1/N))+32768)/65536):(256*1/N);
            6'd2:ramp=EASING_ENABLE!=0?(((256*2/N)*(256*2/N)*(768-2*(256*2/N))+32768)/65536):(256*2/N);
            6'd3:ramp=EASING_ENABLE!=0?(((256*3/N)*(256*3/N)*(768-2*(256*3/N))+32768)/65536):(256*3/N);
            6'd4:ramp=EASING_ENABLE!=0?(((256*4/N)*(256*4/N)*(768-2*(256*4/N))+32768)/65536):(256*4/N);
            6'd5:ramp=EASING_ENABLE!=0?(((256*5/N)*(256*5/N)*(768-2*(256*5/N))+32768)/65536):(256*5/N);
            6'd6:ramp=EASING_ENABLE!=0?(((256*6/N)*(256*6/N)*(768-2*(256*6/N))+32768)/65536):(256*6/N);
            6'd7:ramp=EASING_ENABLE!=0?(((256*7/N)*(256*7/N)*(768-2*(256*7/N))+32768)/65536):(256*7/N);
            6'd8:ramp=EASING_ENABLE!=0?(((256*8/N)*(256*8/N)*(768-2*(256*8/N))+32768)/65536):(256*8/N);
            6'd9:ramp=EASING_ENABLE!=0?(((256*9/N)*(256*9/N)*(768-2*(256*9/N))+32768)/65536):(256*9/N);
            6'd10:ramp=EASING_ENABLE!=0?(((256*10/N)*(256*10/N)*(768-2*(256*10/N))+32768)/65536):(256*10/N);
            6'd11:ramp=EASING_ENABLE!=0?(((256*11/N)*(256*11/N)*(768-2*(256*11/N))+32768)/65536):(256*11/N);
            6'd12:ramp=EASING_ENABLE!=0?(((256*12/N)*(256*12/N)*(768-2*(256*12/N))+32768)/65536):(256*12/N);
            6'd13:ramp=EASING_ENABLE!=0?(((256*13/N)*(256*13/N)*(768-2*(256*13/N))+32768)/65536):(256*13/N);
            6'd14:ramp=EASING_ENABLE!=0?(((256*14/N)*(256*14/N)*(768-2*(256*14/N))+32768)/65536):(256*14/N);
            6'd15:ramp=EASING_ENABLE!=0?(((256*15/N)*(256*15/N)*(768-2*(256*15/N))+32768)/65536):(256*15/N);
            6'd16:ramp=EASING_ENABLE!=0?(((256*16/N)*(256*16/N)*(768-2*(256*16/N))+32768)/65536):(256*16/N);
            6'd17:ramp=EASING_ENABLE!=0?(((256*17/N)*(256*17/N)*(768-2*(256*17/N))+32768)/65536):(256*17/N);
            6'd18:ramp=EASING_ENABLE!=0?(((256*18/N)*(256*18/N)*(768-2*(256*18/N))+32768)/65536):(256*18/N);
            6'd19:ramp=EASING_ENABLE!=0?(((256*19/N)*(256*19/N)*(768-2*(256*19/N))+32768)/65536):(256*19/N);
            6'd20:ramp=EASING_ENABLE!=0?(((256*20/N)*(256*20/N)*(768-2*(256*20/N))+32768)/65536):(256*20/N);
            6'd21:ramp=EASING_ENABLE!=0?(((256*21/N)*(256*21/N)*(768-2*(256*21/N))+32768)/65536):(256*21/N);
            6'd22:ramp=EASING_ENABLE!=0?(((256*22/N)*(256*22/N)*(768-2*(256*22/N))+32768)/65536):(256*22/N);
            6'd23:ramp=EASING_ENABLE!=0?(((256*23/N)*(256*23/N)*(768-2*(256*23/N))+32768)/65536):(256*23/N);
            6'd24:ramp=EASING_ENABLE!=0?(((256*24/N)*(256*24/N)*(768-2*(256*24/N))+32768)/65536):(256*24/N);
            6'd25:ramp=EASING_ENABLE!=0?(((256*25/N)*(256*25/N)*(768-2*(256*25/N))+32768)/65536):(256*25/N);
            6'd26:ramp=EASING_ENABLE!=0?(((256*26/N)*(256*26/N)*(768-2*(256*26/N))+32768)/65536):(256*26/N);
            6'd27:ramp=EASING_ENABLE!=0?(((256*27/N)*(256*27/N)*(768-2*(256*27/N))+32768)/65536):(256*27/N);
            6'd28:ramp=EASING_ENABLE!=0?(((256*28/N)*(256*28/N)*(768-2*(256*28/N))+32768)/65536):(256*28/N);
            6'd29:ramp=EASING_ENABLE!=0?(((256*29/N)*(256*29/N)*(768-2*(256*29/N))+32768)/65536):(256*29/N);
            6'd30:ramp=EASING_ENABLE!=0?(((256*30/N)*(256*30/N)*(768-2*(256*30/N))+32768)/65536):(256*30/N);
            6'd31:ramp=EASING_ENABLE!=0?(((256*31/N)*(256*31/N)*(768-2*(256*31/N))+32768)/65536):(256*31/N);
            6'd32:ramp=EASING_ENABLE!=0?(((256*32/N)*(256*32/N)*(768-2*(256*32/N))+32768)/65536):(256*32/N);
            default:ramp=9'd256;
        endcase end
    endfunction
    function [8:0] fade_out_gain;
        input [5:0] next_step;
        begin fade_out_gain = EASING_ENABLE!=0 ? 256-ramp(next_step):(256*(N-next_step))/N; end
    endfunction
    function [8:0] fade_in_gain;
        input [5:0] next_step;
        begin fade_in_gain = ramp(next_step); end
    endfunction
    function [9:0] wipe_width;
        input [5:0] next_step;
        begin wipe_width = EASING_ENABLE!=0 ? (WIPE_WIDTH*ramp(next_step))/256:(WIPE_WIDTH*next_step)/N; end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=S_IDLE; step<=0; gain<=9'd256;short_profile<=0;
            reveal_width<=WIPE_WIDTH; wipe_active<=0;
            direction_hold<=0;active_direction<=0;
            verifying_frame<=0; accepted_pixels<=0;
            done<=0; error<=0;
        end else begin
            done<=0; error<=0;
            if (abort) begin
                // A cancelled command cannot release a new command until its
                // old gain is safely restored in the next vertical blank.
                if (state != S_IDLE) state<=S_RECOVER;
                verifying_frame<=0; accepted_pixels<=0;
            end else begin
                case (state)
                S_IDLE: if (start) begin
                    short_profile<=EFFECT_SELECT_ENABLE!=0&&effect==2'd3&&N==16;
                    state<=(EFFECT_SELECT_ENABLE != 0 && effect == 2'd2) ? S_W_ARM : S_OUT;
                    step<=0;
                    direction_hold<=DIRECTION_ENABLE!=0?direction:2'd0;
                    verifying_frame<=0; accepted_pixels<=0;
                    // Do not touch gain for a request arriving during a frame.
                end
                S_W_ARM: if (frame_boundary) begin
                    // Select the new bank in this same blanking interval.
                    // A single read stream reveals the new image over black;
                    // it never pretends to combine old/new SDRAM streams.
                    reveal_width<=0; wipe_active<=1; state<=S_W_BLACK;
                    active_direction<=direction_hold;
                end
                S_W_BLACK: if (fetched) begin state<=S_IN; step<=0; end
                S_OUT: if (frame_boundary) begin
                    wipe_active<=0; reveal_width<=WIPE_WIDTH;
                    step<=next_step;
                    gain<=fade_out_gain(next_step);
                    if (next_unclamped>=N) state<=S_BLACK;
                end
                S_BLACK: if (fetched) begin
                    state<=S_IN; step<=0;
                    // This new image is still black. No presentation response
                    // or timing/audio event may be issued at this point.
                end
                S_IN: if (frame_boundary) begin
                    step<=next_step;
                    if (wipe_active) reveal_width<=wipe_width(next_step);
                    else gain<=fade_in_gain(next_step);
                    if (next_unclamped>=N) begin
                        state<=S_VERIFY;
                        verifying_frame<=0; accepted_pixels<=0;
                    end
                end
                S_VERIFY: begin
                    // This HDMI timing stream cannot stretch active pixels.
                    // A dropped pixel invalidates the promised complete frame.
                    if (axis_valid && !axis_ready) begin
                        error<=1; state<=S_RECOVER;
                        verifying_frame<=0; accepted_pixels<=0;
                    end else if (accept_pixel) begin
                        if (axis_user) begin
                            if (verifying_frame) begin
                                // Never join a short frame to the next frame.
                                error<=1; state<=S_RECOVER;
                                verifying_frame<=0; accepted_pixels<=0;
                            end else if (PIXELS == 1) begin
                                done<=1; state<=S_IDLE;
                            end else begin
                                verifying_frame<=1; accepted_pixels<=1;
                            end
                        end else if (verifying_frame) begin
                            if (accepted_pixels == PIXELS-1) begin
                                done<=1; state<=S_IDLE;
                                verifying_frame<=0; accepted_pixels<=0;
                            end else accepted_pixels<=accepted_pixels+1'b1;
                        end
                    end
                end
                S_RECOVER: if (frame_boundary) begin
                    gain<=9'd256; step<=0; state<=S_IDLE;
                    reveal_width<=WIPE_WIDTH; wipe_active<=0;
                    active_direction<=0;
                    verifying_frame<=0; accepted_pixels<=0;
                end
                default: begin
                    error<=1; state<=S_RECOVER;
                    verifying_frame<=0; accepted_pixels<=0;
                end
                endcase
            end
        end
    end
    // synthesis translate_off
`ifndef SYNTHESIS
    initial begin
        if (FADE_FRAMES < 1 || FADE_FRAMES > 32 || FRAME_PIXELS < 1)
            $error("recovery_image_transition parameters require FADE_FRAMES 1..32 and FRAME_PIXELS >= 1");
    end
`endif
    // synthesis translate_on
endmodule

// Combinational RGB-only gain. No clock, stall or extra pixel/control delay;
// all AXIS markers and handshake wires retain their existing direct path.
// 256 is representable, so the disabled/full-gain path is bit-for-bit exact.
module recovery_transition_rgb (
    input wire [23:0] rgb,
    input wire [8:0] gain,
    output wire [23:0] faded_rgb
);

wire [16:0] red_product ;
wire [16:0] green_product ;
wire [16:0] blue_product ;
// Continuous values retain the original net initializer expressions.
assign red_product =  rgb[23:16] * gain;
assign green_product =  rgb[15:8] * gain;
assign blue_product =  rgb[7:0] * gain;

    
    
    
    assign faded_rgb = (gain == 9'd256) ? rgb :
                       {red_product[15:8], green_product[15:8], blue_product[15:8]};
endmodule

`default_nettype wire
