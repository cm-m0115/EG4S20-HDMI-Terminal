`default_nettype none
`timescale 1ns/1ps
// themed UI. Existing fixed 3-clock RGB/DE/VS contract is preserved.
// B owns all qualification, timing and acceptance. This layer only observes.
module recovery_caption_practice_osd #(parameter integer MOUNTAIN_LAYERED=0,parameter integer WAVE_FRACTION_ENABLE=0)(
 input wire clk,rst,vs,de,input wire [23:0] rgb,
 input wire display_enable,history_enable,input wire [5:0] caption_id,
 input wire caption_running,input wire [7:0] caption_generation,
 input wire [15:0] caption_ticks,input wire [23:0] practice,
 input wire [5:0] scene_id,input wire [1:0] question_set,
 input wire [159:0] status_data,input wire [23:0] feedback,
 input wire [255:0] ui_data,input wire ui_valid,
 output wire [8:0] wave_query_index,
 input wire signed [7:0] wave_min,wave_max,
 input wire [7:0] wave_average,wave_peak,
 output wire [23:0] out_rgb,output wire out_de,out_vs,output wire ui_marker,
 output wire feedback_marker,input wire view_prepare,
 input wire [3:0] wave_fraction,
 input wire [9:0] mountain_front_q4,mountain_back_q4,input wire mountain_valid
);

reg previous_de,previous_vs,arm;
reg [9:0] x,y;
wire frame_start,line_start;
wire [9:0] px;
wire [9:0] py;
reg [23:0] fp,ff;
reg [5:0] fs;
reg [1:0] fq;
reg fd,fh,fr;
reg [5:0] fc;
reg [7:0] fg;
reg [15:0] ft;
reg [7:0] last_accept;
reg [5:0] ack_frames;
reg hold_right;
reg [6:0] hint,old_hint;
reg [4:0] animation;
wire practice_on;
wire [2:0] practice_step,practice_phase;
wire education,relax;
wire report_scene;
wire active;
reg accept_seen,validity_lost,hold_view;
reg [73:0] fu;
wire normal_handoff_hold;
wire context_changed;
wire new_accept;
wire [6:0] requested_hint;
wire [7:0] selected_length_raw;
wire [7:0] requested_length;
wire urgent;
wire sensitive;
reg [7:0] hint_length,old_length;
wire [7:0] welcome_length;
wire [15:0] unused_rate0,unused_rate1,unused_rate2;
wire known0,known1,known2;
wire [7:0] chosen_length;
wire [9:0] panel_width;
wire [9:0] panel_left;
wire [11:0] welcome_span;
wire [11:0] welcome_max;
wire [11:0] welcome_scroll;
wire [6:0] edu_text;
wire [6:0] education_sentence;
wire [7:0] education_length_raw;
wire [15:0] education_rate;
wire education_known;
wire [5:0] education_length;
wire [9:0] education_text_left;
wire [9:0] education_box_left;
wire [9:0] education_box_width;
wire [7:0] rest_length_raw;
wire [15:0] rest_rate;
wire rest_known;
wire [5:0] rest_length;
wire [9:0] rest_text_left;
wire [9:0] rest_box_left;
wire [9:0] rest_box_width;
wire [5:0] vertical_shift;
wire practice_page_match;
wire practice_alarm_panel;
wire fixed_buttons;
wire button_hit;
wire [23:0] button_color;
wire legacy_buttons;
wire [24:0] button_meta;
wire [5:0] button_span;
reg [9:0] button_row0,button_cx1;
reg [1:0] button_index0,button_index1;
reg button_read0,button_read1,button_key1,button_row_ok1;
wire [9:0] button_cy;
wire [9:0] button_dy;
reg [9:0] button_left[0:3],button_right[0:3];
reg [3:0] button_valid,button_rightkey;
integer button_reset;
reg [6:0] text_id_comb;
reg [7:0] character_comb;
reg [3:0] glyph_row_comb,glyph_col_comb;
reg text_bounds_comb,theme_pixel_comb;
reg [23:0] base_comb,text_color_comb;
reg [11:0] text_offset;
reg [9:0] text_top;
integer b;
wire [9:0] wave_center;
wire music_page;
wire welcome_panel;
wire light_panel;
wire ordinary_panel;
wire panel_on;
wire [9:0] panel_l;
wire [9:0] panel_w;
wire [9:0] panel_t;
wire [9:0] panel_h;
wire wave_pixel;
wire [9:0] wave_offset;
wire teaching_panel;
wire cue_pixel;
wire [7:0] teaching_length;
wire [9:0] teaching_left;
reg [6:0] native_text;
reg [7:0] native_character;
reg [4:0] native_row,native_col;
reg native_bounds,native_white;
wire [1:0] native_coverage;
reg [2:0] native_scope,native_white_pipe,native_instruction;
wire teaching_alarm;
reg panel_text;
reg [2:0] panel_message;
reg [3:0] panel_character,panel_row,panel_col;
wire [15:0] panel_bits;
reg [15:0] panel_bits1,panel_bits2;
reg [2:0] panel_bounds,cue_pipe;
reg [3:0] panel_col0,panel_col1,panel_col2;
reg [23:0] raw0,raw1,raw2;
reg [6:0] text_id_0;
reg [7:0] character_0;
reg [3:0] row_0,row_1,col_0,col_1,col_2;
reg bounds_0,bounds_1,bounds_2;
reg [23:0] base_0,rgb_1,rgb_2,color_0,color_1,color_2;
reg theme_0;
(* ram_style="bram" *)reg [7:0] tint_channel_r[0:511],tint_channel_g[0:511],tint_channel_b[0:511];
reg [7:0] tint_r,tint_g,tint_b;
integer tint_index;
wire [23:0] rgb_0;
reg de_0,de_1,de_2,vs_0,vs_1,vs_2;
reg feedback_face1,feedback_face2;
reg wave_0;
reg [5:0] wave_dy0;
reg [2:0] wave_column0;
reg wave_lower0;
wire [8:0] glyph_id_1;
wire [15:0] glyph_bits_2;
wire [5:0] front_height;
wire [6:0] far_sum;
wire [5:0] far_height;
wire [1:0] edge_fraction;
wire front_edge;
wire soft_outer;
wire [23:0] outer_color;
wire [23:0] inner_color;
wire front_fill;
wire far_fill;
wire wave_envelope;
wire [23:0] wave_color;
wire panel_ink;
reg [23:0] native_color;
// Two distinct drawing baselines. Color bands belong to the front fill only.
reg [23:0] layered_color,back_color;
wire [5:0] front_integer=mountain_front_q4[9:4];
wire [5:0] back_integer=mountain_back_q4[9:4];
wire [1:0] front_coverage={mountain_front_q4[3],1'b0};
wire [1:0] back_coverage={mountain_back_q4[3],1'b0};
wire [5:0] back_dy=wave_dy0-6'd12;
wire [23:0] front_band=wave_dy0>=35?24'h8ccabd:wave_dy0>=21?24'ha1d5c9:wave_dy0>=10?24'hb4dfd3:24'hc9e8df;
// Half-pixel coverage (phase bit3, alpha0/one-half).
// Q4 DDA and Q1 nodes remain exact. Limited quarter coverages: 10-bit channel sums retain carries (<=1020).
function [23:0] blend_quarter;
 input [23:0] below,above;input [1:0] coverage;
 reg [9:0] r,g,b;
 begin
 case(coverage)
  1:begin
   r=({2'd0,below[23:16]}<<1)+{2'd0,below[23:16]}+{2'd0,above[23:16]};
   g=({2'd0,below[15:8]}<<1)+{2'd0,below[15:8]}+{2'd0,above[15:8]};
   b=({2'd0,below[7:0]}<<1)+{2'd0,below[7:0]}+{2'd0,above[7:0]};
  end
  2:begin
   r=({2'd0,below[23:16]}+{2'd0,above[23:16]})<<1;
   g=({2'd0,below[15:8]}+{2'd0,above[15:8]})<<1;
   b=({2'd0,below[7:0]}+{2'd0,above[7:0]})<<1;
  end
  3:begin
   r={2'd0,below[23:16]}+({2'd0,above[23:16]}<<1)+{2'd0,above[23:16]};
   g={2'd0,below[15:8]}+({2'd0,above[15:8]}<<1)+{2'd0,above[15:8]};
   b={2'd0,below[7:0]}+({2'd0,above[7:0]}<<1)+{2'd0,above[7:0]};
  end
  default:begin r={below[23:16],2'd0};g={below[15:8],2'd0};b={below[7:0],2'd0};end
 endcase
 blend_quarter={r[9:2],g[9:2],b[9:2]};
 end
endfunction
function [23:0] front_inner;input [5:0] dy;input [1:0] coverage_index;
reg [1:0] band;begin
band=dy>=35?2'd0:dy>=21?2'd1:dy>=10?2'd2:2'd3;
case({band,coverage_index})
4'd0:front_inner=24'h4a9f92;
4'd1:front_inner=24'h5aa99c;
4'd2:front_inner=24'h6bb4a7;
4'd3:front_inner=24'h7bbfb2;
4'd4:front_inner=24'h4a9f92;
4'd5:front_inner=24'h5fac9f;
4'd6:front_inner=24'h75baad;
4'd7:front_inner=24'h8bc7bb;
4'd8:front_inner=24'h4a9f92;
4'd9:front_inner=24'h64afa2;
4'd10:front_inner=24'h7fbfb2;
4'd11:front_inner=24'h99cfc2;
4'd12:front_inner=24'h4a9f92;
4'd13:front_inner=24'h69b1a5;
4'd14:front_inner=24'h89c3b8;
4'd15:front_inner=24'ha9d5cb;
default:front_inner=24'h4a9f92;endcase end endfunction
always @*begin
 back_color=rgb_0;
 if(wave_dy0>=12&&mountain_back_q4!=0)begin
  if(back_dy<back_integer)back_color=24'hc3e5de;
  else if(back_dy==back_integer)
   back_color=back_integer==0?blend_quarter(rgb_0,24'ha1cfc5,back_coverage):blend_quarter(24'ha1cfc5,24'hc3e5de,back_coverage);
  else if(back_dy=={1'b0,back_integer}+7'd1&&back_integer!=0)
   back_color=blend_quarter(rgb_0,24'ha1cfc5,back_coverage);
 end
 layered_color=back_color;
 if(mountain_front_q4!=0)begin
  if(wave_dy0<front_integer)layered_color=front_band;
  else if(wave_dy0==front_integer)
   layered_color=front_integer==0?blend_quarter(back_color,24'h4a9f92,front_coverage):front_inner(wave_dy0,front_coverage);
  else if(wave_dy0=={1'b0,front_integer}+7'd1&&front_integer!=0)
   layered_color=blend_quarter(back_color,24'h4a9f92,front_coverage);
 end
end
// Continuous values retain the original net initializer expressions.
assign frame_start = previous_vs&&!vs;
assign line_start = de&&!previous_de;
assign px = line_start?10'd0:x+10'd1;
assign py = line_start?(arm?10'd0:y+10'd1):y;
assign practice_on = fd&&!fh&&fp[23];
assign practice_step = fp[21:19];
assign practice_phase = fp[18:16];
assign education = fs>=23&&fs<=26;
assign relax = fs==49;
assign report_scene = fs==8||fs==22||fs==29||fs==30;
assign active = fd&&!fh&&!report_scene;
assign normal_handoff_hold = practice[1]&&display_enable&&!history_enable&&
  status_data[7:0]==0&&fd&&(fs==1||(fs>=9&&fs<=11))&&scene_id==fs;
assign context_changed = scene_id!=fs||question_set!=fq;
assign new_accept = ui_valid&&ui_data[51]&&(!accept_seen||ui_data[50:43]!=last_accept||context_changed);
assign requested_hint = (!ui_valid||status_data[7:0]!=0)?7'd72:
  ui_data[6:0]==70 ? ((ack_frames!=0||new_accept)?7'd70:ui_data[13:7]):ui_data[6:0];
assign selected_length_raw = ui_data[6:0]==70?
  ((ack_frames!=0||new_accept)?8'd9:ui_data[95:88]):ui_data[87:80];
assign requested_length = (!ui_valid||status_data[7:0]!=0)?8'd10:
  (selected_length_raw>36?8'd0:selected_length_raw);
assign urgent = ui_data[54]||!ui_valid;
assign sensitive = ui_data[53];
assign chosen_length = animation<18&&old_length>hint_length?old_length:hint_length;
assign panel_width = chosen_length>20?10'd344:{chosen_length[5:0],4'b0}+10'd24;
assign panel_left = (10'd640-panel_width)>>1;
assign welcome_span = {welcome_length,4'b0};
assign welcome_max = welcome_span>322?welcome_span-12'd322:12'd0;
assign welcome_scroll = (ft>>2)>welcome_max?welcome_max:(ft>>2);
assign education_sentence = education&&fr&&fc==fs?edu_text:7'd84;
assign education_length = education_known&&education_length_raw>0?
  (education_length_raw>36?6'd36:education_length_raw[5:0]):6'd0;
assign education_text_left = 10'd320-{education_length,3'd0};
assign education_box_left = education_text_left-10'd16;
assign education_box_width = {education_length,4'd0}+10'd32;
assign rest_length = rest_known&&rest_length_raw>0?
   (rest_length_raw>36?6'd36:rest_length_raw[5:0]):6'd0;
assign rest_text_left = 10'd320-{rest_length,3'd0};
assign rest_box_left = rest_text_left-10'd16;
assign rest_box_width = {rest_length,4'd0}+10'd32;
assign vertical_shift = shift_rows(animation);
assign practice_page_match = fp[22] ? fs==1 :
   ((fs==9&&fp[21:19]<=1)||(fs==10&&fp[21:19]==2)||(fs==11&&fp[21:19]==4));
assign practice_alarm_panel = fp[23]&&fp[18:16]==6&&fs==7;
assign fixed_buttons = (fs>=2&&fs<=6)||fs==28||(fs>=13&&fs<=21)||(fu[36]&&(practice_page_match||practice_alarm_panel));
assign legacy_buttons = !fixed_buttons&&(fs==1||fs==9||fs==10||fs==11||fs==12||fs==27);
assign button_cy = {1'b0,button_meta[18:10]};
assign button_dy = button_row0>button_cy?button_row0-button_cy:button_cy-button_row0;
assign wave_center = 10'd289;
assign music_page = active&&(education||relax||fs==27);
assign welcome_panel = fs==0&&fr&&fc==0;
assign light_panel = education||fs==27;
assign ordinary_panel = fs!=0&&!music_page&&!report_scene;
assign panel_on = welcome_panel||light_panel||ordinary_panel;
assign panel_l = education?education_box_left:fs==27?rest_box_left:welcome_panel?10'd147:light_panel?10'd12:panel_left;
assign panel_w = education?education_box_width:fs==27?rest_box_width:welcome_panel?10'd346:light_panel?10'd616:panel_width;
assign panel_t = (education||fs==27)?10'd428:light_panel?10'd402:10'd410;
assign panel_h = (education||fs==27)?10'd40:light_panel?10'd76:10'd38;
assign wave_pixel = active&&relax&&px>=96&&px<544&&py>=241&&py<=289;
assign wave_offset = px-10'd96;
assign teaching_panel = active&&fu[36]&&(practice_page_match||practice_alarm_panel);
assign cue_pixel = teaching_panel&&!practice_alarm_panel&&fu[40]&&fu[42]&&px>=80&&px<560&&py>=200&&py<288;
assign teaching_length = hint_length>15?8'd15:hint_length;
assign teaching_left = 10'd320-{teaching_length[3:0],4'd0};
assign teaching_alarm = teaching_panel&&practice_alarm_panel;
assign rgb_0 = theme_0?{tint_r,tint_g,tint_b}:base_0;
assign front_height = wave_max[5:0]>48?6'd48:wave_max[5:0];
assign far_sum = {1'b0,front_height}+{3'd0,front_height[5:2]};
assign far_height = far_sum>48?6'd48:far_sum[5:0];
assign edge_fraction = WAVE_FRACTION_ENABLE!=0?{wave_fraction[3],1'b0}:2'd0;
assign front_edge = wave_dy0==front_height;
assign soft_outer = WAVE_FRACTION_ENABLE!=0&&edge_fraction!=0&&wave_dy0==({1'b0,front_height}+7'd1);
assign outer_color = 24'ha2d1cd;
assign inner_color = edge_fraction==0?24'h5caa9e:24'h9ecbc3;
assign front_fill = wave_dy0<front_height;
assign far_fill = MOUNTAIN_LAYERED!=0&&wave_dy0<=far_height;
assign wave_envelope = wave_0&&(MOUNTAIN_LAYERED==2?mountain_valid:(front_edge||soft_outer||front_fill||far_fill));
assign wave_color = MOUNTAIN_LAYERED==2?layered_color:soft_outer?outer_color:front_edge?inner_color:
  front_fill?(MOUNTAIN_LAYERED!=0?24'hb4dcd2:
   wave_dy0>=36?24'hb4d7ca:wave_dy0>=24?24'hbfddd2:wave_dy0>=12?24'hcee6dd:24'hdeeee8):
  wave_dy0==far_height?24'ha1c7d5:24'hd6e6ec;
assign panel_ink = de_2&&panel_bounds[2]&&panel_bits2[15-panel_col2];

 
 
 
 
 
 
 
 
 
 
 
 
 
 // M1/M2: B chooses segments and business hints. A runs the requested
 // 60-display-frame lifetime once per accepted identity in this context.
 
 // practice[1] is the B-owned normal handoff transaction. Only the
 // already displayed teaching view may be held while its old canvas stays.
 // A kill withdraws display_enable; SAFE/error/history never enter this path.
 
 
 
 
 
 
 
 
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   previous_de<=0;previous_vs<=1;arm<=1;x<=0;y<=0;
   fp<=0;ff<=0;fs<=0;fq<=0;fd<=0;fh<=0;fr<=0;fc<=0;fg<=0;ft<=0;
   last_accept<=0;accept_seen<=0;validity_lost<=1;hold_view<=0;fu<=0;ack_frames<=0;hold_right<=0;hint<=65;old_hint<=65;hint_length<=11;old_length<=11;animation<=18;
  end else begin
   previous_de<=de;previous_vs<=vs;if(!vs)arm<=1;
   if(de)begin x<=px;y<=py;if(line_start)arm<=0;end
   // Physical memory ACK may follow VS by several blanking clocks. A normal
   // successor's complete, already delivered UI must follow that canvas now,
   // before active video, rather than wait a whole additional frame.
   if(frame_start||(view_prepare===1'b1&&!de))begin
    hold_view<=normal_handoff_hold;
    if(!normal_handoff_hold)begin
    validity_lost<=!ui_valid;
    fp<=practice;ff<=feedback;fu<=ui_valid?ui_data[73:0]:74'd0;fs<=scene_id;fq<=question_set;
    fd<=display_enable;fh<=history_enable;fr<=caption_running;
    fc<=caption_id;fg<=caption_generation;ft<=caption_ticks;
    if(context_changed||validity_lost||!display_enable||history_enable||!ui_valid)begin
     // The first displayed frame already counts as frame one. Keep only
     // 59 following frames; duplicate publications never reload the counter.
     ack_frames<=new_accept&&display_enable&&!history_enable?7'd59:7'd0;
     accept_seen<=new_accept&&display_enable&&!history_enable;
     hold_right<=feedback[2]&&feedback[1];hint<=requested_hint;old_hint<=requested_hint;hint_length<=requested_length;old_length<=requested_length;animation<=18;
     last_accept<=ui_data[50:43];
    end else begin
     if(new_accept)begin last_accept<=ui_data[50:43];accept_seen<=1;ack_frames<=59;end
     else if(ack_frames!=0)ack_frames<=ack_frames-1'b1;
     if(feedback[2]&&(feedback[0]||feedback[1]))hold_right<=feedback[1];
     if(requested_hint!=hint)begin old_hint<=hint;old_length<=hint_length;hint<=requested_hint;hint_length<=requested_length;animation<=urgent||sensitive?18:0;end
     else if(animation<18)animation<=animation+1'b1;
    end
   end
   end
   // Kill qualification in pixel clocks, even between VS boundaries. The
   // first restored full view starts its own hint without old animations.
   if(!ui_valid)begin validity_lost<=1;ack_frames<=0;accept_seen<=0;end
  end
 end
 
 
 recovery_caption_info u_home_info(.text_id(7'd0),.text_length(welcome_length),.scroll_rate(unused_rate2),.valid(known2));
 
 
 
 
 
 
 
 recovery_education_cue u_education(.scene(fs),.ticks(ft),.text_id(edu_text));
 // the sentence ID and its actual length share frame-held scene/tick.
 
 
 recovery_caption_info u_edu_info(.text_id(education_sentence),.text_length(education_length_raw),
  .scroll_rate(education_rate),.valid(education_known));
 
 
 
 
  
  recovery_caption_info u_rest_info(.text_id(7'd84),.text_length(rest_length_raw),
   .scroll_rate(rest_rate),.valid(rest_known));
  
  
  
  
 function [3:0] corner_inset;input [3:0] row;begin case(row)
  0:corner_inset=11;1:corner_inset=8;2:corner_inset=6;3:corner_inset=5;
  4:corner_inset=4;5:corner_inset=3;6:corner_inset=2;7:corner_inset=2;
  8:corner_inset=1;9:corner_inset=1;10:corner_inset=1;
  default:corner_inset=0;endcase end endfunction
 function rounded;input [9:0] xx,yy,left,width,top,height;
  reg [9:0] dy,inset;begin
   rounded=0;dy=yy-top;inset=0;
   if(xx>=left&&xx<left+width&&yy>=top&&yy<top+height)begin
    if(dy<14)inset=corner_inset(dy[3:0]);
    else if(dy>=height-14)inset=corner_inset(height-1-dy);
    rounded=xx>=left+inset&&xx<left+width-inset;
   end
  end
 endfunction
 function [5:0] shift_rows;input [4:0] a;begin case(a)
 0:shift_rows=0;1:shift_rows=2;2:shift_rows=4;3:shift_rows=6;4:shift_rows=8;
 5:shift_rows=10;6:shift_rows=12;7:shift_rows=14;8:shift_rows=16;
 9:shift_rows=19;10:shift_rows=21;11:shift_rows=23;12:shift_rows=25;
 13:shift_rows=27;14:shift_rows=29;15:shift_rows=31;16:shift_rows=33;17:shift_rows=35;
 default:shift_rows=38;endcase end endfunction
 
  
  
  
 
 recovery_button_osd u_fixed_buttons(.clk(clk),.rst(rst),.de(de),.vs(vs),.px(px),.py(py),
  .enable(active&&fixed_buttons&&(ui_valid||hold_view)),.segments(fu[24:19]),.full(fu[25]),
  .track_visible(fu[26]&&!practice_alarm_panel),.green_l(!practice_alarm_panel&&(fu[66]?fu[64]:fu[27])),.green_r(!practice_alarm_panel&&(fu[66]?fu[65]:fu[28])),.progress_right(fu[52]),
  .red_l(!practice_alarm_panel&&fu[67]&&fu[64]),.red_r(!practice_alarm_panel&&fu[67]&&fu[65]),
   .paint_idle(fu[36]&&(practice_page_match||practice_alarm_panel)),.hit(button_hit),.color(button_color));
 // Legacy hotspots: only guidance/teaching/READY/REST, never the 33 new pages.
 
 
 
 
 
 
 
 recovery_button_meta_rom u_button_meta(.clk(clk),.scene(fs),.button_index(px[1:0]),.data(button_meta));
 recovery_button_span_rom u_button_span(.clk(clk),.radius(button_meta[23:19]),.dy(button_dy[4:0]),.span(button_span));
 
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   button_row0<=0;button_cx1<=0;button_index0<=0;button_index1<=0;button_read0<=0;button_read1<=0;
   button_key1<=0;button_row_ok1<=0;button_valid<=0;button_rightkey<=0;
   for(button_reset=0;button_reset<4;button_reset=button_reset+1)begin button_left[button_reset]<=0;button_right[button_reset]<=0;end
  end else begin
   button_read0<=de&&px<4&&legacy_buttons;button_row0<=py;button_index0<=px[1:0];
   button_read1<=button_read0;button_row_ok1<=button_dy<32;
   button_cx1<=button_meta[9:0];button_index1<=button_index0;button_key1<=button_meta[24];
   if(button_read1)begin button_left[button_index1]<=button_cx1-{5'd0,button_span[4:0]};
    button_right[button_index1]<=button_cx1+{5'd0,button_span[4:0]};
    button_valid[button_index1]<=button_row_ok1&&button_span[5];button_rightkey[button_index1]<=button_key1;end
  end
 end
 
 
 
 
 // Only RELAX has a central audio panel; REST is the retest instruction page.
 // The existing 3-clock
 // output pipeline also carries the RAM query and rounded bar coordinates.
 
 
 
 
 
 
  
  
  
  
 
 
 assign wave_query_index=wave_offset[8:0];
  
 
 
 
 
 
 
 
 always @*begin
  native_text=0;native_character=0;native_row=0;native_col=0;native_bounds=0;native_white=0;
  if(teaching_panel)begin
   if(px>=256&&px<384&&py>=100&&py<132)begin
    native_text=teaching_alarm?7'd116:7'd108;native_character=(px-256)>>5;
    native_row=py-100;native_col=px-256;native_bounds=1;
   end else if(teaching_alarm&&px>=160&&px<480&&py>=144&&py<176)begin
    native_text=117;native_character=(px-160)>>5;native_row=py-144;native_col=px-160;native_bounds=1;
   end else if(!teaching_alarm&&fu[40]&&px>=160&&px<480&&py>=144&&py<176)begin
    native_text=115;native_character=(px-160)>>5;native_row=py-144;native_col=px-160;native_bounds=1;
   end else if(!teaching_alarm&&fu[40]&&px>=256&&px<384&&py>=228&&py<260)begin
    native_text=fu[42]?7'd112:7'd111;native_character=(px-256)>>5;
    native_row=py-228;native_col=px-256;native_bounds=1;native_white=fu[42];
   end else if(!teaching_alarm&&!fu[40]&&px>=teaching_left&&px<640-teaching_left&&py>=144&&py<176)begin
    native_text=hint;native_character=(px-teaching_left)>>5;native_row=py-144;
    native_col=px-teaching_left;native_bounds=native_character<teaching_length;
   end
  end
 end
 recovery_teaching_font32 u_native_font(.clk(clk),.text_id(native_text),.character(native_character),.row(native_row),.col(native_col),.coverage(native_coverage));
 always @(posedge clk or posedge rst)begin
  if(rst)begin native_scope<=0;native_white_pipe<=0;native_instruction<=0;end
  else begin native_scope<={native_scope[1:0],native_bounds&&de};native_white_pipe<={native_white_pipe[1:0],native_white};native_instruction<={native_instruction[1:0],native_bounds&&de&&py>=144&&py<176};end
 end
 
 always @*begin
  panel_text=0;panel_message=0;panel_character=0;panel_row=0;panel_col=0;
  if(teaching_panel)begin
   if(px>=194&&px<226&&py>=292&&py<308)begin panel_text=1;panel_message=1;panel_character=(px-194)>>4;panel_col=px-194;panel_row=py-292;end
   else if(px>=414&&px<446&&py>=292&&py<308)begin panel_text=1;panel_message=2;panel_character=(px-414)>>4;panel_col=px-414;panel_row=py-292;end
  end
 end
 
 
 
 recovery_panel_font u_panel_font(.clk(clk),.message(panel_message),.character(panel_character),.row(panel_row),.bits(panel_bits));
 always @(posedge clk or posedge rst)begin
  if(rst)begin panel_bits1<=0;panel_bits2<=0;panel_bounds<=0;cue_pipe<=0;
   panel_col0<=0;panel_col1<=0;panel_col2<=0;raw0<=0;raw1<=0;raw2<=0;end
  else begin panel_bits1<=panel_bits;panel_bits2<=panel_bits1;
   panel_bounds<={panel_bounds[1:0],panel_text&&de};cue_pipe<={cue_pipe[1:0],cue_pixel&&de};
   panel_col0<=panel_col;panel_col1<=panel_col0;panel_col2<=panel_col1;raw0<=rgb;raw1<=raw0;raw2<=raw1;end
 end
 always @*begin
  text_id_comb=0;character_comb=0;glyph_row_comb=0;glyph_col_comb=0;
  text_bounds_comb=0;theme_pixel_comb=0;base_comb=rgb;text_color_comb=24'hffffff;text_offset=0;text_top=421;
  if(de&&active)begin
   // A plain teaching canvas hides cropped legacy labels/key art outside
   // the fixed card, preserving the title y<56 and landscape y>=408.
   if(teaching_panel&&py>=56&&py<408)base_comb=teaching_alarm?24'hfff0ee:24'heef6fb;
   if(teaching_panel&&rounded(px,py,40,560,84,312))begin
    base_comb=teaching_alarm?24'hd94343:24'hb8dcef;
    if(rounded(px,py,42,556,86,308))base_comb=teaching_alarm?24'hfff0ee:24'hf4fbff;
    if(rounded(px,py,179,62,321,62)||rounded(px,py,399,62,321,62))base_comb=24'hffffff;
    if(!teaching_alarm&&fp[21:19]==2&&rounded(px,py,80,480,260,14))
      base_comb=px<80+fu[63:55]?24'h1ca799:24'hd7e7ee;
   end else if(!teaching_panel&&panel_on&&rounded(px,py,panel_l,panel_w,panel_t,panel_h))theme_pixel_comb=1;
   if(cue_pixel)base_comb=24'h25b56b;
   for(b=0;b<4;b=b+1)begin
    if(legacy_buttons&&button_valid[b]&&(button_rightkey[b]?ff[1]:ff[0])&&px>=button_left[b]&&px<=button_right[b])
     begin theme_pixel_comb=0;base_comb={8'd12+{2'b0,rgb[23:18]},8'd156+{2'b0,rgb[15:10]},8'd102+{2'b0,rgb[7:2]}};end
   end
   if(fs==0&&fr&&fc==0)begin
    if(px>=159&&px<481&&py>=421&&py<437)begin
     text_offset={2'b0,px-10'd159}+welcome_scroll;text_id_comb=0;
     text_bounds_comb=text_offset[11:4]<welcome_length;
     character_comb=text_offset[11:4];glyph_col_comb=text_offset[3:0];glyph_row_comb=py-421;
    end
   end else if(teaching_panel)begin
     // Native SimSun32 uses its independent three-clock coverage ROM above.
   end else if(fs!=0&&!music_page&&!report_scene)begin
    if(px>=panel_left+12&&px<panel_left+panel_width-12&&py>=410&&py<448)begin
     text_offset={2'b0,px-panel_left-10'd12};text_id_comb=hint;
     if(animation<18)begin
      if(py>=10'd421-vertical_shift&&py<10'd437-vertical_shift)begin text_id_comb=old_hint;text_top=10'd421-vertical_shift;text_bounds_comb=text_offset[11:4]<old_length;end
      else begin text_top=10'd459-vertical_shift;text_bounds_comb=py>=text_top&&py<text_top+16&&text_offset[11:4]<hint_length;end
     end else text_bounds_comb=py>=421&&py<437&&text_offset[11:4]<hint_length;
     character_comb=text_offset[11:4];glyph_col_comb=text_offset[3:0];glyph_row_comb=py-text_top;
    end
   end
   if(music_page)begin
    if(education||fs==27)begin
      if(px>=(education?education_text_left:fs==27?rest_text_left:10'd24)&&
         px<(education?640-education_text_left:fs==27?640-rest_text_left:10'd616)&&py>=440&&py<456)begin
       text_id_comb=education?education_sentence:7'd84;
       text_offset={2'b0,px-(education?education_text_left:fs==27?rest_text_left:10'd24)};
       text_bounds_comb=education?text_offset[11:4]<education_length:
        fs==27?text_offset[11:4]<rest_length:1'b1;
      character_comb=text_offset[11:4];glyph_col_comb=text_offset[3:0];glyph_row_comb=py-440;text_color_comb=24'h173f63;
     end
    end else begin
     if(px>=144&&px<496&&py>=340&&py<356)begin
      text_id_comb=82;text_offset={2'b0,px-10'd144};text_bounds_comb=1;
      character_comb=text_offset[11:4];glyph_col_comb=text_offset[3:0];glyph_row_comb=py-340;text_color_comb=24'h173f63;
     end
    end
   end
  end
 end
 
 
 // Three byte-wide immutable ROM ports occupy the original first pixel
 // register stage. The palette is exactly (197*theme+59*base+128)>>8.
 
 
 initial begin for(tint_index=0;tint_index<512;tint_index=tint_index+1)begin
  tint_channel_r[tint_index]=(197*(tint_index>=256?232:28)+59*(tint_index%256)+128)>>8;
  tint_channel_g[tint_index]=(197*(tint_index>=256?247:167)+59*(tint_index%256)+128)>>8;
  tint_channel_b[tint_index]=(197*(tint_index>=256?252:153)+59*(tint_index%256)+128)>>8;
 end end
 always @(posedge clk)begin
  tint_r<=tint_channel_r[{light_panel,rgb[23:16]}];
  tint_g<=tint_channel_g[{light_panel,rgb[15:8]}];
  tint_b<=tint_channel_b[{light_panel,rgb[7:0]}];
 end
 
 
 
 
 
 // Height is already filtered/interpolated in blanking. Pixel stage uses
 // comparisons and a fixed palette; no real-time multiplier or extra stage.
 
 
 
 
 
 
 // Half-pixel coverage, two fixed edge shades (resource-budget fallback). Same query, dy/RGB
 // stage and three-clock OSD contract; no extra pixel multiplier/stage.
 
 
 
 
 
 
 recovery_caption_char_rom u_character(.clk(clk),.text_id(text_id_0),.character_index(character_0),.glyph_id(glyph_id_1));
 recovery_caption_font u_glyph(.clk(clk),.glyph_id(glyph_id_1),.row(row_1),.bits(glyph_bits_2));
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   text_id_0<=0;character_0<=0;row_0<=0;row_1<=0;col_0<=0;col_1<=0;col_2<=0;
   bounds_0<=0;bounds_1<=0;bounds_2<=0;base_0<=0;theme_0<=0;rgb_1<=0;rgb_2<=0;color_0<=0;color_1<=0;color_2<=0;
   de_0<=0;de_1<=0;de_2<=0;vs_0<=0;vs_1<=0;vs_2<=0;
   feedback_face1<=0;feedback_face2<=0;
   wave_0<=0;wave_dy0<=0;wave_column0<=0;wave_lower0<=0;
  end else begin
   text_id_0<=text_id_comb;character_0<=character_comb;row_0<=glyph_row_comb;row_1<=row_0;
   col_0<=glyph_col_comb;col_1<=col_0;col_2<=col_1;
   bounds_0<=text_bounds_comb;bounds_1<=bounds_0;bounds_2<=bounds_1;
   color_0<=text_color_comb;color_1<=color_0;color_2<=color_1;
   base_0<=base_comb;theme_0<=theme_pixel_comb;
   rgb_1<=button_hit?button_color:wave_envelope?wave_color:rgb_0;
   rgb_2<=rgb_1;
   feedback_face1<=button_hit&&(button_color==24'h25b56b||button_color==24'hd94343);
   feedback_face2<=feedback_face1;
   de_0<=de;de_1<=de_0;de_2<=de_1;vs_0<=vs;vs_1<=vs_0;vs_2<=vs_1;
   wave_0<=de&&wave_pixel;wave_dy0<=wave_center-py;
   wave_column0<=wave_offset[2:0];wave_lower0<=py>wave_center;
  end
 end
 assign out_de=de_2;assign out_vs=vs_2;
 
 // A white glyph inside the rectangle is not evidence of a green pixel.
 assign ui_marker=ui_valid&&de_2&&cue_pipe[2]&&!panel_ink&&!(native_scope[2]&&native_coverage!=0)&&out_rgb==24'h25b56b;
 // This marker is qualified again at the final AXIS accept point. Either
 // a real colored key face, or red instruction ink for a no-key timeout.
 assign feedback_marker=ui_valid&&de_2&&active&&fu[67:66]!=0&&
   ((feedback_face2&&!panel_ink&&!bounds_2&&
     ((fu[67:66]==1&&out_rgb==24'h25b56b)||(fu[67:66]==2&&out_rgb==24'hd94343)))||
    (fu[67:66]==2&&fu[65:64]==0&&((bounds_2&&glyph_bits_2[15-col_2])||
       (native_instruction[2]&&native_coverage==3&&!teaching_alarm))&&out_rgb==24'hd94343));
 
 always @*begin
  native_color=24'h17334f;
  if(native_white_pipe[2])begin
   case(native_coverage)1:native_color=24'h5cc88f;2:native_color=24'hc9eddA;default:native_color=24'hffffff;endcase
  end else if(teaching_alarm)begin
   case(native_coverage)1:native_color=24'he3c0bd;2:native_color=24'hab5f5c;default:native_color=24'h8f2f2b;endcase
  end else if(fu[67])begin
   case(native_coverage)1:native_color=24'hedcdD0;2:native_color=24'he07172;default:native_color=24'hd94343;endcase
  end else begin
   case(native_coverage)1:native_color=24'hbdc9d3;2:native_color=24'h4e657b;default:native_color=24'h17334f;endcase
  end
 end
 assign out_rgb=(!ui_valid&&!normal_handoff_hold)?raw2:(native_scope[2]&&native_coverage!=0)?native_color:panel_ink?(cue_pipe[2]?24'hffffff:teaching_alarm?24'h8f2f2b:24'h17334f):
  de_2&&bounds_2&&glyph_bits_2[15-col_2]?(teaching_panel&&fu[67]?24'hd94343:color_2):rgb_2;
endmodule



// Legacy six-scene hotspot ROMs.
module recovery_button_meta_rom(input wire clk,input wire [5:0] scene,input wire [1:0] button_index,output wire [24:0] data);

reg [2:0] bank;
wire [4:0] address;
reg [15:0] lo,hi;
(* ram_style="bram" *)reg [15:0] mem[0:63];
integer k;
// Continuous values retain the original net initializer expressions.
assign address = {bank,button_index};

always @*begin case(scene)
6'd1:bank=0;6'd9:bank=1;6'd10:bank=2;6'd11:bank=3;6'd12:bank=4;6'd27:bank=5;default:bank=7;endcase end

initial begin for(k=0;k<64;k=k+1)mem[k]=0;
mem[0]=16'hb446;mem[1]=16'h009c;
mem[2]=16'hb098;mem[3]=16'h0184;
mem[4]=16'hb5ea;mem[5]=16'h008b;
mem[6]=16'hb63f;mem[7]=16'h018b;
mem[8]=16'hc4df;mem[9]=16'h01b3;
mem[10]=16'hc5a0;mem[11]=16'h00b3;
mem[16]=16'h6cd8;mem[17]=16'h006b;
mem[18]=16'h6e2a;mem[19]=16'h006b;
mem[24]=16'hf117;mem[25]=16'h006c;
mem[26]=16'hf169;mem[27]=16'h016c;
mem[28]=16'h2a3f;mem[29]=16'h01ac;
mem[32]=16'hc868;mem[33]=16'h0093;
mem[34]=16'hc8c1;mem[35]=16'h0193;
mem[36]=16'hb594;mem[37]=16'h016b;
mem[38]=16'hb5f6;mem[39]=16'h006b;
mem[40]=16'h808a;mem[41]=16'h008d;
mem[42]=16'h80f8;mem[43]=16'h018d;
end
always @(posedge clk)begin lo<=mem[{address,1'b0}];hi<=mem[{address,1'b1}];end
assign data={hi[8:0],lo};
endmodule
module recovery_button_span_rom(input wire clk,input wire [4:0] radius,dy,output reg [5:0] span);

wire [9:0] address;
// Continuous values retain the original net initializer expressions.
assign address = {radius,dy};

always @(posedge clk)begin case(address)
10'd0:span<=6'h00;
10'd1:span<=6'h00;
10'd2:span<=6'h00;
10'd3:span<=6'h00;
10'd4:span<=6'h00;
10'd5:span<=6'h00;
10'd6:span<=6'h00;
10'd7:span<=6'h00;
10'd8:span<=6'h00;
10'd9:span<=6'h00;
10'd10:span<=6'h00;
10'd11:span<=6'h00;
10'd12:span<=6'h00;
10'd13:span<=6'h00;
10'd14:span<=6'h00;
10'd15:span<=6'h00;
10'd16:span<=6'h00;
10'd17:span<=6'h00;
10'd18:span<=6'h00;
10'd19:span<=6'h00;
10'd20:span<=6'h00;
10'd21:span<=6'h00;
10'd22:span<=6'h00;
10'd23:span<=6'h00;
10'd24:span<=6'h00;
10'd25:span<=6'h00;
10'd26:span<=6'h00;
10'd27:span<=6'h00;
10'd28:span<=6'h00;
10'd29:span<=6'h00;
10'd30:span<=6'h00;
10'd31:span<=6'h00;
10'd32:span<=6'h20;
10'd33:span<=6'h00;
10'd34:span<=6'h00;
10'd35:span<=6'h00;
10'd36:span<=6'h00;
10'd37:span<=6'h00;
10'd38:span<=6'h00;
10'd39:span<=6'h00;
10'd40:span<=6'h00;
10'd41:span<=6'h00;
10'd42:span<=6'h00;
10'd43:span<=6'h00;
10'd44:span<=6'h00;
10'd45:span<=6'h00;
10'd46:span<=6'h00;
10'd47:span<=6'h00;
10'd48:span<=6'h00;
10'd49:span<=6'h00;
10'd50:span<=6'h00;
10'd51:span<=6'h00;
10'd52:span<=6'h00;
10'd53:span<=6'h00;
10'd54:span<=6'h00;
10'd55:span<=6'h00;
10'd56:span<=6'h00;
10'd57:span<=6'h00;
10'd58:span<=6'h00;
10'd59:span<=6'h00;
10'd60:span<=6'h00;
10'd61:span<=6'h00;
10'd62:span<=6'h00;
10'd63:span<=6'h00;
10'd64:span<=6'h21;
10'd65:span<=6'h20;
10'd66:span<=6'h00;
10'd67:span<=6'h00;
10'd68:span<=6'h00;
10'd69:span<=6'h00;
10'd70:span<=6'h00;
10'd71:span<=6'h00;
10'd72:span<=6'h00;
10'd73:span<=6'h00;
10'd74:span<=6'h00;
10'd75:span<=6'h00;
10'd76:span<=6'h00;
10'd77:span<=6'h00;
10'd78:span<=6'h00;
10'd79:span<=6'h00;
10'd80:span<=6'h00;
10'd81:span<=6'h00;
10'd82:span<=6'h00;
10'd83:span<=6'h00;
10'd84:span<=6'h00;
10'd85:span<=6'h00;
10'd86:span<=6'h00;
10'd87:span<=6'h00;
10'd88:span<=6'h00;
10'd89:span<=6'h00;
10'd90:span<=6'h00;
10'd91:span<=6'h00;
10'd92:span<=6'h00;
10'd93:span<=6'h00;
10'd94:span<=6'h00;
10'd95:span<=6'h00;
10'd96:span<=6'h22;
10'd97:span<=6'h21;
10'd98:span<=6'h20;
10'd99:span<=6'h00;
10'd100:span<=6'h00;
10'd101:span<=6'h00;
10'd102:span<=6'h00;
10'd103:span<=6'h00;
10'd104:span<=6'h00;
10'd105:span<=6'h00;
10'd106:span<=6'h00;
10'd107:span<=6'h00;
10'd108:span<=6'h00;
10'd109:span<=6'h00;
10'd110:span<=6'h00;
10'd111:span<=6'h00;
10'd112:span<=6'h00;
10'd113:span<=6'h00;
10'd114:span<=6'h00;
10'd115:span<=6'h00;
10'd116:span<=6'h00;
10'd117:span<=6'h00;
10'd118:span<=6'h00;
10'd119:span<=6'h00;
10'd120:span<=6'h00;
10'd121:span<=6'h00;
10'd122:span<=6'h00;
10'd123:span<=6'h00;
10'd124:span<=6'h00;
10'd125:span<=6'h00;
10'd126:span<=6'h00;
10'd127:span<=6'h00;
10'd128:span<=6'h23;
10'd129:span<=6'h23;
10'd130:span<=6'h22;
10'd131:span<=6'h21;
10'd132:span<=6'h00;
10'd133:span<=6'h00;
10'd134:span<=6'h00;
10'd135:span<=6'h00;
10'd136:span<=6'h00;
10'd137:span<=6'h00;
10'd138:span<=6'h00;
10'd139:span<=6'h00;
10'd140:span<=6'h00;
10'd141:span<=6'h00;
10'd142:span<=6'h00;
10'd143:span<=6'h00;
10'd144:span<=6'h00;
10'd145:span<=6'h00;
10'd146:span<=6'h00;
10'd147:span<=6'h00;
10'd148:span<=6'h00;
10'd149:span<=6'h00;
10'd150:span<=6'h00;
10'd151:span<=6'h00;
10'd152:span<=6'h00;
10'd153:span<=6'h00;
10'd154:span<=6'h00;
10'd155:span<=6'h00;
10'd156:span<=6'h00;
10'd157:span<=6'h00;
10'd158:span<=6'h00;
10'd159:span<=6'h00;
10'd160:span<=6'h24;
10'd161:span<=6'h24;
10'd162:span<=6'h23;
10'd163:span<=6'h22;
10'd164:span<=6'h21;
10'd165:span<=6'h00;
10'd166:span<=6'h00;
10'd167:span<=6'h00;
10'd168:span<=6'h00;
10'd169:span<=6'h00;
10'd170:span<=6'h00;
10'd171:span<=6'h00;
10'd172:span<=6'h00;
10'd173:span<=6'h00;
10'd174:span<=6'h00;
10'd175:span<=6'h00;
10'd176:span<=6'h00;
10'd177:span<=6'h00;
10'd178:span<=6'h00;
10'd179:span<=6'h00;
10'd180:span<=6'h00;
10'd181:span<=6'h00;
10'd182:span<=6'h00;
10'd183:span<=6'h00;
10'd184:span<=6'h00;
10'd185:span<=6'h00;
10'd186:span<=6'h00;
10'd187:span<=6'h00;
10'd188:span<=6'h00;
10'd189:span<=6'h00;
10'd190:span<=6'h00;
10'd191:span<=6'h00;
10'd192:span<=6'h25;
10'd193:span<=6'h25;
10'd194:span<=6'h24;
10'd195:span<=6'h23;
10'd196:span<=6'h22;
10'd197:span<=6'h21;
10'd198:span<=6'h00;
10'd199:span<=6'h00;
10'd200:span<=6'h00;
10'd201:span<=6'h00;
10'd202:span<=6'h00;
10'd203:span<=6'h00;
10'd204:span<=6'h00;
10'd205:span<=6'h00;
10'd206:span<=6'h00;
10'd207:span<=6'h00;
10'd208:span<=6'h00;
10'd209:span<=6'h00;
10'd210:span<=6'h00;
10'd211:span<=6'h00;
10'd212:span<=6'h00;
10'd213:span<=6'h00;
10'd214:span<=6'h00;
10'd215:span<=6'h00;
10'd216:span<=6'h00;
10'd217:span<=6'h00;
10'd218:span<=6'h00;
10'd219:span<=6'h00;
10'd220:span<=6'h00;
10'd221:span<=6'h00;
10'd222:span<=6'h00;
10'd223:span<=6'h00;
10'd224:span<=6'h26;
10'd225:span<=6'h26;
10'd226:span<=6'h25;
10'd227:span<=6'h24;
10'd228:span<=6'h23;
10'd229:span<=6'h22;
10'd230:span<=6'h21;
10'd231:span<=6'h00;
10'd232:span<=6'h00;
10'd233:span<=6'h00;
10'd234:span<=6'h00;
10'd235:span<=6'h00;
10'd236:span<=6'h00;
10'd237:span<=6'h00;
10'd238:span<=6'h00;
10'd239:span<=6'h00;
10'd240:span<=6'h00;
10'd241:span<=6'h00;
10'd242:span<=6'h00;
10'd243:span<=6'h00;
10'd244:span<=6'h00;
10'd245:span<=6'h00;
10'd246:span<=6'h00;
10'd247:span<=6'h00;
10'd248:span<=6'h00;
10'd249:span<=6'h00;
10'd250:span<=6'h00;
10'd251:span<=6'h00;
10'd252:span<=6'h00;
10'd253:span<=6'h00;
10'd254:span<=6'h00;
10'd255:span<=6'h00;
10'd256:span<=6'h27;
10'd257:span<=6'h27;
10'd258:span<=6'h27;
10'd259:span<=6'h27;
10'd260:span<=6'h26;
10'd261:span<=6'h25;
10'd262:span<=6'h24;
10'd263:span<=6'h23;
10'd264:span<=6'h00;
10'd265:span<=6'h00;
10'd266:span<=6'h00;
10'd267:span<=6'h00;
10'd268:span<=6'h00;
10'd269:span<=6'h00;
10'd270:span<=6'h00;
10'd271:span<=6'h00;
10'd272:span<=6'h00;
10'd273:span<=6'h00;
10'd274:span<=6'h00;
10'd275:span<=6'h00;
10'd276:span<=6'h00;
10'd277:span<=6'h00;
10'd278:span<=6'h00;
10'd279:span<=6'h00;
10'd280:span<=6'h00;
10'd281:span<=6'h00;
10'd282:span<=6'h00;
10'd283:span<=6'h00;
10'd284:span<=6'h00;
10'd285:span<=6'h00;
10'd286:span<=6'h00;
10'd287:span<=6'h00;
10'd288:span<=6'h28;
10'd289:span<=6'h28;
10'd290:span<=6'h28;
10'd291:span<=6'h28;
10'd292:span<=6'h27;
10'd293:span<=6'h26;
10'd294:span<=6'h25;
10'd295:span<=6'h24;
10'd296:span<=6'h23;
10'd297:span<=6'h00;
10'd298:span<=6'h00;
10'd299:span<=6'h00;
10'd300:span<=6'h00;
10'd301:span<=6'h00;
10'd302:span<=6'h00;
10'd303:span<=6'h00;
10'd304:span<=6'h00;
10'd305:span<=6'h00;
10'd306:span<=6'h00;
10'd307:span<=6'h00;
10'd308:span<=6'h00;
10'd309:span<=6'h00;
10'd310:span<=6'h00;
10'd311:span<=6'h00;
10'd312:span<=6'h00;
10'd313:span<=6'h00;
10'd314:span<=6'h00;
10'd315:span<=6'h00;
10'd316:span<=6'h00;
10'd317:span<=6'h00;
10'd318:span<=6'h00;
10'd319:span<=6'h00;
10'd320:span<=6'h29;
10'd321:span<=6'h29;
10'd322:span<=6'h29;
10'd323:span<=6'h29;
10'd324:span<=6'h28;
10'd325:span<=6'h27;
10'd326:span<=6'h26;
10'd327:span<=6'h25;
10'd328:span<=6'h24;
10'd329:span<=6'h23;
10'd330:span<=6'h00;
10'd331:span<=6'h00;
10'd332:span<=6'h00;
10'd333:span<=6'h00;
10'd334:span<=6'h00;
10'd335:span<=6'h00;
10'd336:span<=6'h00;
10'd337:span<=6'h00;
10'd338:span<=6'h00;
10'd339:span<=6'h00;
10'd340:span<=6'h00;
10'd341:span<=6'h00;
10'd342:span<=6'h00;
10'd343:span<=6'h00;
10'd344:span<=6'h00;
10'd345:span<=6'h00;
10'd346:span<=6'h00;
10'd347:span<=6'h00;
10'd348:span<=6'h00;
10'd349:span<=6'h00;
10'd350:span<=6'h00;
10'd351:span<=6'h00;
10'd352:span<=6'h2a;
10'd353:span<=6'h2a;
10'd354:span<=6'h2a;
10'd355:span<=6'h2a;
10'd356:span<=6'h29;
10'd357:span<=6'h28;
10'd358:span<=6'h27;
10'd359:span<=6'h26;
10'd360:span<=6'h25;
10'd361:span<=6'h24;
10'd362:span<=6'h23;
10'd363:span<=6'h00;
10'd364:span<=6'h00;
10'd365:span<=6'h00;
10'd366:span<=6'h00;
10'd367:span<=6'h00;
10'd368:span<=6'h00;
10'd369:span<=6'h00;
10'd370:span<=6'h00;
10'd371:span<=6'h00;
10'd372:span<=6'h00;
10'd373:span<=6'h00;
10'd374:span<=6'h00;
10'd375:span<=6'h00;
10'd376:span<=6'h00;
10'd377:span<=6'h00;
10'd378:span<=6'h00;
10'd379:span<=6'h00;
10'd380:span<=6'h00;
10'd381:span<=6'h00;
10'd382:span<=6'h00;
10'd383:span<=6'h00;
10'd384:span<=6'h2b;
10'd385:span<=6'h2b;
10'd386:span<=6'h2b;
10'd387:span<=6'h2b;
10'd388:span<=6'h2b;
10'd389:span<=6'h2a;
10'd390:span<=6'h29;
10'd391:span<=6'h28;
10'd392:span<=6'h27;
10'd393:span<=6'h26;
10'd394:span<=6'h25;
10'd395:span<=6'h24;
10'd396:span<=6'h00;
10'd397:span<=6'h00;
10'd398:span<=6'h00;
10'd399:span<=6'h00;
10'd400:span<=6'h00;
10'd401:span<=6'h00;
10'd402:span<=6'h00;
10'd403:span<=6'h00;
10'd404:span<=6'h00;
10'd405:span<=6'h00;
10'd406:span<=6'h00;
10'd407:span<=6'h00;
10'd408:span<=6'h00;
10'd409:span<=6'h00;
10'd410:span<=6'h00;
10'd411:span<=6'h00;
10'd412:span<=6'h00;
10'd413:span<=6'h00;
10'd414:span<=6'h00;
10'd415:span<=6'h00;
10'd416:span<=6'h2c;
10'd417:span<=6'h2c;
10'd418:span<=6'h2c;
10'd419:span<=6'h2c;
10'd420:span<=6'h2c;
10'd421:span<=6'h2b;
10'd422:span<=6'h2a;
10'd423:span<=6'h29;
10'd424:span<=6'h28;
10'd425:span<=6'h27;
10'd426:span<=6'h26;
10'd427:span<=6'h25;
10'd428:span<=6'h24;
10'd429:span<=6'h00;
10'd430:span<=6'h00;
10'd431:span<=6'h00;
10'd432:span<=6'h00;
10'd433:span<=6'h00;
10'd434:span<=6'h00;
10'd435:span<=6'h00;
10'd436:span<=6'h00;
10'd437:span<=6'h00;
10'd438:span<=6'h00;
10'd439:span<=6'h00;
10'd440:span<=6'h00;
10'd441:span<=6'h00;
10'd442:span<=6'h00;
10'd443:span<=6'h00;
10'd444:span<=6'h00;
10'd445:span<=6'h00;
10'd446:span<=6'h00;
10'd447:span<=6'h00;
10'd448:span<=6'h2d;
10'd449:span<=6'h2d;
10'd450:span<=6'h2d;
10'd451:span<=6'h2d;
10'd452:span<=6'h2d;
10'd453:span<=6'h2c;
10'd454:span<=6'h2b;
10'd455:span<=6'h2a;
10'd456:span<=6'h29;
10'd457:span<=6'h28;
10'd458:span<=6'h27;
10'd459:span<=6'h26;
10'd460:span<=6'h25;
10'd461:span<=6'h24;
10'd462:span<=6'h00;
10'd463:span<=6'h00;
10'd464:span<=6'h00;
10'd465:span<=6'h00;
10'd466:span<=6'h00;
10'd467:span<=6'h00;
10'd468:span<=6'h00;
10'd469:span<=6'h00;
10'd470:span<=6'h00;
10'd471:span<=6'h00;
10'd472:span<=6'h00;
10'd473:span<=6'h00;
10'd474:span<=6'h00;
10'd475:span<=6'h00;
10'd476:span<=6'h00;
10'd477:span<=6'h00;
10'd478:span<=6'h00;
10'd479:span<=6'h00;
10'd480:span<=6'h2e;
10'd481:span<=6'h2e;
10'd482:span<=6'h2e;
10'd483:span<=6'h2e;
10'd484:span<=6'h2e;
10'd485:span<=6'h2d;
10'd486:span<=6'h2c;
10'd487:span<=6'h2b;
10'd488:span<=6'h2a;
10'd489:span<=6'h29;
10'd490:span<=6'h28;
10'd491:span<=6'h27;
10'd492:span<=6'h26;
10'd493:span<=6'h25;
10'd494:span<=6'h24;
10'd495:span<=6'h00;
10'd496:span<=6'h00;
10'd497:span<=6'h00;
10'd498:span<=6'h00;
10'd499:span<=6'h00;
10'd500:span<=6'h00;
10'd501:span<=6'h00;
10'd502:span<=6'h00;
10'd503:span<=6'h00;
10'd504:span<=6'h00;
10'd505:span<=6'h00;
10'd506:span<=6'h00;
10'd507:span<=6'h00;
10'd508:span<=6'h00;
10'd509:span<=6'h00;
10'd510:span<=6'h00;
10'd511:span<=6'h00;
10'd512:span<=6'h2f;
10'd513:span<=6'h2f;
10'd514:span<=6'h2f;
10'd515:span<=6'h2f;
10'd516:span<=6'h2f;
10'd517:span<=6'h2f;
10'd518:span<=6'h2e;
10'd519:span<=6'h2e;
10'd520:span<=6'h2d;
10'd521:span<=6'h2c;
10'd522:span<=6'h2b;
10'd523:span<=6'h2a;
10'd524:span<=6'h29;
10'd525:span<=6'h28;
10'd526:span<=6'h27;
10'd527:span<=6'h25;
10'd528:span<=6'h00;
10'd529:span<=6'h00;
10'd530:span<=6'h00;
10'd531:span<=6'h00;
10'd532:span<=6'h00;
10'd533:span<=6'h00;
10'd534:span<=6'h00;
10'd535:span<=6'h00;
10'd536:span<=6'h00;
10'd537:span<=6'h00;
10'd538:span<=6'h00;
10'd539:span<=6'h00;
10'd540:span<=6'h00;
10'd541:span<=6'h00;
10'd542:span<=6'h00;
10'd543:span<=6'h00;
10'd544:span<=6'h30;
10'd545:span<=6'h30;
10'd546:span<=6'h30;
10'd547:span<=6'h30;
10'd548:span<=6'h30;
10'd549:span<=6'h30;
10'd550:span<=6'h2f;
10'd551:span<=6'h2f;
10'd552:span<=6'h2e;
10'd553:span<=6'h2d;
10'd554:span<=6'h2c;
10'd555:span<=6'h2b;
10'd556:span<=6'h2a;
10'd557:span<=6'h29;
10'd558:span<=6'h28;
10'd559:span<=6'h27;
10'd560:span<=6'h25;
10'd561:span<=6'h00;
10'd562:span<=6'h00;
10'd563:span<=6'h00;
10'd564:span<=6'h00;
10'd565:span<=6'h00;
10'd566:span<=6'h00;
10'd567:span<=6'h00;
10'd568:span<=6'h00;
10'd569:span<=6'h00;
10'd570:span<=6'h00;
10'd571:span<=6'h00;
10'd572:span<=6'h00;
10'd573:span<=6'h00;
10'd574:span<=6'h00;
10'd575:span<=6'h00;
10'd576:span<=6'h31;
10'd577:span<=6'h31;
10'd578:span<=6'h31;
10'd579:span<=6'h31;
10'd580:span<=6'h31;
10'd581:span<=6'h31;
10'd582:span<=6'h30;
10'd583:span<=6'h30;
10'd584:span<=6'h2f;
10'd585:span<=6'h2e;
10'd586:span<=6'h2d;
10'd587:span<=6'h2c;
10'd588:span<=6'h2b;
10'd589:span<=6'h2a;
10'd590:span<=6'h29;
10'd591:span<=6'h28;
10'd592:span<=6'h27;
10'd593:span<=6'h25;
10'd594:span<=6'h00;
10'd595:span<=6'h00;
10'd596:span<=6'h00;
10'd597:span<=6'h00;
10'd598:span<=6'h00;
10'd599:span<=6'h00;
10'd600:span<=6'h00;
10'd601:span<=6'h00;
10'd602:span<=6'h00;
10'd603:span<=6'h00;
10'd604:span<=6'h00;
10'd605:span<=6'h00;
10'd606:span<=6'h00;
10'd607:span<=6'h00;
10'd608:span<=6'h32;
10'd609:span<=6'h32;
10'd610:span<=6'h32;
10'd611:span<=6'h32;
10'd612:span<=6'h32;
10'd613:span<=6'h32;
10'd614:span<=6'h31;
10'd615:span<=6'h31;
10'd616:span<=6'h30;
10'd617:span<=6'h2f;
10'd618:span<=6'h2e;
10'd619:span<=6'h2d;
10'd620:span<=6'h2c;
10'd621:span<=6'h2b;
10'd622:span<=6'h2a;
10'd623:span<=6'h29;
10'd624:span<=6'h28;
10'd625:span<=6'h27;
10'd626:span<=6'h25;
10'd627:span<=6'h00;
10'd628:span<=6'h00;
10'd629:span<=6'h00;
10'd630:span<=6'h00;
10'd631:span<=6'h00;
10'd632:span<=6'h00;
10'd633:span<=6'h00;
10'd634:span<=6'h00;
10'd635:span<=6'h00;
10'd636:span<=6'h00;
10'd637:span<=6'h00;
10'd638:span<=6'h00;
10'd639:span<=6'h00;
10'd640:span<=6'h33;
10'd641:span<=6'h33;
10'd642:span<=6'h33;
10'd643:span<=6'h33;
10'd644:span<=6'h33;
10'd645:span<=6'h33;
10'd646:span<=6'h32;
10'd647:span<=6'h32;
10'd648:span<=6'h32;
10'd649:span<=6'h31;
10'd650:span<=6'h30;
10'd651:span<=6'h2f;
10'd652:span<=6'h2e;
10'd653:span<=6'h2d;
10'd654:span<=6'h2c;
10'd655:span<=6'h2b;
10'd656:span<=6'h2a;
10'd657:span<=6'h29;
10'd658:span<=6'h28;
10'd659:span<=6'h25;
10'd660:span<=6'h00;
10'd661:span<=6'h00;
10'd662:span<=6'h00;
10'd663:span<=6'h00;
10'd664:span<=6'h00;
10'd665:span<=6'h00;
10'd666:span<=6'h00;
10'd667:span<=6'h00;
10'd668:span<=6'h00;
10'd669:span<=6'h00;
10'd670:span<=6'h00;
10'd671:span<=6'h00;
10'd672:span<=6'h34;
10'd673:span<=6'h34;
10'd674:span<=6'h34;
10'd675:span<=6'h34;
10'd676:span<=6'h34;
10'd677:span<=6'h34;
10'd678:span<=6'h33;
10'd679:span<=6'h33;
10'd680:span<=6'h33;
10'd681:span<=6'h32;
10'd682:span<=6'h31;
10'd683:span<=6'h30;
10'd684:span<=6'h2f;
10'd685:span<=6'h2e;
10'd686:span<=6'h2d;
10'd687:span<=6'h2c;
10'd688:span<=6'h2b;
10'd689:span<=6'h2a;
10'd690:span<=6'h29;
10'd691:span<=6'h28;
10'd692:span<=6'h25;
10'd693:span<=6'h00;
10'd694:span<=6'h00;
10'd695:span<=6'h00;
10'd696:span<=6'h00;
10'd697:span<=6'h00;
10'd698:span<=6'h00;
10'd699:span<=6'h00;
10'd700:span<=6'h00;
10'd701:span<=6'h00;
10'd702:span<=6'h00;
10'd703:span<=6'h00;
10'd704:span<=6'h35;
10'd705:span<=6'h35;
10'd706:span<=6'h35;
10'd707:span<=6'h35;
10'd708:span<=6'h35;
10'd709:span<=6'h35;
10'd710:span<=6'h34;
10'd711:span<=6'h34;
10'd712:span<=6'h34;
10'd713:span<=6'h33;
10'd714:span<=6'h32;
10'd715:span<=6'h31;
10'd716:span<=6'h30;
10'd717:span<=6'h2f;
10'd718:span<=6'h2e;
10'd719:span<=6'h2d;
10'd720:span<=6'h2c;
10'd721:span<=6'h2b;
10'd722:span<=6'h2a;
10'd723:span<=6'h29;
10'd724:span<=6'h28;
10'd725:span<=6'h25;
10'd726:span<=6'h00;
10'd727:span<=6'h00;
10'd728:span<=6'h00;
10'd729:span<=6'h00;
10'd730:span<=6'h00;
10'd731:span<=6'h00;
10'd732:span<=6'h00;
10'd733:span<=6'h00;
10'd734:span<=6'h00;
10'd735:span<=6'h00;
10'd736:span<=6'h36;
10'd737:span<=6'h36;
10'd738:span<=6'h36;
10'd739:span<=6'h36;
10'd740:span<=6'h36;
10'd741:span<=6'h36;
10'd742:span<=6'h35;
10'd743:span<=6'h35;
10'd744:span<=6'h35;
10'd745:span<=6'h34;
10'd746:span<=6'h33;
10'd747:span<=6'h32;
10'd748:span<=6'h31;
10'd749:span<=6'h30;
10'd750:span<=6'h2f;
10'd751:span<=6'h2e;
10'd752:span<=6'h2d;
10'd753:span<=6'h2c;
10'd754:span<=6'h2b;
10'd755:span<=6'h2a;
10'd756:span<=6'h29;
10'd757:span<=6'h28;
10'd758:span<=6'h25;
10'd759:span<=6'h00;
10'd760:span<=6'h00;
10'd761:span<=6'h00;
10'd762:span<=6'h00;
10'd763:span<=6'h00;
10'd764:span<=6'h00;
10'd765:span<=6'h00;
10'd766:span<=6'h00;
10'd767:span<=6'h00;
10'd768:span<=6'h37;
10'd769:span<=6'h37;
10'd770:span<=6'h37;
10'd771:span<=6'h37;
10'd772:span<=6'h37;
10'd773:span<=6'h37;
10'd774:span<=6'h37;
10'd775:span<=6'h36;
10'd776:span<=6'h36;
10'd777:span<=6'h36;
10'd778:span<=6'h35;
10'd779:span<=6'h35;
10'd780:span<=6'h34;
10'd781:span<=6'h33;
10'd782:span<=6'h32;
10'd783:span<=6'h31;
10'd784:span<=6'h30;
10'd785:span<=6'h2f;
10'd786:span<=6'h2e;
10'd787:span<=6'h2d;
10'd788:span<=6'h2c;
10'd789:span<=6'h2b;
10'd790:span<=6'h29;
10'd791:span<=6'h26;
10'd792:span<=6'h00;
10'd793:span<=6'h00;
10'd794:span<=6'h00;
10'd795:span<=6'h00;
10'd796:span<=6'h00;
10'd797:span<=6'h00;
10'd798:span<=6'h00;
10'd799:span<=6'h00;
10'd800:span<=6'h38;
10'd801:span<=6'h38;
10'd802:span<=6'h38;
10'd803:span<=6'h38;
10'd804:span<=6'h38;
10'd805:span<=6'h38;
10'd806:span<=6'h38;
10'd807:span<=6'h37;
10'd808:span<=6'h37;
10'd809:span<=6'h37;
10'd810:span<=6'h36;
10'd811:span<=6'h36;
10'd812:span<=6'h35;
10'd813:span<=6'h34;
10'd814:span<=6'h33;
10'd815:span<=6'h32;
10'd816:span<=6'h31;
10'd817:span<=6'h30;
10'd818:span<=6'h2f;
10'd819:span<=6'h2e;
10'd820:span<=6'h2d;
10'd821:span<=6'h2c;
10'd822:span<=6'h2b;
10'd823:span<=6'h29;
10'd824:span<=6'h26;
10'd825:span<=6'h00;
10'd826:span<=6'h00;
10'd827:span<=6'h00;
10'd828:span<=6'h00;
10'd829:span<=6'h00;
10'd830:span<=6'h00;
10'd831:span<=6'h00;
10'd832:span<=6'h39;
10'd833:span<=6'h39;
10'd834:span<=6'h39;
10'd835:span<=6'h39;
10'd836:span<=6'h39;
10'd837:span<=6'h39;
10'd838:span<=6'h39;
10'd839:span<=6'h38;
10'd840:span<=6'h38;
10'd841:span<=6'h38;
10'd842:span<=6'h37;
10'd843:span<=6'h37;
10'd844:span<=6'h36;
10'd845:span<=6'h35;
10'd846:span<=6'h34;
10'd847:span<=6'h33;
10'd848:span<=6'h32;
10'd849:span<=6'h31;
10'd850:span<=6'h30;
10'd851:span<=6'h2f;
10'd852:span<=6'h2e;
10'd853:span<=6'h2d;
10'd854:span<=6'h2c;
10'd855:span<=6'h2b;
10'd856:span<=6'h29;
10'd857:span<=6'h26;
10'd858:span<=6'h00;
10'd859:span<=6'h00;
10'd860:span<=6'h00;
10'd861:span<=6'h00;
10'd862:span<=6'h00;
10'd863:span<=6'h00;
10'd864:span<=6'h3a;
10'd865:span<=6'h3a;
10'd866:span<=6'h3a;
10'd867:span<=6'h3a;
10'd868:span<=6'h3a;
10'd869:span<=6'h3a;
10'd870:span<=6'h3a;
10'd871:span<=6'h39;
10'd872:span<=6'h39;
10'd873:span<=6'h39;
10'd874:span<=6'h38;
10'd875:span<=6'h38;
10'd876:span<=6'h37;
10'd877:span<=6'h36;
10'd878:span<=6'h35;
10'd879:span<=6'h34;
10'd880:span<=6'h33;
10'd881:span<=6'h32;
10'd882:span<=6'h31;
10'd883:span<=6'h30;
10'd884:span<=6'h2f;
10'd885:span<=6'h2e;
10'd886:span<=6'h2d;
10'd887:span<=6'h2c;
10'd888:span<=6'h2b;
10'd889:span<=6'h29;
10'd890:span<=6'h26;
10'd891:span<=6'h00;
10'd892:span<=6'h00;
10'd893:span<=6'h00;
10'd894:span<=6'h00;
10'd895:span<=6'h00;
10'd896:span<=6'h3b;
10'd897:span<=6'h3b;
10'd898:span<=6'h3b;
10'd899:span<=6'h3b;
10'd900:span<=6'h3b;
10'd901:span<=6'h3b;
10'd902:span<=6'h3b;
10'd903:span<=6'h3a;
10'd904:span<=6'h3a;
10'd905:span<=6'h3a;
10'd906:span<=6'h3a;
10'd907:span<=6'h39;
10'd908:span<=6'h39;
10'd909:span<=6'h38;
10'd910:span<=6'h37;
10'd911:span<=6'h36;
10'd912:span<=6'h35;
10'd913:span<=6'h34;
10'd914:span<=6'h33;
10'd915:span<=6'h32;
10'd916:span<=6'h31;
10'd917:span<=6'h30;
10'd918:span<=6'h2f;
10'd919:span<=6'h2e;
10'd920:span<=6'h2d;
10'd921:span<=6'h2c;
10'd922:span<=6'h2a;
10'd923:span<=6'h26;
10'd924:span<=6'h00;
10'd925:span<=6'h00;
10'd926:span<=6'h00;
10'd927:span<=6'h00;
10'd928:span<=6'h3c;
10'd929:span<=6'h3c;
10'd930:span<=6'h3c;
10'd931:span<=6'h3c;
10'd932:span<=6'h3c;
10'd933:span<=6'h3c;
10'd934:span<=6'h3c;
10'd935:span<=6'h3b;
10'd936:span<=6'h3b;
10'd937:span<=6'h3b;
10'd938:span<=6'h3b;
10'd939:span<=6'h3a;
10'd940:span<=6'h3a;
10'd941:span<=6'h39;
10'd942:span<=6'h38;
10'd943:span<=6'h37;
10'd944:span<=6'h36;
10'd945:span<=6'h35;
10'd946:span<=6'h34;
10'd947:span<=6'h33;
10'd948:span<=6'h32;
10'd949:span<=6'h31;
10'd950:span<=6'h30;
10'd951:span<=6'h2f;
10'd952:span<=6'h2e;
10'd953:span<=6'h2d;
10'd954:span<=6'h2c;
10'd955:span<=6'h2a;
10'd956:span<=6'h26;
10'd957:span<=6'h00;
10'd958:span<=6'h00;
10'd959:span<=6'h00;
10'd960:span<=6'h3d;
10'd961:span<=6'h3d;
10'd962:span<=6'h3d;
10'd963:span<=6'h3d;
10'd964:span<=6'h3d;
10'd965:span<=6'h3d;
10'd966:span<=6'h3d;
10'd967:span<=6'h3c;
10'd968:span<=6'h3c;
10'd969:span<=6'h3c;
10'd970:span<=6'h3c;
10'd971:span<=6'h3b;
10'd972:span<=6'h3b;
10'd973:span<=6'h3a;
10'd974:span<=6'h39;
10'd975:span<=6'h38;
10'd976:span<=6'h37;
10'd977:span<=6'h36;
10'd978:span<=6'h35;
10'd979:span<=6'h34;
10'd980:span<=6'h33;
10'd981:span<=6'h32;
10'd982:span<=6'h31;
10'd983:span<=6'h30;
10'd984:span<=6'h2f;
10'd985:span<=6'h2e;
10'd986:span<=6'h2d;
10'd987:span<=6'h2c;
10'd988:span<=6'h2a;
10'd989:span<=6'h26;
10'd990:span<=6'h00;
10'd991:span<=6'h00;
10'd992:span<=6'h3e;
10'd993:span<=6'h3e;
10'd994:span<=6'h3e;
10'd995:span<=6'h3e;
10'd996:span<=6'h3e;
10'd997:span<=6'h3e;
10'd998:span<=6'h3e;
10'd999:span<=6'h3d;
10'd1000:span<=6'h3d;
10'd1001:span<=6'h3d;
10'd1002:span<=6'h3d;
10'd1003:span<=6'h3c;
10'd1004:span<=6'h3c;
10'd1005:span<=6'h3b;
10'd1006:span<=6'h3a;
10'd1007:span<=6'h39;
10'd1008:span<=6'h38;
10'd1009:span<=6'h37;
10'd1010:span<=6'h36;
10'd1011:span<=6'h35;
10'd1012:span<=6'h34;
10'd1013:span<=6'h33;
10'd1014:span<=6'h32;
10'd1015:span<=6'h31;
10'd1016:span<=6'h30;
10'd1017:span<=6'h2f;
10'd1018:span<=6'h2e;
10'd1019:span<=6'h2d;
10'd1020:span<=6'h2c;
10'd1021:span<=6'h2a;
10'd1022:span<=6'h26;
10'd1023:span<=6'h00;
default:span<=0;endcase end endmodule


`default_nettype wire
