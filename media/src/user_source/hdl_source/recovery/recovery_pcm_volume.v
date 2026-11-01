`default_nettype none
`timescale 1ns/1ps
// Signed mono sample scaling; gain is held for a whole stereo
// frame by the caller. Legal gain 0..256, defaults to exact unity.
module recovery_pcm_volume (
    input wire signed [15:0] sample_in,
    input wire [8:0] gain,
    output wire signed [15:0] sample_out
);

wire [8:0] bounded_gain;
wire signed [9:0] signed_gain;
wire signed [25:0] product;
wire signed [25:0] scaled;
// Continuous values retain the original net initializer expressions.
assign bounded_gain = (gain>9'd256)?9'd256:gain;
assign signed_gain = $signed({1'b0,bounded_gain});
assign product = sample_in*signed_gain;
assign scaled = product>>>8;

    
    
    
    
    assign sample_out=(bounded_gain==9'd256)?sample_in:scaled[15:0];
endmodule

`default_nettype wire
