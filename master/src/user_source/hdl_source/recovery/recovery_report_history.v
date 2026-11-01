`default_nettype none
`timescale 1ns/1ps
// B retains 32 immutable raw records in one shared session pool.
// Type-local indices and trend points are prepared on B, never on the pixel path.
// Gallery [737:736] identifies the frozen type (1 PACU, 2 ward).
// Gallery cards use B-prepared summary fields; detail slots are raw records.
// No summary encoding is ever written to raw report RAM. Raw RAM,
// reaction/hold times, validity, outcomes and all original business fields stay.
// Trend read address[6] selects PACU; low bits select the retained type ordinal.
module recovery_report_history #(parameter integer HISTORY_DEPTH=32)(
 input wire clk,rst,enable,left_event,right_event,select_event,capture,input wire clear_commit,
 output wire capture_ready,
 input wire [1:0] view_mode,input wire [159:0] report_status,input wire [23:0] capture_time_bcd,
 output wire [7:0] report_count,output wire full,
 output wire [6:0] selected_index,output reg detail_mode,
 output wire [799:0] gallery_payload,
 input wire pixel_clk,input wire [6:0] trend_read_address,output reg [7:0] trend_read_point
);

localparam integer AB=HISTORY_DEPTH<=1?1:$clog2(HISTORY_DEPTH);
localparam integer CB=$clog2(HISTORY_DEPTH+1);
reg [183:0] report_ram[0:HISTORY_DEPTH-1];
reg [AB-1:0] type_index_ram[0:2*HISTORY_DEPTH-1];
(* ram_style="bram" *) reg [7:0] type_trend_ram[0:511];
reg [CB-1:0] total_count,pacu_count,ward_count;
reg [AB-1:0] write_pointer,oldest_pointer,scan_pointer;
reg [CB-1:0] rebuild_index,rebuild_pacu,rebuild_ward;
reg [1:0] rebuild_phase;
reg rebuilding;
reg rebuild_is_pacu;
reg [7:0] rebuild_trend;
reg [AB:0] rebuild_address;
reg [183:0] history_read;
wire [183:0] rebuild_record;
wire [183:0] raw_q;
reg [AB-1:0] selected_q;
reg [1:0] held_mode;
reg prev_enable,trend_mode;
reg [7:0] latest_pacu,latest_ward;
wire [1:0] requested_mode;
wire [CB-1:0] type_count;
wire [CB-1:0] capture_type_count;
wire capture_pacu;
wire clearing;
wire save;
wire [2:0] pacu_total;
wire pacu_complete;
wire ward_complete;
wire [6:0] pacu_scaled;
wire [2:0] rebuild_total;
wire [6:0] rebuild_scaled;
reg [4:0] build_step;
reg [1:0] build_card;
reg [15:0] rt_shift,hold_shift;
reg [19:0] rt_work,hold_work,rt_digits,hold_digits;
reg [31:0] build_meta;
reg [7:0] build_count,build_latest;
reg [AB-1:0] index_q;
reg [183:0] slot0,slot1,slot2,slot3;
reg [799:0] gallery_data;
reg gallery_available;
wire [6:0] page_base;
wire [3:0] current_valid;
wire build_valid;
wire [6:0] build_ordinal;
wire [AB:0] index_address;
// Continuous values retain the original net initializer expressions.
assign rebuild_record = history_read;
assign raw_q = history_read;
assign requested_mode = view_mode==1?2'd1:view_mode==2?2'd2:held_mode;
assign type_count = requested_mode==1?pacu_count:ward_count;
assign capture_type_count = report_status[158:157]==1?pacu_count:ward_count;
assign capture_pacu = report_status[158:157]==1;
assign clearing = clear_commit===1'b1;
assign save = capture&&capture_ready&&report_status[159]&&
  (report_status[158:157]==1||report_status[158:157]==2);
assign pacu_total = {1'b0,report_status[70:69]}+{1'b0,report_status[68:67]};
assign pacu_complete = &report_status[72:71]&&report_status[142:140]==1;
assign ward_complete = &report_status[19:14]&&report_status[142:140]==1;
assign pacu_scaled = pacu_total>=4?7'd100:
  ({4'd0,pacu_total}<<4)+({4'd0,pacu_total}<<3)+{4'd0,pacu_total};
assign rebuild_total = {1'b0,rebuild_record[70:69]}+{1'b0,rebuild_record[68:67]};
assign rebuild_scaled = rebuild_total>=4?7'd100:({4'd0,rebuild_total}<<4)+({4'd0,rebuild_total}<<3)+{4'd0,rebuild_total};
assign page_base = {selected_index[6:2],2'b00};
assign current_valid = {
  ({2'd0,page_base}+9'd3)<type_count,({2'd0,page_base}+9'd2)<type_count,
  ({2'd0,page_base}+9'd1)<type_count,{2'd0,page_base}<type_count};
assign build_valid = build_meta[25+build_card];
assign build_ordinal = {build_meta[16:12],build_card};
assign index_address = (build_meta[1:0]==1?HISTORY_DEPTH:0)+
  (build_valid?build_ordinal:7'd0);

 
 
  /* fehdl force_ram=1, ram_style="bram" */
  /* fehdl force_ram=1, ram_style="bram" */
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 assign capture_ready=!rebuilding&&!clearing;
 
 
 
 
 
 assign report_count=total_count;
 assign selected_index=selected_q;
 assign full=total_count>=HISTORY_DEPTH;
 function [11:0] bcd8;input [7:0] value;reg [11:0] a;integer i,k;begin
  a=0;for(i=7;i>=0;i=i-1)begin
   for(k=0;k<3;k=k+1)if(a[k*4+:4]>=5)a[k*4+:4]=a[k*4+:4]+4'd3;
   a={a[10:0],value[i]};
  end bcd8=a;
 end endfunction
 function [19:0] bcd_step;input [19:0] value;input bit_in;reg [19:0] a;integer k;begin
  a=value;for(k=0;k<5;k=k+1)if(value[k*4+:4]>=5)a[k*4+:4]=value[k*4+:4]+4'd3;
  bcd_step={a[18:0],bit_in};
 end endfunction
 function [5:0] pending;input visited;input [2:0] outcome;begin
  if(!visited)pending=24;else case(outcome)2:pending=25;3:pending=26;4:pending=27;default:pending=24;endcase
 end endfunction
 function [183:0] displayed_copy;input [183:0] raw;input [6:0] ordinal;input [19:0] reaction_bcd,hold_bcd;
  reg [183:0] d;reg [5:0] valid,started;reg [2:0] outcome,rs,hs,pain;
  reg [1:0] pv;reg [2:0] p;integer k;
 begin
  d=0;d[183:157]=raw[183:157];
  valid=raw[19:14];started=raw[148:143];outcome=raw[142:140];
  rs=raw[44:42];hs=raw[25:23];pain=raw[22:20];pv=raw[72:71];
  p={1'b0,raw[70:69]}+{1'b0,raw[68:67]};
  d[68:49]=reaction_bcd;d[88:69]=hold_bcd;
  d[100:89]=bcd8({1'b0,raw[121:115]});
  d[136:125]=bcd8({1'b0,ordinal}+8'd1);
  d[142:137]=hs==7?6'd27:hs==2?6'd55:6'd38;
  for(k=0;k<4;k=k+1)d[117+k*2+:2]=!raw[86+k]?2'd0:raw[90+k]?2'd2:2'd1;
  if(raw[158:157]==1)begin
   d[5:0]=pending(started[0],outcome);d[11:6]=pending(started[1],outcome);
   d[17:12]=pending(started[1],outcome);d[29:24]=pending(|started[1:0],outcome);
   d[42]=pv[0];d[43]=pv[1];d[44]=&raw[89:86];d[46]=(&pv)&&outcome==1;
   d[104:101]={2'd0,raw[70:69]};d[108:105]={2'd0,raw[68:67]};
   d[112:109]={1'b0,raw[96:94]};d[116:113]={1'b0,p};
  end else begin
   d[5:0]=raw[135:134]!=0?6'd25:pending(started[0],outcome);
   d[11:6]=raw[133:132]!=0?6'd25:pending(started[1],outcome);
   d[17:12]=!valid[2]?pending(started[2],outcome):raw[62:61]==1?6'd28:raw[62:61]==2?6'd29:raw[62:61]==3?6'd25:6'd30;
   d[23:18]=rs==0?pending(started[3],outcome):rs==2?6'd34:rs==5?6'd25:rs==6?6'd26:6'd30;
   d[29:24]=hs==0?pending(started[4],outcome):hs==3?6'd34:hs==5?6'd25:hs==6?6'd26:hs==7?6'd27:6'd30;
   d[35:30]=valid[5]?(pain==1?6'd31:pain==2?6'd32:pain==3?6'd33:6'd35):
    pain==5?6'd25:pain==6?6'd26:pain==7?6'd27:pending(started[5],outcome);
   d[41:36]=pending(|started,outcome);
   d[42]=valid[0];d[43]=valid[1];d[45]=valid[3]&&rs==1;
   d[46]=((hs==1||hs==2)&&valid[4])||hs==7;d[48]=raw[122]&&(&valid)&&outcome==1;
   d[104:101]={2'd0,raw[66:65]};d[108:105]={2'd0,raw[64:63]};
  end
  displayed_copy=d;
 end endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin total_count<=0;pacu_count<=0;ward_count<=0;selected_q<=0;
   write_pointer<=0;oldest_pointer<=0;scan_pointer<=0;
   rebuild_index<=0;rebuild_pacu<=0;rebuild_ward<=0;rebuild_phase<=0;rebuilding<=0;rebuild_is_pacu<=0;rebuild_trend<=0;rebuild_address<=0;
   detail_mode<=0;trend_mode<=0;prev_enable<=0;held_mode<=2;
   latest_pacu<=0;latest_ward<=0;
  end else begin
   prev_enable<=enable;
   if(clearing)begin total_count<=0;pacu_count<=0;ward_count<=0;selected_q<=0;detail_mode<=0;trend_mode<=0;
    write_pointer<=0;oldest_pointer<=0;rebuilding<=0;rebuild_phase<=0;latest_pacu<=0;latest_ward<=0;
   end else if(save)begin
    if(total_count<HISTORY_DEPTH)total_count<=total_count+1'b1;
    else oldest_pointer<=oldest_pointer==HISTORY_DEPTH-1?0:oldest_pointer+1'b1;
    write_pointer<=write_pointer==HISTORY_DEPTH-1?0:write_pointer+1'b1;
    scan_pointer<=total_count>=HISTORY_DEPTH?(oldest_pointer==HISTORY_DEPTH-1?0:oldest_pointer+1'b1):oldest_pointer;
    rebuilding<=1;rebuild_index<=0;rebuild_pacu<=0;rebuild_ward<=0;rebuild_phase<=0;
   end else if(rebuilding)begin
    if(rebuild_phase==0)rebuild_phase<=1;
    else if(rebuild_phase==1)begin
     rebuild_phase<=2;rebuild_is_pacu<=rebuild_record[158:157]==1;
     rebuild_address<={rebuild_record[158:157]==1,(rebuild_record[158:157]==1?rebuild_pacu[AB-1:0]:rebuild_ward[AB-1:0])};
     rebuild_trend<=rebuild_record[158:157]==1?
      {(&rebuild_record[72:71])&&rebuild_record[142:140]==1,rebuild_scaled}:
      {(&rebuild_record[19:14])&&rebuild_record[142:140]==1,rebuild_record[121:115]};
    end
    else begin
     rebuild_phase<=0;
     if(rebuild_is_pacu)begin
      rebuild_pacu<=rebuild_pacu+1'b1;
      latest_pacu<={rebuild_trend[7],4'd0,rebuild_total};
     end else begin rebuild_ward<=rebuild_ward+1'b1;
      latest_ward<=rebuild_trend;end
     if(rebuild_index+1>=total_count)begin
      pacu_count<=rebuild_pacu+rebuild_is_pacu;
      ward_count<=rebuild_ward+!rebuild_is_pacu;rebuilding<=0;
     end else begin rebuild_index<=rebuild_index+1'b1;scan_pointer<=scan_pointer==HISTORY_DEPTH-1?0:scan_pointer+1'b1;end
    end
   end
   held_mode<=requested_mode;
   if(clearing)begin selected_q<=0;detail_mode<=0;trend_mode<=0;end
   else if(!enable)begin detail_mode<=0;trend_mode<=0;end
   else if(!prev_enable||requested_mode!=held_mode)begin
    selected_q<=0;detail_mode<=0;trend_mode<=1;
   end else if(trend_mode)begin
    if(select_event||left_event||right_event)begin trend_mode<=0;detail_mode<=0;end
   end else if(type_count!=0)begin
    if(detail_mode)begin
     // In report detail KEY3 (right_event) means previous and KEY4
     // (left_event) means next. Clamp at the ends; do not change the global
     // patient left/right qualification in recovery_assessment.
     if(right_event&&!left_event)selected_q<=selected_q==0?0:selected_q-1'b1;
     else if(left_event&&!right_event)
      selected_q<=selected_q+1'b1>=type_count?type_count-1'b1:selected_q+1'b1;
    end else begin
     if(right_event&&!left_event)selected_q<=selected_q+1'b1>=type_count?0:selected_q+1'b1;
     else if(left_event&&!right_event)selected_q<=selected_q==0?type_count-1'b1:selected_q-1'b1;
    end
    if(select_event)detail_mode<=~detail_mode;
   end
  end
 end
 
 
 always @(posedge clk)begin
  if(!rst&&save)report_ram[write_pointer]<={capture_time_bcd,report_status};

  if(rebuilding&&rebuild_phase==2)begin
   type_index_ram[rebuild_address]<=scan_pointer;
   type_trend_ram[{{(8-AB){1'b0}},rebuild_address}]<=rebuild_trend;
  end
 end
 // B has one 100MHz application clock; top connects pixel_clk to clk.
 // Use the actual owner clock here to infer one native synchronous RAM.
 always @(posedge clk)
  trend_read_point<=type_trend_ram[{{(8-AB){1'b0}},trend_read_address[6],trend_read_address[AB-1:0]}];
 // Two native synchronous RAM reads per card. Metadata and type are held for
 // the entire build so a type switch never splices records from both stages.
 
 
 
 
 
 
 assign gallery_payload={gallery_data[799:768],gallery_available&&gallery_data[767],gallery_data[766:0]};
 
 
 
 
 
 always @(posedge clk)begin
  if(!rebuilding&&build_step==1)index_q<=type_index_ram[index_address];
  if((rebuilding&&rebuild_phase==0)||(!rebuilding&&build_step==2))
   history_read<=report_ram[rebuilding?scan_pointer:index_q];
 end
 // Unpublished card buffers and complete payload need no reset or
 // rebuild enable. The single availability bit invalidates them atomically.
 always @(posedge clk)begin
  if(build_step==20)begin
    case(build_card)
     0:slot0<=build_valid?(build_meta[30]?raw_q:displayed_copy(raw_q,build_ordinal,rt_digits,hold_digits)):184'd0;
     1:slot1<=build_valid?(build_meta[30]?raw_q:displayed_copy(raw_q,build_ordinal,rt_digits,hold_digits)):184'd0;
     2:slot2<=build_valid?(build_meta[30]?raw_q:displayed_copy(raw_q,build_ordinal,rt_digits,hold_digits)):184'd0;
     3:slot3<=build_valid?(build_meta[30]?raw_q:displayed_copy(raw_q,build_ordinal,rt_digits,hold_digits)):184'd0;
    endcase
   if(build_card==3)begin
     gallery_data<={bcd8({1'b0,build_latest[6:0]}),(bcd8(build_count)|(build_latest[7]?12'h100:12'h000)),build_count,build_meta,
      build_valid?(build_meta[30]?raw_q:displayed_copy(raw_q,build_ordinal,rt_digits,hold_digits)):184'd0,slot2,slot1,slot0};
   end
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin build_step<=0;build_card<=0;build_meta<=0;build_count<=0;
   build_latest<=0;rt_shift<=0;hold_shift<=0;rt_work<=0;hold_work<=0;rt_digits<=0;hold_digits<=0;gallery_available<=0;
  end else if(rebuilding||save||clearing)begin build_step<=0;gallery_available<=0;end else case(build_step)
   0:begin
    build_meta<={enable,detail_mode,full,current_valid,{(8-CB){1'b0}},type_count,
     page_base,selected_index,trend_mode,requested_mode};
    build_count<=type_count;build_latest<=requested_mode==1?latest_pacu:latest_ward;
    build_card<=0;build_step<=1;
   end
   1:build_step<=2;
   2:build_step<=3;
   3:begin
    rt_shift<=raw_q[60:45];hold_shift<=raw_q[41:26];rt_work<=0;hold_work<=0;
    build_step<=build_meta[30]?20:4;
   end
   4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19:begin
    rt_work<=bcd_step(rt_work,rt_shift[15]);hold_work<=bcd_step(hold_work,hold_shift[15]);
    rt_shift<={rt_shift[14:0],1'b0};hold_shift<={hold_shift[14:0],1'b0};
    if(build_step==19)begin rt_digits<=bcd_step(rt_work,rt_shift[15]);hold_digits<=bcd_step(hold_work,hold_shift[15]);end
    build_step<=build_step+1'b1;
   end
   20:begin
    if(build_card==3)begin
     // Last card is committed from its current RAM value, not old slot3.
     gallery_available<=1;
     build_step<=0;
    end else begin build_card<=build_card+1'b1;build_step<=1;end
   end
  endcase
 end
endmodule

`default_nettype wire
