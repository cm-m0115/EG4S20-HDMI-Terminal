`default_nettype none
`timescale 1ns/1ps
// Power session time, independent of media cancellation/reset.
// rst is the existing PLL-lock startup reset, never the physical KEY1.
// BCD counters avoid division or a wide binary-to-decimal pixel path.
module recovery_session_timer #(
 parameter integer CLK_HZ=100000000
)(input wire clk,rst,output wire [23:0] elapsed_bcd);

localparam integer CYCLES_PER_MS=CLK_HZ/1000;
localparam integer DIV_WIDTH=(CYCLES_PER_MS<=1)?1:$clog2(CYCLES_PER_MS);
reg [DIV_WIDTH-1:0] divider;
reg [9:0] millisecond;
reg [3:0] second_units,second_tens,minute_units,minute_tens,hour_units,hour_tens;
wire at_limit;
// Continuous values retain the original net initializer expressions.
assign at_limit = {hour_tens,hour_units,minute_tens,minute_units,second_tens,second_units}==24'h995959;

 
 
 
 
 
 
 assign elapsed_bcd={hour_tens,hour_units,minute_tens,minute_units,second_tens,second_units};
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   divider<=0;millisecond<=0;second_units<=0;second_tens<=0;
   minute_units<=0;minute_tens<=0;hour_units<=0;hour_tens<=0;
  end else if(divider==CYCLES_PER_MS-1)begin
   divider<=0;
   if(millisecond==999)begin
    millisecond<=0;
    if(!at_limit)begin
     if(second_units==9)begin
      second_units<=0;
      if(second_tens==5)begin
       second_tens<=0;
       if(minute_units==9)begin
        minute_units<=0;
        if(minute_tens==5)begin
         minute_tens<=0;
         if(hour_units==9)begin hour_units<=0;hour_tens<=hour_tens+1'b1;end
         else hour_units<=hour_units+1'b1;
        end else minute_tens<=minute_tens+1'b1;
       end else minute_units<=minute_units+1'b1;
      end else second_tens<=second_tens+1'b1;
     end else second_units<=second_units+1'b1;
    end
   end else millisecond<=millisecond+1'b1;
  end else divider<=divider+1'b1;
 end
endmodule

// A single registered pixel stage; held status is accepted in aligned blank.
// The top-right timer stays visible above runtime parameters. KEY1 status is
// shown only when skipping is enabled. Glyph gaps preserve the input pixels.
module recovery_session_timer_osd #(parameter integer THEMED_ENABLE=0)(
 input wire clk,rst,vs,de,input wire [23:0] rgb,
 input wire [24:0] status,input wire hide_timer,output reg [23:0] out_rgb
);

reg previous_de,previous_vs,arm;
reg [9:0] x,y;
reg [24:0] frame_status;
wire line_start;
wire [9:0] px;
wire [9:0] py;
wire timer_hit;
wire skip_hit;
wire [9:0] relative_x;
wire [5:0] glyph_cell;
wire [3:0] gx;
wire [3:0] gy;
reg [15:0] character;
wire [15:0] glyph_row;
reg panel_pipe,highlight_pipe;
reg [3:0] gx_pipe;
reg [23:0] rgb_pipe;
// Continuous values retain the original net initializer expressions.
assign line_start = de&&!previous_de;
assign px = line_start?10'd0:x+10'd1;
assign py = line_start?(arm?10'd0:y+10'd1):y;
assign timer_hit = de&&px>=408&&px<616&&
  (THEMED_ENABLE!=0?(!hide_timer&&py>=6&&py<22):(py>=8&&py<24));
assign skip_hit = de&&frame_status[24]&&px>=504&&px<616&&py>=60&&py<76;
assign relative_x = px-(skip_hit?10'd504:10'd408);
assign glyph_cell = relative_x[9:4];
assign gx = relative_x[3:0];
assign gy = py-(skip_hit?10'd60:THEMED_ENABLE!=0?10'd6:10'd8);

 
 
 
 
 
 
 
 
 
 
 
 recovery_songti_font #(.FONT_SET(2)) u_songti(.clk(clk),.codepoint(character),.row(gy),.bits(glyph_row));
 
 always @*begin
  character=16'h0020;
  if(skip_hit)begin
   case(glyph_cell)
    0:character=16'h8df3;1:character=16'h8fc7; // 跳过等待已开启
    2:character=16'h7b49;3:character=16'h5f85;4:character=16'h5df2;
    5:character=16'h5f00;6:character=16'h542f;
   endcase
  end else begin
   case(glyph_cell)
    0:character=16'h5f00;1:character=16'h673a; // 开机计时
    2:character=16'h8ba1;3:character=16'h65f6;
    5:character=16'd48+{12'd0,frame_status[23:20]};
    6:character=16'd48+{12'd0,frame_status[19:16]};7:character=16'h003a;
    8:character=16'd48+{12'd0,frame_status[15:12]};
    9:character=16'd48+{12'd0,frame_status[11:8]};10:character=16'h003a;
    11:character=16'd48+{12'd0,frame_status[7:4]};
    12:character=16'd48+{12'd0,frame_status[3:0]};
   endcase
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin previous_de<=0;previous_vs<=0;arm<=1;x<=0;y<=0;frame_status<=0;panel_pipe<=0;highlight_pipe<=0;gx_pipe<=0;rgb_pipe<=0;end
  else begin
   previous_de<=de;previous_vs<=vs;
   if(previous_vs&&!vs)arm<=1;
   if(previous_vs!=vs&&!de)frame_status<=status;
   if(de)begin x<=px;y<=py;if(line_start)arm<=0;end
   panel_pipe<=timer_hit||skip_hit;highlight_pipe<=skip_hit;gx_pipe<=gx;rgb_pipe<=rgb;
  end
 end
 always @*begin
  out_rgb=rgb_pipe;
  if(panel_pipe&&glyph_row[15-gx_pipe])out_rgb=highlight_pipe?(THEMED_ENABLE!=0?24'hb87500:24'hffff00):
   THEMED_ENABLE!=0?24'h0757bc:24'hffffff;
 end
endmodule

`default_nettype wire
