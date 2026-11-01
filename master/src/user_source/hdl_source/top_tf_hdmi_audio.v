`default_nettype none
`timescale 1ns/1ps
// Business master B.
module top(
 input wire clk,
 input wire rst_n, // Physical KEY1/A2: SKIP toggle, never reset
 input wire key1, // Physical KEY2/B2: previous / management / history select
 input wire key2, // Physical KEY4/C1: patient L
 input wire key3, // Physical KEY3/B1: patient R
 input wire sw1,sw2,sw3,sw4,
 input wire uart_rx,output wire uart_tx,
 input wire gpio_presented_in,gpio_done_in,gpio_link_ready_in,
 output wire flash_cs_n,output wire flash_sclk,output wire flash_mosi,input wire flash_miso,
 output wire flash_wp_n,output wire flash_hold_n,
 output wire buzzer_n,output wire [3:0] led_n,output wire [5:0] seg_sel,output wire [7:0] seg_data
);

parameter RUNTIME_CONTROLS_ENABLE=1;
parameter RETEST_INTERVAL_MS=30000;
wire sd_card_clk,pll_locked;
wire rst_all;
wire rst_sd;
wire [3:0] state_code;
wire [6:0] seg_data_0;
wire media_cmd_valid,media_cmd_ready,media_cancel,media_done,media_presented,media_fault,media_recover;
wire app_cmd_valid,app_cmd_ready,app_cancel,media_skip_request,history_exit;
wire [5:0] app_scene;
wire [1:0] app_effect;
wire [5:0] media_scene,live_scene,result_valid;
wire [7:0] app_state,media_state,last_media_error,epoch;
wire alarm_active,input_armed,nurse_enabled,release_prompt;
wire [1:0] active_mode;
wire [1:0] question_set;
wire [23:0] practice_data;
wire practice_alarm;
wire [23:0] interaction_data;
wire [7:0] accepted_identity;
wire [1:0] app_wipe_direction;
wire physical_alarm;
wire narration_quiet;
wire voice_complete;
wire ui_presented,ui_confirmed,ui_owner_request,ui_green_request;
wire [1:0] feedback_kind,feedback_mask;
wire [5:0] feedback_seq;
wire feedback_confirmed;
wire [31:0] ui_now_cycles,ui_presented_cycles;
wire [1:0] pacu_p,pacu_a,pacu_valid,t1_correct,t2_correct,t3_result,t1_unanswered,t2_unanswered;
wire [15:0] rt_ms,hold_ms;
wire [2:0] rt_status,hold_status,pain;
wire [3:0] fault_code;
wire education_countdown_active,retest_due;
wire [15:0] retest_seconds;
wire [2:0] limb_count;
wire [3:0] limb_answers,limb_valid;
wire [1:0] last_report_mode;
wire [2:0] report_outcome;
wire [5:0] report_started;
wire [31:0] rt_cycles;
wire audio_active;
wire [1:0] media_effect,adjust_mode;
wire patient_inhibit,skip_audio_wait,report_generated;
wire history_sw1_on,history_sw2_on,history_l_press,history_r_press,history_select;
wire history_clear_request;
wire history_clear_done;
wire flash_ready,flash_storage_ready,flash_fault;
wire pending_report_overflow;
wire [7:0] effective_error;
wire history_enabled;
wire signed [8:0] brightness;
wire [9:0] contrast_gain;
wire [8:0] volume_gain;
reg [26:0] buzz_count;
reg [15:0] buzz_div;
reg buzz_wave;
wire [69:0] report_live_fields;
wire [6:0] live_ward_score;
wire [23:0] session_bcd;
wire [31:0] history_metadata;
wire [5:0] history_report_scene;
wire [159:0] history_report_status;
wire [159:0] status_src;
wire [799:0] history_src;
wire [6:0] history_trend_read_address;
wire [7:0] history_trend_read_point;
wire [7:0] history_count;
wire history_full;
wire [6:0] history_selected;
wire history_detail;
wire history_capture;
wire [159:0] history_capture_status;
wire [23:0] history_capture_time;
wire flash_report_commit,flash_report_error,flash_write_enabled,flash_report_ready,history_capture_ready;
wire flash_restore_valid;
wire [183:0] flash_restore_record,flash_committed_record;
wire [23:0] flash_jedec_id;
wire pending_report;
wire [183:0] pending_report_record;
wire [183:0] history_insert_record;
wire [159:0] history_source_status;
wire history_source_valid;
wire [5:0] history_background_scene;
wire link_up;
// Continuous values retain the original net initializer expressions.
assign rst_all = ~pll_locked;
assign physical_alarm = alarm_active|practice_alarm;
assign effective_error = (flash_fault||pending_report_overflow)?8'hc7:last_media_error;
assign history_enabled = history_sw1_on&&history_sw2_on&&flash_ready;
assign report_live_fields = {limb_count,limb_answers,limb_valid,
 pacu_valid,pacu_p,pacu_a,t1_correct,t2_correct,t3_result,rt_ms,rt_status,hold_ms,hold_status,pain,result_valid};
assign history_metadata = {1'b1,last_report_mode,epoch,report_started,report_outcome,
 fault_code,t1_unanswered,t2_unanswered,4'd0};
assign history_report_scene = (last_report_mode==2'd1) ? 6'd8 : 6'd22;
assign history_report_status = {history_metadata,5'd0,(last_report_mode==2'd2),live_ward_score,1'b0,1'b0,16'd0,
 report_live_fields[69:59],app_state,last_report_mode,input_armed,release_prompt,nurse_enabled,
 report_live_fields[58:0],history_report_scene,effective_error};
assign status_src = {history_metadata,5'd0,(last_report_mode==2'd2),live_ward_score,
 education_countdown_active,retest_due,retest_seconds,
 report_live_fields[69:59],app_state,active_mode,input_armed,release_prompt,nurse_enabled,
 report_live_fields[58:0],live_scene,effective_error};
assign history_insert_record = flash_restore_valid?flash_restore_record:flash_committed_record;
assign history_source_status = selected_history_status(history_src);
assign history_source_valid = history_enabled&&history_src[767]&&history_src[766]&&
 !history_src[738]&&history_src[761+history_src[740:739]];
assign history_background_scene = history_source_status[158:157]==2'd1 ? 6'd29 : 6'd30;


// Engineering demonstration may select 180000; production remains 30000 ms.




recovery_master_clock u_master_clock(.refclk(clk),.reset(1'b0),.clk0_out(sd_card_clk),.locked(pll_locked));
recovery_reset_sync rs0(sd_card_clk,rst_all,rst_sd);
























// Dedicated input filters let both switches enter history before the
// assessment's own mode qualification; the assessment sees a normal exit.
recovery_keys #(.DEBOUNCE_CYCLES(2000000)) u_history_keys(
 .clk(sd_card_clk),.rst(rst_sd),.time_cycles(32'd0),.sw1(sw1),.sw2(sw2),
 .key_l_n(key2),.key_r_n(key3),.key_back_n(key1),
 .sw1_on(history_sw1_on),.sw2_on(history_sw2_on),
 .l_press(history_l_press),.r_press(history_r_press),.b_press(history_select));



generate if(RUNTIME_CONTROLS_ENABLE != 0)begin:g_controls
 recovery_runtime_controls u_controls(.clk(sd_card_clk),.rst(rst_sd),
  .raw_sw3(sw3),.raw_sw4(sw4),.key_left_n(key2),.key_right_n(key3),
  .patient_inhibit(patient_inhibit),.adjust_mode(adjust_mode),.brightness(brightness),
  .contrast_gain(contrast_gain),.volume_gain(volume_gain));
end else begin:g_controls_bypass
 assign patient_inhibit=0;assign adjust_mode=0;assign brightness=0;
 assign contrast_gain=256;assign volume_gain=256;
end endgenerate
recovery_assessment #(.CLK_HZ(100000000),.DEBOUNCE_CYCLES(2000000),.RETEST_INTERVAL_MS(RETEST_INTERVAL_MS),.RELAX_ENABLE(1)) u_assessment(
 .clk(sd_card_clk),.rst(rst_sd),.sw1((history_enabled||!flash_storage_ready)?1'b0:history_sw1_on),
 .sw2((history_enabled||!flash_storage_ready)?1'b0:history_sw2_on),.key_l_n(key2),.key_r_n(key3),
 .key_back_n(history_enabled?1'b1:key1),.key_skip_n(rst_n),
 .skip_audio_wait(skip_audio_wait),.report_generated(report_generated),
 .media_audio_active(audio_active||!narration_quiet),.question_set(question_set),.practice_data(practice_data),.practice_alarm(practice_alarm),
 .media_voice_complete(voice_complete),.interaction_data(interaction_data),
 .ui_presented(ui_presented),.ui_confirmed(ui_confirmed),.ui_owner_request(ui_owner_request),.ui_green_request(ui_green_request),
 .ui_presented_cycles(ui_presented_cycles),.ui_now_cycles(ui_now_cycles),
 .feedback_kind(feedback_kind),.feedback_mask(feedback_mask),.feedback_seq(feedback_seq),.feedback_confirmed(feedback_confirmed),
 .accepted_identity(accepted_identity),.media_wipe_direction(app_wipe_direction),
 .patient_inhibit(patient_inhibit||history_enabled),.media_effect(app_effect),
 .media_cmd_valid(app_cmd_valid),.media_cmd_ready(app_cmd_ready),.media_scene(app_scene),.media_cancel(app_cancel),
 .media_skip_request(media_skip_request),
  .history_exit(history_exit),.history_clear_done(history_clear_done),.history_clear_request(history_clear_request),
 .media_scene_done(media_done&&!history_enabled),.media_presented(media_presented&&!history_enabled),.media_error((media_fault||flash_fault||pending_report_overflow)&&!history_enabled),.state(app_state),
 .alarm_active(alarm_active),.pacu_p(pacu_p),.pacu_a(pacu_a),.pacu_valid(pacu_valid),
 .t1_correct(t1_correct),.t2_correct(t2_correct),.t3_result(t3_result),.rt_ms(rt_ms),.rt_status(rt_status),
 .hold_ms(hold_ms),.hold_status(hold_status),.pain(pain),.result_valid(result_valid),.active_mode(active_mode),
 .input_armed(input_armed),.nurse_enabled(nurse_enabled),.release_prompt(release_prompt),
 .t1_unanswered(t1_unanswered),.t2_unanswered(t2_unanswered),.fault_code(fault_code),.rt_cycles(rt_cycles),.last_report_mode(last_report_mode),.limb_count(limb_count),.limb_answers(limb_answers),.limb_valid(limb_valid),
 .report_outcome(report_outcome),.report_started(report_started),
 .education_countdown_active(education_countdown_active),.retest_due(retest_due),.retest_seconds(retest_seconds));
assign state_code=effective_error!=0?4'hf:app_state[3:0];

always @(posedge sd_card_clk or posedge rst_sd)begin
 if(rst_sd)begin buzz_count<=0;buzz_div<=0;buzz_wave<=0;end
 else begin
  if(buzz_count==99999999)buzz_count<=0;else buzz_count<=buzz_count+1;
  if(buzz_div==49999)begin buzz_div<=0;buzz_wave<=~buzz_wave;end else buzz_div<=buzz_div+1;
 end
end
assign buzzer_n=!(physical_alarm&&!audio_active&&buzz_count<30000000&&buzz_wave);
assign led_n=~{(effective_error!=0||fault_code>=2),physical_alarm,(active_mode!=0),(active_mode==0&&effective_error==0)};
// Live fields ship to A; A freezes reports on real scene8/22 media acceptance.


recovery_ward_score u_ward_live_score(.report_fields({55'd0,report_live_fields[58:0],14'd0}),.total_score(live_ward_score));
// Session records capture business fields at the report-generation event,
// including interrupted rounds. Viewing an old report never emits this event.

recovery_session_timer u_session_timer(.clk(sd_card_clk),.rst(rst_sd),.elapsed_bcd(session_bcd));










recovery_report_pending_queue u_pending_reports(.clk(sd_card_clk),.rst(rst_sd),
 .capture(history_capture),.clear_commit(history_clear_done),.record({history_capture_time,history_capture_status}),
 .valid(pending_report),.data(pending_report_record),.ready(flash_report_ready),.overflow(pending_report_overflow));

recovery_history_capture u_history_capture(.clk(sd_card_clk),.rst(rst_sd),.capture(report_generated),
 .status(history_report_status),.timestamp(session_bcd),.saved_capture(history_capture),
 .saved_status(history_capture_status),.saved_timestamp(history_capture_time));
recovery_report_history #(.HISTORY_DEPTH(32)) u_history(
 .clk(sd_card_clk),.rst(rst_sd),.enable(history_enabled),
 .clear_commit(history_clear_done),
 .view_mode(active_mode == 2'd1 ? 2'd1 : active_mode == 2'd2 ? 2'd2 : last_report_mode),
 .left_event(history_l_press&&!patient_inhibit),.right_event(history_r_press&&!patient_inhibit),
 .select_event(history_select),.capture((flash_restore_valid&&history_capture_ready)||flash_report_commit),
 .capture_ready(history_capture_ready),
 .report_status(history_insert_record[159:0]),.capture_time_bcd(history_insert_record[183:160]),
 .report_count(history_count),.full(history_full),.selected_index(history_selected),
 .detail_mode(history_detail),.gallery_payload(history_src),
 .pixel_clk(sd_card_clk),.trend_read_address(history_trend_read_address),.trend_read_point(history_trend_read_point));
assign flash_ready=flash_storage_ready;
recovery_report_flash_store u_report_flash(
 .clk(sd_card_clk),.rst(rst_sd),.report_valid(pending_report),.report_record(pending_report_record),
 .report_ready(flash_report_ready),.report_commit(flash_report_commit),.committed_record(flash_committed_record),.report_error(flash_report_error),
 .clear_request(history_clear_request),.clear_done(history_clear_done),.restore_valid(flash_restore_valid),
 .restore_record(flash_restore_record),.restore_ready(history_capture_ready),.storage_ready(flash_storage_ready),.storage_fault(flash_fault),.write_enabled(flash_write_enabled),
 .jedec_id(flash_jedec_id),.flash_cs_n(flash_cs_n),.flash_sclk(flash_sclk),.flash_mosi(flash_mosi),.flash_miso(flash_miso),
 .flash_wp_n(flash_wp_n),.flash_hold_n(flash_hold_n));
// selected immutable record drives the same report renderer as a new test.
function [159:0] selected_history_status;
 input [799:0] payload;
 begin case(payload[740:739])
  0:selected_history_status=payload[159:0];
  1:selected_history_status=payload[343:184];
  2:selected_history_status=payload[527:368];
  3:selected_history_status=payload[711:552];
 endcase end
endfunction



recovery_history_media_bridge u_history_media(.clk(sd_card_clk),.rst(rst_sd),.recover(media_recover),
 .enable(history_enabled),.detail_valid(history_source_valid),.detail_scene(history_background_scene),
 .app_valid(app_cmd_valid),.app_scene(app_scene),.app_effect(app_effect),.app_cancel(app_cancel),
 .media_ready(media_cmd_ready),.cmd_valid(media_cmd_valid),.cmd_scene(media_scene),
 .cmd_effect(media_effect),.cancel(media_cancel),.app_ready(app_cmd_ready),.history_exit(history_exit));
// Trend RAM is read locally in the same business domain. KEY2 select stays live
// during SW3/SW4 adjustment; L/R navigation retains the original inhibit guard.

recovery_master_bridge u_board_link(
 .clk(sd_card_clk),.rst(rst_sd),.uart_rx(uart_rx),.uart_tx(uart_tx),
 .gpio_presented_in(gpio_presented_in),.gpio_done_in(gpio_done_in),.gpio_link_ready_in(gpio_link_ready_in),
 .cmd_valid(media_cmd_valid),.cmd_ready(media_cmd_ready),.cmd_scene(media_scene),.cmd_effect(media_effect),
 .cancel(media_cancel),.skip_audio_wait(skip_audio_wait),.skip_page_request(media_skip_request&&!history_enabled),
 .cmd_question_set(history_enabled?2'd0:question_set),.practice_data(history_enabled?24'd0:practice_data),
 .cmd_wipe_direction(history_enabled?2'd0:app_wipe_direction),
 .interaction_data(history_enabled?24'd0:interaction_data),.accepted_identity(accepted_identity),
 .status_data(status_src),.history_data(history_src),.session_data({skip_audio_wait,session_bcd}),
 .runtime_data({1'b1,adjust_mode,brightness,contrast_gain,volume_gain}),
 .trend_read_point(history_trend_read_point),.trend_read_address(history_trend_read_address),
 .ui_owner_request(ui_owner_request),.ui_green_request(ui_green_request),
 .feedback_kind(history_enabled?2'd0:feedback_kind),.feedback_mask(feedback_mask),.feedback_seq(feedback_seq),.feedback_confirmed(feedback_confirmed),
 .ui_now_cycles(ui_now_cycles),.ui_presented_cycles(ui_presented_cycles),
 .ui_presented(ui_presented),.ui_confirmed(ui_confirmed),
 .media_presented(media_presented),.media_done(media_done),.media_fault(media_fault),.media_recover(media_recover),
 .last_error(last_media_error),.live_scene(live_scene),.epoch(epoch),.audio_active(audio_active),
 .debug_state(media_state),.narration_quiet(narration_quiet),.voice_complete(voice_complete),.link_up(link_up));
seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (~rst_all),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);
endmodule

`default_nettype wire
