`default_nettype none
`timescale 1ns/1ps
// fixed gray-button feedback and 32-segment rounded
// progress, shared by the 33 formal pages. Geometry lives in one 826-byte ROM
// (recovery_button_rom). Left/right share one row cache; the next active line
// is prefetched in 34 clocks during horizontal blanking.
// Active-line work uses short
// compares of local x against cached interval ends (+/-220 translation).
// The first line of a frame is prefetched while vs is low (vertical blank).
module recovery_button_osd(
 input wire clk,rst,
 input wire de,vs,input wire [9:0] px,py,                   // coordinates of the pixel at de
 input wire enable,                                    // formal page with fixed buttons
 input wire [5:0] segments,input wire full,track_visible,green_l,green_r,progress_right,input wire paint_idle,
 input wire red_l,red_r,
 output reg hit,output reg [23:0] color           // one clock after (px,py)
);

localparam [9:0] CY=10'd352,CXL=10'd210,CXR=10'd430;
reg prev_de,prev_vs;
reg [9:0] fy;
reg [9:0] rom_addr;
wire [7:0] rom_q;
reg busy;
reg [5:0] st;
reg [7:0] base,endb;
reg [3:0] n;
reg [7:0] b0,b1;
reg [1:0] bi;
reg [7:0] kaddr;
reg [6:0] ax0[0:7],ax1[0:7];
reg [4:0] asg[0:7];
reg [3:0] acnt;
reg [6:0] af0,af1;
wire track_row;
wire [6:0] tly;
wire face_row;
wire [5:0] fly;
integer i;
wire left_side;
wire [9:0] cx;
wire [9:0] lx;
wire in_x;
reg on_track;
reg [4:0] seg;
integer j;
wire on_face;
wire key_green;
wire key_red;
wire track_owner;
// Continuous values retain the original net initializer expressions.
assign track_row = fy+10'd40>=CY&&fy<=CY+10'd40;
assign tly = fy+10'd40-CY;
assign face_row = fy+10'd22>=CY&&fy<CY+10'd22;
assign fly = fy+10'd22-CY;
assign left_side = px<10'd320;
assign cx = left_side?CXL:CXR;
assign lx = px+10'd43-cx;
assign in_x = px+10'd43>=cx&&px<cx+10'd43;
assign on_face = lx[6:0]>=af0&&lx[6:0]<af1&&af1!=0;
assign key_green = left_side?green_l:green_r;
assign key_red = (left_side?red_l:red_r)===1'b1;
assign track_owner = left_side==!progress_right;

 
                 // row being fetched
 
 recovery_button_rom u_rom(.clk(clk),.address(rom_addr),.q(rom_q));
 // fetch sequencer
 
 
 
                     // 0..80
 
                     // 0..43
 
 always @(posedge clk or posedge rst)begin
  if(rst)begin prev_de<=0;prev_vs<=0;fy<=0;rom_addr<=0;busy<=0;st<=0;base<=0;endb<=0;n<=0;b0<=0;b1<=0;bi<=0;kaddr<=0;
acnt<=0;af0<=0;af1<=0;
   for(i=0;i<8;i=i+1)begin ax0[i]<=0;ax1[i]<=0;asg[i]<=0;end
  end else begin
   prev_de<=de;prev_vs<=vs;
   if(prev_vs&&!vs)begin fy<=0;busy<=1;st<=0;end          // frame start: fetch line 0
   else if(!de&&prev_de)begin fy<=py+10'd1;busy<=1;st<=0;end // line end: fetch next line
   else if(busy)begin
    st<=st+1'b1;
    case(st)
     0:begin acnt<=0;af0<=0;af1<=0;rom_addr<={3'd0,tly};end
     1:rom_addr<={3'd0,tly}+10'd1;
     2:base<=track_row?rom_q:8'd0;                                // row base (q of tly)
     3:begin endb<=!track_row?8'd0:(tly==80)?8'd219:rom_q;
        kaddr<=0;bi<=0;rom_addr<=10'd81+{base,1'b0}+{2'd0,base};end
     default:begin
      // st>=4: stream 3 bytes per interval; q arrives one clock after address
      if(st>=5&&base+n<endb)begin
       case(bi)
        0:b0<=rom_q;1:b1<=rom_q;
        default:begin ax0[n[2:0]]<=b0[6:0];ax1[n[2:0]]<={b1[5:0],b0[7]};asg[n[2:0]]<={rom_q[2:0],b1[7:6]};
                n<=n+1'b1;acnt<=n+1'b1;end
       endcase
       bi<=(bi==2)?2'd0:bi+1'b1;
      end
      if(st==4)n<=0;
      rom_addr<=rom_addr+1'b1;
      if(st==29)rom_addr<=10'd738+{3'd0,fly,1'b0};
      if(st==30)rom_addr<=10'd739+{3'd0,fly,1'b0};
      if(st==31)af0<=face_row?rom_q:7'd0;
      if(st==32)begin af1<=face_row?rom_q:7'd0;busy<=0;end
     end
    endcase
   end
  end
 end
 // ---- active pixel: local x for both buttons, one-clock registered result ----
 
 
                        // 0..85 inside reserve
 
 
 always @*begin
  on_track=0;seg=0;
  for(j=0;j<8;j=j+1)if(j<acnt&&lx[6:0]>=ax0[j]&&lx[6:0]<ax1[j])begin on_track=1;seg=asg[j];end
 end
 
 
 
 
 always @(posedge clk or posedge rst)begin
  if(rst)begin hit<=0;color<=0;end
  else begin
   hit<=0;color<=0;
   if(de&&enable&&in_x)begin
    if(on_track&&track_visible&&track_owner)begin
     hit<=1;color<={1'b0,seg}<segments?(full?24'h25b56b:24'he95055):24'hd7e7ee;
    end else if(on_face&&(key_red||key_green||paint_idle))begin hit<=1;color<=key_red?24'hd94343:key_green?24'h25b56b:24'h99a3b3;end
   end
  end
 end
endmodule

`default_nettype wire
