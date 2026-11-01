`default_nettype none
`timescale 1ns/1ps
// Inputs must be one coherent pixel-domain frame-held packet.
// Signed arithmetic and saturation
// give exact identity at B=0,C=256.
// Apply to picture RGB BEFORE OSD, so setting text remains readable.
module recovery_image_adjust (
    input wire [23:0] rgb,
    input wire signed [8:0] brightness,
    input wire [9:0] contrast_gain,
    output wire [23:0] adjusted_rgb
);
    function [7:0] adjust_channel;
        input [7:0] channel;
        input signed [8:0] offset;
        input [9:0] contrast;
        reg signed [9:0] centered;
        reg signed [10:0] unsigned_gain_as_signed;
        reg signed [20:0] product;
        reg signed [21:0] result;
        begin
            centered=$signed({2'b00,channel})-10'sd128;
            unsigned_gain_as_signed=$signed({1'b0,contrast});
            product=centered*unsigned_gain_as_signed;
            result=(product>>>8)+22'sd128+offset;
            if(result<0)adjust_channel=8'd0;
            else if(result>255)adjust_channel=8'd255;
            else adjust_channel=result[7:0];
        end
    endfunction
    assign adjusted_rgb=(brightness==0&&contrast_gain==10'd256)?rgb:
        {adjust_channel(rgb[23:16],brightness,contrast_gain),
         adjust_channel(rgb[15:8],brightness,contrast_gain),
         adjust_channel(rgb[7:0],brightness,contrast_gain)};
endmodule

`default_nettype wire
