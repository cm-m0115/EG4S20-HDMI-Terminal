`default_nettype none
`timescale 1ns/1ps
// The BMP owns fixed Chinese labels and layout. Reports
// replace glyph pixels only; no opaque report panel or duplicated labels.
// Reference: lesson 9 OSD glyph hit/transparent bypass and frame commit ideas.
// Its unacknowledged subtitle CDC is not copied; the existing held mailbox is used.
module recovery_result_osd #(parameter integer INPUT_FRAME_COMMITTED=0,parameter integer SHARED_ROM=0,
 parameter integer LEGACY_HINTS_ENABLE=1,
 parameter integer THEMED_COUNTDOWN_ENABLE=0,
 parameter integer CANVAS_GUARD_ENABLE=0)(input wire clk,rst,input wire vs,de,input wire [23:0] rgb,
 input wire [159:0] status,input wire [255:0] report_text,input wire waiting_report,
 input wire canvas_valid,canvas_prepare,input wire [5:0] canvas_scene,input wire [7:0] canvas_epoch,
 input wire report_input_valid,input wire [5:0] report_input_scene,input wire [7:0] report_input_epoch,
 input wire emergency_clear,
 output reg [23:0] out_rgb,output wire [10:0] shared_message_address,input wire [6:0] shared_message_q,input wire [7:0] display_epoch);

wire guarded;
wire canvas_report;
wire [5:0] normalized_canvas;
wire [5:0] normalized_input;
reg cache_valid;
reg [63:0] cache_draw;
reg [7:0] cache_small;
wire new_report;
wire keep_report;
wire [255:0] draw_text;
wire [2:0] draw_limb_count;
wire [1:0] draw_pa;
wire [2:0] draw_total;
wire [1:0] draw_t1;
wire [1:0] draw_t2;
wire [2:0] draw_pain;
wire [159:0] frame_status;
wire [7:0] state;
wire [1:0] mode,pp,pa,pv,t1,t2,t3;
wire [15:0] rt,hold;
wire [2:0] rs,hs,pain;
wire [5:0] valid,source_scene;
wire [7:0] err;
wire armed,release_prompt,nurse,countdown_active,retest_due;
wire [12:0] unused;
wire [15:0] countdown_seconds;
wire [2:0] limb_count;
wire [3:0] limb_answers,limb_valid;
wire [5:0] scene;
wire snapshot_valid;
wire [1:0] snapshot_mode;
wire [7:0] snapshot_epoch;
wire [5:0] started;
wire [2:0] outcome;
wire [3:0] report_fault,report_sequence;
wire [1:0] t1_unanswered,t2_unanswered;
wire report_scene;
wire report_ready;
wire full_fault;
reg prev_de,prev_vs,arm;
reg [10:0] x,y;
wire line_start;
wire [10:0] px;
wire [10:0] py;
wire report_error_banner;
wire frame_mark;
wire loading;
wire [15:0] loading_bits;
reg [15:0] loading_bits_pipe;
reg loading_address,loading_pipe;
reg [3:0] loading_col_address,loading_col_pipe;
wire [10:0] loading_x,loading_y;
reg [5:0] col;
reg [3:0] x_cell;
reg [3:0] slot;
reg slot_hit;
reg [10:0] slot_y;
wire themed_countdown;
wire [10:0] cell_start;
wire [10:0] cell_end;
wire [3:0] gx;
wire [3:0] gy;
wire [2:0] total;
reg [4:0] decimal_cycle;
reg [2:0] decimal_field;
reg [15:0] decimal_shift;
reg [19:0] decimal_work;
reg [19:0] rt_bcd,hold_bcd,err_bcd,countdown_bcd;
reg [11:0] score_bcd;
wire [19:0] decimal_next;
reg [6:0] text_id;
reg [15:0] ch;
integer fault_row;
reg [15:0] ch_pipe;
reg [3:0] gx_pipe,gy_pipe;
reg inside_pipe,panel_pipe;
reg [23:0] rgb_pipe;
wire [15:0] glyph_row;
wire [6:0] message_q;
reg [15:0] direct_ch_address;
reg use_message_address;
wire [15:0] ch_address;
reg [3:0] gx_address,gy_address;
reg inside_address,panel_address;
reg [23:0] rgb_address;
// Continuous values retain the original net initializer expressions.
assign guarded = CANVAS_GUARD_ENABLE!=0;
assign canvas_report = canvas_scene==8||canvas_scene==22||canvas_scene==29||canvas_scene==30;
assign normalized_canvas = (canvas_scene==8||canvas_scene==29)?6'd8:6'd22;
assign normalized_input = (report_input_scene==8||report_input_scene==29)?6'd8:6'd22;
assign new_report = guarded&&canvas_prepare&&canvas_valid&&canvas_report&&report_input_valid&&report_text[86]&&
   report_input_scene==canvas_scene&&report_input_epoch==canvas_epoch&&emergency_clear!==1'b1;
assign keep_report = guarded&&cache_valid&&canvas_valid&&canvas_report&&emergency_clear!==1'b1;
assign draw_text = guarded?{169'd0,1'b1,cache_draw[63:56],cache_draw[55],1'b0,
   cache_draw[54:49],cache_draw[48:42],7'd0,cache_draw[41:0],14'd0}:report_text;
assign draw_limb_count = guarded?cache_small[7:5]:limb_count;
assign draw_pa = guarded?cache_small[4:3]:pa;
assign draw_total = guarded?cache_small[2:0]:total;
assign draw_t1 = guarded?cache_small[7:6]:t1;
assign draw_t2 = guarded?cache_small[5:4]:t2;
assign draw_pain = guarded?cache_small[3:1]:pain;
assign scene = frame_status[13:8];
assign report_scene = scene==6'd8||scene==6'd22;
assign report_ready = guarded?keep_report:(snapshot_valid&&snapshot_epoch==display_epoch&&
  ((scene==6'd8&&snapshot_mode==2'd1)||(scene==6'd22&&snapshot_mode==2'd2)));
assign full_fault = !report_scene&&frame_status[7:0]!=0;
assign line_start = de&&!prev_de;
assign px = line_start?11'd0:x+11'd1;
assign py = line_start?(arm?11'd0:y+11'd1):y;
assign report_error_banner = report_scene&&frame_status[7:0]!=0&&py>=430&&py<450;
assign frame_mark = prev_vs!=vs&&!de;
assign loading = waiting_report===1'b1&&!keep_report;
assign loading_x = px-11'd272;
assign loading_y = py-11'd210;
assign themed_countdown = THEMED_COUNTDOWN_ENABLE!=0&&!report_scene&&!full_fault&&
  countdown_active&&((scene>=6'd23&&scene<=6'd26)||scene==6'd49);
assign cell_start = themed_countdown?11'd180:
  (report_scene&&!report_error_banner)?11'd304:11'd16;
assign cell_end = themed_countdown?11'd244:
  (report_scene&&!report_error_banner)?11'd608:11'd616;
assign gx = x_cell;
assign gy = py-slot_y-11'd2;
assign total = {1'b0,pp}+{1'b0,pa};
assign decimal_next = bcd_step(decimal_work,decimal_shift[15]);
assign ch_address = use_message_address?{9'd0,message_q}:direct_ch_address;

 
 
 
 
 // Only the compact draw description is retained. Existing BCD registers
 // remain the single decimal copy and freeze while the old canvas survives.
 
 
 // The physical canvas itself is the retained identity. Every new physical
 // prepare withdraws the old cache, so no duplicate scene/epoch bank is needed.
 
 
 // Small numbers share eight bits by report mode. RT/hold/score retain the
 // existing BCD registers; no second report/status or BCD bank is introduced.
 
 
 
 
 
 
 always @(posedge clk or posedge rst)begin
  if(rst)begin cache_valid<=0;cache_draw<=0;cache_small<=0;end
  else if(guarded)begin
   if(!canvas_valid||!canvas_report||emergency_clear===1'b1||canvas_prepare)cache_valid<=0;
   if(new_report)begin
    cache_valid<=1;cache_draw<={report_text[85:78],report_text[77],report_text[75:70],report_text[69:63],report_text[55:14]};
    cache_small<=normalized_canvas==8?{limb_count,pa,total}:{t1,t2,pain,1'b0};
   end
  end
 end
 
 
 
 
 
 assign {unused,countdown_active,retest_due,countdown_seconds,limb_count,limb_answers,limb_valid,state,mode,armed,release_prompt,nurse,pv,pp,pa,t1,t2,t3,rt,rs,hold,hs,pain,valid,source_scene,err}=frame_status[127:0];
 
 
 
 
 assign {snapshot_valid,snapshot_mode,snapshot_epoch,started,outcome,report_fault,t1_unanswered,t2_unanswered,report_sequence}=frame_status[159:128];
 
 
 
 
 
 
 
 
 
 
 
 
 
 recovery_panel_font u_loading_font(.clk(clk),.message(3'd5),.character(loading_x[7:4]),.row(loading_y[3:0]),.bits(loading_bits));
 always @(posedge clk or posedge rst)begin
  if(rst)begin loading_bits_pipe<=0;loading_address<=0;loading_pipe<=0;loading_col_address<=0;loading_col_pipe<=0;end
  else begin
   loading_bits_pipe<=loading_bits;loading_address<=loading&&de&&px>=272&&px<320&&py>=210&&py<226;
   loading_pipe<=loading_address;loading_col_address<=px-11'd272;loading_col_pipe<=loading_col_address;
  end
 end
 generate if(INPUT_FRAME_COMMITTED!=0)begin:g_committed_status
  reg [5:0] source_scene_hold;
  always @(posedge clk or posedge rst)
   if(rst)source_scene_hold<=0;else if(frame_mark)source_scene_hold<=status[13:8];
  assign frame_status={status[159:14],(guarded&&emergency_clear===1'b1) ? 6'd7 : guarded&&canvas_valid ?
    (canvas_report?normalized_canvas:canvas_scene):source_scene_hold,status[7:0]};
 end else begin:g_local_status
  reg [159:0] held_status;
  always @(posedge clk or posedge rst)
   if(rst)held_status<=0;else if(frame_mark)held_status<=status;
  assign frame_status=held_status;
 end endgenerate

 
 
 
 
 
 
 
 
 function [15:0] digit;input [3:0] n;begin digit=16'd5+{12'd0,n};end endfunction
 // One binary snapshot is captured in vertical blank and all decimal fields
 // are prepared from that same snapshot. No converter runs during report rows.
 function [19:0] bcd_step;input [19:0] value;input next_bit;
  reg [19:0] adjusted;integer k;begin
   adjusted=value;
   for(k=0;k<5;k=k+1)if(value[k*4+:4]>=5)adjusted[k*4+:4]=value[k*4+:4]+4'd3;
   bcd_step={adjusted[18:0],next_bit};
  end
 endfunction
 // one shared 16-bit shift / 20-bit double-dabble engine.
 // INPUT_FRAME_COMMITTED guarantees all five source fields stay constant
 // throughout the frame. All results finish within 80 clocks of frame_mark.
 
 
 
 
 always @(posedge clk or posedge rst)begin
  if(rst)begin decimal_cycle<=0;decimal_field<=0;decimal_shift<=0;decimal_work<=0;
   rt_bcd<=0;hold_bcd<=0;err_bcd<=0;countdown_bcd<=0;score_bcd<=0;
  end else if(new_report||frame_mark&&!(guarded&&canvas_valid&&canvas_report&&emergency_clear!==1'b1))begin
   decimal_field<=0;decimal_cycle<=1;decimal_shift<=status[60:45];decimal_work<=0;
  end else if(decimal_cycle!=0)begin
   decimal_work<=decimal_next;decimal_shift<={decimal_shift[14:0],1'b0};
   if(decimal_cycle==16)begin
    case(decimal_field)
     0:begin rt_bcd<=decimal_next;decimal_shift<=frame_status[41:26];end
     1:begin hold_bcd<=decimal_next;decimal_shift<={8'd0,frame_status[7:0]};end
     2:begin err_bcd<=decimal_next;decimal_shift<=frame_status[112:97];end
     3:begin countdown_bcd<=decimal_next;decimal_shift<={9'd0,frame_status[121:115]};end
     4:score_bcd<=decimal_next[11:0];
    endcase
    decimal_field<=decimal_field+1'b1;decimal_work<=0;
    decimal_cycle<=decimal_field==4?5'd0:5'd1;
   end else decimal_cycle<=decimal_cycle+1'b1;
  end
 end
 
 always @*begin
  slot=0;slot_y=0;slot_hit=0;
  if(report_error_banner)begin slot=6;slot_y=430;slot_hit=1;end
  else if(report_scene)begin
   if(scene==8)begin
    if(py>=120&&py<140)begin slot=0;slot_y=120;slot_hit=1;end
    else if(py>=164&&py<184)begin slot=1;slot_y=164;slot_hit=1;end
    else if(py>=208&&py<228)begin slot=2;slot_y=208;slot_hit=1;end
    else if(py>=252&&py<272)begin slot=3;slot_y=252;slot_hit=1;end
    else if(py>=296&&py<316)begin slot=4;slot_y=296;slot_hit=1;end
   end else begin
    if(py>=112&&py<132)begin slot=0;slot_y=112;slot_hit=1;end
    else if(py>=154&&py<174)begin slot=1;slot_y=154;slot_hit=1;end
    else if(py>=196&&py<216)begin slot=2;slot_y=196;slot_hit=1;end
    else if(py>=238&&py<258)begin slot=3;slot_y=238;slot_hit=1;end
    else if(py>=280&&py<300)begin slot=4;slot_y=280;slot_hit=1;end
    else if(py>=322&&py<342)begin slot=5;slot_y=322;slot_hit=1;end
    else if(py>=364&&py<384)begin slot=7;slot_y=364;slot_hit=1;end
   end
  end else if(full_fault)begin
   for(fault_row=0;fault_row<9;fault_row=fault_row+1)
    if(py>=16+fault_row*20&&py<36+fault_row*20)begin slot=fault_row;slot_y=16+fault_row*20;slot_hit=1;end
  end else if(themed_countdown&&py>=79&&py<99)begin slot=0;slot_y=79;slot_hit=1;end
  else if(LEGACY_HINTS_ENABLE!=0&&py>=430&&py<450)begin slot=0;slot_y=430;slot_hit=1;end
 end
 always @*begin
  text_id=7'd0;
  if(report_error_banner)text_id=7'd5;
  else if(report_scene)begin
   // M3 is prepared on B from this same raw report. A retains only safe
   // loading/error overrides, digit formatting, font lookup and pixels.
   if(report_ready&&draw_text[86])case(slot)
    0:text_id=draw_text[20:14];1:text_id=draw_text[27:21];2:text_id=draw_text[34:28];3:text_id=draw_text[41:35];
    4:text_id=draw_text[48:42];5:text_id=draw_text[55:49];6:text_id=draw_text[62:56];7:text_id=draw_text[69:63];
    default:text_id=0;
   endcase else text_id=7'd1;
  end else if(full_fault)begin
   if(slot==0)text_id=7'd40;
   else if(slot==6)text_id=7'd5;
  end else if(LEGACY_HINTS_ENABLE!=0)begin
   if(release_prompt)text_id=7'd41;
   else if(retest_due&&scene==27&&state==55)text_id=7'd41;
   else if(armed)text_id=7'd42;
   else if(countdown_active&&scene>=23&&scene<=26)text_id=7'd43;
   else if(state==2)text_id=7'd44;
   else text_id=7'd45;
  end
  ch=(col<16)?{1'b1,8'd0,text_id}:16'd0;
  if(themed_countdown)case(col)
   0:ch=digit(countdown_seconds>999?4'd9:countdown_bcd[11:8]);
   1:ch=digit(countdown_seconds>999?4'd9:countdown_bcd[7:4]);
   2:ch=digit(countdown_seconds>999?4'd9:countdown_bcd[3:0]);
   3:ch=16'd59;
   default:ch=16'd0;
  endcase
  if(report_scene&&report_ready)begin
   if(scene==8)case(slot)
    1:case(col)
     0:ch=draw_text[79:78]==1?16'd27:draw_text[79:78]==2?16'd28:16'd3;
     2:ch=draw_text[81:80]==1?16'd27:draw_text[81:80]==2?16'd28:16'd3;
     4:ch=draw_text[83:82]==1?16'd27:draw_text[83:82]==2?16'd28:16'd3;
     6:ch=draw_text[85:84]==1?16'd27:draw_text[85:84]==2?16'd28:16'd3;
    endcase
    2:if(draw_text[72]&&col==0)ch=digit({1'b0,draw_limb_count});
    3:if(draw_text[73]&&col==0)ch=digit({2'd0,draw_pa});
    4:if(draw_text[74]&&col==0)ch=digit({1'b0,draw_total});
   endcase
   else case(slot)
    0:if(draw_text[70]&&col==0)ch=digit({2'd0,draw_t1});
    1:if(draw_text[71]&&col==0)ch=digit({2'd0,draw_t2});
    3:if(draw_text[73]&&col<5)case(col)
     0:ch=digit(rt_bcd[19:16]);1:ch=digit(rt_bcd[15:12]);2:ch=digit(rt_bcd[11:8]);3:ch=digit(rt_bcd[7:4]);4:ch=digit(rt_bcd[3:0]);endcase
    4:if(draw_text[74]&&col<5)case(col)
     0:ch=digit(hold_bcd[19:16]);1:ch=digit(hold_bcd[15:12]);2:ch=digit(hold_bcd[11:8]);3:ch=digit(hold_bcd[7:4]);4:ch=digit(hold_bcd[3:0]);endcase
    7:if(draw_text[77])case(col)0:ch=digit(score_bcd[11:8]);1:ch=digit(score_bcd[7:4]);2:ch=digit(score_bcd[3:0]);endcase
    5:if(draw_text[75]&&col==0)ch=digit({1'b0,draw_pain});
   endcase
  end
  if((full_fault||report_error_banner)&&slot==6)case(col)5:ch=digit(err_bcd[11:8]);6:ch=digit(err_bcd[7:4]);7:ch=digit(err_bcd[3:0]);endcase
  if(!report_scene&&!full_fault&&!armed&&!release_prompt&&countdown_active&&scene>=23&&scene<=26)
   case(col)6:ch=digit(countdown_bcd[19:16]);7:ch=digit(countdown_bcd[15:12]);8:ch=digit(countdown_bcd[11:8]);9:ch=digit(countdown_bcd[7:4]);10:ch=digit(countdown_bcd[3:0]);endcase
 end
 
 
  // character address register splits status-to-font address timing.
  // Total RGB latency is two pixel clocks (originally one).
  // Static UTF-16 text expands in the existing character-address stage.
  
  
  
  
  assign shared_message_address={text_id,col[3:0]};
  generate if(SHARED_ROM!=0)begin:shared_message
   assign message_q=shared_message_q;
  end else begin:original_message
   recovery_result_message_rom u_message(.clk(clk),.address({text_id,col[3:0]}),.q(message_q));
  end endgenerate
  
  
  always @(posedge clk or posedge rst)begin
   if(rst)begin direct_ch_address<=32;use_message_address<=0;gx_address<=0;gy_address<=0;
    inside_address<=0;panel_address<=0;rgb_address<=0;end
   else begin
    direct_ch_address<=ch[15]?16'd0:ch;use_message_address<=ch[15]&&col<16;gx_address<=gx;gy_address<=gy;
    inside_address<=!loading&&de&&px>=cell_start&&px<cell_end&&slot_hit&&py>=slot_y+2&&py<slot_y+18;
    panel_address<=!report_scene||report_error_banner;rgb_address<=rgb;
   end
  end
  recovery_songti_font #(.FONT_SET(3),.DIRECT_GLYPH(1)) u_songti(.clk(clk),.codepoint(ch_address),.row(gy_address),.bits(glyph_row));
 always @(posedge clk or posedge rst)begin
  if(rst)begin ch_pipe<=32;gx_pipe<=0;gy_pipe<=0;inside_pipe<=0;panel_pipe<=0;rgb_pipe<=0;end
  else begin
   ch_pipe<=ch_address;gx_pipe<=gx_address;gy_pipe<=gy_address;
   inside_pipe<=inside_address;
   panel_pipe<=panel_address;rgb_pipe<=rgb_address;
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin prev_de<=0;prev_vs<=0;arm<=1;x<=0;y<=0;col<=0;x_cell<=0;end
  else begin
   prev_de<=de;prev_vs<=vs;if(prev_vs!=vs)arm<=1;
   if(!de||px<cell_start||px>=cell_end)begin col<=0;x_cell<=0;end
   else if(x_cell==15)begin x_cell<=0;col<=col+1'b1;end
   else x_cell<=x_cell+1'b1;
   if(de)begin x<=px;if(line_start)begin y<=py;arm<=0;end end
  end
 end
 always @*begin
  out_rgb=rgb_pipe;
  if(loading_pipe&&loading_bits_pipe[15-loading_col_pipe])out_rgb=24'h17334f;
  if(inside_pipe&&glyph_row[15-gx_pipe])out_rgb=panel_pipe?24'hffffff:24'h17334f;
 end
endmodule

// Exact former 16-character constants; no new display pipeline clock.
module recovery_result_message_rom(input wire clk,input wire [10:0] address,output reg [6:0] q);

(* ram_style="bram_32k" *) reg [6:0] mem [0:2047];
integer i;
// Continuous values retain the original net initializer expressions.


 
 initial begin
  for(i=0;i<2048;i=i+1)mem[i]=7'd0;
  mem[16]=7'd50;
  mem[17]=7'd64;
  mem[18]=7'd18;
  mem[32]=7'd47;
  mem[33]=7'd35;
  mem[34]=7'd60;
  mem[48]=7'd44;
  mem[49]=7'd72;
  mem[64]=7'd17;
  mem[65]=7'd46;
  mem[80]=7'd33;
  mem[81]=7'd19;
  mem[82]=7'd70;
  mem[83]=7'd65;
  mem[85]=7'd5;
  mem[86]=7'd5;
  mem[87]=7'd5;
  mem[96]=7'd73;
  mem[97]=7'd53;
  mem[99]=7'd7;
  mem[101]=7'd24;
  mem[112]=7'd22;
  mem[113]=7'd53;
  mem[115]=7'd6;
  mem[117]=7'd24;
  mem[128]=7'd47;
  mem[129]=7'd35;
  mem[130]=7'd60;
  mem[132]=7'd5;
  mem[134]=7'd24;
  mem[144]=7'd3;
  mem[146]=7'd3;
  mem[148]=7'd3;
  mem[150]=7'd3;
  mem[152]=7'd49;
  mem[153]=7'd45;
  mem[160]=7'd3;
  mem[162]=7'd3;
  mem[164]=7'd3;
  mem[166]=7'd3;
  mem[168]=7'd47;
  mem[169]=7'd35;
  mem[170]=7'd60;
  mem[176]=7'd3;
  mem[178]=7'd3;
  mem[180]=7'd3;
  mem[182]=7'd3;
  mem[184]=7'd44;
  mem[185]=7'd72;
  mem[192]=7'd3;
  mem[194]=7'd3;
  mem[196]=7'd3;
  mem[198]=7'd3;
  mem[200]=7'd17;
  mem[201]=7'd46;
  mem[208]=7'd3;
  mem[210]=7'd3;
  mem[212]=7'd3;
  mem[214]=7'd3;
  mem[216]=7'd50;
  mem[217]=7'd64;
  mem[218]=7'd18;
  mem[224]=7'd5;
  mem[225]=7'd4;
  mem[226]=7'd9;
  mem[228]=7'd62;
  mem[230]=7'd49;
  mem[231]=7'd45;
  mem[240]=7'd5;
  mem[242]=7'd24;
  mem[244]=7'd49;
  mem[245]=7'd45;
  mem[256]=7'd5;
  mem[257]=7'd4;
  mem[258]=7'd9;
  mem[260]=7'd24;
  mem[262]=7'd49;
  mem[263]=7'd45;
  mem[272]=7'd3;
  mem[273]=7'd4;
  mem[274]=7'd7;
  mem[276]=7'd49;
  mem[277]=7'd45;
  mem[288]=7'd3;
  mem[289]=7'd4;
  mem[290]=7'd7;
  mem[292]=7'd47;
  mem[293]=7'd35;
  mem[294]=7'd60;
  mem[304]=7'd3;
  mem[305]=7'd4;
  mem[306]=7'd7;
  mem[308]=7'd44;
  mem[309]=7'd72;
  mem[320]=7'd3;
  mem[321]=7'd4;
  mem[322]=7'd7;
  mem[324]=7'd17;
  mem[325]=7'd46;
  mem[336]=7'd3;
  mem[337]=7'd4;
  mem[338]=7'd7;
  mem[340]=7'd50;
  mem[341]=7'd64;
  mem[342]=7'd18;
  mem[352]=7'd73;
  mem[353]=7'd53;
  mem[354]=7'd35;
  mem[355]=7'd60;
  mem[368]=7'd22;
  mem[369]=7'd53;
  mem[370]=7'd35;
  mem[371]=7'd60;
  mem[384]=7'd47;
  mem[385]=7'd45;
  mem[400]=7'd3;
  mem[401]=7'd3;
  mem[402]=7'd3;
  mem[403]=7'd3;
  mem[404]=7'd3;
  mem[406]=7'd54;
  mem[407]=7'd59;
  mem[409]=7'd49;
  mem[410]=7'd45;
  mem[416]=7'd3;
  mem[417]=7'd3;
  mem[418]=7'd3;
  mem[419]=7'd3;
  mem[420]=7'd3;
  mem[422]=7'd54;
  mem[423]=7'd59;
  mem[425]=7'd47;
  mem[426]=7'd45;
  mem[432]=7'd3;
  mem[433]=7'd3;
  mem[434]=7'd3;
  mem[435]=7'd3;
  mem[436]=7'd3;
  mem[438]=7'd54;
  mem[439]=7'd59;
  mem[441]=7'd47;
  mem[442]=7'd35;
  mem[443]=7'd60;
  mem[448]=7'd3;
  mem[449]=7'd3;
  mem[450]=7'd3;
  mem[451]=7'd3;
  mem[452]=7'd3;
  mem[454]=7'd54;
  mem[455]=7'd59;
  mem[457]=7'd43;
  mem[458]=7'd25;
  mem[459]=7'd42;
  mem[460]=7'd71;
  mem[464]=7'd3;
  mem[465]=7'd3;
  mem[466]=7'd3;
  mem[467]=7'd3;
  mem[468]=7'd3;
  mem[470]=7'd54;
  mem[471]=7'd59;
  mem[473]=7'd44;
  mem[474]=7'd72;
  mem[480]=7'd3;
  mem[481]=7'd3;
  mem[482]=7'd3;
  mem[483]=7'd3;
  mem[484]=7'd3;
  mem[486]=7'd54;
  mem[487]=7'd59;
  mem[489]=7'd17;
  mem[490]=7'd46;
  mem[496]=7'd3;
  mem[497]=7'd3;
  mem[498]=7'd3;
  mem[499]=7'd3;
  mem[500]=7'd3;
  mem[502]=7'd54;
  mem[503]=7'd59;
  mem[505]=7'd50;
  mem[506]=7'd64;
  mem[507]=7'd18;
  mem[512]=7'd3;
  mem[513]=7'd3;
  mem[514]=7'd3;
  mem[515]=7'd3;
  mem[516]=7'd3;
  mem[518]=7'd54;
  mem[519]=7'd59;
  mem[521]=7'd20;
  mem[522]=7'd41;
  mem[523]=7'd16;
  mem[524]=7'd67;
  mem[528]=7'd3;
  mem[529]=7'd3;
  mem[530]=7'd3;
  mem[531]=7'd3;
  mem[532]=7'd3;
  mem[534]=7'd54;
  mem[535]=7'd59;
  mem[537]=7'd50;
  mem[538]=7'd34;
  mem[539]=7'd39;
  mem[544]=7'd5;
  mem[545]=7'd5;
  mem[546]=7'd5;
  mem[547]=7'd4;
  mem[548]=7'd6;
  mem[549]=7'd5;
  mem[550]=7'd5;
  mem[552]=7'd24;
  mem[560]=7'd50;
  mem[561]=7'd61;
  mem[562]=7'd63;
  mem[576]=7'd6;
  mem[578]=7'd47;
  mem[579]=7'd56;
  mem[581]=7'd49;
  mem[582]=7'd45;
  mem[592]=7'd7;
  mem[594]=7'd68;
  mem[595]=7'd36;
  mem[597]=7'd49;
  mem[598]=7'd45;
  mem[608]=7'd8;
  mem[610]=7'd17;
  mem[611]=7'd36;
  mem[613]=7'd49;
  mem[614]=7'd45;
  mem[624]=7'd9;
  mem[626]=7'd69;
  mem[627]=7'd36;
  mem[629]=7'd49;
  mem[630]=7'd45;
  mem[640]=7'd33;
  mem[641]=7'd19;
  mem[642]=7'd44;
  mem[643]=7'd72;
  mem[645]=7'd66;
  mem[646]=7'd26;
  mem[647]=7'd40;
  mem[648]=7'd52;
  mem[649]=7'd57;
  mem[656]=7'd66;
  mem[657]=7'd51;
  mem[658]=7'd37;
  mem[659]=7'd42;
  mem[660]=7'd71;
  mem[672]=7'd66;
  mem[673]=7'd42;
  mem[674]=7'd43;
  mem[675]=7'd58;
  mem[676]=7'd35;
  mem[677]=7'd60;
  mem[688]=7'd31;
  mem[689]=7'd55;
  mem[690]=7'd21;
  mem[691]=7'd63;
  mem[692]=7'd48;
  mem[694]=7'd5;
  mem[695]=7'd5;
  mem[696]=7'd5;
  mem[697]=7'd5;
  mem[698]=7'd5;
  mem[700]=7'd59;
  mem[704]=7'd66;
  mem[705]=7'd29;
  mem[706]=7'd43;
  mem[707]=7'd58;
  mem[720]=7'd23;
  mem[721]=7'd30;
  mem[722]=7'd34;
  mem[723]=7'd39;
 end
 always @(posedge clk)q<=mem[address];
endmodule

`default_nettype wire
