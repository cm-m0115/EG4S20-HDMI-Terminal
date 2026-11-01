`default_nettype none
`timescale 1ns/1ps
// B owns business, physical keys, and both stimulus/key timestamps.
// Presentation/done GPIO are persistent toggles; acknowledgements travel in
// reliable UART snapshots. Rebase only while disarmed, canceling, or restarting.
module recovery_master_bridge #(parameter integer CLK_HZ=100000000,BAUD=115200,
 SNAPSHOT_MS=25)(
 input wire clk,rst,input wire uart_rx,output wire uart_tx,
 input wire gpio_presented_in,gpio_done_in,gpio_link_ready_in,
 input wire cmd_valid,input wire [5:0] cmd_scene,input wire [1:0] cmd_effect,
 input wire [1:0] cmd_question_set,input wire [23:0] practice_data,
 input wire [1:0] cmd_wipe_direction,input wire [23:0] interaction_data,
 input wire [7:0] accepted_identity,
 input wire cancel,skip_audio_wait,skip_page_request,
 input wire [159:0] status_data,input wire [799:0] history_data,
 input wire [24:0] session_data,input wire [30:0] runtime_data,
 input wire [7:0] trend_read_point,output reg [6:0] trend_read_address,
 // B-prepared union256 (LIVE_UI/REPORT_TEXT) and UI sequence.
 input wire ui_owner_request,ui_green_request,
 input wire [1:0] feedback_kind,feedback_mask,input wire [5:0] feedback_seq,
 output reg feedback_confirmed,
 input wire [31:0] ui_now_cycles,output reg [31:0] ui_presented_cycles,
 output reg ui_presented,ui_confirmed,
 output wire cmd_ready,output reg media_presented,media_done,media_fault,media_recover,
 output reg [7:0] last_error,debug_state,epoch,output reg [5:0] live_scene,
 output reg audio_active,output reg narration_quiet,output reg voice_complete,output wire link_up
);

localparam [31:0] SNAPSHOT_LIMIT=(CLK_HZ/1000)*SNAPSHOT_MS;
(* ASYNC_REG="TRUE" *) reg [2:0] present_sync,done_sync,ready_sync;
reg [3:0] ready_history,present_event_pipe,done_event_pipe;
(* max_fanout=4 *) reg gpio_qualified;
reg present_seen,done_seen,armed,fault_seen,prev_link;
reg remote_ready,cancel_wait,cmd_outstanding,cmd_pending,skip_pending;
reg ui_owner,green_seen,green_requested,ui_gpio_pending,ui_identity_pending,ui_confirmed_seen;
reg [5:0] ui_seq;
reg ui_gpio_level;
reg feedback_confirmed_seen;
reg [31:0] ui_edge_cycles;
wire events_retired;
reg peer_compatible;
reg [7:0] accepted_seen,held_accepted_identity;
reg [15:0] held_accepted_transaction;
reg [1:0] held_wipe_direction;
reg [15:0] transaction,cancel_generation;
reg [5:0] held_scene;
reg [1:0] held_effect,held_question_set;
reg [159:0] held_report_status;
reg [31:0] refresh_count;
reg [3:0] settle_count;
reg force_snapshot,assembling,send_valid;
wire send_ready,in_valid,session_restart;
wire [7:0] in_length;
wire [1407:0] in_data;
reg [1407:0] send_data;
reg [5:0] scan_index;
reg [1:0] scan_phase;
wire [159:0] prep_selected;
wire prep_history_report;
wire [159:0] prep_status;
wire [23:0] prep_interaction;
wire [255:0] prepared_union;
reg remote_caption_running,snapshot_caption_running;
wire snapshot_start;
wire snapshot_expire_next;
wire [1:0] sync_levels;
// Continuous values retain the original net initializer expressions.
assign events_retired = present_event_pipe==0&&done_event_pipe==0&&
   present_sync[2]==present_seen&&done_sync[2]==done_seen;
assign prep_selected = send_data[900:899]==0?send_data[319:160]:
  send_data[900:899]==1?send_data[503:344]:
  send_data[900:899]==2?send_data[687:528]:send_data[871:712];
assign prep_history_report = send_data[927]&&send_data[926]&&!send_data[898];
assign prep_status = prep_history_report?prep_selected:send_data[159:0];
assign prep_interaction = {send_data[1375:1359],
  send_data[1358]&&send_data[1399:1384]==send_data[1299:1284]&&
   send_data[1383:1376]=={send_data[1319:1318],send_data[1277:1272]},send_data[1357:1352]};
assign snapshot_start = !assembling&&!send_valid&&send_ready&&settle_count==0&&
     (interaction_data[6]!==1'b1 || accepted_seen==interaction_data[21:14])&&
     (force_snapshot||cmd_pending||skip_pending);
assign snapshot_expire_next = SNAPSHOT_LIMIT==0?1'b1:refresh_count>=SNAPSHOT_LIMIT-1'b1;
assign sync_levels = {done_sync[2],present_sync[2]};

 
 
  /* fehdl async_reg=1 */
 // Equal to &ready_history after every edge, including reset. Predict its
 // next shift rather than putting the reduction in every application cone.
 always @(posedge clk or posedge rst)
  if(rst)gpio_qualified<=0;
  else gpio_qualified<=&{ready_history[2:0],ready_sync[2]};
 
 
 
 
 
 
 
 
 
 
 
 
 
 // One immutable report command context. Later display refreshes must not
 // alter M3 input or the raw report while A is still waiting cmd_ready.
 
 
 
 
 
 
 
 
 // M1/M2/M3 consume the same frozen send_data as every other field.
 // scan_phase=0/1 allows preparation to settle, phase2 commits its result.
 
 
 
 
 
 
 recovery_display_prep u_prepare(.clk(clk),.rst(rst),.status(prep_status),
  .report_ready(prep_status[159]),.scene(prep_history_report?
   (prep_selected[158:157]==1?6'd29:6'd30):send_data[1277:1272]),
  .question_set(send_data[1319:1318]),.practice(send_data[1343:1320]),
  .interaction(prep_interaction),.caption_running(snapshot_caption_running),
  .ui_step(6'd0),.ui_teach_step(send_data[1341:1339]),.ui_teach_panel(send_data[1343]),
  .teach_percent(send_data[1330:1324]),.green_cue(send_data[1374]),.ui_owner(send_data[1375]),
  .feedback_mask(send_data[1081:1080]),.feedback_kind(send_data[1083:1082]),.feedback_seq(send_data[1089:1084]),.union_out(prepared_union));
 // A payload is consumed only after all 32 trend bytes and the fixed fields
 // have been written; control validity retains its original asynchronous reset.
 
 
 
 
 assign cmd_ready=link_up&&peer_compatible&&gpio_qualified&&remote_ready&&!cancel_wait&&!cmd_outstanding&&!cmd_pending&&!cancel;
 recovery_uart_link #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.MASTER(1),.MAX_BYTES(176)) u_link(
  .clk(clk),.rst(rst),.uart_rx(uart_rx),.uart_tx(uart_tx),
  .send_valid(send_valid),.send_ready(send_ready),.send_length(8'd176),.send_data(send_data),
  .in_valid(in_valid),.in_length(in_length),.in_data(in_data),.link_up(link_up),.session_restart(session_restart));
 always @(posedge clk or posedge rst)begin
  if(rst)begin present_sync<=0;done_sync<=0;ready_sync<=0;ready_history<=0;end
  else begin present_sync<={present_sync[1:0],gpio_presented_in};done_sync<={done_sync[1:0],gpio_done_in};ready_sync<={ready_sync[1:0],gpio_link_ready_in};ready_history<={ready_history[2:0],ready_sync[2]};end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   present_seen<=0;done_seen<=0;present_event_pipe<=0;done_event_pipe<=0;armed<=0;fault_seen<=0;prev_link<=0;
   remote_ready<=0;cancel_wait<=1;cmd_outstanding<=0;cmd_pending<=0;skip_pending<=0;
   ui_owner<=0;green_seen<=0;green_requested<=0;ui_gpio_pending<=0;ui_identity_pending<=0;ui_confirmed_seen<=0;
   ui_seq<=0;ui_gpio_level<=0;ui_presented<=0;ui_confirmed<=0;ui_edge_cycles<=0;ui_presented_cycles<=0;
   feedback_confirmed<=0;feedback_confirmed_seen<=0;
   transaction<=0;cancel_generation<=0;held_scene<=0;held_effect<=0;held_question_set<=0;
   refresh_count<=0;settle_count<=0;force_snapshot<=1;assembling<=0;send_valid<=0;
   scan_index<=0;scan_phase<=0;trend_read_address<=0;
   media_presented<=0;media_done<=0;media_fault<=0;media_recover<=0;last_error<=0;debug_state<=0;
   epoch<=0;live_scene<=0;audio_active<=0;narration_quiet<=0;
   voice_complete<=0;remote_caption_running<=0;snapshot_caption_running<=0;peer_compatible<=0;accepted_seen<=0;
   held_accepted_identity<=0;held_accepted_transaction<=0;held_wipe_direction<=0;held_report_status<=0;
  end else begin
   prev_link<=link_up;media_presented<=0;media_done<=0;media_fault<=0;media_recover<=0;
   ui_presented<=0;ui_confirmed<=0;
   feedback_confirmed<=0;
   if(feedback_kind==0)feedback_confirmed_seen<=0;
   if(!ui_green_request)green_seen<=0;
   if(!cancel_wait&&events_retired&&!cmd_pending&&!cmd_outstanding&&remote_ready&&gpio_qualified)begin
    if(ui_owner_request!==ui_owner)begin ui_owner<=ui_owner_request;force_snapshot<=1;end
    if(ui_owner&&ui_green_request&&!green_seen)begin
     ui_seq<=ui_seq+1'b1;green_requested<=1;green_seen<=1;
     ui_gpio_pending<=0;ui_identity_pending<=0;ui_confirmed_seen<=0;force_snapshot<=1;
    end
   end
   if(!ui_green_request&&green_requested)begin green_requested<=0;force_snapshot<=1;end
   if(ui_gpio_pending&&ui_identity_pending&&!ui_confirmed_seen)begin
    ui_confirmed<=1;ui_confirmed_seen<=1;
   end
   if(interaction_data[6]===1'b1 && interaction_data[21:14]!=accepted_seen)begin
    accepted_seen<=interaction_data[21:14];held_accepted_identity<=accepted_identity;
    held_accepted_transaction<=transaction;force_snapshot<=1;
   end
   if(refresh_count<SNAPSHOT_LIMIT)refresh_count<=refresh_count+1'b1;
   if(!assembling&&!send_valid&&snapshot_expire_next)force_snapshot<=1;
   if(settle_count!=0)settle_count<=settle_count-1'b1;
   if(!link_up||!gpio_qualified||!armed||cancel_wait)begin
    present_seen<=present_sync[2];done_seen<=done_sync[2];present_event_pipe<=0;done_event_pipe<=0;
   end else begin
    // Timestamp the FIRST synchronized GPIO edge; the existing event dispatch
    // pipeline must not shift the input qualification boundary by four clocks.
    if(ui_owner&&green_requested&&present_sync[2]!=present_seen)ui_edge_cycles<=ui_now_cycles;
    present_event_pipe<={present_event_pipe[2:0],present_sync[2]!=present_seen};
    done_event_pipe<={done_event_pipe[2:0],done_sync[2]!=done_seen};
    present_seen<=present_sync[2];done_seen<=done_sync[2];
    if(present_event_pipe[3])begin
     if(ui_owner&&green_requested&&!ui_gpio_pending)begin
      ui_presented<=1;ui_presented_cycles<=ui_edge_cycles;ui_gpio_pending<=1;ui_gpio_level<=present_sync[2];
     end else if(!ui_owner)media_presented<=1;
     force_snapshot<=1;
    end
    if(done_event_pipe[3])begin media_done<=1;force_snapshot<=1;end
   end
   if(link_up&&armed&&!gpio_qualified)begin
    ui_owner<=0;green_requested<=0;ui_gpio_pending<=0;ui_identity_pending<=0;ui_confirmed_seen<=0;
    ui_presented<=0;ui_confirmed<=0;
    media_recover<=1;
    if(!fault_seen)begin media_fault<=1;last_error<=8'he2;fault_seen<=1;end
    armed<=0;remote_ready<=0;cancel_wait<=1;cancel_generation<=cancel_generation+1'b1;narration_quiet<=0;
    cmd_pending<=0;cmd_outstanding<=0;force_snapshot<=1;
   end
   if(prev_link&&!link_up)begin
    ui_owner<=0;green_requested<=0;ui_gpio_pending<=0;ui_identity_pending<=0;ui_confirmed_seen<=0;
    peer_compatible<=0;voice_complete<=0;
    media_recover<=1;
    if(armed&&!fault_seen)begin media_fault<=1;last_error<=8'he1;end
    narration_quiet<=0;armed<=0;remote_ready<=0;cmd_outstanding<=0;cmd_pending<=0;send_valid<=0;assembling<=0;cancel_wait<=1;
   end
   if(session_restart)begin
    ui_owner<=0;green_requested<=0;green_seen<=0;ui_gpio_pending<=0;ui_identity_pending<=0;ui_confirmed_seen<=0;
    peer_compatible<=0;voice_complete<=0;
    media_recover<=1;
    cancel_generation<=cancel_generation+1'b1;narration_quiet<=0;cancel_wait<=1;armed<=0;
    remote_ready<=0;cmd_outstanding<=0;cmd_pending<=0;skip_pending<=0;
    send_valid<=0;assembling<=0;force_snapshot<=1;settle_count<=4;
   end
   if(link_up&&in_valid&&in_length==12&&in_data[87:80]==8'h43)begin
    peer_compatible<=1;
    if(ui_owner&&green_requested&&in_data[95]&&in_data[94]&&in_data[93:91]==1&&
      in_data[78:73]==ui_seq&&in_data[72:67]==held_scene&&
      in_data[47:32]==transaction&&in_data[63:48]==cancel_generation&&
      in_data[79]==(ui_gpio_pending?ui_gpio_level:present_sync[2]))
      ui_identity_pending<=1;
    if(feedback_kind!=0&&!feedback_confirmed_seen&&!cancel&&!cancel_wait&&!session_restart&&
      in_data[94]&&in_data[93:91]==2&&in_data[78:73]==feedback_seq&&in_data[72:67]==held_scene&&
      in_data[13:6]==epoch&&in_data[47:32]==transaction&&in_data[63:48]==cancel_generation)begin
     feedback_confirmed<=1;feedback_confirmed_seen<=1;
    end
    remote_caption_running<=in_data[47:32]==transaction&&in_data[5:0]==held_scene&&in_data[88]&&!cancel_wait;
    live_scene<=in_data[5:0];epoch<=in_data[13:6];last_error<=in_data[21:14];
    debug_state<=in_data[29:22];audio_active<=in_data[30];remote_ready<=in_data[31];
    // Only current-command IDLE proves narration has completed. An early DONE
    // (SKIP), stale quiet snapshot or an image-load gap cannot unlock practice.
    voice_complete<=in_data[47:32]==transaction&&in_data[5:0]==held_scene&&in_data[90]&&in_data[31]&&!in_data[66]&&!cancel_wait;
    narration_quiet<=in_data[47:32]==transaction&&in_data[5:0]==held_scene&&
      in_data[90]&&in_data[31]&&!in_data[88]&&!in_data[66]&&!cancel_wait;
    if(cancel_wait&&in_data[63:48]==cancel_generation&&in_data[31]&&!in_data[66])begin
     cancel_wait<=0;force_snapshot<=1;
     present_seen<=present_sync[2];done_seen<=done_sync[2];
    end
    if(cmd_outstanding&&in_data[47:32]==transaction&&in_data[31]&&!in_data[66])cmd_outstanding<=0;
    // A can fault while B is already canceling/disarmed. A fault tagged with
    // the current cancel generation requires a fresh cancel/recovery barrier.
    // Older fault snapshots never advance generations or duplicate reports.
    if(in_data[66]&&in_data[63:48]==cancel_generation)begin
    media_recover<=1;
     if(armed&&!fault_seen)begin media_fault<=1;fault_seen<=1;end
     armed<=0;remote_ready<=0;cancel_wait<=1;
     cancel_generation<=cancel_generation+1'b1;narration_quiet<=0;
     cmd_pending<=0;cmd_outstanding<=0;force_snapshot<=1;settle_count<=4;
    end
   end
   if(link_up&&in_valid&&(in_length!=12||in_data[87:80]!=8'h43))begin
    peer_compatible<=0;remote_ready<=0;voice_complete<=0;narration_quiet<=0;
    if(armed&&!fault_seen)begin media_fault<=1;last_error<=8'he3;fault_seen<=1;end
    armed<=0;cmd_pending<=0;cmd_outstanding<=0;cancel_wait<=1;force_snapshot<=1;
   end
   if(cmd_valid&&cmd_ready)begin
    if(cmd_scene==8||cmd_scene==22)held_report_status<=status_data;
    narration_quiet<=0;voice_complete<=0;
    case(cmd_wipe_direction)
     2'd1:held_wipe_direction<=1;2'd2:held_wipe_direction<=2;2'd3:held_wipe_direction<=3;
     default:held_wipe_direction<=0;
    endcase
    transaction<=transaction+1'b1;held_scene<=cmd_scene;held_effect<=cmd_effect;
    case(cmd_question_set) 2'd1:held_question_set<=1;2'd2:held_question_set<=2;default:held_question_set<=0;endcase
    cmd_outstanding<=1;cmd_pending<=1;armed<=1;fault_seen<=0;
    present_seen<=present_sync[2];done_seen<=done_sync[2];
    force_snapshot<=1;settle_count<=8;
   end
   if(skip_page_request)begin skip_pending<=1;force_snapshot<=1;end
   if(cancel)begin
    feedback_confirmed<=0;feedback_confirmed_seen<=0;
    ui_owner<=0;green_requested<=0;ui_gpio_pending<=0;ui_identity_pending<=0;ui_confirmed_seen<=0;
    ui_presented<=0;ui_confirmed<=0;
    voice_complete<=0;
    media_presented<=0;media_done<=0;present_event_pipe<=0;done_event_pipe<=0;
    cancel_generation<=cancel_generation+1'b1;narration_quiet<=0;cancel_wait<=1;cmd_outstanding<=0;cmd_pending<=0;
    armed<=0;skip_pending<=0;force_snapshot<=1;settle_count<=4;
   end
   if(send_valid&&send_ready)begin
    send_valid<=0;refresh_count<=0;
    if(send_data[1280]&&send_data[1299:1284]==transaction)cmd_pending<=0;
    if(send_data[1283])skip_pending<=0;
   end
   // New accepted command has final priority over retiring an old packet.
   // cmd_ready already excludes cancel, so mode-off/recovery cannot re-arm.
   if(cmd_valid&&cmd_ready)cmd_pending<=1;
   if(snapshot_start)begin
    // M2 sees the media fact frozen on the same edge as status/practice/UI.
    // A voice-completion return during assembly belongs to the NEXT snapshot.
    snapshot_caption_running<=remote_caption_running;
    assembling<=1;scan_index<=0;scan_phase<=0;force_snapshot<=0;
   end else if(assembling)begin
    if(scan_phase==0)begin trend_read_address<={(send_data[897:896]==2'd1),1'b0,scan_index[4:0]};scan_phase<=1;end
    else if(scan_phase==1)scan_phase<=2;
    else begin
     scan_phase<=0;
     if(scan_index==31)begin assembling<=0;send_valid<=1;end
     else scan_index<=scan_index+1'b1;
    end
   end
  end
 end
 // Payload clear is synchronous; reset still asynchronously invalidates every
 // consumer. All reset-active clock edges clear the complete reserved tail too.
 always @(posedge clk)begin
  if(rst)send_data<=0;
  else if(snapshot_start)begin
    send_data<=0;
    send_data[159:0]<=(held_scene==8||held_scene==22)?held_report_status:status_data;
    send_data[959:160]<=history_data;
    send_data[984:960]<=session_data;send_data[1015:985]<=runtime_data;
    send_data[1277:1272]<=held_scene;send_data[1279:1278]<=held_effect;
    send_data[1280]<=cmd_pending;send_data[1281]<=cancel_wait;
    send_data[1282]<=skip_audio_wait;send_data[1283]<=skip_pending;
    send_data[1299:1284]<=transaction;send_data[1300]<=present_seen;send_data[1301]<=done_seen;
    send_data[1317:1302]<=cancel_generation;
    // reserved payload tail. Legacy disconnected inputs normalize to zero.
    send_data[1319:1318]<=held_question_set;
    send_data[1343:1320]<=(practice_data[23]===1'b1)?practice_data:24'd0;
    send_data[1351:1344]<=8'h43; // effect3; paired upgrade only
    send_data[1375:1352]<=interaction_data;
    send_data[1375]<=ui_owner;send_data[1374]<=green_requested;
    send_data[1383:1376]<=held_accepted_identity;
    send_data[1399:1384]<=held_accepted_transaction;
    send_data[1401:1400]<=held_wipe_direction;
    send_data[1407:1402]<=ui_seq;
    // LIVE/TEACH reserved union[73:64] = {sequence6,kind2,mask2}.
    // Capture with this snapshot, never from changing live inputs at publish.
    send_data[1089:1080]<=(feedback_kind==1||feedback_kind==2)?{feedback_seq,feedback_kind,feedback_mask}:10'd0;
    send_data[947:945]<=cancel_wait||(!armed&&!history_data[767])?3'd0:history_data[767]?(history_data[738]?3'd4:history_data[766]?3'd5:3'd3):
      ((held_scene==8||held_scene==22)?3'd5:practice_data[23]?3'd2:3'd1);
    // Non-trend views carry the B-prepared union; TREND is filled by the scan.
    // union is written after the same frozen status/context has settled.
  end else if(assembling)begin
   case(scan_phase)
    2'd0,2'd1:begin end
    default:begin
     if(send_data[927]&&send_data[898])send_data[1016+scan_index*8+:8]<=(scan_index<send_data[935:928])?trend_read_point:8'd0;
     else if(scan_index==0)begin
      send_data[1271:1016]<=send_data[947:945]==0?256'd0:prepared_union;
     end
    end
   endcase
  end
 end
endmodule

`default_nettype wire
