
`default_nettype none
`timescale 1ns/1ps
// Media slave A. User controls are connected to B; legacy A inputs
// are retained only to preserve the original physical pin map.
module top(
    input wire uart_rx,output wire uart_tx,
    output wire gpio_presented_out,output wire gpio_done_out,output wire gpio_link_ready_out,
    input wire                       clk,
    input wire                       rst_n,          // Retained physical input; user controls are handled by B.
    input wire                       key1,           // Retained physical KEY2 input.
    input wire                       key2,           // Retained physical KEY4 input.
    input wire                       key3,           // Retained physical KEY3 input.
    input wire                       sw1, sw2, sw3, sw4,
    output wire                      buzzer_n,
    output wire [3:0]                led_n,

    output wire [5:0]                seg_sel,
    output wire [7:0]                seg_data,

    // HDMI TMDS
    output wire                      HDMI_CLK_P,
    output wire                      HDMI_D2_P,
    output wire                      HDMI_D1_P,
    output wire                      HDMI_D0_P,

    // HDMI DDC
    output wire                      HDMI_DDC_SCL,
    inout wire                       HDMI_DDC_SDA,

    // TF card SPI
    output wire                      sd_ncs,
    output wire                      sd_dclk,
    output wire                      sd_mosi,
    input wire                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter [ADDR_BITS-1:0] FRAME_PIXELS  = 21'd307200;   // 640*480
parameter [ADDR_BITS-1:0] BUF0_ADDR     = 21'd0;
parameter [ADDR_BITS-1:0] BUF1_ADDR     = FRAME_PIXELS;
parameter [ADDR_BITS-1:0] BUF2_ADDR     = FRAME_PIXELS*2;
parameter [ADDR_BITS-1:0] BUF3_ADDR     = FRAME_PIXELS*3;
parameter AUDIO_TEST_MODE= 0;
// 1..32 frames per fade direction; disabled selects direct frame commit.
parameter IMAGE_TRANSITION_ENABLE = 1;
parameter IMAGE_TRANSITION_FRAMES = 16;
parameter RUNTIME_CONTROLS_ENABLE = 1;
parameter KEEP_PREVIOUS_ENABLE = 1;

generate if(ADDR_BITS!=21||MEM_DATA_BITS!=32||FRAME_PIXELS!=307200||
 {1'b0,BUF3_ADDR}+FRAME_PIXELS>22'd2097152)begin:g_invalid_geometry
 C28_UNSUPPORTED_FRAME_GEOMETRY invalid_parameter_configuration();
end endgenerate

wire Sdr_init_done;
wire Sdr_refresh_fault;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire sys_pll_lock,video_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
wire rst_all;
wire media_device_reset;
wire rst_sd,rst_mem,rst_pixel,rst_audio;
wire frame_rst_mem,frame_rst_pixel;
(* ASYNC_REG="TRUE" *)reg [1:0] refresh_fault_pixel;
always @(posedge video_clk or posedge rst_pixel)
 if(rst_pixel)refresh_fault_pixel<=0;else refresh_fault_pixel<={refresh_fault_pixel[0],Sdr_refresh_fault};
(* ASYNC_REG="TRUE" *)reg [1:0] refresh_fault_sd;
always @(posedge sd_card_clk or posedge rst_sd)
 if(rst_sd)refresh_fault_sd<=0;else refresh_fault_sd<={refresh_fault_sd[0],Sdr_refresh_fault};

recovery_reset_sync rs0(sd_card_clk,rst_all,rst_sd);
recovery_reset_sync rs1(ext_mem_clk,rst_all,rst_mem);
recovery_reset_sync rs2(video_clk,rst_all,rst_pixel);
recovery_reset_sync rs3(audio_mclk,rst_all,rst_audio);
recovery_reset_sync rs4(ext_mem_clk,rst_all|media_device_reset,frame_rst_mem);
recovery_reset_sync rs5(video_clk,rst_all|media_device_reset,frame_rst_pixel);
// physical KEY1 no longer asserts any system reset. Existing PLL-lock
// startup/reset and every domain-local reset synchronizer remain in use.
// adapters expose every PLL lock with unchanged primitive parameters.
// Loss of any lock asserts reset; each local release remains synchronized.
assign rst_all=~(audio_pll_lock&&sys_pll_lock&&video_pll_lock);
wire startup_wait_reset;
recovery_startup_wait #(.WAIT_BITS(19)) u_startup_wait(
 .clk(clk),.arst(rst_all),.reset(startup_wait_reset));
// Keep original domain reset topology. Wait qualification crosses as DATA
// into the existing 100MHz application clock, never as an async reset from
// refclk into unrelated audio/video FFs. Both stages remain fully timed.
(* ASYNC_REG="TRUE" *)reg [1:0] startup_ready_sd;
always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)startup_ready_sd<=0;
 else startup_ready_sd<={startup_ready_sd[0],!startup_wait_reset};
end

// 保持你原来的 TF / SDRAM / video 时钟
recovery_sys_pll_locked sys_pll_m0(
    .locked(sys_pll_lock),
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

recovery_video_pll_locked video_pll_m0(
    .locked(video_pll_lock),
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);

// 复用你 I2S->HDMI 工程里的 PLL，保留生成文件的 12.295082MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// Four logical frame regions. Frozen controller source retained; uses
// authorized 40MHz SDRAM clocks, matched periods/refresh, and SD100MHz.
wire media_cmd_valid,media_cmd_ready,media_cancel,media_done,media_presented,media_fault;
wire app_cmd_valid,app_cmd_ready,app_cancel,media_skip_request,history_exit;
wire [5:0] app_scene;wire [1:0] app_effect;
reg history_snapshot_delivered;
wire [5:0] media_scene,live_scene,result_valid;wire [7:0] app_state,media_state,last_media_error,epoch;
wire alarm_active,input_armed,nurse_enabled,release_prompt;wire [1:0] active_mode;
wire [1:0] pacu_p,pacu_a,pacu_valid,t1_correct,t2_correct,t3_result,t1_unanswered,t2_unanswered;
wire [15:0] rt_ms,hold_ms;wire [2:0] rt_status,hold_status,pain;wire [3:0] fault_code;
wire education_countdown_active,retest_due;wire [15:0] retest_seconds;
wire [2:0] limb_count;wire [3:0] limb_answers,limb_valid;wire [1:0] last_report_mode;
wire [2:0] report_outcome;wire [5:0] report_started;
wire [31:0] rt_cycles;wire [3:0] bank_valid,protect_mask;wire audio_active;
wire commit_valid,commit_ready,frame_presented,frame_present_error,commit_busy;
wire commit_ready_raw,report_snapshot_ready;
wire teaching_snapshot_ready; // Declared before its first commit qualification use.
wire [1:0] commit_bank,active_bank,presented_bank;wire [5:0] commit_scene,presented_scene;
wire [7:0] commit_epoch,presented_epoch;wire frame_read_req,mem_read_ack;
wire pixel_presented,pixel_display_valid;wire [5:0] pixel_scene;wire [7:0] pixel_epoch;
wire canvas_prepare,canvas_valid;wire [5:0] canvas_scene;wire [7:0] canvas_epoch;
wire [8:0] transition_gain;
wire [9:0] transition_reveal_width;
wire transition_wipe_active;
wire [1:0] transition_direction,cmd_wipe_direction;
reg [1:0] command_wipe_direction;
wire [23:0] remote_interaction;
wire [7:0] remote_accepted_identity;
wire [15:0] remote_accepted_transaction,remote_transaction;
reg [15:0] command_transaction,shown_transaction;
wire voice_active,music_active,voice_complete;
wire [1:0] media_effect,commit_effect,adjust_mode;
wire patient_inhibit;
wire skip_audio_wait,report_generated;
wire [159:0] remote_status;
wire [799:0] history_pixel;wire [31:0] history_meta;
wire [24:0] remote_session;
wire [30:0] remote_runtime;
wire [6:0] remote_ui_seq;
wire mb_build_req,mb_build_grant,rx_display_valid,mb_read,mb_read_locked,mb_build_done,mb_ready,mb_fault;
wire ui_event_valid,ui_event_ready;wire [19:0] ui_event_identity;
wire feedback_event_valid,feedback_event_ready;wire [19:0] feedback_event_identity;
wire [31:0] mb_bank_session;wire [15:0] mb_bank_sequence;
wire [7:0] mb_bank_addr,mb_bank_data;
wire board_link_up;
wire history_enabled=history_meta[31];
wire signed [8:0] brightness=remote_runtime[27:19];
wire [9:0] contrast_gain=remote_runtime[18:9];
wire [8:0] volume_gain=remote_runtime[8:0];
assign adjust_mode=remote_runtime[29:28];
assign patient_inhibit=0;
assign app_state=remote_status[85:78];
assign active_mode=remote_status[77:76];
assign input_armed=remote_status[75];
assign release_prompt=remote_status[74];
assign nurse_enabled=remote_status[73];
assign education_countdown_active=remote_status[114];
assign retest_due=remote_status[113];
assign retest_seconds=remote_status[112:97];
assign {limb_count,limb_answers,limb_valid,pacu_valid,pacu_p,pacu_a,
 t1_correct,t2_correct,t3_result,rt_ms,rt_status,hold_ms,hold_status,pain,result_valid}=
 {remote_status[96:86],remote_status[72:14]};
assign {last_report_mode,report_started,report_outcome,fault_code,t1_unanswered,t2_unanswered}=
 {remote_status[158:157],remote_status[148:143],remote_status[142:140],
 remote_status[139:136],remote_status[135:134],remote_status[133:132]};
assign alarm_active=0; // B retains the original buzzer/alarm owner.
assign report_generated=0;
wire [1:0] cmd_question_set;wire [23:0] remote_practice;
wire [30:0] caption_audio_data,caption_pixel;
wire caption_audio_rst;
recovery_media_bridge u_board_link(
 .clk(sd_card_clk),.rst(rst_sd),.uart_rx(uart_rx),.uart_tx(uart_tx),
 .gpio_presented_out(gpio_presented_out),.gpio_done_out(gpio_done_out),.gpio_link_ready_out(gpio_link_ready_out),
 .cmd_valid(media_cmd_valid),.cmd_ready(media_cmd_ready),.cmd_scene(media_scene),
 .cmd_effect(media_effect),.cancel(media_cancel),.skip_audio_wait(skip_audio_wait),
 .cmd_question_set(cmd_question_set),.practice_data(remote_practice),
 .interaction_data(remote_interaction),.accepted_identity(remote_accepted_identity),
 .accepted_transaction(remote_accepted_transaction),.visible_transaction(remote_transaction),
 .cmd_wipe_direction(cmd_wipe_direction),
 .skip_page_request(media_skip_request),.status_data(remote_status),
 .history_meta(history_meta),.session_data(remote_session),.runtime_data(remote_runtime),
 .ui_seq(remote_ui_seq),.link_up(board_link_up),
 .build_req(mb_build_req),.build_read(mb_read),.build_locked(mb_read_locked),.build_done(mb_build_done),
 .mailbox_ready(mb_ready),.mailbox_fault(mb_fault),.build_grant(mb_build_grant),.display_valid(rx_display_valid),
 .display_session(mb_bank_session),.display_sequence(mb_bank_sequence),
 .build_addr(mb_bank_addr),.build_data(mb_bank_data),
 .ui_event_valid(ui_event_valid),.ui_event_identity(ui_event_identity),.ui_event_ready(ui_event_ready),
 .feedback_event_valid(feedback_event_valid),.feedback_event_identity(feedback_event_identity),.feedback_event_ready(feedback_event_ready),
 .media_presented(media_presented),.media_done(media_done),.media_fault(media_fault),
 .last_error(last_media_error),.debug_state(media_state),.epoch(epoch),
 .live_scene(live_scene),.audio_active(audio_active),
 .voice_active(voice_active),.music_active(music_active),.voice_complete(voice_complete));
always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)begin command_wipe_direction<=0;command_transaction<=0;shown_transaction<=0;end
 else begin
  if(media_cmd_valid&&media_cmd_ready)begin
   command_wipe_direction<=cmd_wipe_direction;command_transaction<=remote_transaction;
  end
  if(frame_presented)shown_transaction<=command_transaction;
 end
end
wire write_fifo_full,read_fifo_empty,video_locked;
reg [1:0] read_underflow_pipe;
reg video_lock_seen;reg [23:0] video_lock_wait;
wire video_lock_fault=pixel_display_valid&&!video_locked&&(video_lock_seen||video_lock_wait>=12500000);
always @(posedge video_clk or posedge frame_rst_pixel)begin
 if(frame_rst_pixel)begin video_lock_seen<=0;video_lock_wait<=0;end
 else begin
  if(video_locked)video_lock_seen<=1;
  if(!pixel_display_valid||video_locked)video_lock_wait<=0;
  else if(video_lock_wait<12500000)video_lock_wait<=video_lock_wait+1;
 end
end
always @(posedge video_clk or posedge frame_rst_pixel)begin
 if(frame_rst_pixel)read_underflow_pipe<=0;
 else read_underflow_pipe<={read_underflow_pipe[0],video_read_en&&read_fifo_empty};
end
reg mem_ready1,mem_ready2,wr_ack1,wr_ack2,finish1,finish2,finish_seen;
reg write_drain_pending;reg [6:0] write_drain_count;
wire qualified_write_finish=finish2!=finish_seen;
always @(posedge ext_mem_clk or posedge frame_rst_mem)begin
 if(frame_rst_mem)begin frame_write_toggle_mem<=0;write_drain_pending<=0;write_drain_count<=0;end
 else begin
  if(frame_write_finish)begin write_drain_pending<=1;write_drain_count<=64;end
  else if(write_drain_pending)begin
   if(write_drain_count!=0)write_drain_count<=write_drain_count-1'b1;
   else if(!Sdr_busy&&!App_wr_en)begin frame_write_toggle_mem<=~frame_write_toggle_mem;write_drain_pending<=0;end
  end
 end
end
always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)begin mem_ready1<=0;mem_ready2<=0;wr_ack1<=0;wr_ack2<=0;finish1<=0;finish2<=0;finish_seen<=0;end
 else begin
  mem_ready1<=Sdr_init_done;mem_ready2<=mem_ready1;wr_ack1<=sd_card_write_req_ack;wr_ack2<=wr_ack1;
  finish1<=frame_write_toggle_mem;finish2<=finish1;finish_seen<=finish2;
 end
end
wire pcm_bclk,pcm_lrck,pcm_dout;
recovery_media_controller #(.REQUEST_EFFECT_ENABLE(1),.KEEP_PREVIOUS_ENABLE(KEEP_PREVIOUS_ENABLE),
 .VOLUME_ENABLE(RUNTIME_CONTROLS_ENABLE)) u_media(
 .clk(sd_card_clk),.rst(rst_sd),.audio_mclk(audio_mclk),.audio_rst(rst_audio),.mem_ready(mem_ready2&&startup_ready_sd[1]&&!refresh_fault_sd[1]),
 .cmd_valid(media_cmd_valid),.cmd_ready(media_cmd_ready),.cmd_scene(media_scene),.cancel(media_cancel),
 .cmd_question_set(cmd_question_set),.caption_audio_data(caption_audio_data),.caption_audio_rst(caption_audio_rst),
 .skip_audio_wait(skip_audio_wait),
 .voice_active(voice_active),.music_active(music_active),.voice_complete(voice_complete),
 .skip_page_request(media_skip_request&&!history_enabled),
 .cmd_effect(media_effect),.commit_effect(commit_effect),.volume_gain(volume_gain),
 .scene_done(media_done),.scene_presented(media_presented),.media_error(media_fault),.last_error(last_media_error),
 .live_scene(live_scene),.epoch(epoch),.device_reset(media_device_reset),.audio_active(audio_active),.bank_valid(bank_valid),
 .protect_mask(protect_mask),.commit_valid(commit_valid),.commit_ready(commit_ready),.commit_bank(commit_bank),
 .commit_scene(commit_scene),.commit_epoch(commit_epoch),.presented(frame_presented),.present_error(frame_present_error),
 .presented_scene(presented_scene),.presented_epoch(presented_epoch),.write_req(sd_card_write_req),
 .write_req_ack(wr_ack2),.write_bank(write_buf_idx),.write_en(sd_card_write_en),.write_data(sd_card_write_data),
 .write_full(write_fifo_full),.write_finish(qualified_write_finish),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),
 .SD_MOSI(sd_mosi),.SD_MISO(sd_miso),.debug_state(media_state),
 .i2s_bclk(pcm_bclk),.i2s_lrck(pcm_lrck),.i2s_dout(pcm_dout));
recovery_frame_commit #(.TRANSITION_ENABLE(IMAGE_TRANSITION_ENABLE),
 .TRANSITION_FRAMES(IMAGE_TRANSITION_FRAMES),.TRANSITION_FRAME_PIXELS(FRAME_PIXELS),
 .REQUEST_EFFECT_ENABLE(1),.THEMED_TRANSITION_ENABLE(1)) u_commit(
 .src_clk(sd_card_clk),.src_rst(rst_sd|media_device_reset),.current_epoch(epoch),.cancel(media_cancel),
 .commit_valid(commit_valid&&report_snapshot_ready&&teaching_snapshot_ready),.commit_ready(commit_ready_raw),.commit_bank(commit_bank),.commit_scene(commit_scene),
 .commit_epoch(commit_epoch),.protect_mask(protect_mask),.active_bank(active_bank),.presented(frame_presented),
 .commit_effect(commit_effect),
 .commit_direction(command_wipe_direction),
 .present_error(frame_present_error),.presented_bank(presented_bank),.presented_scene(presented_scene),
 .presented_epoch(presented_epoch),.busy(commit_busy),.pixel_clk(video_clk),.pixel_rst(frame_rst_pixel),
 .video_read_req(video_read_req),.video_read_ack(video_read_req_ack),.frame_read_req(frame_read_req),
 .mem_read_ack(mem_read_ack),.reader_bank(disp_buf_idx),.axis_user(axis_s_user),.axis_valid(axis_s_valid),
 .axis_ready(axis_s_ready),.pixel_fault((pixel_display_valid&&de&&(read_underflow_pipe[1]||video_lock_fault))||refresh_fault_pixel[1]),
 .pixel_presented(pixel_presented),.pixel_scene(pixel_scene),.pixel_epoch(pixel_epoch),.pixel_display_valid(pixel_display_valid),
 .canvas_prepare(canvas_prepare),.canvas_valid(canvas_valid),.canvas_scene(canvas_scene),.canvas_epoch(canvas_epoch),
 .transition_gain(transition_gain),.transition_reveal_width(transition_reveal_width),
 .transition_wipe_active(transition_wipe_active),.transition_direction(transition_direction));
assign display_valid=pixel_display_valid;
assign state_code=last_media_error!=0?4'hf:app_state[3:0];
reg [26:0] buzz_count;reg [15:0] buzz_div;reg buzz_wave;
always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)begin buzz_count<=0;buzz_div<=0;buzz_wave<=0;end
 else begin
  if(buzz_count==99999999)buzz_count<=0;else buzz_count<=buzz_count+1;
  if(buzz_div==49999)begin buzz_div<=0;buzz_wave<=~buzz_wave;end else buzz_div<=buzz_div+1;
 end
end
assign buzzer_n=!(alarm_active&&!audio_active&&buzz_count<30000000&&buzz_wave);
assign led_n=~{(last_media_error!=0||fault_code>=2),alarm_active,(active_mode!=0),(active_mode==0&&last_media_error==0)};
// report fields and their metadata are one immutable transaction snapshot.
// Low 128 bit positions remain compatible; the high 32 bits carry the report
// mode/epoch/started/outcome/validity context. Existing wildcard CDC constraints
// cover all hold_data[*] -> dst_data[*] bits without changing timing.sdc.
wire [69:0] report_live_fields={limb_count,limb_answers,limb_valid,
 pacu_valid,pacu_p,pacu_a,t1_correct,t2_correct,t3_result,rt_ms,rt_status,hold_ms,hold_status,pain,result_valid};
wire [69:0] report_fields;wire [31:0] report_metadata;
wire report_capture=media_cmd_valid&&media_cmd_ready&&(media_scene==6'd8||media_scene==6'd22);
recovery_report_snapshot u_report_snapshot(.clk(sd_card_clk),.rst(rst_sd),.capture(report_capture),
 .report_mode(last_report_mode),.report_epoch(epoch),.started(report_started),.outcome(report_outcome),.fault(fault_code),
 .t1_unanswered(t1_unanswered),.t2_unanswered(t2_unanswered),.fields(report_live_fields),
 .metadata(report_metadata),.snapshot_fields(report_fields));
// six-test engineering score comes from the immutable report snapshot.
// Reuse reserved bits; existing business/status/CDC field positions stay fixed.
reg [6:0] snapshot_ward_score;
wire snapshot_ward_score_valid=report_metadata[31]&&report_metadata[30:29]==2'd2;
// B computes the score and sends it atomically with the report fields.
// A captures that value on the same edge as its immutable report snapshot.
always @(posedge sd_card_clk or posedge rst_sd)
 if(rst_sd)snapshot_ward_score<=0;
 else if(report_capture)snapshot_ward_score<=remote_status[121:115];
wire [159:0] status_src={report_metadata,5'd0,snapshot_ward_score_valid,snapshot_ward_score,education_countdown_active,retest_due,retest_seconds,
 report_fields[69:59],app_state,active_mode,input_armed,release_prompt,nurse_enabled,
 report_fields[58:0],live_scene,last_media_error};
reg [7:0] mailbox_display_error;
reg board_link_seen;
always @(posedge sd_card_clk or posedge rst_sd)
 if(rst_sd)board_link_seen<=0;else board_link_seen<=board_link_up;
always @(posedge sd_card_clk or posedge rst_sd)
 if(rst_sd)mailbox_display_error<=0;
 else if(mb_fault)mailbox_display_error<=8'he4;
 else if(board_link_seen&&!board_link_up)mailbox_display_error<=8'he1;
 else if(media_cmd_valid&&media_cmd_ready)mailbox_display_error<=0;
wire [7:0] local_display_error=last_media_error!=0?last_media_error:mailbox_display_error;
wire [159:0] status_pixel,status_echo;wire status_settled;
// One acknowledged frame snapshot binds UI, report, history, runtime,
// session and every trend sample. No independent cross-board pixel reads.
// Compare reliable transaction identities in their common 100MHz source
// domain. Only the resulting scoped feedback, scene/set and epoch need cross
// the existing held mailbox; repeated 16-bit identities need not be stored
// a second time in the pixel domain.
wire source_feedback_scope=board_link_up&&shown_transaction==remote_transaction;
wire source_feedback_accept=remote_accepted_identity[5:0]==media_scene&&
 remote_accepted_identity[7:6]==cmd_question_set&&remote_accepted_transaction==remote_transaction;
wire source_feedback_button=remote_practice[23]||remote_interaction[2]||source_feedback_accept;
wire [23:0] source_interaction={remote_interaction[23:7],
 remote_interaction[6]&&source_feedback_accept,remote_interaction[5:2],
 remote_interaction[1]&&source_feedback_button,remote_interaction[0]&&source_feedback_button};
// one 896-bit held display mailbox (header96 + body800).


wire [895:0] joint_pixel;
wire local_safe_fault,report_canvas_ready;
wire runtime_frame_boundary;
wire mb_kill=media_cancel||media_device_reset||(!board_link_up&&local_display_error==0);
wire [95:0] mb_header={8'h43,history_enabled?3'd3:3'd1,rx_display_valid,
 2'b00,history_meta[30]&&history_enabled,1'b0,media_scene,cmd_question_set,epoch,remote_ui_seq[5:0],
 source_feedback_scope,1'b0,remote_runtime,remote_session};
wire pixel_ui_valid;
wire mb_ack,mb_ack_report,mb_ack_history;wire [31:0] mb_ack_key,mb_history_meta,mb_token;
wire mb_ack_display;wire [15:0] mb_ack_transaction,mb_ack_identity;
recovery_teaching_handoff_guard u_teaching_handoff(
 .clk(sd_card_clk),.rst(rst_sd),.withdraw(media_cancel||media_device_reset||!board_link_up||!mb_ready||mb_fault),
 .new_command(media_cmd_valid&&media_cmd_ready),.required((remote_practice[1]||(commit_effect==0&&
  (commit_scene==2||(commit_scene>=10&&commit_scene<=12))))&&commit_scene!=6'd19),
 .ack_valid(mb_ack_display),.ack_transaction(mb_ack_transaction),.ack_identity(mb_ack_identity),
 .transaction(command_transaction),.identity({media_scene,cmd_question_set,epoch}),.ready(teaching_snapshot_ready));
reg [31:0] report_key;reg report_capture_valid;reg [15:0] report_capture_transaction;
always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)begin report_key<=0;report_capture_valid<=0;report_capture_transaction<=0;end
 else if(media_cancel||media_device_reset||!board_link_up)report_capture_valid<=0;
 else if(report_capture)begin
  report_key<=report_key+1'b1;report_capture_valid<=1;report_capture_transaction<=remote_transaction;
 end
end
recovery_status_mailbox #(.WIDTH(31)) u_caption_status(
 .src_clk(audio_mclk),.src_rst(caption_audio_rst),.src_data(caption_audio_data),
 .dst_clk(video_clk),.dst_rst(frame_rst_pixel),.frame_boundary(runtime_frame_boundary),
 .dst_data(caption_pixel),.src_settled(),.src_echo());
recovery_display_mailbox u_status(
 .src_clk(sd_card_clk),.src_rst(rst_sd),.payload_valid(rx_display_valid),
 .bank_session(mb_bank_session),.bank_sequence(mb_bank_sequence),.local_status({status_src[159:8],local_display_error}),.header(mb_header),.kill(mb_kill),
 .capture_valid(report_capture_valid),.capture_transaction(report_capture_transaction),.capture_key(report_key),
 .build_req(mb_build_req),.build_grant(mb_build_grant),.bank_addr(mb_bank_addr),.bank_data(mb_bank_data),
 .read_request(mb_read),.read_locked(mb_read_locked),.src_settled(status_settled),.build_done(mb_build_done),
 .source_ready(mb_ready),.source_fault(mb_fault),.ack_event(mb_ack),.ack_report(mb_ack_report),.ack_history(mb_ack_history),
 .ack_report_key(mb_ack_key),.ack_history_meta(mb_history_meta),.display_token(mb_token),
 .acknowledged_valid(mb_ack_display),.acknowledged_transaction(mb_ack_transaction),.acknowledged_identity(mb_ack_identity),
 .dst_clk(video_clk),.dst_rst(rst_pixel),.frame_boundary(runtime_frame_boundary),.dst_data(joint_pixel),.pixel_ui_valid(pixel_ui_valid));
wire [2:0] pixel_kind=joint_pixel[887:885];
wire pixel_history=pixel_ui_valid&&(pixel_kind==3||pixel_kind==4||(pixel_kind==5&&joint_pixel[881]));
wire [23:0] practice_raw=pixel_kind==5?joint_pixel[687:664]:
 (pixel_kind<=2?joint_pixel[183:160]:24'd0);
// B deliberately zeros inactive practice bytes on the existing UART wire.
// Source-scoped DIRECT is unique to the audited four normal teaching edges.
// Recover visual hold locally from complete future UI and old canvas identity;
// no new packet bit, state bank, clock crossing or patient qualification.
wire direct_teaching_pixel=transition_gain==256&&!transition_wipe_active;
wire narrated_handoff=direct_teaching_pixel&&
 (canvas_scene==1||(canvas_scene>=9&&canvas_scene<=11))&&
 joint_pixel[879:874]==canvas_scene+6'd1;
wire [23:0] practice_pixel={practice_raw[23:2],practice_raw[1]||narrated_handoff,practice_raw[0]};
wire [255:0] ui_union_pixel=pixel_kind==5?joint_pixel[663:408]:
 (pixel_kind<=2?joint_pixel[463:208]:256'd0);
wire [23:0] interaction_data_pixel=pixel_kind==5?joint_pixel[711:688]:
 (pixel_kind<=2?joint_pixel[207:184]:24'd0);
wire [40:0] interaction_pixel={joint_pixel[857],interaction_data_pixel,
 joint_pixel[879:874],joint_pixel[873:872],joint_pixel[871:864]};
wire feedback_scope_ok=pixel_ui_valid&&interaction_pixel[40]&&interaction_pixel[15:10]==pixel_scene&&
 interaction_pixel[7:0]==pixel_epoch;
// A prepared teaching view may draw as soon as the matching physical canvas
// changes. Patient markers remain independently gated by feedback_scope_ok.
wire teaching_visual_scope=pixel_ui_valid&&canvas_valid&&
 (practice_pixel[1]||(direct_teaching_pixel&&(canvas_scene==2||(canvas_scene>=10&&canvas_scene<=12))))&&
 interaction_pixel[15:10]==canvas_scene&&interaction_pixel[7:0]==canvas_epoch;
wire [23:0] themed_feedback=feedback_scope_ok?interaction_pixel[39:16]:24'd0;
assign status_pixel=pixel_kind==5?joint_pixel[343:184]:pixel_kind==4?joint_pixel[479:320]:joint_pixel[159:0];
// Consumers retain a combinational history800 port; only the applicable
// GALLERY/metadata/selected raw view is reconstructed from dst896 (no FF copy).
assign history_pixel=!pixel_history?800'd0:pixel_kind==3?joint_pixel[799:0]:
 pixel_kind==4?{joint_pixel[319:256],736'd0}:{joint_pixel[407:344],736'd0};
// A cached report must not commit before the same snapshot is delivered. Only
// immutable report fields are compared; live prompts/scene/countdown may change.
// Compare the held echo in bounded groups, then register delivery. A wide
// combinational comparison on commit_ready would enter the bank/media FSM's
// 100MHz control paths. Live prompt updates need not withdraw a delivered
// immutable report; every new capture/cancel invalidates this barrier.
reg report_snapshot_delivered;
always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)report_snapshot_delivered<=0;
 else if(report_capture||media_cancel||media_device_reset||!board_link_up||mb_fault)report_snapshot_delivered<=0;
 else if(mb_ack_report&&report_capture_valid&&mb_ack_key==report_key)report_snapshot_delivered<=1;
end
assign report_snapshot_ready=(commit_scene==6'd29||commit_scene==6'd30)?history_snapshot_delivered:
 ((commit_scene!=6'd8&&commit_scene!=6'd22)||report_snapshot_delivered);
assign commit_ready=commit_ready_raw&&report_snapshot_ready&&teaching_snapshot_ready;
wire [159:0] status_osd={status_pixel[159:14],pixel_kind==0?6'd0:canvas_scene,status_pixel[7:0]};
wire physical_report=canvas_valid&&(canvas_scene==8||canvas_scene==22||canvas_scene==29||canvas_scene==30);
// Session records capture business fields at the report-generation event,
// including interrupted rounds. Viewing an old report never emits this event.
wire [23:0] session_bcd=remote_session[23:0];
wire [6:0] history_trend_read_address;
reg [7:0] history_trend_read_point;
always @(posedge video_clk)
 history_trend_read_point<=history_trend_read_address<32?
  joint_pixel[history_trend_read_address[4:0]*8+:8]:8'd0;
// TREND has exactly 32 bytes. Narrow the physical RAM/mux address before
// selection: an out-of-range request must never read a different union field.
wire history_source_valid=history_enabled&&history_meta[31]&&history_meta[30]&&
 !history_meta[2]&&history_meta[25+history_meta[4:3]];
// The packet's count/page/focus metadata identifies immutable stored records.
// Observe acknowledgement in the source domain before releasing the new BMP.
always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)history_snapshot_delivered<=0;
 else if(media_cancel||media_device_reset||!board_link_up||!history_source_valid||mb_fault)history_snapshot_delivered<=0;
 else if(mb_ack_history&&mb_history_meta==history_meta)history_snapshot_delivered<=1;
end
wire [23:0] osd_rgb;reg osd_de,osd_vs,osd_de_stage,osd_vs_stage;
reg runtime_frame_previous,runtime_boundary_d;
assign runtime_frame_boundary=video_read_req&&!runtime_frame_previous;
always @(posedge video_clk or posedge rst_pixel)begin
 if(rst_pixel)begin runtime_frame_previous<=0;runtime_boundary_d<=0;end
 else begin runtime_frame_previous<=video_read_req;runtime_boundary_d<=runtime_frame_boundary;end
end
wire [30:0] runtime_pixel;
wire [24:0] session_pixel=joint_pixel[824:800];
assign runtime_pixel=joint_pixel[855:825];
wire signed [8:0] pixel_brightness=runtime_pixel[30]?runtime_pixel[27:19]:9'd0;
wire [9:0] pixel_contrast=runtime_pixel[30]?runtime_pixel[18:9]:10'd256;
wire [8:0] pixel_volume=runtime_pixel[30]?runtime_pixel[8:0]:9'd256;
wire [1:0] pixel_adjust_mode=runtime_pixel[30]?runtime_pixel[29:28]:2'd0;
wire [23:0] adjusted_rgb,pre_osd_rgb;
wire pre_osd_de,pre_osd_vs;
generate if(RUNTIME_CONTROLS_ENABLE != 0)begin:g_image_adjust
 wire [23:0] adjust_comb;reg [23:0] adjust_q;reg de_q,vs_q;
 recovery_image_adjust u_adjust(.rgb(display_valid?vout_data_raw:24'h102030),
  .brightness(pixel_brightness),.contrast_gain(pixel_contrast),.adjusted_rgb(adjust_comb));
 // Ordinary display pipeline; retain the reset value on clock edges.
 always @(posedge video_clk)begin
  if(frame_rst_pixel)begin adjust_q<=0;de_q<=0;vs_q<=0;end
  else begin adjust_q<=adjust_comb;de_q<=de;vs_q<=vs;end
 end
 assign pre_osd_rgb=(pixel_ui_valid&&pixel_kind==5&&!physical_report&&!report_canvas_ready)?24'heef6fb:adjust_q;
 assign pre_osd_de=de_q;assign pre_osd_vs=vs_q;
end else begin:g_image_bypass
 assign pre_osd_rgb=display_valid?vout_data_raw:24'h102030;
 assign pre_osd_de=de;assign pre_osd_vs=vs;
end endgenerate
always @(posedge video_clk or posedge frame_rst_pixel)begin
 if(frame_rst_pixel)begin osd_de<=0;osd_vs<=0;osd_de_stage<=0;osd_vs_stage<=0;end else begin osd_de_stage<=pre_osd_de;osd_vs_stage<=pre_osd_vs;osd_de<=osd_de_stage;osd_vs<=osd_vs_stage;end
end
// DETAIL bodies carry the focused raw record in slot 0 (display mailbox map).
// REPORT status is the same selected raw record as body[183:0]. Share the
// existing view decoder; keep the complete raw184 in the transported body.
wire [159:0] history_selected_status=status_pixel;
wire history_pixel_detail_valid=history_pixel[767]&&history_pixel[766]&&!history_pixel[738]&&
 history_pixel[761+history_pixel[740:739]];
wire history_detail_ready=history_pixel_detail_valid&&display_valid&&
 pixel_scene==(history_selected_status[158:157]==2'd1 ? 6'd29 : 6'd30);
assign report_canvas_ready=pixel_ui_valid&&canvas_valid&&canvas_scene==
 (joint_pixel[881]?(status_pixel[158:157]==1?6'd29:6'd30):(status_pixel[158:157]==1?6'd8:6'd22))&&
 canvas_scene==joint_pixel[879:874]&&canvas_epoch==joint_pixel[871:864];
// Prepare historical fields in vertical blank while their BMP is loading.
// Only glyph drawing waits for the matching presented image, so the first
// visible report frame already uses the selected immutable snapshot.
wire [159:0] result_display_status=history_pixel[767]?
 (history_pixel_detail_valid?history_selected_status:160'd0):status_osd;
wire [7:0] result_display_epoch=history_pixel[767]?history_selected_status[156:149]:pixel_epoch;
wire [10:0] result_message_address,history_message_address;
wire [6:0] result_message_q,history_message_q;
recovery_shared_messages u_display_messages(.clk(video_clk),.result_address(result_message_address),
 .history_address(history_message_address),.result_q(result_message_q),.history_q(history_message_q));
recovery_result_osd #(.SHARED_ROM(1),.INPUT_FRAME_COMMITTED(1),.LEGACY_HINTS_ENABLE(0),
 .THEMED_COUNTDOWN_ENABLE(1),.CANVAS_GUARD_ENABLE(1)) u_results(.clk(video_clk),.rst(frame_rst_pixel),.vs(pre_osd_vs),
 .de(pre_osd_de),.waiting_report(pixel_ui_valid&&pixel_kind==5&&!physical_report&&!report_canvas_ready),
 .canvas_valid(canvas_valid),.canvas_prepare(canvas_prepare),.canvas_scene(canvas_scene),.canvas_epoch(canvas_epoch),
 .report_input_valid(pixel_ui_valid&&pixel_kind==5),.report_input_scene(joint_pixel[879:874]),.report_input_epoch(joint_pixel[871:864]),
 .emergency_clear(local_safe_fault||!canvas_valid),
 .rgb(pre_osd_rgb),.status(result_display_status),
 .report_text(ui_union_pixel),.shared_message_address(result_message_address),.shared_message_q(result_message_q),.out_rgb(osd_rgb),.display_epoch(result_display_epoch));
wire [23:0] history_rgb;reg history_de,history_vs,history_de_pipe,history_vs_pipe;
reg history_de_pipe2,history_vs_pipe2,history_de_pipe3,history_vs_pipe3;
always @(posedge video_clk or posedge frame_rst_pixel)begin
 if(frame_rst_pixel)begin
  history_de<=0;history_vs<=0;history_de_pipe<=0;history_vs_pipe<=0;
  history_de_pipe2<=0;history_vs_pipe2<=0;history_de_pipe3<=0;history_vs_pipe3<=0;
 end
 else begin
  history_de_pipe<=osd_de;history_vs_pipe<=osd_vs;
  history_de_pipe2<=history_de_pipe;history_vs_pipe2<=history_vs_pipe;
  history_de_pipe3<=history_de_pipe2;history_vs_pipe3<=history_vs_pipe2;
  history_de<=history_de_pipe3;history_vs<=history_vs_pipe3;
 end
end
recovery_history_osd #(.SHARED_ROM(1)) u_history_osd(.clk(video_clk),.rst(frame_rst_pixel),
 .vs(osd_vs),.de(osd_de),.rgb(osd_rgb),.gallery_payload(history_pixel),.out_rgb(history_rgb),
 .shared_message_address(history_message_address),.shared_message_q(history_message_q),.trend_read_address(history_trend_read_address),.trend_read_point(history_trend_read_point));
wire [23:0] final_osd_rgb;wire final_de,final_vs;
generate if(RUNTIME_CONTROLS_ENABLE != 0)begin:g_runtime_osd
 reg de_q,vs_q;wire [23:0] runtime_rgb;
 always @(posedge video_clk or posedge frame_rst_pixel)begin
  if(frame_rst_pixel)begin de_q<=0;vs_q<=0;end
  else begin de_q<=history_de;vs_q<=history_vs;end
 end
 recovery_runtime_osd #(.THEMED_ENABLE(1)) u_osd(.clk(video_clk),.rst(frame_rst_pixel),.vs(history_vs),.de(history_de),.rgb(history_rgb),
  .frame_boundary(runtime_boundary_d),.brightness(pixel_brightness),.contrast_gain(pixel_contrast),
  .volume_gain(pixel_volume),.adjust_mode(pixel_adjust_mode),.out_rgb(runtime_rgb));
 // settings are below the always-visible timer; idle controls are hidden.
 // The same one-cycle caption stage now serves every page, including history.
 assign final_osd_rgb=runtime_rgb;
 assign final_de=de_q;assign final_vs=vs_q;
end else begin:g_runtime_osd_bypass
 assign final_osd_rgb=history_rgb;assign final_de=history_de;assign final_vs=history_vs;
end endgenerate

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_scan #(.CLK_FREQ(100000000),.SCAN_COUNT(2*(50000000/(200*6))-1)) seg_scan_m0(
    .clk               (sd_card_clk),
    .rst_n             (~rst_sd),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (frame_rst_pixel),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (frame_rst_pixel),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
// Pure combinational scaling adds no pixel/control latency. Fault/initial
// display uses full gain so built-in status remains visible during recovery.
wire [23:0] faded_rgb,wiped_rgb;
recovery_transition_rgb u_transition_rgb(.rgb(final_osd_rgb),
 .gain(display_valid&&!history_pixel[767] ? transition_gain : 9'd256),.faded_rgb(faded_rgb));
recovery_wipe_rgb #(.THEMED_ENABLE(1)) u_wipe_rgb(.clk(video_clk),.rst(frame_rst_pixel),
 .vs(final_vs),.direction(transition_direction),.de(final_de),.rgb(faded_rgb),
 .active(display_valid&&!history_pixel[767]&&transition_wipe_active),.reveal_width(transition_reveal_width),.out_rgb(wiped_rgb));
reg timer_de,timer_vs;
always @(posedge video_clk or posedge frame_rst_pixel)begin
 if(frame_rst_pixel)begin timer_de<=0;timer_vs<=0;end
 else begin timer_de<=final_de;timer_vs<=final_vs;end
end
// Session time remains readable throughout ordinary fade/wipe effects.
recovery_session_timer_osd #(.THEMED_ENABLE(1)) u_session_osd(.clk(video_clk),.rst(frame_rst_pixel),
 .vs(final_vs),.de(final_de),.rgb(wiped_rgb),.status(session_pixel),
 .hide_timer(pixel_adjust_mode!=0),.out_rgb(vout_data));

// captions use actual audio sample progress; practice stays independent of formal results.
wire [23:0] caption_rgb;wire caption_de,caption_vs,caption_marker;reg axis_ui_marker;
wire caption_feedback_marker;reg axis_feedback_marker;
always @(posedge video_clk or posedge frame_rst_pixel)
 if(frame_rst_pixel)axis_feedback_marker<=0;else axis_feedback_marker<=caption_feedback_marker;
always @(posedge video_clk or posedge frame_rst_pixel)
 if(frame_rst_pixel)axis_ui_marker<=0;else axis_ui_marker<=caption_marker;
wire shared_event_valid,shared_event_ready;wire [20:0] shared_event_identity;
wire pixel_feedback_request=ui_union_pixel[67:66]!=0;
wire pixel_cue_request=ui_union_pixel[40]&&ui_union_pixel[42]&&!pixel_feedback_request;
assign ui_event_valid=shared_event_valid&&!shared_event_identity[20];
assign feedback_event_valid=shared_event_valid&&shared_event_identity[20];
assign ui_event_identity=shared_event_identity[19:0];
assign feedback_event_identity=shared_event_identity[19:0];
assign shared_event_ready=shared_event_identity[20]?feedback_event_ready:ui_event_ready;
// One original held CDC remains under the existing exact SDC endpoints.
// The extra type bit prevents a cue identity from becoming an answer ACK.
recovery_pixel_ui_event #(.ID_WIDTH(21)) u_ui_event(
 .pixel_clk(video_clk),.pixel_rst(frame_rst_pixel),
 .pixel_valid(feedback_scope_ok&&(pixel_cue_request||pixel_feedback_request)),
 .pixel_marker(axis_s_valid&&axis_s_ready&&
   (pixel_cue_request?axis_ui_marker&&axis_s_data==24'h25b56b:
    pixel_feedback_request&&axis_feedback_marker&&(axis_s_data==24'h25b56b||axis_s_data==24'hd94343))),
 .pixel_identity({pixel_feedback_request,pixel_feedback_request?ui_union_pixel[73:68]:joint_pixel[863:858],joint_pixel[879:874],joint_pixel[871:864]}),
 .app_clk(sd_card_clk),.app_rst(rst_sd),.app_enable(board_link_up&&mb_ready&&!media_cancel),
 .event_valid(shared_event_valid),.event_identity(shared_event_identity),.event_ready(shared_event_ready));
wire [8:0] wave_query_index;wire [6:0] wave_newest_index;
wire signed [7:0] wave_min,wave_max;wire [3:0] wave_fraction;
wire [7:0] wave_average,wave_peak;
wire [9:0] mountain_front_q4,mountain_back_q4;wire mountain_valid;
wire education_audio_panel=display_valid&&!history_pixel[767]&&feedback_scope_ok&&
 pixel_scene==6'd49;
recovery_audio_visualizer u_audio_visualizer(
 .clk(video_clk),.rst(frame_rst_pixel),.vs(timer_vs),
 .audio_valid(audio_valid),.audio_left(audio_left_data),.enable(education_audio_panel),
 .source_tag({interaction_pixel[7:0],caption_pixel[23:16]}),.query_index(wave_query_index),
 .wave_min(wave_min),.wave_max(wave_max),.average(wave_average),.peak(wave_peak),
 .newest_index(wave_newest_index),.wave_fraction(wave_fraction),
 .de(timer_de),.front_q4(mountain_front_q4),.back_q4(mountain_back_q4),.mountain_valid(mountain_valid));
// A local SAFE snapshot contains no B business feedback. Allow its fault
// message even when the previous background was a report or never loaded.
assign local_safe_fault=pixel_ui_valid&&pixel_kind==0&&status_osd[7:0]!=0;
recovery_caption_practice_osd #(.MOUNTAIN_LAYERED(2),.WAVE_FRACTION_ENABLE(1)) u_caption_osd(
 .clk(video_clk),.rst(frame_rst_pixel),.vs(timer_vs),.de(timer_de),.rgb(vout_data),
 .display_enable((display_valid||local_safe_fault)&&pixel_ui_valid),.history_enable(history_pixel[767]),
 .caption_id(caption_pixel[29:24]),.caption_running(caption_pixel[30]),
 .caption_generation(caption_pixel[23:16]),.caption_ticks(caption_pixel[15:0]),
 .scene_id(local_safe_fault?6'd7:canvas_scene),.question_set(interaction_pixel[9:8]),
 .status_data(status_osd),.feedback(themed_feedback),
 .ui_data(ui_union_pixel),.ui_valid(feedback_scope_ok||local_safe_fault||teaching_visual_scope),
 .wave_query_index(wave_query_index),.wave_min(wave_min),.wave_max(wave_max),
 .wave_average(wave_average),.wave_peak(wave_peak),.wave_fraction(wave_fraction),
 .mountain_front_q4(mountain_front_q4),.mountain_back_q4(mountain_back_q4),.mountain_valid(mountain_valid),
 .view_prepare(canvas_prepare&&teaching_visual_scope),.practice(practice_pixel),.out_rgb(caption_rgb),.out_de(caption_de),.out_vs(caption_vs),.ui_marker(caption_marker),.feedback_marker(caption_feedback_marker));

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (frame_rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (frame_read_req),
    .read_req_ack      (mem_read_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_index   (disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .write_fifo_full   (write_fifo_full),
    .read_fifo_empty   (read_fifo_empty)
);

sdram #(.REFRESH_PERIOD_CLOCKS(320),.REFRESH_DRAIN_CLOCKS(32),.REFRESH_GUARD_CLOCKS(16)) U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (frame_rst_mem),
    .Sdr_refresh_fault(Sdr_refresh_fault),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// Compile-time diagnostic mode preserves the official test-tone source.
wire tone_bclk,tone_lrck,tone_dout;
hdmi_audio_tone_i2s_64fs u_test_tone(.I_mclk(audio_mclk),.I_rst(rst_audio),
 .O_i2s_BCLK(tone_bclk),.O_i2s_LRCK(tone_lrck),.O_i2s_DOUT(tone_dout));
assign audio_i2s_bclk=AUDIO_TEST_MODE?tone_bclk:pcm_bclk;
assign audio_i2s_lrck=AUDIO_TEST_MODE?tone_lrck:pcm_lrck;
assign audio_i2s_dout=AUDIO_TEST_MODE?tone_dout:pcm_dout;

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (frame_rst_pixel),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (frame_rst_pixel),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (frame_rst_pixel),
    .I_vs          (caption_vs),
    .I_de          (caption_de),
    .I_rgb         (caption_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (frame_rst_pixel),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (frame_rst_pixel),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (video_locked),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (frame_rst_pixel),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule

// Restore compilation-unit defaults before subsequent legacy source files.
`default_nettype wire
