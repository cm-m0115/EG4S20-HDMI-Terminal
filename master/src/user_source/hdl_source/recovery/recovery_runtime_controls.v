`default_nettype none
`timescale 1ns/1ps
// Session-only settings; resets restore neutral image/full volume.
// One stable fresh press changes one step. Holding a key NEVER repeats.
// Every mode change requires BOTH keys fully released before a new adjustment.
// Simultaneous left/right candidates cancel the adjustment until both release.
// References: lesson 14 setting/saturation principles; current key filtering.
module recovery_runtime_input_filter #(
    parameter integer DEBOUNCE_CYCLES=2000000
) (
    input wire clk,rst,raw_active,
    output wire synchronized_active,
    output reg stable_active,
    output wire synchronized_next,stable_next
);

localparam integer N=(DEBOUNCE_CYCLES<1)?1:DEBOUNCE_CYCLES;
localparam integer CW=(N<=1)?1:$clog2(N);
(* ASYNC_REG="TRUE" *) reg sync1,sync2;
reg [CW-1:0] count;
// Continuous values retain the original net initializer expressions.


    
    
    
    
    assign synchronized_active=sync2;
    // Final synchronizer stage only; functional consumers never use sync1.
    assign synchronized_next=sync2;
    assign stable_next=(sync2!=stable_active && count>=N-1)?sync2:stable_active;
    always @(posedge clk or posedge rst)begin
        if(rst)begin sync1<=0;sync2<=0;stable_active<=0;count<=0;end
        else begin
            sync1<=raw_active;sync2<=sync1;
            if(sync2==stable_active)count<=0;
            else if(count>=N-1)begin stable_active<=sync2;count<=0;end
            else count<=count+1'b1;
        end
    end
endmodule

module recovery_runtime_controls #(
    parameter integer CLK_HZ=100000000,
    parameter integer DEBOUNCE_MS=20,
    parameter integer DEBOUNCE_CYCLES=(CLK_HZ/1000)*DEBOUNCE_MS,
    // board convention: raw high means physically UP and active.
    parameter integer SWITCH_ACTIVE_LOW=0,
    // Both settings switches active: 1 brightness, 2 volume, 3 contrast.
    parameter integer BOTH_MODE=3
) (
    input wire clk,rst,
    input wire raw_sw3,raw_sw4,
    input wire key_left_n,key_right_n,
    (* max_fanout=8 *) output reg patient_inhibit,
    output wire [1:0] adjust_mode,
    output reg signed [8:0] brightness,
    output reg [9:0] contrast_gain,
    output reg [8:0] volume_gain
);

wire sw3_sync,sw4_sync,sw3_stable,sw4_stable;
wire sw3_sync_next,sw4_sync_next,sw3_stable_next,sw4_stable_next;
wire left_sync,right_sync,left_stable,right_stable;
wire sw3_active;
wire sw4_active;
reg [1:0] previous_mode;
reg adjust_armed,patient_guard;
wire both_released;
wire patient_guard_next;
// Continuous values retain the original net initializer expressions.
assign sw3_active = SWITCH_ACTIVE_LOW?!raw_sw3:raw_sw3;
assign sw4_active = SWITCH_ACTIVE_LOW?!raw_sw4:raw_sw4;
assign both_released = !left_sync&&!right_sync&&!left_stable&&!right_stable;
assign patient_guard_next = (sw3_sync||sw4_sync||adjust_mode!=0)?1'b1:
                            both_released?1'b0:patient_guard;

    
    
    
    
    
    recovery_runtime_input_filter #(DEBOUNCE_CYCLES) s3(clk,rst,sw3_active,sw3_sync,sw3_stable,sw3_sync_next,sw3_stable_next);
    recovery_runtime_input_filter #(DEBOUNCE_CYCLES) s4(clk,rst,sw4_active,sw4_sync,sw4_stable,sw4_sync_next,sw4_stable_next);
    recovery_runtime_input_filter #(DEBOUNCE_CYCLES) kl(clk,rst,!key_left_n,left_sync,left_stable,,);
    recovery_runtime_input_filter #(DEBOUNCE_CYCLES) kr(clk,rst,!key_right_n,right_sync,right_stable,,);
    
    
    assign adjust_mode=(sw3_stable&&sw4_stable)?BOTH_MODE[1:0]:
                       sw3_stable?2'd1:sw4_stable?2'd2:2'd0;
    // Inhibit starts at synchronized switch entry, ahead of debounce. It ends
    // only after exit is stable and both keys have genuinely been released.
    
    // the registered inhibit follows settled sync2. A switch entry
    // costs one extra 100MHz edge; debounce and release guards are unchanged.
    
    always @(posedge clk or posedge rst)begin
        if(rst)patient_inhibit<=0;
        else patient_inhibit<=sw3_sync_next||sw4_sync_next||
             sw3_stable_next||sw4_stable_next||patient_guard_next;
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            previous_mode<=0;adjust_armed<=0;patient_guard<=0;
            brightness<=0;contrast_gain<=10'd256;volume_gain<=9'd256;
        end else begin
            previous_mode<=adjust_mode;
            if(sw3_sync||sw4_sync||adjust_mode!=0)patient_guard<=1;
            else if(both_released)patient_guard<=0;
            if(adjust_mode!=previous_mode || adjust_mode==0)adjust_armed<=0;
            else if(both_released)adjust_armed<=1;
            else if(left_sync&&right_sync)adjust_armed<=0;
            else if(adjust_armed&&left_stable&&!right_stable&&!right_sync)begin
                adjust_armed<=0;
                case(adjust_mode)
                2'd1: if(brightness<9'sd64)brightness<=brightness+9'sd8;
                2'd2: if(volume_gain<9'd256)volume_gain<=volume_gain+9'd16;
                2'd3: if(contrast_gain<10'd384)contrast_gain<=contrast_gain+10'd32;
                endcase
            end else if(adjust_armed&&right_stable&&!left_stable&&!left_sync)begin
                adjust_armed<=0;
                case(adjust_mode)
                2'd1: if(brightness> -9'sd64)brightness<=brightness-9'sd8;
                2'd2: if(volume_gain>9'd0)volume_gain<=volume_gain-9'd16;
                2'd3: if(contrast_gain>10'd128)contrast_gain<=contrast_gain-10'd32;
                endcase
            end
        end
    end
endmodule

`default_nettype wire
