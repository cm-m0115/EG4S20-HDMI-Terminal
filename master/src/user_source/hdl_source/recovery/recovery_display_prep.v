`default_nettype none
`timescale 1ns/1ps
// (M1/M2/M3) business display preparation on B.
// Registered low-rate preparation from held business inputs.
// Output union256 carries LIVE_UI or REPORT_TEXT and is
// latched by the master bridge with the same snapshot as status160.
//  M1: p clamped to 0..100, n=min(32,floor(p*32/100)) by threshold compare.
//  M2: business prompt id, target key and feedback class selection.

//  M3: per-row report status tokens.
module recovery_display_prep(
 input wire clk,rst,
 input wire [159:0] status,           // status160 (current report or selected history record)
 input wire report_ready,              // report snapshot valid for this view
 input wire [5:0] scene,input wire [1:0] question_set,
 input wire [23:0] practice,input wire [23:0] interaction,
 input wire caption_running,           // A media fact (voice active for the current transaction)
 input wire [5:0] ui_step,input wire [2:0] ui_teach_step,input wire ui_teach_panel,input wire [6:0] teach_percent,
 input wire green_cue,input wire ui_owner,
 input wire [1:0] feedback_kind,feedback_mask,input wire [5:0] feedback_seq,
 output reg [255:0] union_out
);

wire [6:0] p_raw;
wire [6:0] p;
reg [6:0] hint;
wire [1:0] target_key;
wire accept_priority;
reg [2:0] feedback_class;
wire [1:0] pp,pa,pv;
wire [1:0] t1u,t2u;
wire [5:0] valid,started;
wire [2:0] outcome,rs,hs,pain;
wire [1:0] t3;
wire [3:0] limb_valid;
wire [3:0] limb_ans;
wire [5:0] rscene;
wire ward;
reg [6:0] row [0:7];
integer r;
reg [7:0] numv;
reg [7:0] limb_class;
integer q;
wire report_view;
wire [5:0] teach_segments;
// Continuous values retain the original net initializer expressions.
assign p_raw = practice[23]?practice[10:4]:interaction[13:7];
assign p = p_raw>100?7'd100:p_raw;
assign target_key = interaction[1:0];
assign accept_priority = interaction[6]&&!interaction[2]&&!interaction[5]&&
  !(scene==17||scene==18||scene==19||scene==35||scene==36||scene==37||scene==44||scene==45||scene==46)&&
  status[7:0]==0&&status[85:78]!=60&&status[85:78]!=61&&scene!=7;
assign pp = status[70:69];
assign pa = status[68:67];
assign pv = status[72:71];
assign t1u = status[135:134];
assign t2u = status[133:132];
assign valid = status[19:14];
assign started = status[148:143];
assign outcome = status[142:140];
assign rs = status[44:42];
assign hs = status[25:23];
assign pain = status[22:20];
assign t3 = status[62:61];
assign limb_valid = status[89:86];
assign limb_ans = status[93:90];
assign rscene = status[13:8];
assign ward = status[158:157]==2;
assign report_view = scene==8||scene==22||scene==29||scene==30;
assign teach_segments = segments(teach_percent>100?7'd100:teach_percent);

 // ---------------- M1 ----------------
 
 
 // floor(p*32/100) >= k  <=>  p >= ceil(100k/32)
 function [5:0] segments;input [6:0] v;integer k;begin
  segments=0;for(k=1;k<=32;k=k+1)if(v>=(100*k+31)/32)segments=k;
 end endfunction
 // ---------------- M2 (priority identical to A requested_hint) -------
 
 always @*begin
  hint=caption_running?7'd64:7'd65;
  if(interaction[4])hint=66;
  if(practice[23])begin
   case(practice[21:19])0:hint=76;1:hint=77;2:hint=78;3:hint=79;4:hint=80;default:hint=81;endcase
   if(practice[18:16]==0)hint=67;
   if(practice[18:16]==2)hint=68;
   if(practice[18:16]==3)hint=69;
   if(practice[18:16]==4||practice[18:16]==7)hint=73;
   if(practice[18:16]==5)hint=71;
   if(practice[18:16]==6)hint=72;
  end
  if(interaction[2])hint=68;
  if(interaction[5])hint=interaction[3]?7'd69:7'd67;
  if(scene==17||scene==35||scene==44)hint=74;
  if(scene==18||scene==19||scene==36||scene==37||scene==45||scene==46)hint=75;
  if(status[7:0]!=0||status[85:78]==60||status[85:78]==61||scene==7)hint=72;
 end
 // A applies the 60-frame accepted-prompt lifetime (token 70) itself, keyed by
 // accept_seq, and then shows this B-selected successor hint.
 // Target selection belongs to B; A only performs the selected drawing.
 
 
 
 always @*begin
  feedback_class=0;
  if(interaction[6])feedback_class=1;
  if(interaction[2])feedback_class=5;
  if(interaction[5])feedback_class=6;
  if(practice[23]&&practice[18:16]==4)feedback_class=2;
  if(practice[23]&&practice[18:16]==5)feedback_class=3;
  if(practice[23]&&practice[18:16]==6)feedback_class=4;
 end
 // ---------------- M3 (A result OSD text classification) -------------
 
 
 
 
 
 
 function [6:0] pending_text;input visited;begin
  if(!visited)pending_text=7'd1;
  else case(outcome)2:pending_text=7'd2;3:pending_text=7'd3;4:pending_text=7'd4;default:pending_text=7'd1;endcase
 end endfunction
 
 always @*begin
  for(r=0;r<8;r=r+1)row[r]=7'd0;
  if(!report_ready)for(r=0;r<8;r=r+1)row[r]=7'd1;
  else if(!ward)begin
   if(pv[0])case(pp)2:row[0]=7'd6;1:row[0]=7'd7;default:row[0]=7'd8;endcase else row[0]=pending_text(started[0]);
   if(&limb_valid)row[1]=7'd9;else if(started[1]&&outcome==2)row[1]=7'd10;
   else if(started[1]&&outcome==3)row[1]=7'd11;else if(started[1]&&outcome==4)row[1]=7'd12;else row[1]=7'd13;
   if(&limb_valid)row[2]=7'd14;else row[2]=pending_text(started[1]);
   if(pv[1])row[3]=7'd15;else row[3]=pending_text(started[1]);
   if(&pv)row[4]=7'd16;else row[4]=pending_text(|started[1:0]);
  end else begin
   if(valid[0])row[0]=7'd17;else if(t1u!=0)row[0]=7'd18;else if(started[0]&&outcome==3)row[0]=7'd19;
   else if(started[0]&&outcome==4)row[0]=7'd20;else row[0]=7'd21;
   if(valid[1])row[1]=7'd17;else if(t2u!=0)row[1]=7'd18;else if(started[1]&&outcome==3)row[1]=7'd19;
   else if(started[1]&&outcome==4)row[1]=7'd20;else row[1]=7'd21;
   if(valid[2])case(t3)1:row[2]=7'd22;2:row[2]=7'd23;3:row[2]=7'd2;default:row[2]=7'd24;endcase
   else row[2]=pending_text(started[2]);
   case(rs)
    1:row[3]=valid[3]?7'd25:7'd26;2:row[3]=7'd27;3:row[3]=7'd28;4:row[3]=7'd26;5:row[3]=7'd29;6:row[3]=7'd30;
    default:if(!started[3])row[3]=7'd31;else case(outcome)2:row[3]=7'd27;3:row[3]=7'd29;4:row[3]=7'd30;default:row[3]=7'd31;endcase
   endcase
   case(hs)
    1:row[4]=valid[4]?7'd25:7'd26;2:row[4]=valid[4]?7'd32:7'd26;3:row[4]=7'd27;4:row[4]=7'd26;
    5:row[4]=7'd29;6:row[4]=7'd30;7:row[4]=7'd33;
    default:if(!started[4])row[4]=7'd31;else case(outcome)2:row[4]=7'd27;3:row[4]=7'd29;4:row[4]=7'd30;default:row[4]=7'd31;endcase
   endcase
   if(valid[5]&&pain>=1&&pain<=4)case(pain)1:row[5]=7'd36;2:row[5]=7'd37;3:row[5]=7'd38;default:row[5]=7'd39;endcase
   else case(pain)5:row[5]=7'd2;6:row[5]=7'd3;7:row[5]=7'd4;default:row[5]=pending_text(started[5]);endcase
   row[7]=status[122]?7'd34:7'd35;
  end
 end
 // Row number-valid bits (original digits drawn by A from the raw fields).
 
 always @*begin
  numv=0;
  if(report_ready)begin
   if(!ward)begin numv[2]=&limb_valid;numv[3]=pv[1];numv[4]=&pv;numv[1]=1'b1;end
   else begin
    numv[0]=valid[0]||(started[0]&&status[66:65]!=0);numv[1]=valid[1]||(started[1]&&status[64:63]!=0);
    numv[3]=rs==1&&valid[3];numv[4]=((hs==1||hs==2)&&valid[4])||hs==7;numv[7]=status[122];
    numv[5]=valid[5]&&pain>=1&&pain<=4;
   end
  end
 end
 
 always @*for(q=0;q<4;q=q+1)limb_class[q*2+:2]=!limb_valid[q]?2'd0:limb_ans[q]?2'd1:2'd2;
 function [7:0] hint_length;input [6:0] id;begin case(id)
 7'd64:hint_length=8'd12;
 7'd65:hint_length=8'd11;
 7'd66:hint_length=8'd11;
 7'd67:hint_length=8'd11;
 7'd68:hint_length=8'd10;
 7'd69:hint_length=8'd12;
 7'd70:hint_length=8'd9;
 7'd71:hint_length=8'd11;
 7'd72:hint_length=8'd10;
 7'd73:hint_length=8'd12;
 7'd74:hint_length=8'd10;
 7'd75:hint_length=8'd11;
 7'd76:hint_length=8'd11;
 7'd77:hint_length=8'd11;
 7'd78:hint_length=8'd12;
 7'd79:hint_length=8'd13;
 7'd80:hint_length=8'd11;
 7'd81:hint_length=8'd12;
 default:hint_length=0;endcase end endfunction
 
 
 always @(posedge clk or posedge rst)begin
  if(rst)union_out<=0;
  else begin
   union_out<=0;
   union_out[6:0]<=accept_priority?7'd70:hint;union_out[13:7]<=hint;
   if(report_view)begin
    union_out[20:14]<=row[0];union_out[27:21]<=row[1];union_out[34:28]<=row[2];union_out[41:35]<=row[3];
    union_out[48:42]<=row[4];union_out[55:49]<=row[5];union_out[62:56]<=row[6];union_out[69:63]<=row[7];
    union_out[77:70]<=numv;union_out[85:78]<=limb_class;union_out[86]<=report_ready;
   end else begin
    // semantic0x43 LIVE/TEACH fields. Feedback padding[79:74]
    // remains zero; REPORT_TEXT uses its original overlapping union layout.
    union_out[87:80]<=accept_priority?8'd9:hint_length(hint);
    union_out[95:88]<=hint_length(hint);
    union_out[15:14]<=target_key;union_out[18:16]<=feedback_class;
    union_out[24:19]<=segments(p);union_out[25]<=p==100;
    union_out[26]<=interaction[2]&&(interaction[0]||interaction[1]);
    union_out[27]<=interaction[0];union_out[28]<=interaction[1];
    union_out[35:29]<=teach_percent;union_out[36]<=ui_teach_panel;union_out[39:37]<=ui_teach_step;
    union_out[40]<=ui_owner;union_out[42]<=green_cue;
    union_out[50:43]<=interaction[21:14];
    union_out[51]<=accept_priority; // acceptance identity applies to hint70
    union_out[52]<=interaction[1]&&!interaction[0];
    union_out[53]<=scene==17||scene==18||scene==19||scene==35||scene==36||scene==37||scene==44||scene==45||scene==46;
    union_out[54]<=hint==67||hint==69||hint==71||hint==72;
    // Teaching bar has its own percent contract; B prepares its pixel width.
    union_out[63:55]<=({3'd0,teach_segments}<<4)-{3'd0,teach_segments};
    if(feedback_kind==1||feedback_kind==2)begin
     union_out[65:64]<=feedback_mask;union_out[67:66]<=feedback_kind;union_out[73:68]<=feedback_seq;
    end
   end
  end
 end
endmodule

`default_nettype wire
