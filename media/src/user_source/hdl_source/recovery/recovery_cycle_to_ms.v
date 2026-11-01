`default_nettype none
`timescale 1ns/1ps
// Unsigned constant-divider for cycle-to-ms conversion. Independently written
// Converts cycles without a 32-bit combinational divider in the 100MHz app path.
// 32 restoring steps, one cycle per numerator bit; result saturates at 65535.
// start is accepted only while !busy. done is a one-cycle pulse, all in clk.
module recovery_cycle_to_ms #(
    parameter integer DIVISOR = 50000
) (
    input wire clk, input wire rst, input wire start,
    input wire [31:0] cycles,
    output reg busy, output reg done, output reg [15:0] milliseconds
);

localparam integer REM_BITS=(DIVISOR<2)?1:$clog2(DIVISOR);
localparam [REM_BITS:0] DENOMINATOR=DIVISOR;
reg [REM_BITS-1:0] remainder;
reg [31:0] numerator, quotient;
reg [5:0] step;
wire [REM_BITS:0] trial;
wire [REM_BITS+1:0] difference;
wire quotient_bit;
wire [31:0] next_quotient;
// Continuous values retain the original net initializer expressions.
assign trial = {remainder,numerator[31]};
assign difference = {1'b0,trial}-{1'b0,DENOMINATOR};
assign quotient_bit = !difference[REM_BITS+1];
assign next_quotient = {quotient[30:0],quotient_bit};

    
    
    
    
    
    
    // Extended subtraction shares the compare/borrow carry chain.
    
    
    
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            busy<=0;done<=0;milliseconds<=0;remainder<=0;numerator<=0;quotient<=0;step<=0;
        end else begin
            done<=0;
            if(start && !busy) begin
                busy<=1;remainder<=0;numerator<=cycles;quotient<=0;step<=0;
            end else if(busy) begin
                numerator<={numerator[30:0],1'b0};quotient<=next_quotient;
                remainder<=quotient_bit?difference[REM_BITS-1:0]:trial[REM_BITS-1:0];
                if(step==31) begin
                    milliseconds<=(|next_quotient[31:16])?16'hffff:next_quotient[15:0];
                    busy<=0;done<=1;
                end else step<=step+1'b1;
            end
        end
    end
endmodule

`default_nettype wire
