`default_nettype none
`timescale 1ns/1ps
// one hold896/dst896, explicit bank copy and ACK.
// The 32-byte context holds only THIS bank's meta64/runtime-session56/envelope136.
// Body LSB-first: GALLERY slots736/meta64; TREND points256/meta64/status160;
// REPORT raw184/status160/meta64/text256/practice24/interaction24;
// LIVE/TEACH/SAFE status160/practice24/interaction24/ui256. Remaining bits zero.
module recovery_display_mailbox #(
 parameter integer CLK_HZ=100000000, INTERNAL_CYCLES=CLK_HZ/1000,
 ACK_CYCLES=CLK_HZ/20, BOOT_CYCLES=CLK_HZ/5
)(
 input wire src_clk,src_rst,input wire payload_valid,
 input wire [31:0] bank_session,input wire [15:0] bank_sequence,
 input wire [159:0] local_status,input wire [95:0] header,input wire kill,
 input wire capture_valid,input wire [15:0] capture_transaction,input wire [31:0] capture_key,
 output reg build_req,input wire build_grant,output reg [7:0] bank_addr,input wire [7:0] bank_data,
 output wire read_request,output wire read_locked,
 output wire src_settled,output reg build_done,output reg source_fault,output wire source_ready,
 output reg ack_event,output reg ack_report,ack_history,output reg [31:0] ack_report_key,
 output wire [31:0] ack_history_meta,output wire [31:0] display_token,
 output wire acknowledged_valid,output wire [15:0] acknowledged_transaction,acknowledged_identity,
 input wire dst_clk,dst_rst,frame_boundary,output reg [895:0] dst_data,output reg pixel_ui_valid
);

localparam [2:0] SAFE=0,LIVE=1,TEACH=2,GALLERY=3,TREND=4,REPORT=5;
localparam [3:0] IDLE=0,CTX_ADDR=1,CTX_STORE=2,CONTEXT=3,WAIT_REPORT=4,
   BODY_ADDR=5,BODY_STORE=6,PUBLISH=7,WAIT_ACK=8,ABORT=9,SAFE_INIT=10,BODY_PREP=11;
localparam integer IW=INTERNAL_CYCLES<2?1:$clog2(INTERNAL_CYCLES+1);
localparam integer AW=ACK_CYCLES<2?1:$clog2(ACK_CYCLES+1);
localparam integer BW=BOOT_CYCLES<2?1:$clog2(BOOT_CYCLES+1);
reg [3:0] state;
reg [6:0] index;
reg req,ack;
reg [895:0] hold_data;
(* ASYNC_REG="TRUE" *)reg ack1,ack2,req1,req2;
reg src_boot,dst_boot,src_boot_ack,dst_boot_ack;
(* ASYNC_REG="TRUE" *)reg db1,db2,sba1,sba2,sb1,sb2,dba1,dba2;
reg kill_req,kill_ack,kill_seen,pending_canceled;
(* ASYNC_REG="TRUE" *)reg ka1,ka2,k1,k2;
reg [4:0] flush_left;
wire boot_barrier;
reg [255:0] context_data;
wire [63:0] meta;
wire [55:0] session_runtime;
wire [135:0] env;
wire [2:0] kind;
wire historical;
wire current_report;
wire [15:0] transaction;
wire [23:0] interaction_raw;
wire accepted_matches;
wire button_scope;
wire [23:0] interaction_scoped;
reg [31:0] token_counter,pending_token,pending_key;
reg [31:0] pending_session;
reg [15:0] pending_sequence,pending_transaction,pending_cancel;
reg [31:0] report_metadata;
reg [69:0] report_fields;
reg [7:0] report_score;
reg local_safe,safe_published;
reg [7:0] safe_error;
reg [15:0] local_identity;
reg feedback_scope;
reg in_flight,ever_ready;
reg [IW-1:0] stall_count;
reg [AW-1:0] ack_count;
reg [BW-1:0] boot_count;
reg use_ram;
// index/kind decode ends at this descriptor register.
// index and pending bank identity stay held through PREP -> ADDR -> STORE.
reg descriptor_valid,descriptor_ram;
reg [7:0] descriptor_address,descriptor_local,descriptor_mask,descriptor_capture;
reg [7:0] body_local,source_address;
// extract local bytes at PREP, select the captured byte at ADDR.
// The immutable context and index remain held through both phases. RAM request
// descriptors still commit at PREP; local data is first consumed at STORE, so
// grant timing, publication, kill handling and public cycle latency stay exact.
reg [7:0] meta_local_q,report_metadata_q,practice_local_q,interaction_local_q;
wire [2:0] meta_byte;
wire [1:0] report_metadata_byte;
wire [1:0] practice_byte;
wire [1:0] interaction_byte;
wire [7:0] selected_base;
wire read_progress;
reg [7:0] report_mask;
reg [7:0] captured_byte;
wire [7:0] raw_body_byte;
wire [7:0] body_byte;
// Continuous values retain the original net initializer expressions.
assign boot_barrier = src_boot||sba2||db2||dst_boot_ack;
assign meta = context_data[63:0];
assign session_runtime = context_data[119:64];
assign env = context_data[255:120];
assign kind = meta[51:49];
assign historical = kind==REPORT&&meta[31]&&meta[30]&&!meta[2];
assign current_report = kind==REPORT&&!historical;
assign transaction = env[27:12];
assign interaction_raw = env[103:80];
assign accepted_matches = env[127:112]==transaction&&env[111:104]=={env[47:46],env[5:0]};
assign button_scope = env[71]||interaction_raw[2]||accepted_matches;
assign interaction_scoped = {interaction_raw[23:7],interaction_raw[6]&&accepted_matches,
   interaction_raw[5:2],interaction_raw[1]&&button_scope,interaction_raw[0]&&button_scope};
assign meta_byte = kind==REPORT?index[2:0]-3'd3:index[2:0];
assign report_metadata_byte = index[1:0]-2'd3;
assign practice_byte = index[1:0]-(kind==REPORT?2'd3:2'd0);
assign interaction_byte = index[1:0]-(kind==REPORT?2'd2:2'd3);
assign selected_base = meta[4:3]==0?8'd20:meta[4:3]==1?8'd43:meta[4:3]==2?8'd66:8'd89;
assign read_progress = state==CTX_STORE||state==BODY_PREP||state==BODY_STORE||
   (state==CTX_ADDR&&build_grant)||
   (state==BODY_ADDR&&descriptor_valid&&(!descriptor_ram||build_grant));
assign raw_body_byte = descriptor_ram?bank_data:descriptor_local;
assign body_byte = (raw_body_byte&~descriptor_mask)|(descriptor_capture&descriptor_mask);

 
 
 
 
 // Persistent reset notifications both ways: short unilateral pulses remain
 // asserted until acknowledged; req/ack baselines rebase behind this barrier.
 
 
 
 
 
 
 assign source_ready=!boot_barrier&&kill_req==ka2&&!kill;
 assign src_settled=state==IDLE&&req==ack2&&source_ready;
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 assign display_token=pending_token;
 // Source-owned payload remains held through the ACK pulse. These are local
 // wires, not another CDC bus or a copy of the 896-bit mailbox.
 assign acknowledged_valid=ack_event&&!pending_canceled&&!kill&&!local_safe;
 assign acknowledged_transaction=pending_transaction;
 assign acknowledged_identity=local_identity;
 assign ack_history_meta=hold_data[375:344];
 
 
 
 
 
 
 // Address accepted at *_ADDR; synchronous bank data sampled at *_STORE.
 always @*begin
  use_ram=0;body_local=0;source_address=0;
  if(local_safe)begin
   if(index==0)body_local=safe_error;
   else if(index==1)body_local={2'd0,env[5:0]};
  end else case(kind)
   GALLERY:begin use_ram=1;source_address=8'd20+index;end
   TREND:begin
    if(index<32)begin use_ram=1;source_address=8'd127+index;end
    else if(index<40)body_local=meta_local_q;
    else if(index<60)begin use_ram=1;source_address=index-8'd40;end
   end
   REPORT:begin
    if(index<23)begin use_ram=historical;source_address=selected_base+index;end
    else if(index<43)begin
     use_ram=1;source_address=(historical?selected_base:8'd0)+index-8'd23;
     if(current_report&&index>=39)begin use_ram=0;body_local=report_metadata_q;end
    end else if(index<51)body_local=meta_local_q;
    else if(index<83)begin use_ram=1;source_address=8'd127+index-8'd51;end
    else if(index<86)body_local=practice_local_q;
    else if(index<89)body_local=interaction_local_q;
   end
   default:begin
    if(index<20)begin use_ram=1;source_address=index;end
    else if(index<23)body_local=practice_local_q;
    else if(index<26)body_local=interaction_local_q;
    else if(index<58)begin use_ram=1;source_address=8'd127+index-8'd26;end
   end
  endcase
  if(state==CTX_ADDR)begin
   if(index<8)bank_addr=8'd112+index;
   else if(index<15)bank_addr=8'd120+index-8'd8;
   else bank_addr=8'd159+index-8'd15;
  end else bank_addr=descriptor_address;
 end
 
 // Only the immutable fields captured on A's cmd_accept edge replace raw
 // bank bytes. Ordinary state/countdown/scene bits remain from THIS bank.
 
 always @*begin
  report_mask=0;captured_byte=0;
  if(current_report&&index>=23&&index<43)begin
   case(index)
    24:begin report_mask=8'hc0;captured_byte={report_fields[1:0],6'd0};end
    25:begin report_mask=8'hff;captured_byte=report_fields[9:2];end
    26:begin report_mask=8'hff;captured_byte=report_fields[17:10];end
    27:begin report_mask=8'hff;captured_byte=report_fields[25:18];end
    28:begin report_mask=8'hff;captured_byte=report_fields[33:26];end
    29:begin report_mask=8'hff;captured_byte=report_fields[41:34];end
    30:begin report_mask=8'hff;captured_byte=report_fields[49:42];end
    31:begin report_mask=8'hff;captured_byte=report_fields[57:50];end
    32:begin report_mask=8'h01;captured_byte={7'd0,report_fields[58]};end
    33:begin report_mask=8'hc0;captured_byte={report_fields[60:59],6'd0};end
    34:begin report_mask=8'hff;captured_byte=report_fields[68:61];end
    35:begin report_mask=8'h01;captured_byte={7'd0,report_fields[69]};end
    37:begin report_mask=8'hf8;captured_byte={report_score[4:0],3'd0};end
    38:begin report_mask=8'h07;captured_byte={5'd0,report_score[7:5]};end
    default:report_mask=0;
   endcase
  end
 end
 
 
 assign read_request=state==CTX_ADDR||
   (state==BODY_ADDR&&descriptor_valid&&descriptor_ram);
 assign read_locked=state==CTX_STORE||
   (state==BODY_STORE&&descriptor_valid&&descriptor_ram);
 // No reset on unpublished descriptor data. Its valid bit is canceled with
 // the transaction; STORE is reachable only after this exact PREP/ADDR pair.
 always @(posedge src_clk)if(state==BODY_PREP)begin
  descriptor_ram<=use_ram;descriptor_address<=source_address;
  meta_local_q<=meta[meta_byte*8+:8];
  report_metadata_q<=report_metadata[report_metadata_byte*8+:8];
  practice_local_q<=env[48+practice_byte*8+:8];
  interaction_local_q<=interaction_scoped[interaction_byte*8+:8];
  descriptor_mask<=report_mask;descriptor_capture<=captured_byte;
 end
 always @(posedge src_clk)if(state==BODY_ADDR)descriptor_local<=body_local;
 // Data storage needs no reset value: boot invalidates dst/req, and BUILD
 // writes every byte before PUBLISH. Separating this from resettable control
 // avoids reset/constant-valid fanout across 896 unpublished source data bits.
 // Unpublished context is overwritten completely before CONTEXT. No reset
 // or fault/cancel enable is required on its 256 data bits. SAFE uses its
 // own explicit construction state so error decoding never drives this CE.
 always @(posedge src_clk)begin
  if(state==CTX_STORE)context_data<={bank_data,context_data[255:8]};
  if(state==SAFE_INIT)context_data<={56'd0,8'h43,24'd0,header[73:72],40'd0,header[79:74],header[55:0],64'd0};
 end
 always @(posedge src_clk)begin
  begin
   if(state==BODY_STORE)hold_data[799:0]<={body_byte,hold_data[799:8]};
   if(state==PUBLISH)hold_data[895:800]<={8'h43,kind,1'b1,2'b00,historical,1'b0,local_identity,env[135:130],feedback_scope,1'b0,session_runtime};
  end
 end
 // Private bank identity is captured on the existing IDLE acceptance edge.
 // Repeated IDLE writes while unowned are unobservable; address/store identity
 // checks begin only after that edge and retain the same captured bank values.
 // Current report data is consumed only after WAIT_REPORT accepts a matching
 // valid capture. Sampling on every WAIT_REPORT edge takes that exact accepted
 // sample without propagating kill/fault/session decisions to 142 data enables.
 // Public ACK registers and every ownership/reset/valid control remain reset.
 always @(posedge src_clk)begin
  if(state==IDLE)begin pending_session<=bank_session;pending_sequence<=bank_sequence;end
  if(state==CONTEXT)pending_key<=0;
  if(state==WAIT_REPORT)begin
   pending_key<=capture_key;
   report_metadata<=local_status[159:128];
   report_fields<={local_status[96:86],local_status[72:14]};
   report_score<=local_status[122:115];
  end
 end
 always @(posedge src_clk or posedge src_rst)begin
  if(src_rst)begin
   state<=IDLE;index<=0;req<=0;build_req<=0;build_done<=0;source_fault<=0;descriptor_valid<=0;
   ack1<=0;ack2<=0;db1<=1;db2<=1;sba1<=0;sba2<=0;ka1<=0;ka2<=0;
   src_boot<=1;dst_boot_ack<=0;kill_req<=0;kill_seen<=0;pending_canceled<=0;ever_ready<=0;
   token_counter<=0;pending_token<=0;
   pending_transaction<=0;pending_cancel<=0;local_identity<=0;feedback_scope<=0;
   local_safe<=0;safe_published<=0;safe_error<=0;
   in_flight<=0;ack_event<=0;ack_report<=0;ack_history<=0;ack_report_key<=0;
   stall_count<=0;ack_count<=0;boot_count<=0;
  end else begin
   ack1<=ack;ack2<=ack1;db1<=dst_boot;db2<=db1;sba1<=src_boot_ack;sba2<=sba1;
   ka1<=kill_ack;ka2<=ka1;dst_boot_ack<=db2;
   if(sba2)src_boot<=0;
   build_done<=0;source_fault<=0;ack_event<=0;ack_report<=0;ack_history<=0;
   if(!kill)kill_seen<=0;
   if(local_status[7:0]==0)safe_published<=0;
   if(kill&&!kill_seen&&!boot_barrier)begin kill_req<=~kill_req;kill_seen<=1;pending_canceled<=1;end
   if(boot_barrier)begin
    if(state!=IDLE&&state!=WAIT_ACK)build_done<=1;
    req<=0;state<=IDLE;build_req<=0;in_flight<=0;kill_req<=0;pending_canceled<=1;ack_count<=0;stall_count<=0;safe_published<=0;descriptor_valid<=0;
    if(ever_ready&&db2)source_fault<=1;
    ever_ready<=0;
    if(boot_count<BOOT_CYCLES)boot_count<=boot_count+1'b1;else begin source_fault<=1;boot_count<=0;end
   end else begin
    boot_count<=0;if(source_ready)ever_ready<=1;
    if(state==WAIT_ACK)begin
     if(ack_count<ACK_CYCLES)ack_count<=ack_count+1'b1;else begin source_fault<=1;src_boot<=1;end
    end else ack_count<=0;
    if(state==CTX_ADDR||state==CTX_STORE||state==BODY_PREP||state==BODY_ADDR||state==BODY_STORE||state==PUBLISH)begin
     if(read_progress)stall_count<=0;
     else if(stall_count<INTERNAL_CYCLES)stall_count<=stall_count+1'b1;else begin source_fault<=1;src_boot<=1;end
    end else stall_count<=0;
    if(kill&&state!=IDLE&&state!=WAIT_ACK)begin
     state<=IDLE;build_req<=0;build_done<=1;pending_canceled<=1;descriptor_valid<=0;
    end else if(!local_safe&&
      (state==CTX_ADDR||state==CTX_STORE||state==BODY_PREP||state==BODY_ADDR||state==BODY_STORE||state==PUBLISH)&&
      (bank_session!=pending_session||bank_sequence!=pending_sequence))begin
     source_fault<=1;state<=ABORT;descriptor_valid<=0;
    end else case(state)
     IDLE:if(source_ready)begin
      if(local_status[7:0]!=0&&(!safe_published||safe_error!=local_status[7:0]))begin
       local_safe<=1;safe_error<=local_status[7:0];
       pending_canceled<=0;state<=SAFE_INIT;
      end else if(local_status[7:0]!=0&&payload_valid)begin
       // Fault safely withdraws unbuilt display snapshots after their control
       // commit; no RAM reference remains, so banks can be retired.
       build_done<=1;
      end else if(payload_valid)begin
       local_safe<=0;build_req<=1;index<=0;state<=CTX_ADDR;
       pending_canceled<=0;
      end
     end
     SAFE_INIT:state<=CONTEXT;
     CTX_ADDR:if(build_grant)state<=CTX_STORE;
     CTX_STORE:begin
      if(index==31)begin state<=CONTEXT;build_req<=0;end else begin index<=index+1'b1;state<=CTX_ADDR;end
     end
     CONTEXT:begin
      if(env[79:72]!=8'h43||kind>REPORT||((kind==GALLERY||kind==TREND)&&!meta[31]))begin source_fault<=1;state<=ABORT;end
      else begin
       pending_transaction<=transaction;pending_cancel<=env[45:30];
       local_identity<={env[5:0],env[47:46],header[71:64]};
       feedback_scope<=!local_safe&&header[57]&&header[79:74]==env[5:0]&&header[73:72]==env[47:46];
       if(current_report)state<=WAIT_REPORT;
       else begin build_req<=1;index<=0;state<=BODY_PREP;end
      end
     end
     WAIT_REPORT:if(capture_valid&&capture_transaction==pending_transaction&&local_status[159])begin
      
      build_req<=1;index<=0;state<=BODY_PREP;
     end
     BODY_PREP:begin descriptor_valid<=1;state<=BODY_ADDR;end
     BODY_ADDR:if(descriptor_valid&&(!descriptor_ram||build_grant))state<=BODY_STORE;
     BODY_STORE:begin
      descriptor_valid<=0;
      if(index==99)begin state<=PUBLISH;build_req<=0;end else begin index<=index+1'b1;state<=BODY_PREP;end
     end
     PUBLISH:begin
      pending_token<=token_counter+1'b1;token_counter<=token_counter+1'b1;
      req<=~req;in_flight<=1;state<=WAIT_ACK;build_done<=1;
      if(local_safe)safe_published<=1;
     end
     WAIT_ACK:if(in_flight&&ack2==req)begin
      in_flight<=0;state<=IDLE;ack_event<=1;
      if(!pending_canceled&&!kill)begin ack_report<=current_report;ack_history<=historical;ack_report_key<=pending_key;end
     end
     ABORT:begin build_done<=1;build_req<=0;state<=IDLE;descriptor_valid<=0;end
     default:state<=IDLE;
    endcase
   end
  end
 end
 always @(posedge dst_clk)begin
  if(!dst_boot&&!dba2&&!sb2&&!src_boot_ack&&k2==kill_ack&&
     frame_boundary&&req2!=ack&&flush_left==0)dst_data<=hold_data;
 end
 always @(posedge dst_clk or posedge dst_rst)begin
  if(dst_rst)begin
   pixel_ui_valid<=0;ack<=0;req1<=0;req2<=0;dst_boot<=1;src_boot_ack<=0;
   sb1<=1;sb2<=1;dba1<=0;dba2<=0;k1<=0;k2<=0;kill_ack<=0;flush_left<=13;
  end else begin
   sb1<=src_boot;sb2<=sb1;dba1<=dst_boot_ack;dba2<=dba1;src_boot_ack<=sb2;
   if(dba2)dst_boot<=0;
   if(dst_boot||dba2||sb2||src_boot_ack)begin
    pixel_ui_valid<=0;ack<=0;req1<=0;req2<=0;k1<=0;k2<=0;kill_ack<=0;flush_left<=13;
   end else begin
    req1<=req;req2<=req1;k1<=kill_req;k2<=k1;
    if(flush_left!=0)flush_left<=flush_left-1'b1;
    if(k2!=kill_ack)begin kill_ack<=k2;pixel_ui_valid<=0;flush_left<=13;ack<=req2;end
    else if(frame_boundary&&req2!=ack&&flush_left==0)begin
     ack<=req2;pixel_ui_valid<=hold_data[895:888]==8'h43&&hold_data[884];
    end
   end
  end
 end
endmodule

// a normal teaching successor may fetch only after its matching complete
// UI has crossed at a pixel frame boundary. B owns the required flag. ACK is
// transport-to-pixels, never the actual PRESENTED event used for GO/timing.
module recovery_teaching_handoff_guard(
 input wire clk,rst,withdraw,new_command,required,
 input wire ack_valid,input wire [15:0] ack_transaction,ack_identity,
 input wire [15:0] transaction,identity,output wire ready
);

reg delivered;
// Continuous values retain the original net initializer expressions.


 
 always @(posedge clk or posedge rst)begin
  if(rst)delivered<=0;
  else if(withdraw||new_command)delivered<=0;
  else if(ack_valid&&ack_transaction==transaction&&ack_identity==identity)delivered<=1;
 end
 assign ready=!required||delivered;
endmodule

`default_nettype wire
