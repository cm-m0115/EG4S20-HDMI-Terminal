`default_nettype none
`timescale 1ns/1ps
// Application input filtering and edge timestamps.
// Reference: official SD/sd_card_bmp.v key_press_debounce and course lesson 3
// dual_key_chord_router.v; no source copied. Unlike the reference, both edges
// carry the first synchronized candidate timestamp. A bounced candidate is
// cancelled. All outputs belong to clk; this module is NOT an event CDC bridge.
module recovery_key_filter #(
    parameter integer DEBOUNCE_CYCLES = 1000000
) (
    input wire clk, input wire rst, input wire raw_n,
    input wire [31:0] time_cycles,
    output wire down, output wire sync_down,
    output reg press, output reg release_event,
    output reg [31:0] press_cycles, output reg [31:0] release_cycles,
    output wire pending_press, output wire pending_release,
    output reg [31:0] candidate_cycles
);

(* ASYNC_REG = "TRUE" *) reg sync1_n, sync2_n;
reg stable_n, candidate_valid;
reg [31:0] count;
// Continuous values retain the original net initializer expressions.


    
    
    
    assign down = !stable_n;
    assign sync_down = !sync2_n;
    assign pending_press = candidate_valid && stable_n && !sync2_n;
    assign pending_release = candidate_valid && !stable_n && sync2_n;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync1_n <= 1'b1; sync2_n <= 1'b1; stable_n <= 1'b1;
            candidate_valid <= 0; candidate_cycles <= 0; count <= 0;
            press <= 0; release_event <= 0; press_cycles <= 0; release_cycles <= 0;
        end else begin
            sync1_n <= raw_n; sync2_n <= sync1_n;
            press <= 0; release_event <= 0;
            if (sync2_n == stable_n) begin
                candidate_valid <= 0; count <= 0;
            end else if (!candidate_valid) begin
                candidate_cycles <= time_cycles;
                if (DEBOUNCE_CYCLES <= 1) begin
                    stable_n <= sync2_n;
                    if (!sync2_n) begin press <= 1; press_cycles <= time_cycles; end
                    else begin release_event <= 1; release_cycles <= time_cycles; end
                    candidate_valid <= 0;
                end else begin candidate_valid <= 1; count <= 1; end
            end else if (count >= DEBOUNCE_CYCLES-1) begin
                stable_n <= sync2_n; candidate_valid <= 0; count <= 0;
                if (!sync2_n) begin press <= 1; press_cycles <= candidate_cycles; end
                else begin release_event <= 1; release_cycles <= candidate_cycles; end
            end else count <= count + 1'b1;
        end
    end
endmodule

module recovery_switch_filter #(
    parameter integer DEBOUNCE_CYCLES = 1000000
) (input wire clk, input wire rst, input wire raw,
   output reg stable);

(* ASYNC_REG = "TRUE" *) reg sync1, sync2;
reg [31:0] count;
// Continuous values retain the original net initializer expressions.


    
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin sync1 <= 0; sync2 <= 0; stable <= 0; count <= 0; end
        else begin
            sync1 <= raw; sync2 <= sync1;
            if (sync2 == stable) count <= 0;
            else if (count >= DEBOUNCE_CYCLES-1) begin stable <= sync2; count <= 0; end
            else count <= count + 1'b1;
        end
    end
endmodule

module recovery_keys #(
    parameter integer DEBOUNCE_CYCLES = 1000000
) (
    input wire clk, input wire rst, input wire [31:0] time_cycles,
    input wire sw1, input wire sw2,
    input wire key_l_n, input wire key_r_n, input wire key_back_n,
    output wire sw1_on, output wire sw2_on,
    output wire l_down, output wire r_down, output wire b_down,
    output wire l_sync_down, output wire r_sync_down, output wire b_sync_down,
    output wire l_press, output wire r_press, output wire b_press,
    output wire l_release, output wire r_release, output wire b_release,
    output wire [31:0] l_press_cycles, output wire [31:0] r_press_cycles,
    output wire [31:0] b_press_cycles,
    output wire [31:0] l_release_cycles, output wire [31:0] r_release_cycles,
    output wire [31:0] b_release_cycles,
    output wire l_pending_press, output wire r_pending_press,
    output wire l_pending_release, output wire r_pending_release,
    output wire [31:0] l_candidate_cycles, output wire [31:0] r_candidate_cycles
);

wire bp_unused, br_unused;
wire [31:0] bc_unused;
// Continuous values retain the original net initializer expressions.


     
    recovery_switch_filter #(DEBOUNCE_CYCLES) s1(clk,rst,sw1,sw1_on);
    recovery_switch_filter #(DEBOUNCE_CYCLES) s2(clk,rst,sw2,sw2_on);
    recovery_key_filter #(DEBOUNCE_CYCLES) kl(
        clk,rst,key_l_n,time_cycles,l_down,l_sync_down,l_press,l_release,
        l_press_cycles,l_release_cycles,l_pending_press,l_pending_release,l_candidate_cycles);
    recovery_key_filter #(DEBOUNCE_CYCLES) kr(
        clk,rst,key_r_n,time_cycles,r_down,r_sync_down,r_press,r_release,
        r_press_cycles,r_release_cycles,r_pending_press,r_pending_release,r_candidate_cycles);
    recovery_key_filter #(DEBOUNCE_CYCLES) kb(
        clk,rst,key_back_n,time_cycles,b_down,b_sync_down,b_press,b_release,
        b_press_cycles,b_release_cycles,bp_unused,br_unused,bc_unused);
endmodule

`default_nettype wire
