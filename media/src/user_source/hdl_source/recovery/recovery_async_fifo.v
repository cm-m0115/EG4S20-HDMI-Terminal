`default_nettype none
`timescale 1ns/1ps
// Dual-clock FIFO with source-domain Gray pointers and synchronous RAM read.
// Common reset asserts asynchronously. Dedicated reset synchronizers release
// the pointer/synchronizer registers on their own clock domains; raw arst never
// releases those ordinary registers directly. RAM contents need no reset: the
// cleared pointers make old samples unreachable until a new accepted write.
module recovery_async_fifo #(
    parameter integer WIDTH=16, parameter integer ADDR_BITS=13
)(
    input wire arst, input wire wr_clk, input wire wr_en,
    input wire [WIDTH-1:0] wr_data, output wire full,
    output wire [ADDR_BITS:0] wr_level,
    input wire rd_clk, input wire rd_en, output reg [WIDTH-1:0] rd_data,
    output wire empty, output wire [ADDR_BITS:0] rd_level
);

(* ram_style="bram_32k" *) reg [WIDTH-1:0] mem[0:(1<<ADDR_BITS)-1];
(* ASYNC_REG="TRUE" *) reg [1:0] wr_reset_sync, rd_reset_sync;
wire wr_rst;
wire rd_rst;
reg [ADDR_BITS:0] wb, wg, rb, rg;
(* ASYNC_REG="TRUE" *) reg [ADDR_BITS:0] rg1,rg2,wg1,wg2;
wire [ADDR_BITS:0] wb_next;
wire [ADDR_BITS:0] rb_next;
// Continuous values retain the original net initializer expressions.
assign wr_rst = wr_reset_sync[1];
assign rd_rst = rd_reset_sync[1];
assign wb_next = wb+1'b1;
assign rb_next = rb+1'b1;

    // TD SWUG106 4.2.6: select large block RAM explicitly.
    
    // The stream-domain mixer uses 8192x17 and maps to 6 BRAM32K.
    
    
    
    
    
    
    function [ADDR_BITS:0] gray_to_bin;
        input [ADDR_BITS:0] g; integer i;
        begin
            gray_to_bin[ADDR_BITS]=g[ADDR_BITS];
            for(i=ADDR_BITS-1;i>=0;i=i-1)
                gray_to_bin[i]=gray_to_bin[i+1]^g[i];
        end
    endfunction
    
    
    assign full = wr_rst || wg == {~rg2[ADDR_BITS:ADDR_BITS-1],rg2[ADDR_BITS-2:0]};
    assign empty = rd_rst || rg==wg2;
    assign wr_level=wb-gray_to_bin(rg2);
    assign rd_level=gray_to_bin(wg2)-rb;
    always @(posedge wr_clk or posedge arst)
      if(arst) wr_reset_sync<=2'b11;
      else wr_reset_sync<={wr_reset_sync[0],1'b0};
    always @(posedge rd_clk or posedge arst)
      if(arst) rd_reset_sync<=2'b11;
      else rd_reset_sync<={rd_reset_sync[0],1'b0};
    always @(posedge wr_clk or posedge wr_rst) begin
        if(wr_rst) begin wb<=0; wg<=0; rg1<=0; rg2<=0; end
        else begin
            rg1<=rg; rg2<=rg1;
            if(wr_en && !full) begin wb<=wb_next; wg<=(wb_next>>1)^wb_next; end
        end
    end
    always @(posedge wr_clk)
        if(wr_en && !full) mem[wb[ADDR_BITS-1:0]]<=wr_data;
    always @(posedge rd_clk or posedge rd_rst) begin
        if(rd_rst) begin rb<=0; rg<=0; wg1<=0; wg2<=0; end
        else begin
            wg1<=wg; wg2<=wg1;
            if(rd_en && !empty) begin rb<=rb_next; rg<=(rb_next>>1)^rb_next; end
        end
    end
    always @(posedge rd_clk)
        if(rd_en && !empty) rd_data<=mem[rb[ADDR_BITS-1:0]];
endmodule

`default_nettype wire
