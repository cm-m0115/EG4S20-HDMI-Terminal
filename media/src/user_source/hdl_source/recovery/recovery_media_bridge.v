`default_nettype none
`timescale 1ns/1ps
// Reliable reception, atomic control projection, immutable command
// context and direct RX-bank display service.
module recovery_media_bridge #(parameter integer CLK_HZ=100000000,BAUD=115200,
 COMMAND_CYCLES=2*CLK_HZ,INTERNAL_CYCLES=CLK_HZ/1000)(
 input wire clk,rst,input wire uart_rx,output wire uart_tx,
 output reg gpio_presented_out,gpio_done_out,output wire gpio_link_ready_out,
 output wire cmd_valid,input wire cmd_ready,output reg [5:0] cmd_scene,output reg [1:0] cmd_effect,
 output reg cancel,skip_audio_wait,skip_page_request,
 output reg [1:0] cmd_question_set,output reg [23:0] practice_data,interaction_data,
 output reg [7:0] accepted_identity,output reg [15:0] accepted_transaction,
 output wire [15:0] visible_transaction,output reg [1:0] cmd_wipe_direction,
 output wire [159:0] status_data,output reg [31:0] history_meta,
 output reg [24:0] session_data,output reg [30:0] runtime_data,output reg [6:0] ui_seq,
 output wire link_up,
 input wire build_req,build_read,build_locked,build_done,input wire mailbox_ready,mailbox_fault,
 output wire build_grant,output wire display_valid,output wire [31:0] display_session,output wire [15:0] display_sequence,
 input wire [7:0] build_addr,output wire [7:0] build_data,
 input wire ui_event_valid,input wire [19:0] ui_event_identity,output wire ui_event_ready,
 input wire feedback_event_valid,input wire [19:0] feedback_event_identity,output wire feedback_event_ready,
 input wire media_presented,media_done,media_fault,input wire [7:0] last_error,debug_state,epoch,
 input wire [5:0] live_scene,input wire audio_active,voice_active,music_active,voice_complete
);

localparam integer PW=INTERNAL_CYCLES<2?1:$clog2(INTERNAL_CYCLES+1);
reg have_transaction,command_pending,present_pending,done_pending,fault_latch,prev_link,peer_compatible;
reg ui_owner,green_requested,ui_event_pending;
reg [5:0] presented_ui_seq,presented_ui_scene;
reg [9:0] feedback_stage,feedback_request;
reg feedback_padding_ok;
reg feedback_pending;
wire feedback_matches;
wire ui_event_matches;
reg [15:0] transaction,cancel_generation;
reg [159:0] live_status,command_status;
reg [31:0] refresh_count,command_count;
reg force_status,send_valid;
reg [95:0] send_data;
wire send_ready,link_in_valid,session_restart,link_in_bank;
wire [7:0] link_in_length;
wire [31:0] link_session;
wire [15:0] link_in_sequence;
reg protocol_fault;
reg command_expired;
wire restart;
reg [1:0] ctrl_pending,display_pending,owned;
reg [31:0] bank_session[0:1];
reg [15:0] bank_seq[0:1];
reg [15:0] bank_cancel[0:1],bank_transaction[0:1];
reg [1:0] bank_control_done;
reg [1:0] bank_release;
reg projection_bank,projection_busy;
reg [6:0] pi;
reg [1:0] ps;
reg [383:0] control_stage;
wire [159:0] in_status;
wire [31:0] in_meta;
wire [55:0] in_runtime_session;
wire [135:0] in_env;
wire [15:0] in_transaction,in_cancel;
wire control_apply;
wire control_valid_decoded;
reg control_valid_q,control_cancel_q,control_command_q;
wire control_valid;
wire cancel_commit;
wire new_command;
reg snapshot_active,snapshot_bank;
reg expected_ctrl,expected_display;
wire ctrl_available;
wire next_ctrl;
wire next_display;
wire projection_launch;
wire [7:0] rd_addr;
wire rd_bank;
wire [7:0] rd_data;
reg [PW-1:0] projection_stall;
integer b;
// Continuous values retain the original net initializer expressions.
assign feedback_matches = feedback_request[3:2]!=0&&
   feedback_event_identity=={feedback_request[9:4],cmd_scene,epoch};
assign ui_event_matches = ui_owner&&green_requested&&ui_event_identity=={ui_seq[5:0],cmd_scene,epoch};
assign restart = protocol_fault||mailbox_fault||(COMMAND_CYCLES<=0?1'b1:command_expired);
assign in_status = control_stage[159:0];
assign in_meta = control_stage[191:160];
assign in_runtime_session = control_stage[247:192];
assign in_env = control_stage[383:248];
assign in_transaction = in_env[27:12];
assign in_cancel = in_env[45:30];
assign control_apply = projection_busy&&ps==3;
assign control_valid_decoded = in_env[79]&&in_env[74:72]<=5&&
  ((in_env[74:72]!=1&&in_env[74:72]!=2)||(feedback_padding_ok&&feedback_stage[3:2]!=3));
assign control_valid = control_valid_q;
assign cancel_commit = control_apply&&control_valid_q&&control_cancel_q;
assign new_command = control_apply&&control_valid_q&&!control_cancel_q&&control_command_q;
assign ctrl_available = |ctrl_pending;
assign next_ctrl = ctrl_pending[expected_ctrl]?expected_ctrl:!expected_ctrl;
assign next_display = display_pending[expected_display]?expected_display:!expected_display;
assign projection_launch = !projection_busy&&ctrl_available&&!build_locked;
assign rd_addr = projection_busy?projection_address(pi):build_addr;
assign rd_bank = projection_busy?projection_bank:snapshot_bank;

 
 
 
 
 
 
 
 assign feedback_event_ready=!feedback_matches||(link_up&&!cancel&&!cancel_commit&&!restart&&!ui_event_pending);
 
 assign ui_event_ready=!ui_event_matches||(!present_pending&&!done_pending&&link_up&&!cancel&&!restart);
 
 
 assign status_data=command_pending?command_status:live_status;
 assign visible_transaction=transaction;
 assign gpio_link_ready_out=link_up&&peer_compatible&&!rst&&!session_restart&&!fault_latch&&mailbox_ready;
 assign cmd_valid=link_up&&peer_compatible&&command_pending&&!present_pending&&!done_pending&&!cancel&&!cancel_commit&&!restart;
 
 
 
 
 
 
 // Predict the original saturating counter's comparison. Reset priority is
 // shared with command_count; no extra timeout cycle or weaker target.
 
 // Bank descriptors and independent control/display ownership.
 
 
 
 
 
  // 48 bytes: status20+meta4+session/runtime7+env17
 
 
 
 
 
 
 
 
 
 
 
 function [7:0] projection_address;input [6:0] k;begin
  if(k<20)projection_address=k;
  else if(k<24)projection_address=8'd112+k-8'd20;
  else if(k<31)projection_address=8'd120+k-8'd24;
  else if(k<48)projection_address=8'd159+k-8'd31;
  else if(k==48)projection_address=8'd118;
  else projection_address=8'd135+k-8'd49;
 end endfunction
 // One bank may be BUILD's immutable read source while the other projects a
 // later control/cancel. The read port is locked only over its actual latency.
 
 
 
 
 
 
 
 
 
 assign build_data=rd_data;
 assign build_grant=snapshot_active&&!projection_busy&&!projection_launch;
 assign display_valid=snapshot_active&&bank_control_done[snapshot_bank]&&!cancel&&!restart;
 assign display_session=bank_session[snapshot_bank];
 assign display_sequence=bank_seq[snapshot_bank];
 recovery_uart_link #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.MASTER(0),.MAX_BYTES(176)) u_link(
  .clk(clk),.rst(rst),.uart_rx(uart_rx),.uart_tx(uart_tx),
  .send_valid(send_valid),.send_ready(send_ready),.send_length(8'd12),.send_data({1312'd0,send_data}),
  .in_valid(link_in_valid),.in_length(link_in_length),.in_bank(link_in_bank),.bank_release(bank_release),
  .rd_bank(rd_bank),.rd_addr(rd_addr),.rd_data(rd_data),.link_up(link_up),.session_restart(session_restart),
  .restart_request(restart),.link_session(link_session),.in_sequence(link_in_sequence));
 
 
 // This private scratch is never published before all 48 bytes and the
 // validated version have arrived. Reset invalidates projection/validity;
 // data need not fan out the reset tree to 384 unpublished registers.
 always @(posedge clk)begin
  if(projection_busy&&ps==1)begin
   if(pi==48)control_stage[327:320]<={control_stage[327:320]==8'h43,4'd0,rd_data[3:1]};
   else if(pi<48)control_stage<={rd_data,control_stage[383:8]};
  end
 end
 
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   ctrl_pending<=0;display_pending<=0;owned<=0;bank_control_done<=0;bank_release<=0;
   projection_bank<=0;projection_busy<=0;pi<=0;ps<=0;
   snapshot_active<=0;snapshot_bank<=0;expected_ctrl<=0;expected_display<=0;protocol_fault<=0;projection_stall<=0;feedback_stage<=0;feedback_padding_ok<=0;
   control_valid_q<=0;control_cancel_q<=0;control_command_q<=0;
   for(b=0;b<2;b=b+1)begin bank_session[b]<=0;bank_seq[b]<=0;bank_cancel[b]<=0;bank_transaction[b]<=0;end
  end else begin
   bank_release<=0;protocol_fault<=0;
   if(projection_busy)begin
    projection_stall<=0;
    case(ps)
     0:ps<=1;
     1:begin
      // Byte49 validates kind without another persistent data copy. The
      // local version byte becomes {compatible,0000,kind}; this scratch
      // encoding is never sent or used by the display mailbox.
      if(pi==48)begin end
      else if(pi==49)feedback_stage[7:0]<=rd_data;
      else if(pi==50)begin feedback_stage[9:8]<=rd_data[1:0];feedback_padding_ok<=rd_data[7:2]==0;end

      if(pi==50)ps<=2;else begin pi<=pi+1'b1;ps<=0;end
     end
     // Data is already complete in this existing settle cycle. Register the
     // decoded predicates here, retaining the exact original ps3 apply edge.
     2:begin
      control_valid_q<=control_valid_decoded;control_cancel_q<=in_cancel!=cancel_generation;
      control_command_q<=in_env[8]&&(!have_transaction||in_transaction!=transaction);ps<=3;
     end
     3:begin
      projection_busy<=0;bank_control_done[projection_bank]<=1;
      if(!control_valid)begin protocol_fault<=1;bank_release[projection_bank]<=1;owned[projection_bank]<=0;end
      else begin
       bank_cancel[projection_bank]<=in_cancel;bank_transaction[projection_bank]<=in_transaction;
       // A report command waiting for media acceptance already retains its
       // immutable bank. Ordinary refreshes of THAT same report can be
       // canceled before display publication, after their control commit.
       // This leaves a free bank for a later reliable cancellation packet.
       if(cancel_commit||in_env[9])begin
        display_pending[projection_bank]<=0;owned[projection_bank]<=0;bank_release[projection_bank]<=1;
       end else if(snapshot_active&&command_pending&&projection_bank!=snapshot_bank&&
         bank_control_done[snapshot_bank]&&bank_transaction[snapshot_bank]==in_transaction&&
         bank_cancel[snapshot_bank]==in_cancel&&in_env[74:72]==5&&!cancel_commit)begin
        display_pending[projection_bank]<=0;owned[projection_bank]<=0;bank_release[projection_bank]<=1;
       end else display_pending[projection_bank]<=1;
       // A fully received cancellation can invalidate older unbuilt banks.
       if(cancel_commit)for(b=0;b<2;b=b+1)if(b!=projection_bank&&owned[b]&&bank_control_done[b])begin
        display_pending[b]<=0;
        if(!(snapshot_active&&snapshot_bank==b))begin owned[b]<=0;bank_release[b]<=1;end
       end
      end
     end
    endcase
   end else if(projection_launch)begin
    projection_bank<=next_ctrl;projection_busy<=1;pi<=0;ps<=0;
    ctrl_pending[next_ctrl]<=0;expected_ctrl<=!next_ctrl;
   end else if(ctrl_available&&build_locked)begin
    if(projection_stall<INTERNAL_CYCLES)projection_stall<=projection_stall+1'b1;
    else protocol_fault<=1;
   end else projection_stall<=0;
   if(!snapshot_active&&(|display_pending)&&mailbox_ready&&!cancel_commit)begin
    snapshot_bank<=next_display;snapshot_active<=1;display_pending[next_display]<=0;expected_display<=!next_display;
   end
   if(build_done&&snapshot_active)begin
    snapshot_active<=0;owned[snapshot_bank]<=0;bank_release[snapshot_bank]<=1;bank_control_done[snapshot_bank]<=0;
   end
   if(link_in_valid)begin
    if(link_in_length!=176||owned[link_in_bank])protocol_fault<=1;
    else begin
     owned[link_in_bank]<=1;ctrl_pending[link_in_bank]<=1;bank_control_done[link_in_bank]<=0;
     bank_session[link_in_bank]<=link_session;bank_seq[link_in_bank]<=link_in_sequence;
    end
   end
   if(session_restart||restart||!link_up)begin
    ctrl_pending<=0;display_pending<=0;owned<=0;bank_control_done<=0;projection_busy<=0;snapshot_active<=0;
    bank_release<=0;expected_ctrl<=0;expected_display<=0;
   end
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   gpio_presented_out<=0;gpio_done_out<=0;command_pending<=0;have_transaction<=0;present_pending<=0;done_pending<=0;
   fault_latch<=0;prev_link<=0;transaction<=0;cancel_generation<=0;refresh_count<=0;command_count<=0;
   command_expired<=0;force_status<=1;send_valid<=0;send_data<=0;cmd_scene<=0;ui_seq<=0;cmd_effect<=0;cmd_question_set<=0;
   practice_data<=0;interaction_data<=0;accepted_identity<=0;accepted_transaction<=0;cmd_wipe_direction<=0;
   cancel<=0;skip_audio_wait<=0;skip_page_request<=0;live_status<=0;command_status<=0;history_meta<=0;
   session_data<=0;runtime_data<=0;peer_compatible<=0;ui_owner<=0;green_requested<=0;ui_event_pending<=0;presented_ui_seq<=0;presented_ui_scene<=0;
   feedback_request<=0;feedback_pending<=0;
  end else begin
   prev_link<=link_up;cancel<=0;skip_page_request<=0;
   command_expired<=command_pending&&command_count>=COMMAND_CYCLES-1;
   if(refresh_count<CLK_HZ/50)refresh_count<=refresh_count+1'b1;
   if(command_pending)begin if(command_count<COMMAND_CYCLES)command_count<=command_count+1'b1;end
   else command_count<=0;
   if(control_apply&&control_valid&&link_up)begin
    if((in_env[74:72]==1||in_env[74:72]==2)&&!cancel_commit&&!in_env[9]&&in_transaction==transaction)begin
     feedback_request<=feedback_stage;
     if(feedback_stage[3:2]==0||feedback_stage[9:4]!=feedback_request[9:4])feedback_pending<=0;
    end else begin feedback_request<=0;feedback_pending<=0;end
    peer_compatible<=1;live_status<=in_status;history_meta<=in_meta[31:0];
    ui_seq<={1'b1,in_env[135:130]};session_data<=in_runtime_session[24:0];runtime_data<=in_runtime_session[55:25];
    skip_audio_wait<=in_env[10];practice_data<=in_env[71:48];interaction_data<=in_env[103:80];
    accepted_identity<=in_env[111:104];accepted_transaction<=in_env[127:112];
    // Ownership transition occurs only after old GPIO events are acknowledged.
    if(!present_pending&&!done_pending)ui_owner<=in_env[103];
    green_requested<=in_env[102];
    if(!in_env[102])ui_event_pending<=0;
    if(in_env[28]==gpio_presented_out)present_pending<=0;
    if(in_env[29]==gpio_done_out)done_pending<=0;
    if(cancel_commit)begin
     cancel_generation<=in_cancel;cancel<=1;command_pending<=0;have_transaction<=0;
     ui_owner<=0;green_requested<=0;ui_event_pending<=0;fault_latch<=0;force_status<=1;
    end else begin
     if(new_command)begin
      if(command_pending)begin fault_latch<=1;end
      else begin
       have_transaction<=1;transaction<=in_transaction;cmd_scene<=in_env[5:0];cmd_effect<=in_env[7:6];
       cmd_question_set<=in_env[47:46];cmd_wipe_direction<=in_env[129:128];command_status<=in_status;
       command_pending<=1;fault_latch<=0;force_status<=1;
      end
     end
     if(in_env[11])skip_page_request<=1;
    end
   end
   if(cmd_valid&&cmd_ready)begin command_pending<=0;force_status<=1;end
   if(media_presented&&!ui_owner&&link_up&&!session_restart&&!cancel&&!cancel_commit)begin
    if(!present_pending)begin gpio_presented_out<=~gpio_presented_out;present_pending<=1;end else fault_latch<=1;
    force_status<=1;
   end
   if(media_done&&link_up&&!session_restart&&!cancel&&!cancel_commit)begin
    if(!done_pending)begin gpio_done_out<=~gpio_done_out;done_pending<=1;end else fault_latch<=1;
    force_status<=1;
   end
   if(ui_event_valid&&ui_event_ready&&ui_event_matches&&!session_restart&&!cancel_commit&&!cancel)begin
    gpio_presented_out<=~gpio_presented_out;present_pending<=1;ui_event_pending<=1;
    presented_ui_seq<=ui_event_identity[19:14];presented_ui_scene<=ui_event_identity[13:8];force_status<=1;
   end
   if(feedback_event_valid&&feedback_event_ready&&feedback_matches&&!session_restart&&!cancel_commit&&!cancel)begin
    feedback_pending<=1;presented_ui_seq<=feedback_event_identity[19:14];
    presented_ui_scene<=feedback_event_identity[13:8];force_status<=1;
   end
   if(media_fault)begin fault_latch<=1;force_status<=1;end
   if(send_valid&&send_ready)begin send_valid<=0;refresh_count<=0;end
   if(!send_valid&&send_ready&&(force_status||refresh_count>=CLK_HZ/50))begin
    send_data<=0;send_data[5:0]<=live_scene;send_data[13:6]<=epoch;
    send_data[21:14]<=last_error;send_data[29:22]<=debug_state;send_data[30]<=audio_active;
    send_data[31]<=peer_compatible&&!command_pending&&!present_pending&&!done_pending&&!cancel&&!fault_latch;
    send_data[47:32]<=transaction;send_data[63:48]<=cancel_generation;
    send_data[64]<=gpio_presented_out;send_data[65]<=gpio_done_out;send_data[66]<=fault_latch;
    send_data[79:67]<={ui_event_pending?gpio_presented_out:1'b0,presented_ui_seq,presented_ui_scene};
    send_data[95:91]<={ui_owner,ui_event_pending||feedback_pending,ui_event_pending?3'd1:feedback_pending?3'd2:3'd0};
    send_data[87:80]<=8'h43;send_data[88]<=voice_active;send_data[89]<=music_active;send_data[90]<=voice_complete;
    send_valid<=1;force_status<=0;
   end
   if(prev_link&&!link_up||session_restart||restart)begin
    feedback_request<=0;feedback_pending<=0;
    peer_compatible<=0;interaction_data<=0;practice_data<=0;cancel<=1;
    ui_owner<=0;green_requested<=0;ui_event_pending<=0;
    command_pending<=0;command_count<=0;command_expired<=0;have_transaction<=0;fault_latch<=0;
    present_pending<=0;done_pending<=0;force_status<=1;send_valid<=0;
   end
  end
 end
endmodule

`default_nettype wire
