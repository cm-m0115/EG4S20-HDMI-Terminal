`default_nettype none
`timescale 1ns/1ps
`include "recovery_scene_ids.vh"
// Application control and assessment state machine.


// Reference only: course lesson 3 key routing, lesson 9 OSD frame commit and
// lesson 14 parameter menu. No clinical threshold or complete Aldrete scoring.

// MEDIA CONTRACT (all signals synchronous to clk, one accepted command):
// valid+ready accepts scene; valid and scene remain stable under backpressure.
// presented is a ONE-CYCLE event for the current accepted scene's first actual
// output pixel; scene_done requires that presentation AND final source I2S
// frame completion (silent scenes may complete on presentation). With the
// session skip option, patient scenes may complete after presentation/PCM
// readiness while narration continues; the media owner retires that narration
// safely before accepting a replacement. T4WAIT still guarantees GO prefetch.
// cancel flushes all old events. ready MUST stay low until old work is safely
// retired; old presented/done/error must not reach the new command. T4WAIT
// scene_done additionally guarantees T4GO is fully prefetched, silent and ready.
// T4GO timestamp is the synchronized application-clock presentation event
// (CLK_HZ=100MHz in the application top); CDC delay is a
// measured integration limitation, not a claim of physical/pixel-domain onset.
module recovery_assessment #(
    parameter integer CLK_HZ = 50000000,
    parameter integer DEBOUNCE_CYCLES = 1000000,
    parameter integer RESPONSE_MS = 10000,
    parameter integer HOLD_TARGET_MS = 3000,
    parameter integer HOLD_MAX_MS = 10000,
    parameter integer EDUCATION_MS = 3000,
    parameter integer RESULTS_MS = 10000,
    parameter integer RETEST_INTERVAL_MS = 30000,
    parameter integer PACU_REMIND_LIMIT = 2,
    parameter integer PRACTICE_ENABLE = 1,
    parameter integer RELAX_ENABLE = 1,
    parameter integer PRACTICE_FEEDBACK_MS = 600, // original finished-page duration
    parameter integer ANSWER_FEEDBACK_MS = 600,
    parameter integer PRACTICE_CORRECT_FEEDBACK_MS = 600,
    parameter integer PRACTICE_ERROR_FEEDBACK_MS = 600,
    parameter integer FEEDBACK_CONFIRM_TIMEOUT_MS = 2000,
    parameter integer PRACTICE_RELEASE_MS = 10000,
    parameter integer PRACTICE_AUDIO_GUARD_MS = 50,
    parameter integer PRACTICE_WAIT_MS = 1000,
    parameter integer WELCOME_CLEAR_HOLD_MS = 3000
) (
    input wire clk, input wire rst,
    input wire sw1, input wire sw2,
    input wire key_l_n, input wire key_r_n, input wire key_back_n,
    input wire key_skip_n,
    output reg skip_audio_wait,
    // A fresh patient key can retire narration on any presented page. The
    // media owner latches this request until PCM readiness and retires it once.
    output reg media_skip_request,
    output reg report_generated,
    input wire patient_inhibit,
    // The media owner changed during history. An idle application rebuilds
    // its own welcome transaction when both qualified mode inputs are off.
    input wire history_exit,
    // A held KEY2 clear remains pending until the persistent report store
    // confirms the new empty generation has committed.
    input wire history_clear_done,
    output wire history_clear_request,
    output reg media_cmd_valid, input wire media_cmd_ready,
    output reg [5:0] media_scene, output reg media_cancel,
    output reg [1:0] media_effect,
    input wire media_scene_done, input wire media_presented, input wire media_error,
    input wire media_audio_active,
    input wire media_voice_complete,
    input wire ui_presented,input wire ui_confirmed,input wire [31:0] ui_presented_cycles,
    output wire [31:0] ui_now_cycles,
    input wire feedback_confirmed,
    output reg [1:0] feedback_kind,feedback_mask,output reg [5:0] feedback_seq,
    output wire ui_owner_request,output wire ui_green_request,
    output reg [1:0] question_set,
    output wire [23:0] practice_data,
    output wire [23:0] interaction_data,
    output reg [7:0] accepted_identity,
    output reg [1:0] media_wipe_direction,
    output reg practice_alarm,
    (* max_fanout=8 *) output reg [7:0] state,
    output reg alarm_active,
    output reg [1:0] pacu_p, output reg [1:0] pacu_a, output reg [1:0] pacu_valid,
    output reg [1:0] t1_correct, output reg [1:0] t2_correct,
    output reg [1:0] t3_result,
    output reg [15:0] rt_ms, output reg [2:0] rt_status,
    output reg [15:0] hold_ms, output reg [2:0] hold_status,
    output reg [2:0] pain, output reg [5:0] result_valid,
    (* max_fanout=8 *) output reg [1:0] active_mode,
    output wire input_armed, output reg nurse_enabled, output reg release_prompt,
    output reg [1:0] t1_unanswered, output reg [1:0] t2_unanswered,
    output reg [3:0] fault_code, output reg [31:0] rt_cycles,
    output reg [1:0] last_report_mode,
    // Current round metadata. Values and valid bits remain the business source.
    // 0 not started, 1 active/completed, 2 no response, 3 fault, 4 interrupted.
    output reg [2:0] report_outcome,
    output reg [5:0] report_started,
    output reg [2:0] limb_count,output reg [3:0] limb_answers,limb_valid,
    output reg education_countdown_active,output reg retest_due,
    output reg [15:0] retest_seconds
);

localparam integer CYCLES_PER_MS = CLK_HZ/1000;
localparam [31:0] RESPONSE_CYCLES = CYCLES_PER_MS*RESPONSE_MS;
localparam [31:0] HOLD_TARGET_CYCLES = CYCLES_PER_MS*HOLD_TARGET_MS;
localparam [31:0] HOLD_COMPLETE_CYCLES = CYCLES_PER_MS*2000;
localparam [31:0] HOLD_MAX_CYCLES = CYCLES_PER_MS*HOLD_MAX_MS;
localparam [31:0] EDU_CYCLES = CYCLES_PER_MS*EDUCATION_MS;
localparam [31:0] RESULTS_CYCLES = CYCLES_PER_MS*RESULTS_MS;
localparam [31:0] WELCOME_CLEAR_CYCLES = CYCLES_PER_MS*WELCOME_CLEAR_HOLD_MS;
localparam [31:0] CONFIRM_TAIL = DEBOUNCE_CYCLES+8;
localparam integer RETEST_DIV_WIDTH = (CYCLES_PER_MS<=1) ? 1:$clog2(CYCLES_PER_MS);
localparam integer RETEST_COUNT_WIDTH=(RETEST_INTERVAL_MS<1) ? 1:$clog2(RETEST_INTERVAL_MS+1);
localparam integer RETEST_INITIAL_SECONDS = (RETEST_INTERVAL_MS+999)/1000;
localparam integer RETEST_FIRST_SECOND_MS = (RETEST_INTERVAL_MS%1000==0) ? 1000:RETEST_INTERVAL_MS%1000;
localparam [7:0] BOOT=0, WELCOME=1, PAGE=2, CANCEL_WAIT=3,
        P_GUID_END=10, P_CALL_RELEASE=11, P_CALL=12, P_LIMB_RELEASE=13,
        P_LIMB=14, P_RESULTS=19, LEARN_END=30, READY_RELEASE=31, READY_INPUT=32,
        CHOICE_RELEASE=40, CHOICE=41, T4_PREP_END=42, T4_INPUT=43,
        HOLD_RELEASE=44, HOLD_START=45, HOLD_ACTIVE=46,
        PAIN_RELEASE=47, PAIN_START=48, PAIN_ACTIVE=49, PAIN_RETRY_RELEASE=50,
        RESULTS_END=51, RESULTS_WAIT=52, EDU_END=53, EDU_ACTIVE=54,
        REST_RELEASE=55, REST_INPUT=56, CONVERT_START=57, CONVERT_WAIT=58,
        HOLD_RETRY_RELEASE=59, PAUSE=60, FAULT=61,
        PRACT_AUDIO_WAIT=70, PRACT_RELEASE=71, PRACT_PRESS=72,
        PRACT_HELD=73, PRACT_CONFIRM=74, PRACT_RETRY=75,
        PRACT_ALARM=76, PRACT_FINISHED=77, RELAX_ACTIVE=78, FEEDBACK_WAIT=79;
localparam integer STATE_HOT_WIDTH=45;
localparam [1:0] EFFECT_DIRECT=0, EFFECT_FADE=1, EFFECT_WIPE=2;
localparam [31:0] ANSWER_VISUAL_CYCLES=CYCLES_PER_MS*ANSWER_FEEDBACK_MS;
localparam [31:0] CORRECT_VISUAL_CYCLES=CYCLES_PER_MS*PRACTICE_CORRECT_FEEDBACK_MS;
localparam [31:0] ERROR_VISUAL_CYCLES=CYCLES_PER_MS*PRACTICE_ERROR_FEEDBACK_MS;
localparam [31:0] PRACTICE_FEEDBACK_CYCLES=CYCLES_PER_MS*PRACTICE_FEEDBACK_MS;
localparam [31:0] PRACTICE_AUDIO_GUARD_CYCLES=CYCLES_PER_MS*PRACTICE_AUDIO_GUARD_MS;
localparam [31:0] PRACTICE_PROGRESS_CYCLES=(HOLD_TARGET_CYCLES<100) ? 1:HOLD_TARGET_CYCLES/100;
(* max_fanout=8 *) reg [STATE_HOT_WIDTH-1:0] state_hot;
wire [STATE_HOT_WIDTH-1:0] state_target_0;
reg [STATE_HOT_WIDTH-1:0] state_target_1;
reg [STATE_HOT_WIDTH-1:0] state_target_3;
reg [STATE_HOT_WIDTH-1:0] state_target_2;
wire [STATE_HOT_WIDTH-1:0] state_target_4;
reg [STATE_HOT_WIDTH-1:0] state_target_5;
reg [STATE_HOT_WIDTH-1:0] state_target_6;
reg [STATE_HOT_WIDTH-1:0] state_target_7;
reg [STATE_HOT_WIDTH-1:0] state_target_8;
wire [STATE_HOT_WIDTH-1:0] state_target_9;
reg [STATE_HOT_WIDTH-1:0] state_target_10;
reg [STATE_HOT_WIDTH-1:0] state_target_11;
reg [STATE_HOT_WIDTH-1:0] state_target_12;
reg [STATE_HOT_WIDTH-1:0] state_target_13;
reg [STATE_HOT_WIDTH-1:0] state_target_14;
reg [STATE_HOT_WIDTH-1:0] state_target_15;
reg [STATE_HOT_WIDTH-1:0] state_target_16;
reg [STATE_HOT_WIDTH-1:0] state_target_17;
reg [STATE_HOT_WIDTH-1:0] state_target_18;
reg [STATE_HOT_WIDTH-1:0] state_target_19;
reg [STATE_HOT_WIDTH-1:0] state_target_32;
reg [STATE_HOT_WIDTH-1:0] state_target_20;
reg [STATE_HOT_WIDTH-1:0] state_target_21;
reg [STATE_HOT_WIDTH-1:0] state_target_22;
reg [STATE_HOT_WIDTH-1:0] state_target_23;
wire [STATE_HOT_WIDTH-1:0] state_target_24;
wire [STATE_HOT_WIDTH-1:0] state_target_25;
reg [STATE_HOT_WIDTH-1:0] state_target_26;
reg [STATE_HOT_WIDTH-1:0] state_target_27;
reg [STATE_HOT_WIDTH-1:0] state_target_43;
reg [STATE_HOT_WIDTH-1:0] state_target_28;
reg [STATE_HOT_WIDTH-1:0] state_target_29;
reg [STATE_HOT_WIDTH-1:0] state_target_35;
reg [STATE_HOT_WIDTH-1:0] state_target_36;
reg [STATE_HOT_WIDTH-1:0] state_target_37;
reg [STATE_HOT_WIDTH-1:0] state_target_38;
reg [STATE_HOT_WIDTH-1:0] state_target_39;
reg [STATE_HOT_WIDTH-1:0] state_target_40;
reg [STATE_HOT_WIDTH-1:0] state_target_41;
reg [STATE_HOT_WIDTH-1:0] state_target_42;
reg [STATE_HOT_WIDTH-1:0] state_target_30;
reg [STATE_HOT_WIDTH-1:0] state_target_31;
wire [STATE_HOT_WIDTH-1:0] state_target_33;
reg [STATE_HOT_WIDTH-1:0] state_target_34;
reg [STATE_HOT_WIDTH-1:0] state_target_44;
wire [7:0] state_code_target_0;
reg [7:0] state_code_target_1;
reg [7:0] state_code_target_3;
reg [7:0] state_code_target_2;
wire [7:0] state_code_target_4;
reg [7:0] state_code_target_5;
reg [7:0] state_code_target_6;
reg [7:0] state_code_target_7;
reg [7:0] state_code_target_8;
wire [7:0] state_code_target_9;
reg [7:0] state_code_target_10;
reg [7:0] state_code_target_11;
reg [7:0] state_code_target_12;
reg [7:0] state_code_target_13;
reg [7:0] state_code_target_14;
reg [7:0] state_code_target_15;
reg [7:0] state_code_target_16;
reg [7:0] state_code_target_17;
reg [7:0] state_code_target_18;
reg [7:0] state_code_target_19;
reg [7:0] state_code_target_32;
reg [7:0] state_code_target_20;
reg [7:0] state_code_target_21;
reg [7:0] state_code_target_22;
reg [7:0] state_code_target_23;
wire [7:0] state_code_target_24;
wire [7:0] state_code_target_25;
reg [7:0] state_code_target_26;
reg [7:0] state_code_target_27;
reg [7:0] state_code_target_43;
reg [7:0] state_code_target_28;
reg [7:0] state_code_target_29;
reg [7:0] state_code_target_35;
reg [7:0] state_code_target_36;
reg [7:0] state_code_target_37;
reg [7:0] state_code_target_38;
reg [7:0] state_code_target_39;
reg [7:0] state_code_target_40;
reg [7:0] state_code_target_41;
reg [7:0] state_code_target_42;
reg [7:0] state_code_target_30;
reg [7:0] state_code_target_31;
wire [7:0] state_code_target_33;
reg [7:0] state_code_target_34;
reg [7:0] state_code_target_44;
wire [STATE_HOT_WIDTH-1:0] state_case_next;
wire state_non_onehot;
reg state_encoding_fault;
wire state_mode_off;
wire state_media_fault;
wire state_other_cancel;
reg [STATE_HOT_WIDTH-1:0] state_next;
wire [7:0] state_case_code;
reg [7:0] state_code_next;
(* max_fanout=4 *) reg [STATE_HOT_WIDTH-1:0] resume_hot;
(* max_fanout=12 *) reg [31:0] time_cycles;
reg [31:0] window_start, barrier_start, hold_start_cycles;
reg [31:0] page_start,startup_qualifier;
reg [RETEST_DIV_WIDTH-1:0] retest_prescaler;
reg [RETEST_COUNT_WIDTH-1:0] retest_ms_left;
reg [9:0] retest_second_ms_left;
reg retest_dispatched,report_input_armed,report_round_saved;
reg skip_navigation_armed;
reg window_generation,barrier_generation,hold_generation;
reg page_generation;
reg window_timeout_tag,barrier_timeout_tag,hold_timeout_tag;
reg page_timeout_tag;
reg response_expired_q,response_deadline_q,pain_retry_expired_q;
reg barrier_expired_q,hold_expired_q,hold_target_q;
reg results_expired_q,education_expired_q;
wire education_page_complete;
reg [7:0] resume_state, queued_resume;
reg [5:0] queued_scene;
reg [1:0] queued_effect;
reg media_accepted, page_seen, mode_rearmed;
reg scene_welcome,scene_go,scene_wait,scene_hold,scene_pain;
reg scene_learning,scene_learning_advance,scene_education,scene_report;
reg [5:0] scene_next,scene_previous;
reg retry, pain_right, invalid_overlap;
reg [1:0] limb_index;
reg [2:0] question;
reg practice_active,practice_finished,practice_initialized;
(* max_fanout=8 *) reg practice_pacu;
reg practice_handoff_pending;
reg [5:0] practice_handoff_scene;
reg [2:0] practice_step,practice_phase,practice_errors;
reg [6:0] practice_progress;
reg practice_l_feedback,practice_r_feedback;
reg [5:0] practice_passed;
reg [3:0] education_voice_seen;
reg page_skip_used;
reg [2:0] practice_error_bank [0:5];
reg [7:0] accepted_seq;
reg accepted_valid,accepted_l,accepted_r;
reg [31:0] interaction_mark;
reg [6:0] interaction_progress;
reg interaction_hold_q;
reg [31:0] interaction_delta_q;
reg [6:0] interaction_delta_progress_q;
reg interaction_delta_valid_q;
integer practice_bank_index;
reg [31:0] practice_quiet_start,practice_feedback_start;
reg welcome_clear_armed,welcome_clear_active,clear_hold_consumed,history_clear_pending;
reg [31:0] welcome_clear_cycles;
reg visual_expired_q,feedback_timeout_q;
reg feedback_confirm_latched;
reg [5:0] feedback_ack_seq;
reg [31:0] visual_visible_start;
wire feedback_seen;
reg [5:0] feedback_next_scene,practice_return_scene,last_education_scene;
reg [7:0] feedback_next_resume;
reg [1:0] feedback_next_effect;
reg visual_expired;
wire [31:0] visual_duration;
reg [31:0] visual_age_q;
reg [5:0] visual_age_seq_q;
reg visual_age_seen_q;
reg release_watchdog_q;
wire release_watchdog;
reg practice_quiet_expired_q;
reg response_expired_qualified_q;
reg [7:0] response_expired_state_q;
reg practice_feedback_generation,practice_feedback_timeout_tag,practice_feedback_expired_q;
wire practice_feedback_expired;
wire practice_audio_quiet;
wire formal_visual;
wire measured_visual;
wire practice_visual_ok;
wire practice_visual_error;
wire visual_begin;
reg [31:0] visual_request_start;
wire [1:0] accepted_key_mask;
wire [1:0] wrong_key_mask;
reg visual_begin_q,visual_error_q;
reg [1:0] visual_mask_q;
reg convert_start, convert_hold, convert_seen_busy;
reg [31:0] convert_cycles;
reg [2:0] pending_hold_status;
wire convert_busy, convert_done;
wire [15:0] convert_ms;
wire sw1_on, sw2_on, l_down, r_down, b_down;
wire skip_press;
wire l_sync_down, r_sync_down, b_sync_down;
wire l_press_raw, r_press_raw, b_press, l_release_raw, r_release_raw, b_release;
wire [31:0] lp_raw, rp_raw, bp, lr_raw, rr_raw, br, lc, rc;
reg l_press_q,r_press_q,l_release_q,r_release_q;
reg go_check_pending_q,go_early_q,go_both_q;
reg [31:0] lp,rp,l_delta_q,r_delta_q,l_release_delta_q,r_release_delta_q;
(* max_fanout=2 *)reg l_inside_q,r_inside_q;
reg l_release_max_q,r_release_max_q;
reg l_release_target_q,r_release_target_q;
reg l_release_complete_q;
reg [7:0] press_state_q,release_state_q;
(* max_fanout=12 *) reg [STATE_HOT_WIDTH-1:0] press_state_hot_q;
reg press_window_tag_q,release_hold_tag_q;
reg press_l_sync_q,press_r_sync_q,press_invalid_q;
reg release_l_sync_q,release_r_sync_q,release_r_down_q;
wire press_matches ;
wire release_matches ;
wire l_press ;
wire r_press ;
wire l_release ;
wire r_release ;
wire press_event ;
wire release_event ;
wire l_event_sync ;
wire r_event_sync ;
wire r_event_down ;
wire event_invalid ;
wire lpp, rpp, lpr, rpr;
wire released ;
reg patient_blocked;
wire patient_eligible ;
wire practice_key_armed;
wire [6:0] practice_visible_progress;
wire cue_pass,cue_fail,cue_right;
wire cue_enable;
wire interaction_holding;
wire interaction_target;
wire interaction_feedback_allowed;
wire interaction_l;
wire interaction_r;
wire both_raw ;
wire both ;
wire [31:0] elapsed ;
wire [31:0] held ;
wire l_inside ;
wire r_inside ;
wire candidate_inside ;
wire response_expired_now ;
wire l_release_inside ;
wire r_release_inside ;
wire hold_expired_now ;
wire window_flags_valid ;
wire hold_flags_valid ;
wire expired ;
wire response_deadline ;
wire pain_retry_expired ;
wire barrier_expired ;
wire hold_expired ;
wire hold_target_reached ;
wire results_expired ;
wire education_expired ;
wire report_visible ;
wire report_press_source ;
wire report_l_press ;
wire report_r_press ;
reg report_auto_advance_q,report_manual_advance_q;
wire report_advance ;
wire welcome_clear_context;
wire welcome_clear_complete_now;
reg rest_new_round;
wire education_first_presented ;
// Continuous values retain the original net initializer expressions.
assign state_target_0 = encode_state(PAGE);
assign state_target_9 = encode_state(P_RESULTS);
assign state_target_24 = encode_state(RESULTS_WAIT);
assign state_target_25 = encode_state(RESULTS_WAIT);
assign state_target_33 = encode_state(PAUSE);
assign state_code_target_0 = PAGE;
assign state_code_target_9 = P_RESULTS;
assign state_code_target_24 = RESULTS_WAIT;
assign state_code_target_25 = RESULTS_WAIT;
assign state_code_target_33 = PAUSE;
assign state_case_next = 
        (state_target_0 & {STATE_HOT_WIDTH{state_hot[0]}}) |
        (state_target_1 & {STATE_HOT_WIDTH{state_hot[1]}}) |
        (state_target_2 & {STATE_HOT_WIDTH{state_hot[2]}}) |
        (state_target_3 & {STATE_HOT_WIDTH{state_hot[3]}}) |
        (state_target_4 & {STATE_HOT_WIDTH{state_hot[4]}}) |
        (state_target_5 & {STATE_HOT_WIDTH{state_hot[5]}}) |
        (state_target_6 & {STATE_HOT_WIDTH{state_hot[6]}}) |
        (state_target_7 & {STATE_HOT_WIDTH{state_hot[7]}}) |
        (state_target_8 & {STATE_HOT_WIDTH{state_hot[8]}}) |
        (state_target_9 & {STATE_HOT_WIDTH{state_hot[9]}}) |
        (state_target_10 & {STATE_HOT_WIDTH{state_hot[10]}}) |
        (state_target_11 & {STATE_HOT_WIDTH{state_hot[11]}}) |
        (state_target_12 & {STATE_HOT_WIDTH{state_hot[12]}}) |
        (state_target_13 & {STATE_HOT_WIDTH{state_hot[13]}}) |
        (state_target_14 & {STATE_HOT_WIDTH{state_hot[14]}}) |
        (state_target_15 & {STATE_HOT_WIDTH{state_hot[15]}}) |
        (state_target_16 & {STATE_HOT_WIDTH{state_hot[16]}}) |
        (state_target_17 & {STATE_HOT_WIDTH{state_hot[17]}}) |
        (state_target_18 & {STATE_HOT_WIDTH{state_hot[18]}}) |
        (state_target_19 & {STATE_HOT_WIDTH{state_hot[19]}}) |
        (state_target_20 & {STATE_HOT_WIDTH{state_hot[20]}}) |
        (state_target_21 & {STATE_HOT_WIDTH{state_hot[21]}}) |
        (state_target_22 & {STATE_HOT_WIDTH{state_hot[22]}}) |
        (state_target_23 & {STATE_HOT_WIDTH{state_hot[23]}}) |
        (state_target_24 & {STATE_HOT_WIDTH{state_hot[24]}}) |
        (state_target_25 & {STATE_HOT_WIDTH{state_hot[25]}}) |
        (state_target_26 & {STATE_HOT_WIDTH{state_hot[26]}}) |
        (state_target_27 & {STATE_HOT_WIDTH{state_hot[27]}}) |
        (state_target_28 & {STATE_HOT_WIDTH{state_hot[28]}}) |
        (state_target_29 & {STATE_HOT_WIDTH{state_hot[29]}}) |
        (state_target_30 & {STATE_HOT_WIDTH{state_hot[30]}}) |
        (state_target_31 & {STATE_HOT_WIDTH{state_hot[31]}}) |
        (state_target_32 & {STATE_HOT_WIDTH{state_hot[32]}}) |
        (state_target_33 & {STATE_HOT_WIDTH{state_hot[33]}}) |
        (state_target_34 & {STATE_HOT_WIDTH{state_hot[34]}}) |
        (state_target_35 & {STATE_HOT_WIDTH{state_hot[35]}}) |
        (state_target_36 & {STATE_HOT_WIDTH{state_hot[36]}}) |
        (state_target_37 & {STATE_HOT_WIDTH{state_hot[37]}}) |
        (state_target_38 & {STATE_HOT_WIDTH{state_hot[38]}}) |
        (state_target_39 & {STATE_HOT_WIDTH{state_hot[39]}}) |
        (state_target_40 & {STATE_HOT_WIDTH{state_hot[40]}}) |
        (state_target_41 & {STATE_HOT_WIDTH{state_hot[41]}}) |
        (state_target_42 & {STATE_HOT_WIDTH{state_hot[42]}}) |
        (state_target_43 & {STATE_HOT_WIDTH{state_hot[43]}}) |
        (state_target_44 & {STATE_HOT_WIDTH{state_hot[44]}});
assign state_non_onehot = (state_hot==0)||((state_hot&(state_hot-45'd1))!=0);
assign state_mode_off = (active_mode[0] && !sw1_on) || (active_mode[1] && !sw2_on);
assign state_media_fault = (media_error||feedback_timeout_q||state_encoding_fault) && !state_hot[34];
assign state_other_cancel = (active_mode[1] && retest_due && !retest_dispatched && !state_hot[34]) ||
        report_advance ||
        (active_mode==0 && mode_rearmed && sw1_on && !sw2_on && !state_hot[3]) ||
        (active_mode==0 && mode_rearmed && sw2_on && !sw1_on && !state_hot[3]) ||
        (history_exit===1'b1 && active_mode==0 && !sw1 && !sw2);
assign feedback_seen = feedback_confirm_latched&&feedback_ack_seq==feedback_seq&&feedback_kind!=0;
assign visual_duration = practice_active?
        (feedback_kind==1?CORRECT_VISUAL_CYCLES:ERROR_VISUAL_CYCLES):ANSWER_VISUAL_CYCLES;
assign release_watchdog = state_hot[36]&&!released&&release_watchdog_q&&barrier_timeout_tag==barrier_generation;
assign practice_feedback_expired = practice_feedback_expired_q &&
        practice_feedback_timeout_tag==practice_feedback_generation;
assign practice_audio_quiet = media_audio_active!==1'b1;
assign formal_visual = (state_hot[6]&&state_target_6[44])||(state_hot[8]&&state_target_8[44])||
        (state_hot[14]&&state_target_14[44])||(state_hot[22]&&state_target_22[44]);
assign measured_visual = (state_hot[16]&&state_target_16[30])||(state_hot[19]&&state_target_19[30]);
assign practice_visual_ok = (state_hot[37]&&state_target_37[39])||(state_hot[38]&&state_target_38[39]);
assign practice_visual_error = (state_hot[37]&&state_target_37[40])||(state_hot[38]&&state_target_38[40]);
assign visual_begin = formal_visual||measured_visual||practice_visual_ok||practice_visual_error;
assign accepted_key_mask = state_hot[19]?2'b01:state_hot[22]?{pain_right,!pain_right}:
        state_hot[38]?{practice_r_feedback,practice_l_feedback}:
        state_hot[37]&&practice_step==4?{cue_right,!cue_right}:{r_press_q,!r_press_q};
assign wrong_key_mask = {r_event_sync||r_press_raw||practice_r_feedback,
        l_event_sync||l_press_raw||practice_l_feedback};
assign press_matches =  (|(press_state_hot_q&state_hot)) && press_window_tag_q==window_generation;
assign release_matches =  release_state_q==state && release_hold_tag_q==hold_generation;
assign l_press =  l_press_q && press_matches;
assign r_press =  r_press_q && press_matches;
assign l_release =  l_release_q && release_matches;
assign r_release =  r_release_q && release_matches;
assign press_event =  l_press || r_press;
assign release_event =  l_release || r_release;
assign l_event_sync =  press_event ? press_l_sync_q:(release_event ? release_l_sync_q:l_sync_down);
assign r_event_sync =  press_event ? press_r_sync_q:(release_event ? release_r_sync_q:r_sync_down);
assign r_event_down =  release_event ? release_r_down_q:r_down;
assign event_invalid =  press_event ? press_invalid_q:invalid_overlap;
assign released =  !l_down && !r_down && !l_sync_down && !r_sync_down && !lpp && !rpp;
assign patient_eligible =  !patient_inhibit && !patient_blocked;
assign practice_key_armed = patient_eligible &&
        (state_hot[37] || state_hot[38]);
assign practice_visible_progress = (practice_active && practice_step==2 && state_hot[38]) ?
        interaction_progress:practice_progress;
assign cue_enable = practice_active&&!practice_pacu&&practice_step==4&&state_hot[37]&&patient_eligible;
assign interaction_holding = patient_eligible && (state_hot[19] || state_hot[22] ||
        (state_hot[38] && practice_step==2));
assign interaction_target = interaction_holding && hold_target_q && hold_timeout_tag==hold_generation;
assign interaction_feedback_allowed = patient_eligible && active_mode!=0 && !media_error &&
        !media_cancel && !state_hot[3] && !state_hot[34] && !state_hot[33];
assign interaction_l = interaction_feedback_allowed && !(l_sync_down&&r_sync_down) &&
        ((practice_active&&practice_l_feedback) ||
         (state_hot[19]) || (state_hot[22]&&!pain_right) ||
         (accepted_valid&&accepted_l&&l_down));
assign interaction_r = interaction_feedback_allowed && !(l_sync_down&&r_sync_down) &&
        ((practice_active&&practice_r_feedback) || (state_hot[22]&&pain_right) ||
         (accepted_valid&&accepted_r&&r_down));
assign both_raw =  l_sync_down && r_sync_down;
assign both =  l_event_sync && r_event_sync;
assign elapsed =  time_cycles-window_start;
assign held =  time_cycles-hold_start_cycles;
assign l_inside =  l_inside_q;
assign r_inside =  r_inside_q;
assign candidate_inside =  patient_eligible && ((lpp && ((lc-window_start)<RESPONSE_CYCLES)) ||
                            (rpp && ((rc-window_start)<RESPONSE_CYCLES)));
assign response_expired_now =  (elapsed>=RESPONSE_CYCLES) &&
        (!candidate_inside || elapsed>=RESPONSE_CYCLES+CONFIRM_TAIL);
assign l_release_inside =  patient_eligible && lpr && ((lc-hold_start_cycles)<=HOLD_MAX_CYCLES);
assign r_release_inside =  patient_eligible && rpr && ((rc-hold_start_cycles)<=HOLD_MAX_CYCLES);
assign hold_expired_now =  held>HOLD_MAX_CYCLES &&
        (!(pain_right  ?  r_release_inside : l_release_inside) ||
          held>HOLD_MAX_CYCLES+CONFIRM_TAIL);
assign window_flags_valid =  window_timeout_tag==window_generation;
assign hold_flags_valid =  hold_timeout_tag==hold_generation;
assign expired =  response_expired_qualified_q && response_expired_state_q==state && !l_press_raw && !r_press_raw;
assign response_deadline =  response_deadline_q && window_flags_valid;
assign pain_retry_expired =  pain_retry_expired_q && window_flags_valid;
assign barrier_expired =  barrier_expired_q && barrier_timeout_tag==barrier_generation;
assign hold_expired =  hold_expired_q && hold_flags_valid && !l_release_raw && !r_release_raw;
assign hold_target_reached =  hold_target_q && hold_flags_valid;
assign results_expired =  results_expired_q && window_flags_valid;
assign education_expired =  education_expired_q && page_timeout_tag==page_generation;
// release only the presented education PAGE wait at its dwell
// deadline. Reuse original EDU_END -> EDU_ACTIVE -> replace_page/cancel flow.
// A timer expiration does not mean the complete narration was heard.
assign education_page_complete = media_scene_done || education_expired;
assign report_visible =  active_mode[1] && scene_report && resume_state==RESULTS_END &&
                          media_accepted && page_seen;
assign report_press_source =  press_state_hot_q[2] || press_state_hot_q[24] || press_state_hot_q[25];
assign report_l_press =  patient_eligible && l_press_q && report_press_source && press_window_tag_q==window_generation && $signed(l_delta_q)>=0;
assign report_r_press =  patient_eligible && r_press_q && report_press_source && press_window_tag_q==window_generation && $signed(r_delta_q)>=0;
assign report_advance =  report_visible &&
                         (report_auto_advance_q || (!patient_inhibit && report_manual_advance_q));
assign welcome_clear_context = active_mode==0&&scene_welcome&&
        media_scene==`SC_WELCOME&&media_accepted&&page_seen;
assign welcome_clear_complete_now = welcome_clear_active&&
        welcome_clear_cycles+1>=WELCOME_CLEAR_CYCLES;
assign education_first_presented =  active_mode[1] && state_hot[2] &&
        scene_education && media_accepted && media_presented;

    
    
    
    
    
    
    
    
    
    
    // parameter-bounded counter; exact original countdown cycles.
    
    
    
    
    // Preserve the original registered one-hot state and every event payload.
    // Constant eligibility and the main state case use this same state bank.
    
    
    function [STATE_HOT_WIDTH-1:0] encode_state;
        input [7:0] value;
        begin
            encode_state=0;
            case(value)
                BOOT:encode_state[0]=1'b1;
                WELCOME:encode_state[1]=1'b1;
                PAGE:encode_state[2]=1'b1;
                CANCEL_WAIT:encode_state[3]=1'b1;
                P_GUID_END:encode_state[4]=1'b1;
                P_CALL_RELEASE:encode_state[5]=1'b1;
                P_CALL:encode_state[6]=1'b1;
                P_LIMB_RELEASE:encode_state[7]=1'b1;
                P_LIMB:encode_state[8]=1'b1;
                P_RESULTS:encode_state[9]=1'b1;
                LEARN_END:encode_state[10]=1'b1;
                READY_RELEASE:encode_state[11]=1'b1;
                READY_INPUT:encode_state[12]=1'b1;
                CHOICE_RELEASE:encode_state[13]=1'b1;
                CHOICE:encode_state[14]=1'b1;
                T4_PREP_END:encode_state[15]=1'b1;
                T4_INPUT:encode_state[16]=1'b1;
                HOLD_RELEASE:encode_state[17]=1'b1;
                HOLD_START:encode_state[18]=1'b1;
                HOLD_ACTIVE:encode_state[19]=1'b1;
                PAIN_RELEASE:encode_state[20]=1'b1;
                PAIN_START:encode_state[21]=1'b1;
                PAIN_ACTIVE:encode_state[22]=1'b1;
                PAIN_RETRY_RELEASE:encode_state[23]=1'b1;
                RESULTS_END:encode_state[24]=1'b1;
                RESULTS_WAIT:encode_state[25]=1'b1;
                EDU_END:encode_state[26]=1'b1;
                EDU_ACTIVE:encode_state[27]=1'b1;
                REST_RELEASE:encode_state[28]=1'b1;
                REST_INPUT:encode_state[29]=1'b1;
                CONVERT_START:encode_state[30]=1'b1;
                CONVERT_WAIT:encode_state[31]=1'b1;
                HOLD_RETRY_RELEASE:encode_state[32]=1'b1;
                PAUSE:encode_state[33]=1'b1;
                FAULT:encode_state[34]=1'b1;
                PRACT_AUDIO_WAIT:encode_state[35]=1'b1;
                PRACT_RELEASE:encode_state[36]=1'b1;
                PRACT_PRESS:encode_state[37]=1'b1;
                PRACT_HELD:encode_state[38]=1'b1;
                PRACT_CONFIRM:encode_state[39]=1'b1;
                PRACT_RETRY:encode_state[40]=1'b1;
                PRACT_ALARM:encode_state[41]=1'b1;
                PRACT_FINISHED:encode_state[42]=1'b1;
                RELAX_ACTIVE:encode_state[43]=1'b1;
                FEEDBACK_WAIT:encode_state[44]=1'b1;
                default:begin end
            endcase
        end
    endfunction
    // One registered one-hot bank owns the state. The published binary code
    // is a parallel OR of constant bit memberships from that same bank.
    // It changes on the state-update edge with no additional stage;
    // event tags, timing comparisons and all case eligibility retain their code.
    // Each current one-hot state prepares its own transition in parallel.
    // Predicates and priority inside a state are unchanged. Masked OR selection
    // prevents unrelated state transitions becoming a cascaded priority mux.
    
    
    
    always @* begin
        state_target_1=encode_state(WELCOME);
        if (b_release && last_report_mode != 0 && !scene_welcome && !clear_hold_consumed) begin
            if (scene_welcome) begin
                state_target_1=encode_state(PAGE);
            end else begin
                state_target_1=encode_state(PAGE);
            end
        end
    end
    
    always @*begin
        state_target_3=media_cmd_ready?encode_state(PAGE):encode_state(CANCEL_WAIT);
    end
    
    always @(active_mode or b_release or clear_hold_consumed or l_press_q or l_release_q or l_sync_down or last_report_mode or media_accepted or media_presented or education_page_complete or page_seen or patient_eligible or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or resume_hot or scene_education or scene_go or scene_learning or scene_learning_advance or scene_welcome or skip_audio_wait or skip_navigation_armed or window_generation) begin
        state_target_2=encode_state(PAGE);
        if (media_accepted && scene_go && media_presented) begin
            state_target_2=encode_state(T4_INPUT);
        end else begin
            if (media_accepted && education_page_complete && ! scene_go) begin
                state_target_2=resume_hot;
            end
        end
        if (active_mode == 0 && skip_audio_wait && b_release && last_report_mode != 0 && !scene_welcome && !clear_hold_consumed && media_accepted && page_seen) begin
            state_target_2=encode_state(CANCEL_WAIT);
        end else begin
            if (active_mode[1] && b_release) begin
                if (scene_learning) begin
                    state_target_2=encode_state(CANCEL_WAIT);
                end else begin
                    if (scene_education) begin
                        state_target_2=encode_state(CANCEL_WAIT);
                    end
                end
            end else begin
                if (skip_audio_wait && media_accepted && page_seen && skip_navigation_armed && patient_eligible && ( ( local_l_press ( PAGE ) && ! local_r_sync ( PAGE ) ) || ( local_r_press ( PAGE ) && ! local_l_sync ( PAGE ) ) )) begin
                    if (active_mode[1] && ( scene_education || ( scene_learning_advance && PRACTICE_ENABLE == 0 ) )) begin
                        state_target_2=encode_state(CANCEL_WAIT);
                    end
                end
            end
        end
        if(active_mode[1]&&scene_education&&media_accepted&&page_seen&&skip_navigation_armed&&patient_eligible&&
          ((local_r_press(PAGE)&&!local_l_sync(PAGE))||(local_l_press(PAGE)&&!local_r_sync(PAGE))))
          state_target_2=encode_state(CANCEL_WAIT);
    end
    
    assign state_target_4=(PRACTICE_ENABLE!=0&&!practice_finished)?encode_state(PRACT_AUDIO_WAIT):encode_state(PAGE);
    
    always @* begin
        state_target_5=encode_state(P_CALL_RELEASE);
        if (released) begin
            state_target_5=encode_state(P_CALL);
        end else begin
            if (barrier_expired) begin
                state_target_5=encode_state(PAUSE);
            end
        end
    end
    
    always @(expired or invalid_overlap or l_inside or l_press_q or l_release_q or l_sync_down or patient_inhibit or press_invalid_q or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or retry or window_generation) begin
        state_target_6=encode_state(P_CALL);
        if (! patient_inhibit && ! local_invalid ( P_CALL ) && ! local_both ( P_CALL ) && ( ( local_l_press ( P_CALL ) && l_inside && ! local_r_sync ( P_CALL ) ) || ( local_r_press ( P_CALL ) && r_inside && ! local_l_sync ( P_CALL ) ) )) begin
            state_target_6=encode_state(FEEDBACK_WAIT);
        end else begin
            if (expired) begin
                if (! retry) begin
                    state_target_6=encode_state(PAGE);
                end else begin
                    state_target_6=encode_state(PAGE);
                end
            end
        end
    end
    
    always @* begin
        state_target_7=encode_state(P_LIMB_RELEASE);
        if (released) begin
            state_target_7=encode_state(P_LIMB);
        end else begin
            if (barrier_expired) begin
                state_target_7=encode_state(PAGE);
            end
        end
    end
    
    always @(expired or invalid_overlap or l_inside or l_press_q or l_release_q or l_sync_down or limb_index or patient_inhibit or press_invalid_q or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or retry or window_generation) begin
        state_target_8=encode_state(P_LIMB);
        if (! patient_inhibit && ! local_invalid ( P_LIMB ) && ! local_both ( P_LIMB ) && ( ( local_l_press ( P_LIMB ) && l_inside && ! local_r_sync ( P_LIMB ) ) || ( local_r_press ( P_LIMB ) && r_inside && ! local_l_sync ( P_LIMB ) ) )) begin
            if (limb_index == 3) begin
                state_target_8=encode_state(FEEDBACK_WAIT);
            end else begin
                state_target_8=encode_state(FEEDBACK_WAIT);
            end
        end else begin
            if (expired) begin
                if (! retry) begin
                    state_target_8=encode_state(PAGE);
                end else begin
                    state_target_8=encode_state(PAGE);
                end
            end
        end
    end
    
    
    always @* begin
        state_target_10=encode_state(LEARN_END);
        if (PRACTICE_ENABLE != 0 && ( ( media_scene == `SC_LEARNKEY && ! practice_passed [ 1 ] ) || ( media_scene == `SC_LEARNHLD && ! practice_passed [ 2 ] ) || ( media_scene == `SC_LEARNVIS && ! practice_passed [ 4 ] ) )) begin
            state_target_10=encode_state(PRACT_AUDIO_WAIT);
        end else begin
            if (scene_learning_advance) begin
                state_target_10=encode_state(PAGE);
            end else begin
                state_target_10=encode_state(READY_RELEASE);
            end
        end
    end
    
    always @* begin
        state_target_11=encode_state(READY_RELEASE);
        if (b_release) begin
            state_target_11=encode_state(CANCEL_WAIT);
        end else begin
            if (released) begin
                state_target_11=encode_state(READY_INPUT);
            end
        end
    end
    
    always @(b_release or l_press_q or l_release_q or l_sync_down or patient_inhibit or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_target_12=encode_state(READY_INPUT);
        if (b_release) begin
            state_target_12=encode_state(CANCEL_WAIT);
        end else begin
            if (! patient_inhibit && ( ( local_l_press ( READY_INPUT ) && ! local_r_sync ( READY_INPUT ) ) || ( local_r_press ( READY_INPUT ) && ! local_l_sync ( READY_INPUT ) ) )) begin
                state_target_12=encode_state(PAGE);
            end
        end
    end
    
    always @* begin
        state_target_13=encode_state(CHOICE_RELEASE);
        if (released) begin
            state_target_13=encode_state(CHOICE);
        end else begin
            if (barrier_expired) begin
                state_target_13=encode_state(PAUSE);
            end
        end
    end
    
    always @(expired or invalid_overlap or l_inside or l_press_q or l_release_q or l_sync_down or patient_inhibit or press_invalid_q or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or retry or window_generation) begin
        state_target_14=encode_state(CHOICE);
        if (! patient_inhibit && ! local_both ( CHOICE ) && ! local_invalid ( CHOICE ) && local_l_press ( CHOICE ) && l_inside && ! local_r_sync ( CHOICE )) begin
            state_target_14=encode_state(FEEDBACK_WAIT);
        end else begin
            if (! patient_inhibit && ! local_both ( CHOICE ) && ! local_invalid ( CHOICE ) && local_r_press ( CHOICE ) && r_inside && ! local_l_sync ( CHOICE )) begin
                state_target_14=encode_state(FEEDBACK_WAIT);
            end else begin
                if (expired) begin
                    if (! retry) begin
                        state_target_14=encode_state(PAGE);
                    end else begin
                        state_target_14=encode_state(PAGE);
                    end
                end
            end
        end
    end
    
    always @* begin
        state_target_15=encode_state(T4_PREP_END);
        if (released || ! patient_eligible) begin
            state_target_15=encode_state(PAGE);
        end else begin
            state_target_15=encode_state(PAGE);
        end
    end
    
    always @(expired or go_both_q or go_check_pending_q or go_early_q or l_delta_q or l_inside or l_press_q or l_release_q or l_sync_down or patient_eligible or patient_inhibit or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_delta_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_target_16=encode_state(T4_INPUT);
        if (! patient_inhibit && go_check_pending_q && go_both_q) begin
            state_target_16=encode_state(PAGE);
        end else begin
            if (! patient_inhibit && go_check_pending_q && go_early_q) begin
                state_target_16=encode_state(PAGE);
            end else begin
                if (patient_eligible && ( local_both ( T4_INPUT ) || ( local_l_press ( T4_INPUT ) && local_r_sync ( T4_INPUT ) ) || ( local_r_press ( T4_INPUT ) && local_l_sync ( T4_INPUT ) ) )) begin
                    state_target_16=encode_state(PAGE);
                end else begin
                    if (! patient_inhibit && ( ( local_l_press ( T4_INPUT ) && $signed ( l_delta_q ) < 0 ) || ( local_r_press ( T4_INPUT ) && $signed ( r_delta_q ) < 0 ) )) begin
                        state_target_16=encode_state(PAGE);
                    end else begin
                        if (! patient_inhibit && ( ( local_l_press ( T4_INPUT ) && l_inside ) || ( local_r_press ( T4_INPUT ) && r_inside ) )) begin
                            state_target_16=encode_state(CONVERT_START);
                        end else begin
                            if (expired) begin
                                state_target_16=encode_state(PAGE);
                            end
                        end
                    end
                end
            end
        end
    end
    
    always @* begin
        state_target_17=encode_state(HOLD_RELEASE);
        if (released) begin
            state_target_17=encode_state(HOLD_START);
        end else begin
            if (barrier_expired) begin
                state_target_17=encode_state(PAGE);
            end
        end
    end
    
    always @(expired or invalid_overlap or l_inside or l_press_q or l_release_q or patient_inhibit or press_invalid_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_q or r_sync_down or release_r_sync_q or release_state_q or window_generation) begin
        state_target_18=encode_state(HOLD_START);
        if (! patient_inhibit && local_l_press ( HOLD_START ) && l_inside && ! local_r_sync ( HOLD_START ) && ! local_invalid ( HOLD_START )) begin
            state_target_18=encode_state(HOLD_ACTIVE);
        end else begin
            if (expired) begin
                state_target_18=encode_state(PAGE);
            end
        end
    end
    
    always @(hold_expired or l_press_q or l_release_max_q or l_release_q or patient_inhibit or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_down or r_press_q or r_release_q or r_sync_down or release_r_down_q or release_r_sync_q or release_state_q or window_generation) begin
        state_target_19=encode_state(HOLD_ACTIVE);
        if (patient_inhibit) begin
            state_target_19=encode_state(HOLD_RETRY_RELEASE);
        end else begin
            if (local_r_sync ( HOLD_ACTIVE ) || local_r_down ( HOLD_ACTIVE )) begin
                state_target_19=encode_state(PAGE);
            end else begin
                if (local_l_release ( HOLD_ACTIVE )) begin
                    if (l_release_max_q) begin
                        state_target_19=encode_state(CONVERT_START);
                    end else begin
                        state_target_19=encode_state(PAGE);
                    end
                end else begin
                    if (hold_expired) begin
                        state_target_19=encode_state(PAGE);
                    end
                end
            end
        end
    end
    
    always @* begin
        state_target_32=encode_state(HOLD_RETRY_RELEASE);
        if (released && patient_eligible) begin
            if (! response_deadline) begin
                state_target_32=encode_state(HOLD_START);
            end else begin
                state_target_32=encode_state(PAGE);
            end
        end else begin
            if (pain_retry_expired) begin
                state_target_32=encode_state(PAGE);
            end
        end
    end
    
    always @* begin
        state_target_20=encode_state(PAIN_RELEASE);
        if (released) begin
            state_target_20=encode_state(PAIN_START);
        end else begin
            if (barrier_expired) begin
                state_target_20=encode_state(PAGE);
            end
        end
    end
    
    always @(expired or l_inside or l_press_q or l_release_q or l_sync_down or patient_eligible or patient_inhibit or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_target_21=encode_state(PAIN_START);
        if (patient_eligible && ( local_both ( PAIN_START ) || ( local_l_press ( PAIN_START ) && local_r_sync ( PAIN_START ) ) || ( local_r_press ( PAIN_START ) && local_l_sync ( PAIN_START ) ) )) begin
            state_target_21=encode_state(PAIN_RETRY_RELEASE);
        end else begin
            if (! patient_inhibit && ( ( local_l_press ( PAIN_START ) && l_inside ) || ( local_r_press ( PAIN_START ) && r_inside ) )) begin
                state_target_21=encode_state(PAIN_ACTIVE);
            end else begin
                if (expired) begin
                    state_target_21=encode_state(PAGE);
                end
            end
        end
    end
    
    always @(hold_expired or l_press_q or l_release_max_q or l_release_q or l_sync_down or pain_right or patient_inhibit or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_max_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_target_22=encode_state(PAIN_ACTIVE);
        if (patient_inhibit) begin
            state_target_22=encode_state(PAIN_RETRY_RELEASE);
        end else begin
            if (( ! pain_right && local_r_sync ( PAIN_ACTIVE ) ) || ( pain_right && local_l_sync ( PAIN_ACTIVE ) )) begin
                state_target_22=encode_state(PAIN_RETRY_RELEASE);
            end else begin
                if (( ! pain_right && local_l_release ( PAIN_ACTIVE ) ) || ( pain_right && local_r_release ( PAIN_ACTIVE ) )) begin
                    if (pain_right ? r_release_max_q : l_release_max_q) begin
                        state_target_22=encode_state(FEEDBACK_WAIT);
                    end else begin
                        state_target_22=encode_state(PAGE);
                    end
                end else begin
                    if (hold_expired) begin
                        state_target_22=encode_state(PAGE);
                    end
                end
            end
        end
    end
    
    always @* begin
        state_target_23=encode_state(PAIN_RETRY_RELEASE);
        if (released && patient_eligible) begin
            if (! response_deadline) begin
                state_target_23=encode_state(PAIN_START);
            end else begin
                state_target_23=encode_state(PAGE);
            end
        end else begin
            if (pain_retry_expired) begin
                state_target_23=encode_state(PAGE);
            end
        end
    end
    
    
    
    always @* begin
        state_target_26=encode_state(EDU_END);
        if (! page_seen) begin
            state_target_26=encode_state(FAULT);
        end else begin
            state_target_26=encode_state(EDU_ACTIVE);
        end
    end
    
    always @(b_release or education_expired or l_press_q or l_release_q or l_sync_down or patient_eligible or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or skip_navigation_armed or window_generation)begin
        state_target_27=encode_state(EDU_ACTIVE);
        if(b_release||(skip_navigation_armed&&patient_eligible&&
          ((local_r_press(EDU_ACTIVE)&&!local_l_sync(EDU_ACTIVE))||(local_l_press(EDU_ACTIVE)&&!local_r_sync(EDU_ACTIVE))))||education_expired)
          state_target_27=encode_state(CANCEL_WAIT);
    end
    
    always @* begin
        state_target_43=encode_state(RELAX_ACTIVE);
        if (b_release) begin
            state_target_43=encode_state(CANCEL_WAIT);
        end
    end
    
    always @* begin
        state_target_28=encode_state(REST_RELEASE);
        if (released) begin
            state_target_28=encode_state(REST_INPUT);
        end
    end
    
    always @* begin
        state_target_29=encode_state(REST_INPUT);
        if (rest_new_round && ! patient_inhibit) begin
            state_target_29=encode_state(PAGE);
        end
    end
    
    always @* begin
        state_target_35=encode_state(PRACT_AUDIO_WAIT);
        if (! practice_audio_quiet) begin
        end else begin
            if (practice_quiet_expired_q) begin
                if (practice_alarm) begin
                    state_target_35=encode_state(CANCEL_WAIT);
                end else begin
                    state_target_35=encode_state(PRACT_RELEASE);
                end
            end
        end
    end
    
    always @* begin
        state_target_36=encode_state(PRACT_RELEASE);
        if (! practice_pacu && b_release) begin
            state_target_36=encode_state(CANCEL_WAIT);
        end else begin
            if (release_watchdog)begin state_target_36=encode_state(CANCEL_WAIT);end else if (released && patient_eligible) begin
                state_target_36=encode_state(PRACT_PRESS);
            end
        end
    end
    
    always @(b_release or cue_fail or cue_pass or expired or invalid_overlap or l_inside or l_press_q or l_release_q or l_sync_down or patient_eligible or practice_errors or practice_pacu or practice_step or press_invalid_q or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_target_37=encode_state(PRACT_PRESS);
        if (! practice_pacu && b_release) begin
            state_target_37=encode_state(CANCEL_WAIT);
        end else begin
            if (! patient_eligible) begin
                state_target_37=encode_state(PRACT_RELEASE);
            end else if(!practice_pacu&&practice_step==4)begin
                if(cue_pass)state_target_37=encode_state(PRACT_CONFIRM);
                else if(cue_fail||expired)state_target_37=encode_state(practice_errors>=3?CANCEL_WAIT:PRACT_RETRY);
            end else begin
                if (local_both ( PRACT_PRESS ) || local_invalid ( PRACT_PRESS )) begin
                    if (practice_errors>=3) begin
                        state_target_37=encode_state(CANCEL_WAIT);
                    end else begin
                        state_target_37=encode_state(PRACT_RETRY);
                    end
                end else begin
                    if (local_l_press ( PRACT_PRESS ) || local_r_press ( PRACT_PRESS )) begin
                        if (( local_l_press ( PRACT_PRESS ) && ! l_inside ) || ( local_r_press ( PRACT_PRESS ) && ! r_inside )) begin
                            if (practice_errors>=3) begin
                                state_target_37=encode_state(CANCEL_WAIT);
                            end else begin
                                state_target_37=encode_state(PRACT_RETRY);
                            end
                        end else begin
                            if (( practice_step == 0 || practice_step == 2 ) && local_r_press ( PRACT_PRESS )) begin
                                if (practice_errors>=3) begin
                                    state_target_37=encode_state(CANCEL_WAIT);
                                end else begin
                                    state_target_37=encode_state(PRACT_RETRY);
                                end
                            end else begin
                                if (practice_step == 1 && local_l_press ( PRACT_PRESS )) begin
                                    if (practice_errors>=3) begin
                                        state_target_37=encode_state(CANCEL_WAIT);
                                    end else begin
                                        state_target_37=encode_state(PRACT_RETRY);
                                    end
                                end else begin
                                    state_target_37=encode_state(PRACT_HELD);
                                end
                            end
                        end
                    end else begin
                        if (expired) begin
                            if (practice_errors>=3) begin
                                state_target_37=encode_state(CANCEL_WAIT);
                            end else begin
                                state_target_37=encode_state(PRACT_RETRY);
                            end
                        end
                    end
                end
            end
        end
    end
    
    always @(b_release or hold_expired or l_press_q or l_release_max_q or l_release_q or l_release_target_q or l_sync_down or patient_eligible or practice_errors or practice_l_feedback or practice_pacu or practice_r_feedback or practice_step or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_max_q or r_release_q or r_release_target_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_target_38=encode_state(PRACT_HELD);
        if (! practice_pacu && b_release) begin
            state_target_38=encode_state(CANCEL_WAIT);
        end else begin
            if (! patient_eligible) begin
                state_target_38=encode_state(PRACT_RELEASE);
            end else begin
                if (( practice_l_feedback && local_r_sync ( PRACT_HELD ) ) || ( practice_r_feedback && local_l_sync ( PRACT_HELD ) )) begin
                    if (practice_errors>=3) begin
                        state_target_38=encode_state(CANCEL_WAIT);
                    end else begin
                        state_target_38=encode_state(PRACT_RETRY);
                    end
                end else begin
                    if (( practice_l_feedback && local_l_release ( PRACT_HELD ) ) || ( practice_r_feedback && local_r_release ( PRACT_HELD ) )) begin
                        if (practice_step == 2) begin
                            if (l_release_target_q && l_release_max_q) begin
                                state_target_38=encode_state(PRACT_CONFIRM);
                            end else begin
                                if (practice_errors>=3) begin
                                    state_target_38=encode_state(CANCEL_WAIT);
                                end else begin
                                    state_target_38=encode_state(PRACT_RETRY);
                                end
                            end
                        end else begin
                            if (practice_pacu && practice_step == 3) begin
                                if (practice_l_feedback ? l_release_max_q : r_release_max_q) begin
                                    state_target_38=encode_state(PRACT_CONFIRM);
                                end else begin
                                    if (practice_errors>=3) begin
                                        state_target_38=encode_state(CANCEL_WAIT);
                                    end else begin
                                        state_target_38=encode_state(PRACT_RETRY);
                                    end
                                end
                            end else begin
                                if (practice_l_feedback ? l_release_target_q : r_release_target_q) begin
                                    if (practice_errors>=3) begin
                                        state_target_38=encode_state(CANCEL_WAIT);
                                    end else begin
                                        state_target_38=encode_state(PRACT_RETRY);
                                    end
                                end else begin
                                    state_target_38=encode_state(PRACT_CONFIRM);
                                end
                            end
                        end
                    end else begin
                        if (hold_expired) begin
                            if (practice_errors>=3) begin
                                state_target_38=encode_state(CANCEL_WAIT);
                            end else begin
                                state_target_38=encode_state(PRACT_RETRY);
                            end
                        end
                    end
                end
            end
        end
    end
    
    always @* begin
        state_target_39=encode_state(PRACT_CONFIRM);
        if (! practice_pacu && b_release) begin
            state_target_39=encode_state(CANCEL_WAIT);
        end else begin
            if (visual_expired) begin
                if (( practice_pacu && practice_step == 1 ) || ( ! practice_pacu && practice_step == 4 )) begin
                    state_target_39=encode_state(PAGE);
                end else begin
                    if (! practice_pacu && ( practice_step == 1 || practice_step == 2 )) begin
                        state_target_39=encode_state(PAGE);
                    end else begin
                        state_target_39=encode_state(PRACT_RELEASE);
                    end
                end
            end
        end
    end
    
    always @* begin
        state_target_40=encode_state(PRACT_RETRY);
        if (! practice_pacu && b_release) begin
            state_target_40=encode_state(CANCEL_WAIT);
        end else begin
            if (visual_expired && released && patient_eligible) begin
                state_target_40=encode_state(PRACT_RELEASE);
            end
        end
    end
    
    always @* begin
        state_target_41=encode_state(PRACT_ALARM);
        if (b_release) begin
            state_target_41=encode_state(CANCEL_WAIT);
        end
    end
    
    always @* begin
        state_target_42=encode_state(PRACT_FINISHED);
        if (practice_feedback_expired) begin
            if (practice_pacu) begin
                state_target_42=encode_state(PAGE);
            end else begin
                state_target_42=encode_state(PAGE);
            end
        end
    end
    
    always @* begin
        state_target_30=encode_state(CONVERT_START);
        if (! convert_busy) begin
            state_target_30=encode_state(CONVERT_WAIT);
        end
    end
    
    always @* begin
        state_target_31=encode_state(CONVERT_WAIT);
        if (convert_done && convert_seen_busy) begin
            if (convert_hold) begin
                state_target_31=encode_state(FEEDBACK_WAIT);
            end else begin
                state_target_31=encode_state(FEEDBACK_WAIT);
            end
        end
    end
    
    
    always @* begin
        state_target_34=encode_state(FAULT);
        if (active_mode == 0 && b_release) begin
            state_target_34=encode_state(CANCEL_WAIT);
        end
    end
    
    always @*begin
        state_target_44=visual_expired?encode_state(PAGE):encode_state(FEEDBACK_WAIT);
    end
    // Binary counterparts are mechanically derived from the exact hot trees.
    
    
    always @* begin
        state_code_target_1=WELCOME;
        if (b_release && last_report_mode != 0 && !scene_welcome && !clear_hold_consumed) begin
            if (scene_welcome) begin
                state_code_target_1=PAGE;
            end else begin
                state_code_target_1=PAGE;
            end
        end
    end
    
    always @*begin
        state_code_target_3=media_cmd_ready?PAGE:CANCEL_WAIT;
    end
    
    always @(active_mode or b_release or clear_hold_consumed or l_press_q or l_release_q or l_sync_down or last_report_mode or media_accepted or media_presented or education_page_complete or page_seen or patient_eligible or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or resume_state or scene_education or scene_go or scene_learning or scene_learning_advance or scene_welcome or skip_audio_wait or skip_navigation_armed or window_generation) begin
        state_code_target_2=PAGE;
        if (media_accepted && scene_go && media_presented) begin
            state_code_target_2=T4_INPUT;
        end else begin
            if (media_accepted && education_page_complete && ! scene_go) begin
                state_code_target_2=resume_state;
            end
        end
        if (active_mode == 0 && skip_audio_wait && b_release && last_report_mode != 0 && !scene_welcome && !clear_hold_consumed && media_accepted && page_seen) begin
            state_code_target_2=CANCEL_WAIT;
        end else begin
            if (active_mode[1] && b_release) begin
                if (scene_learning) begin
                    state_code_target_2=CANCEL_WAIT;
                end else begin
                    if (scene_education) begin
                        state_code_target_2=CANCEL_WAIT;
                    end
                end
            end else begin
                if (skip_audio_wait && media_accepted && page_seen && skip_navigation_armed && patient_eligible && ( ( local_l_press ( PAGE ) && ! local_r_sync ( PAGE ) ) || ( local_r_press ( PAGE ) && ! local_l_sync ( PAGE ) ) )) begin
                    if (active_mode[1] && ( scene_education || ( scene_learning_advance && PRACTICE_ENABLE == 0 ) )) begin
                        state_code_target_2=CANCEL_WAIT;
                    end
                end
            end
        end
        if(active_mode[1]&&scene_education&&media_accepted&&page_seen&&skip_navigation_armed&&patient_eligible&&
          ((local_r_press(PAGE)&&!local_l_sync(PAGE))||(local_l_press(PAGE)&&!local_r_sync(PAGE))))
          state_code_target_2=CANCEL_WAIT;
    end
    
    assign state_code_target_4=(PRACTICE_ENABLE!=0&&!practice_finished)?PRACT_AUDIO_WAIT:PAGE;
    
    always @* begin
        state_code_target_5=P_CALL_RELEASE;
        if (released) begin
            state_code_target_5=P_CALL;
        end else begin
            if (barrier_expired) begin
                state_code_target_5=PAUSE;
            end
        end
    end
    
    always @(expired or invalid_overlap or l_inside or l_press_q or l_release_q or l_sync_down or patient_inhibit or press_invalid_q or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or retry or window_generation) begin
        state_code_target_6=P_CALL;
        if (! patient_inhibit && ! local_invalid ( P_CALL ) && ! local_both ( P_CALL ) && ( ( local_l_press ( P_CALL ) && l_inside && ! local_r_sync ( P_CALL ) ) || ( local_r_press ( P_CALL ) && r_inside && ! local_l_sync ( P_CALL ) ) )) begin
            state_code_target_6=FEEDBACK_WAIT;
        end else begin
            if (expired) begin
                if (! retry) begin
                    state_code_target_6=PAGE;
                end else begin
                    state_code_target_6=PAGE;
                end
            end
        end
    end
    
    always @* begin
        state_code_target_7=P_LIMB_RELEASE;
        if (released) begin
            state_code_target_7=P_LIMB;
        end else begin
            if (barrier_expired) begin
                state_code_target_7=PAGE;
            end
        end
    end
    
    always @(expired or invalid_overlap or l_inside or l_press_q or l_release_q or l_sync_down or limb_index or patient_inhibit or press_invalid_q or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or retry or window_generation) begin
        state_code_target_8=P_LIMB;
        if (! patient_inhibit && ! local_invalid ( P_LIMB ) && ! local_both ( P_LIMB ) && ( ( local_l_press ( P_LIMB ) && l_inside && ! local_r_sync ( P_LIMB ) ) || ( local_r_press ( P_LIMB ) && r_inside && ! local_l_sync ( P_LIMB ) ) )) begin
            if (limb_index == 3) begin
                state_code_target_8=FEEDBACK_WAIT;
            end else begin
                state_code_target_8=FEEDBACK_WAIT;
            end
        end else begin
            if (expired) begin
                if (! retry) begin
                    state_code_target_8=PAGE;
                end else begin
                    state_code_target_8=PAGE;
                end
            end
        end
    end
    
    
    always @* begin
        state_code_target_10=LEARN_END;
        if (PRACTICE_ENABLE != 0 && ( ( media_scene == `SC_LEARNKEY && ! practice_passed [ 1 ] ) || ( media_scene == `SC_LEARNHLD && ! practice_passed [ 2 ] ) || ( media_scene == `SC_LEARNVIS && ! practice_passed [ 4 ] ) )) begin
            state_code_target_10=PRACT_AUDIO_WAIT;
        end else begin
            if (scene_learning_advance) begin
                state_code_target_10=PAGE;
            end else begin
                state_code_target_10=READY_RELEASE;
            end
        end
    end
    
    always @* begin
        state_code_target_11=READY_RELEASE;
        if (b_release) begin
            state_code_target_11=CANCEL_WAIT;
        end else begin
            if (released) begin
                state_code_target_11=READY_INPUT;
            end
        end
    end
    
    always @(b_release or l_press_q or l_release_q or l_sync_down or patient_inhibit or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_code_target_12=READY_INPUT;
        if (b_release) begin
            state_code_target_12=CANCEL_WAIT;
        end else begin
            if (! patient_inhibit && ( ( local_l_press ( READY_INPUT ) && ! local_r_sync ( READY_INPUT ) ) || ( local_r_press ( READY_INPUT ) && ! local_l_sync ( READY_INPUT ) ) )) begin
                state_code_target_12=PAGE;
            end
        end
    end
    
    always @* begin
        state_code_target_13=CHOICE_RELEASE;
        if (released) begin
            state_code_target_13=CHOICE;
        end else begin
            if (barrier_expired) begin
                state_code_target_13=PAUSE;
            end
        end
    end
    
    always @(expired or invalid_overlap or l_inside or l_press_q or l_release_q or l_sync_down or patient_inhibit or press_invalid_q or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or retry or window_generation) begin
        state_code_target_14=CHOICE;
        if (! patient_inhibit && ! local_both ( CHOICE ) && ! local_invalid ( CHOICE ) && local_l_press ( CHOICE ) && l_inside && ! local_r_sync ( CHOICE )) begin
            state_code_target_14=FEEDBACK_WAIT;
        end else begin
            if (! patient_inhibit && ! local_both ( CHOICE ) && ! local_invalid ( CHOICE ) && local_r_press ( CHOICE ) && r_inside && ! local_l_sync ( CHOICE )) begin
                state_code_target_14=FEEDBACK_WAIT;
            end else begin
                if (expired) begin
                    if (! retry) begin
                        state_code_target_14=PAGE;
                    end else begin
                        state_code_target_14=PAGE;
                    end
                end
            end
        end
    end
    
    always @* begin
        state_code_target_15=T4_PREP_END;
        if (released || ! patient_eligible) begin
            state_code_target_15=PAGE;
        end else begin
            state_code_target_15=PAGE;
        end
    end
    
    always @(expired or go_both_q or go_check_pending_q or go_early_q or l_delta_q or l_inside or l_press_q or l_release_q or l_sync_down or patient_eligible or patient_inhibit or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_delta_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_code_target_16=T4_INPUT;
        if (! patient_inhibit && go_check_pending_q && go_both_q) begin
            state_code_target_16=PAGE;
        end else begin
            if (! patient_inhibit && go_check_pending_q && go_early_q) begin
                state_code_target_16=PAGE;
            end else begin
                if (patient_eligible && ( local_both ( T4_INPUT ) || ( local_l_press ( T4_INPUT ) && local_r_sync ( T4_INPUT ) ) || ( local_r_press ( T4_INPUT ) && local_l_sync ( T4_INPUT ) ) )) begin
                    state_code_target_16=PAGE;
                end else begin
                    if (! patient_inhibit && ( ( local_l_press ( T4_INPUT ) && $signed ( l_delta_q ) < 0 ) || ( local_r_press ( T4_INPUT ) && $signed ( r_delta_q ) < 0 ) )) begin
                        state_code_target_16=PAGE;
                    end else begin
                        if (! patient_inhibit && ( ( local_l_press ( T4_INPUT ) && l_inside ) || ( local_r_press ( T4_INPUT ) && r_inside ) )) begin
                            state_code_target_16=CONVERT_START;
                        end else begin
                            if (expired) begin
                                state_code_target_16=PAGE;
                            end
                        end
                    end
                end
            end
        end
    end
    
    always @* begin
        state_code_target_17=HOLD_RELEASE;
        if (released) begin
            state_code_target_17=HOLD_START;
        end else begin
            if (barrier_expired) begin
                state_code_target_17=PAGE;
            end
        end
    end
    
    always @(expired or invalid_overlap or l_inside or l_press_q or l_release_q or patient_inhibit or press_invalid_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_q or r_sync_down or release_r_sync_q or release_state_q or window_generation) begin
        state_code_target_18=HOLD_START;
        if (! patient_inhibit && local_l_press ( HOLD_START ) && l_inside && ! local_r_sync ( HOLD_START ) && ! local_invalid ( HOLD_START )) begin
            state_code_target_18=HOLD_ACTIVE;
        end else begin
            if (expired) begin
                state_code_target_18=PAGE;
            end
        end
    end
    
    always @(hold_expired or l_press_q or l_release_max_q or l_release_q or patient_inhibit or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_down or r_press_q or r_release_q or r_sync_down or release_r_down_q or release_r_sync_q or release_state_q or window_generation) begin
        state_code_target_19=HOLD_ACTIVE;
        if (patient_inhibit) begin
            state_code_target_19=HOLD_RETRY_RELEASE;
        end else begin
            if (local_r_sync ( HOLD_ACTIVE ) || local_r_down ( HOLD_ACTIVE )) begin
                state_code_target_19=PAGE;
            end else begin
                if (local_l_release ( HOLD_ACTIVE )) begin
                    if (l_release_max_q) begin
                        state_code_target_19=CONVERT_START;
                    end else begin
                        state_code_target_19=PAGE;
                    end
                end else begin
                    if (hold_expired) begin
                        state_code_target_19=PAGE;
                    end
                end
            end
        end
    end
    
    always @* begin
        state_code_target_32=HOLD_RETRY_RELEASE;
        if (released && patient_eligible) begin
            if (! response_deadline) begin
                state_code_target_32=HOLD_START;
            end else begin
                state_code_target_32=PAGE;
            end
        end else begin
            if (pain_retry_expired) begin
                state_code_target_32=PAGE;
            end
        end
    end
    
    always @* begin
        state_code_target_20=PAIN_RELEASE;
        if (released) begin
            state_code_target_20=PAIN_START;
        end else begin
            if (barrier_expired) begin
                state_code_target_20=PAGE;
            end
        end
    end
    
    always @(expired or l_inside or l_press_q or l_release_q or l_sync_down or patient_eligible or patient_inhibit or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_code_target_21=PAIN_START;
        if (patient_eligible && ( local_both ( PAIN_START ) || ( local_l_press ( PAIN_START ) && local_r_sync ( PAIN_START ) ) || ( local_r_press ( PAIN_START ) && local_l_sync ( PAIN_START ) ) )) begin
            state_code_target_21=PAIN_RETRY_RELEASE;
        end else begin
            if (! patient_inhibit && ( ( local_l_press ( PAIN_START ) && l_inside ) || ( local_r_press ( PAIN_START ) && r_inside ) )) begin
                state_code_target_21=PAIN_ACTIVE;
            end else begin
                if (expired) begin
                    state_code_target_21=PAGE;
                end
            end
        end
    end
    
    always @(hold_expired or l_press_q or l_release_max_q or l_release_q or l_sync_down or pain_right or patient_inhibit or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_max_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_code_target_22=PAIN_ACTIVE;
        if (patient_inhibit) begin
            state_code_target_22=PAIN_RETRY_RELEASE;
        end else begin
            if (( ! pain_right && local_r_sync ( PAIN_ACTIVE ) ) || ( pain_right && local_l_sync ( PAIN_ACTIVE ) )) begin
                state_code_target_22=PAIN_RETRY_RELEASE;
            end else begin
                if (( ! pain_right && local_l_release ( PAIN_ACTIVE ) ) || ( pain_right && local_r_release ( PAIN_ACTIVE ) )) begin
                    if (pain_right ? r_release_max_q : l_release_max_q) begin
                        state_code_target_22=FEEDBACK_WAIT;
                    end else begin
                        state_code_target_22=PAGE;
                    end
                end else begin
                    if (hold_expired) begin
                        state_code_target_22=PAGE;
                    end
                end
            end
        end
    end
    
    always @* begin
        state_code_target_23=PAIN_RETRY_RELEASE;
        if (released && patient_eligible) begin
            if (! response_deadline) begin
                state_code_target_23=PAIN_START;
            end else begin
                state_code_target_23=PAGE;
            end
        end else begin
            if (pain_retry_expired) begin
                state_code_target_23=PAGE;
            end
        end
    end
    
    
    
    always @* begin
        state_code_target_26=EDU_END;
        if (! page_seen) begin
            state_code_target_26=FAULT;
        end else begin
            state_code_target_26=EDU_ACTIVE;
        end
    end
    
    always @(b_release or education_expired or l_press_q or l_release_q or l_sync_down or patient_eligible or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or skip_navigation_armed or window_generation)begin
        state_code_target_27=EDU_ACTIVE;
        if(b_release||(skip_navigation_armed&&patient_eligible&&
          ((local_r_press(EDU_ACTIVE)&&!local_l_sync(EDU_ACTIVE))||(local_l_press(EDU_ACTIVE)&&!local_r_sync(EDU_ACTIVE))))||education_expired)
          state_code_target_27=CANCEL_WAIT;
    end
    
    always @* begin
        state_code_target_43=RELAX_ACTIVE;
        if (b_release) begin
            state_code_target_43=CANCEL_WAIT;
        end
    end
    
    always @* begin
        state_code_target_28=REST_RELEASE;
        if (released) begin
            state_code_target_28=REST_INPUT;
        end
    end
    
    always @* begin
        state_code_target_29=REST_INPUT;
        if (rest_new_round && ! patient_inhibit) begin
            state_code_target_29=PAGE;
        end
    end
    
    always @* begin
        state_code_target_35=PRACT_AUDIO_WAIT;
        if (! practice_audio_quiet) begin
        end else begin
            if (practice_quiet_expired_q) begin
                if (practice_alarm) begin
                    state_code_target_35=CANCEL_WAIT;
                end else begin
                    state_code_target_35=PRACT_RELEASE;
                end
            end
        end
    end
    
    always @* begin
        state_code_target_36=PRACT_RELEASE;
        if (! practice_pacu && b_release) begin
            state_code_target_36=CANCEL_WAIT;
        end else begin
            if (release_watchdog)begin state_code_target_36=CANCEL_WAIT;end else if (released && patient_eligible) begin
                state_code_target_36=PRACT_PRESS;
            end
        end
    end
    
    always @(b_release or cue_fail or cue_pass or expired or invalid_overlap or l_inside or l_press_q or l_release_q or l_sync_down or patient_eligible or practice_errors or practice_pacu or practice_step or press_invalid_q or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_inside or r_press_q or r_release_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_code_target_37=PRACT_PRESS;
        if (! practice_pacu && b_release) begin
            state_code_target_37=CANCEL_WAIT;
        end else begin
            if (! patient_eligible) begin
                state_code_target_37=PRACT_RELEASE;
            end else if(!practice_pacu&&practice_step==4)begin
                if(cue_pass)state_code_target_37=PRACT_CONFIRM;
                else if(cue_fail||expired)state_code_target_37=practice_errors>=3?CANCEL_WAIT:PRACT_RETRY;
            end else begin
                if (local_both ( PRACT_PRESS ) || local_invalid ( PRACT_PRESS )) begin
                    if (practice_errors>=3) begin
                        state_code_target_37=CANCEL_WAIT;
                    end else begin
                        state_code_target_37=PRACT_RETRY;
                    end
                end else begin
                    if (local_l_press ( PRACT_PRESS ) || local_r_press ( PRACT_PRESS )) begin
                        if (( local_l_press ( PRACT_PRESS ) && ! l_inside ) || ( local_r_press ( PRACT_PRESS ) && ! r_inside )) begin
                            if (practice_errors>=3) begin
                                state_code_target_37=CANCEL_WAIT;
                            end else begin
                                state_code_target_37=PRACT_RETRY;
                            end
                        end else begin
                            if (( practice_step == 0 || practice_step == 2 ) && local_r_press ( PRACT_PRESS )) begin
                                if (practice_errors>=3) begin
                                    state_code_target_37=CANCEL_WAIT;
                                end else begin
                                    state_code_target_37=PRACT_RETRY;
                                end
                            end else begin
                                if (practice_step == 1 && local_l_press ( PRACT_PRESS )) begin
                                    if (practice_errors>=3) begin
                                        state_code_target_37=CANCEL_WAIT;
                                    end else begin
                                        state_code_target_37=PRACT_RETRY;
                                    end
                                end else begin
                                    state_code_target_37=PRACT_HELD;
                                end
                            end
                        end
                    end else begin
                        if (expired) begin
                            if (practice_errors>=3) begin
                                state_code_target_37=CANCEL_WAIT;
                            end else begin
                                state_code_target_37=PRACT_RETRY;
                            end
                        end
                    end
                end
            end
        end
    end
    
    always @(b_release or hold_expired or l_press_q or l_release_max_q or l_release_q or l_release_target_q or l_sync_down or patient_eligible or practice_errors or practice_l_feedback or practice_pacu or practice_r_feedback or practice_step or press_l_sync_q or press_r_sync_q or press_state_hot_q or press_window_tag_q or r_press_q or r_release_max_q or r_release_q or r_release_target_q or r_sync_down or release_l_sync_q or release_r_sync_q or release_state_q or window_generation) begin
        state_code_target_38=PRACT_HELD;
        if (! practice_pacu && b_release) begin
            state_code_target_38=CANCEL_WAIT;
        end else begin
            if (! patient_eligible) begin
                state_code_target_38=PRACT_RELEASE;
            end else begin
                if (( practice_l_feedback && local_r_sync ( PRACT_HELD ) ) || ( practice_r_feedback && local_l_sync ( PRACT_HELD ) )) begin
                    if (practice_errors>=3) begin
                        state_code_target_38=CANCEL_WAIT;
                    end else begin
                        state_code_target_38=PRACT_RETRY;
                    end
                end else begin
                    if (( practice_l_feedback && local_l_release ( PRACT_HELD ) ) || ( practice_r_feedback && local_r_release ( PRACT_HELD ) )) begin
                        if (practice_step == 2) begin
                            if (l_release_target_q && l_release_max_q) begin
                                state_code_target_38=PRACT_CONFIRM;
                            end else begin
                                if (practice_errors>=3) begin
                                    state_code_target_38=CANCEL_WAIT;
                                end else begin
                                    state_code_target_38=PRACT_RETRY;
                                end
                            end
                        end else begin
                            if (practice_pacu && practice_step == 3) begin
                                if (practice_l_feedback ? l_release_max_q : r_release_max_q) begin
                                    state_code_target_38=PRACT_CONFIRM;
                                end else begin
                                    if (practice_errors>=3) begin
                                        state_code_target_38=CANCEL_WAIT;
                                    end else begin
                                        state_code_target_38=PRACT_RETRY;
                                    end
                                end
                            end else begin
                                if (practice_l_feedback ? l_release_target_q : r_release_target_q) begin
                                    if (practice_errors>=3) begin
                                        state_code_target_38=CANCEL_WAIT;
                                    end else begin
                                        state_code_target_38=PRACT_RETRY;
                                    end
                                end else begin
                                    state_code_target_38=PRACT_CONFIRM;
                                end
                            end
                        end
                    end else begin
                        if (hold_expired) begin
                            if (practice_errors>=3) begin
                                state_code_target_38=CANCEL_WAIT;
                            end else begin
                                state_code_target_38=PRACT_RETRY;
                            end
                        end
                    end
                end
            end
        end
    end
    
    always @* begin
        state_code_target_39=PRACT_CONFIRM;
        if (! practice_pacu && b_release) begin
            state_code_target_39=CANCEL_WAIT;
        end else begin
            if (visual_expired) begin
                if (( practice_pacu && practice_step == 1 ) || ( ! practice_pacu && practice_step == 4 )) begin
                    state_code_target_39=PAGE;
                end else begin
                    if (! practice_pacu && ( practice_step == 1 || practice_step == 2 )) begin
                        state_code_target_39=PAGE;
                    end else begin
                        state_code_target_39=PRACT_RELEASE;
                    end
                end
            end
        end
    end
    
    always @* begin
        state_code_target_40=PRACT_RETRY;
        if (! practice_pacu && b_release) begin
            state_code_target_40=CANCEL_WAIT;
        end else begin
            if (visual_expired && released && patient_eligible) begin
                state_code_target_40=PRACT_RELEASE;
            end
        end
    end
    
    always @* begin
        state_code_target_41=PRACT_ALARM;
        if (b_release) begin
            state_code_target_41=CANCEL_WAIT;
        end
    end
    
    always @* begin
        state_code_target_42=PRACT_FINISHED;
        if (practice_feedback_expired) begin
            if (practice_pacu) begin
                state_code_target_42=PAGE;
            end else begin
                state_code_target_42=PAGE;
            end
        end
    end
    
    always @* begin
        state_code_target_30=CONVERT_START;
        if (! convert_busy) begin
            state_code_target_30=CONVERT_WAIT;
        end
    end
    
    always @* begin
        state_code_target_31=CONVERT_WAIT;
        if (convert_done && convert_seen_busy) begin
            if (convert_hold) begin
                state_code_target_31=FEEDBACK_WAIT;
            end else begin
                state_code_target_31=FEEDBACK_WAIT;
            end
        end
    end
    
    
    always @* begin
        state_code_target_34=FAULT;
        if (active_mode == 0 && b_release) begin
            state_code_target_34=CANCEL_WAIT;
        end
    end
    
    always @*begin
        state_code_target_44=visual_expired?PAGE:FEEDBACK_WAIT;
    end
    // Binary counterparts are mechanically derived from the exact hot trees.
    
    
    
    
    always @(posedge clk or posedge rst)
      if(rst)state_encoding_fault<=0;else state_encoding_fault<=state_non_onehot;
    
    
    
    
    always @* begin
        state_next=state_case_next;
        if(state_mode_off) state_next=encode_state(CANCEL_WAIT);
        else if(state_media_fault) state_next=encode_state(FAULT);
        else if(state_other_cancel) state_next=encode_state(CANCEL_WAIT);
        else if(!(|state_hot)) state_next=encode_state(FAULT);
    end
    
    // Select binary values directly from the CURRENT one-hot state.
    // Avoid the next-hot OR -> decode chain, without delaying any state edge.
    assign state_case_code=
        (state_code_target_0 & {8{state_hot[0]}}) |
        (state_code_target_1 & {8{state_hot[1]}}) |
        (state_code_target_2 & {8{state_hot[2]}}) |
        (state_code_target_3 & {8{state_hot[3]}}) |
        (state_code_target_4 & {8{state_hot[4]}}) |
        (state_code_target_5 & {8{state_hot[5]}}) |
        (state_code_target_6 & {8{state_hot[6]}}) |
        (state_code_target_7 & {8{state_hot[7]}}) |
        (state_code_target_8 & {8{state_hot[8]}}) |
        (state_code_target_9 & {8{state_hot[9]}}) |
        (state_code_target_10 & {8{state_hot[10]}}) |
        (state_code_target_11 & {8{state_hot[11]}}) |
        (state_code_target_12 & {8{state_hot[12]}}) |
        (state_code_target_13 & {8{state_hot[13]}}) |
        (state_code_target_14 & {8{state_hot[14]}}) |
        (state_code_target_15 & {8{state_hot[15]}}) |
        (state_code_target_16 & {8{state_hot[16]}}) |
        (state_code_target_17 & {8{state_hot[17]}}) |
        (state_code_target_18 & {8{state_hot[18]}}) |
        (state_code_target_19 & {8{state_hot[19]}}) |
        (state_code_target_20 & {8{state_hot[20]}}) |
        (state_code_target_21 & {8{state_hot[21]}}) |
        (state_code_target_22 & {8{state_hot[22]}}) |
        (state_code_target_23 & {8{state_hot[23]}}) |
        (state_code_target_24 & {8{state_hot[24]}}) |
        (state_code_target_25 & {8{state_hot[25]}}) |
        (state_code_target_26 & {8{state_hot[26]}}) |
        (state_code_target_27 & {8{state_hot[27]}}) |
        (state_code_target_28 & {8{state_hot[28]}}) |
        (state_code_target_29 & {8{state_hot[29]}}) |
        (state_code_target_30 & {8{state_hot[30]}}) |
        (state_code_target_31 & {8{state_hot[31]}}) |
        (state_code_target_32 & {8{state_hot[32]}}) |
        (state_code_target_33 & {8{state_hot[33]}}) |
        (state_code_target_34 & {8{state_hot[34]}}) |
        (state_code_target_35 & {8{state_hot[35]}}) |
        (state_code_target_36 & {8{state_hot[36]}}) |
        (state_code_target_37 & {8{state_hot[37]}}) |
        (state_code_target_38 & {8{state_hot[38]}}) |
        (state_code_target_39 & {8{state_hot[39]}}) |
        (state_code_target_40 & {8{state_hot[40]}}) |
        (state_code_target_41 & {8{state_hot[41]}}) |
        (state_code_target_42 & {8{state_hot[42]}}) |
        (state_code_target_43 & {8{state_hot[43]}}) |
        (state_code_target_44 & {8{state_hot[44]}});
    // Apply global priority AFTER binary encoding, avoiding a 44-wide
    // override mux feeding another wide OR tree. State/actions stay same edge.
    always @*begin
        state_code_next=state_case_code;
        if(state_mode_off)state_code_next=CANCEL_WAIT;
        else if(state_media_fault)state_code_next=FAULT;
        else if(state_other_cancel)state_code_next=CANCEL_WAIT;
        else if(!(|state_hot))state_code_next=FAULT;
    end
    always @(posedge clk or posedge rst) begin
        if(rst)begin state_hot<=encode_state(BOOT);state<=BOOT;end
        else begin state_hot<=state_next;state<=state_code_next;end
    end
    
    
    // rt: 0 unassessed,1 valid,2 no response,3 early,4 both,5 media fault,6 abort.
    // hold: 0 unassessed,1 >=target,2 shorter,3 not started,4 invalid,5 fault,6 abort,7 incomplete (<2s).
    // pain: 0 unassessed,1 none,2 mild,3 moderate,4 severe,5 unanswered,6 invalid,7 abort.
    
    assign ui_now_cycles=time_cycles;
    
    
    
    
    
    
    
    // Timeout comparisons are registered before the FSM priority/mux logic.
    // Each start-point generation changes with its timestamp. A flag tagged
    // with an old generation cannot terminate a newly opened response window.
    // Only control expiry is delayed by one clk; accepted key timestamps and
    // the T4/hold/pain classifications below retain their original boundaries.
    
    
    
    
    
    
    
    
    
    
    
    // One-bit scene categories are committed with media_scene. Navigation
    // metadata is decoded in its own register stage, outside the FSM enable
    // chain; every post-presentation state sees the current scene's metadata.
    
    
    
    
    
    
    // independent practice: per-step attempts 1..3 retry, fourth alarms.
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    assign history_clear_request=history_clear_pending;
    
    
    
    // The reliable confirmation has a small independent register cone. Do not
    // route it through every business show/score/management priority branch.
    always @(posedge clk or posedge rst)begin
        if(rst)begin feedback_confirm_latched<=0;feedback_ack_seq<=0;visual_visible_start<=0;end
        else if(feedback_kind==0||media_cancel||media_error||active_mode==0||state_hot[34])feedback_confirm_latched<=0;
        else if(feedback_confirmed===1'b1)begin
            feedback_confirm_latched<=1;feedback_ack_seq<=feedback_seq;visual_visible_start<=time_cycles;
        end
    end
    
    
    
    // Retire a visible feedback interval through one registered dispatch bit.
    // Full seq equality still qualifies the event. Only these waiting states
    // can arm it, so a previous interval cannot retire a newly entered wait.
    // This adds one application clock after the complete 600ms interval.
    
    always @(posedge clk or posedge rst)begin
        if(rst)visual_expired<=0;
        else visual_expired<=feedback_seen&&visual_expired_q&&
            (state_hot[39]||state_hot[40]||state_hot[44]);
    end
    // Multiply only constants at elaboration; a run-time multiply here would
    // infer DSP and put kind/state -> multiplier -> 32-bit compare on 100MHz.
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    // Prepare navigation from the current accepted-question context. These
    // values may settle before the key edge; only FEEDBACK_WAIT consumes them.
    // This removes a full state_next/global-priority cone from their CEs.
    always @(posedge clk or posedge rst)begin
        if(rst)begin feedback_next_scene<=0;feedback_next_resume<=0;feedback_next_effect<=0;end
        else begin
            feedback_next_effect<=EFFECT_FADE;
            if(state_hot[6])begin feedback_next_scene<=`SC_PACULARM;feedback_next_resume<=P_LIMB_RELEASE;end
            else if(state_hot[8])begin
                feedback_next_scene<=limb_index==3?`SC_PACURSLT:limb_scene(limb_index+1'b1);
                feedback_next_resume<=limb_index==3?P_RESULTS:P_LIMB_RELEASE;
            end else if(state_hot[14])begin
                feedback_next_scene<=question==4?`SC_T4WAIT:question_scene(question+1'b1);
                feedback_next_resume<=question==4?T4_PREP_END:CHOICE_RELEASE;
            end
            else if(state_hot[16])begin feedback_next_scene<=`SC_T5HOLD;feedback_next_resume<=HOLD_RELEASE;end
            else if(state_hot[19])begin feedback_next_scene<=`SC_T6PAIN;feedback_next_resume<=PAIN_RELEASE;end
            else if(state_hot[22])begin feedback_next_scene<=`SC_RESULTS;feedback_next_resume<=RESULTS_END;end
        end
    end
    
    
    
    
    
    
    
    
    
    always @(posedge clk or posedge rst)begin
        if(rst)begin visual_begin_q<=0;visual_error_q<=0;visual_mask_q<=0;end
        else begin
            visual_begin_q<=visual_begin&&!state_mode_off&&!state_media_fault&&!state_other_cancel;
            visual_error_q<=practice_visual_error;
            visual_mask_q<=practice_visual_error?wrong_key_mask:accepted_key_mask;
        end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin feedback_kind<=0;feedback_mask<=0;feedback_seq<=0;visual_request_start<=0;end
        else if(media_cancel||state_mode_off||state_media_fault||state_other_cancel||state_hot[34]||active_mode==0)feedback_kind<=0;
        else if(visual_begin_q)begin
            feedback_kind<=visual_error_q?2'd2:2'd1;feedback_mask<=visual_mask_q;
            feedback_seq<=feedback_seq+1'b1;visual_request_start<=time_cycles;
        end else if(feedback_kind!=0&&!state_hot[44]&&!state_hot[30]&&!state_hot[31]&&!state_hot[39]&&!state_hot[40])feedback_kind<=0;
    end
    
    
    
    
    
    
    
    // KEY1 toggles the session option, never a reset. Each fresh synchronized
    // press changes it once; a hold or short bounce cannot change it again.
    recovery_key_filter #(DEBOUNCE_CYCLES) u_skip_key(
        .clk(clk),.rst(rst),.raw_n(key_skip_n),.time_cycles(time_cycles),
        .down(),.sync_down(),.press(skip_press),.release_event(),
        .press_cycles(),.release_cycles(),.pending_press(),
        .pending_release(),.candidate_cycles());
    always @(posedge clk or posedge rst) begin
        if(rst) skip_audio_wait<=0;
        else if(skip_press) skip_audio_wait<=~skip_audio_wait;
    end
    
    
    
    
    
    
     
    
    
    
    // Captured on the same edge as press_state_q, with the same source state.
    // Local constant-source qualification reads one bit instead of decoding
    // the binary context again; event payloads and generations do not move.
    
    
    
    
    
    
    
    
    
    
    
    
    // An event is decided using the synchronized levels/overlap which were
    // observed when its confirmation pulse was captured, not one cycle later.
    
    
    
    
    
    
    // Keep observing real key levels. Settings never synthesize a release or
    // reset the key filters; rearming requires an actual complete release.
    
    
    
    
    assign practice_data={practice_active,practice_pacu,practice_step,practice_phase,
        practice_errors,(practice_active&&practice_l_feedback),
        (practice_active&&practice_r_feedback),practice_visible_progress,
        practice_key_armed,practice_finished,practice_handoff_pending,1'b0};
    // third-page wait: separate from formal T4 and from hold timing.
    
    
    assign ui_owner_request=practice_active&&!practice_alarm&&!practice_pacu&&practice_step==4&&state_hot[37];
    recovery_practice_cue #(.CLK_HZ(CLK_HZ),.WAIT_MS(PRACTICE_WAIT_MS),.SHORT_MS(HOLD_TARGET_MS)) u_practice_cue(
      .clk(clk),.rst(rst),.enable(cue_enable),.now_cycles(time_cycles),
      .presented(ui_presented===1'b1),.confirmed(ui_confirmed===1'b1),.presented_cycles(ui_presented_cycles),
      .press_l(l_press_raw),.press_r(r_press_raw),.release_l(l_release_raw),.release_r(r_release_raw),
      .press_l_time(lp_raw),.press_r_time(rp_raw),.release_l_time(lr_raw),.release_r_time(rr_raw),
      .sync_l(l_sync_down),.sync_r(r_sync_down),.green_request(ui_green_request),
      .pass_event(cue_pass),.fail_event(cue_fail),.answer_right(cue_right));
    // Observation only: these signals never feed the business acceptance or
    // timestamp paths. Progress shares the original 3-second hold origin.
    
    
    
    
    
    assign interaction_data={2'b00,accepted_seq,interaction_progress,accepted_valid,
        release_prompt,(input_armed||practice_key_armed),interaction_target,
        interaction_holding,interaction_r,interaction_l};
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            interaction_hold_q<=0;interaction_mark<=0;interaction_progress<=0;
            interaction_delta_q<=0;interaction_delta_progress_q<=0;interaction_delta_valid_q<=0;
        end
        else begin
            interaction_hold_q<=interaction_holding;
            // Separate the timestamp subtraction from the progress/mark CE.
            // The progress tag rejects the stale subtraction after each tick;
            // qualification flushes old hold origins before a new attempt.
            interaction_delta_q<=time_cycles-interaction_mark;
            interaction_delta_progress_q<=interaction_progress;
            interaction_delta_valid_q<=interaction_holding&&interaction_hold_q;
            if(!interaction_holding) begin interaction_progress<=0;interaction_mark<=hold_start_cycles;end
            else if(!interaction_hold_q) begin interaction_progress<=0;interaction_mark<=hold_start_cycles;end
            else if(hold_target_q && hold_timeout_tag==hold_generation) interaction_progress<=100;
            else if(interaction_delta_valid_q && interaction_delta_progress_q==interaction_progress &&
                interaction_delta_q>=PRACTICE_PROGRESS_CYCLES && interaction_progress<100) begin
                interaction_mark<=interaction_mark+PRACTICE_PROGRESS_CYCLES;
                interaction_progress<=interaction_progress+1'b1;
            end
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) patient_blocked<=0;
        else if(patient_inhibit) patient_blocked<=1;
        else if(released && !lpr && !rpr) patient_blocked<=0;
    end
    
    
    
    
    
    
    
    
    
    
    
    
    
    // Confirmation pulses in the capture stage must retire before an expiry
    // decision. Their saved timestamp still rejects every out-of-window key.
    
    
    
    
    
    
    
    
    
    // A report remains the same response window across PAGE/RESULTS_END/WAIT.
    // Its presentation changes the generation, rejecting old page candidates.
    
    
    
    
    
    // Retire the qualified report control decision separately from the
    // global FSM priority mux. Presentation and patient timestamps retain
    // their exact values; replacing a report is delayed by one clk.
    always @(posedge clk or posedge rst) begin
        if(rst) begin report_auto_advance_q<=0;report_manual_advance_q<=0;end
        else begin
            report_manual_advance_q<=report_visible && report_input_armed && (report_l_press || report_r_press);
            report_auto_advance_q<=report_visible && results_expired;
        end
    end
    assign input_armed = patient_eligible && (state_hot[6] || state_hot[8] || state_hot[12] ||
        state_hot[14] || state_hot[16] || state_hot[18] || state_hot[19] || state_hot[32] ||
        state_hot[21] || state_hot[22] || state_hot[29] ||
        state_hot[37] || state_hot[38]);
    recovery_keys #(DEBOUNCE_CYCLES) u_keys (
        .clk(clk),.rst(rst),.time_cycles(time_cycles),.sw1(sw1),.sw2(sw2),
        .key_l_n(key_l_n),.key_r_n(key_r_n),.key_back_n(key_back_n),
        .sw1_on(sw1_on),.sw2_on(sw2_on),.l_down(l_down),.r_down(r_down),.b_down(b_down),
        .l_sync_down(l_sync_down),.r_sync_down(r_sync_down),.b_sync_down(b_sync_down),
        .l_press(l_press_raw),.r_press(r_press_raw),.b_press(b_press),
        .l_release(l_release_raw),.r_release(r_release_raw),.b_release(b_release),
        .l_press_cycles(lp_raw),.r_press_cycles(rp_raw),.b_press_cycles(bp),
        .l_release_cycles(lr_raw),.r_release_cycles(rr_raw),.b_release_cycles(br),
        .l_pending_press(lpp),.r_pending_press(rpp),.l_pending_release(lpr),
        .r_pending_release(rpr),.l_candidate_cycles(lc),.r_candidate_cycles(rc));

    
    
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            welcome_clear_armed<=0;welcome_clear_active<=0;clear_hold_consumed<=0;
            history_clear_pending<=0;welcome_clear_cycles<=0;
        end else begin
            if(history_clear_done===1'b1&&history_clear_pending)history_clear_pending<=0;
            if(b_release)begin
                if(welcome_clear_context&&welcome_clear_complete_now&&!history_clear_pending)begin
                    history_clear_pending<=1;clear_hold_consumed<=1;welcome_clear_armed<=0;
                end else begin clear_hold_consumed<=0;welcome_clear_armed<=1;end
                welcome_clear_active<=0;
                welcome_clear_cycles<=0;
            end else if(!welcome_clear_context)begin
                welcome_clear_active<=0;welcome_clear_cycles<=0;
                welcome_clear_armed<=!b_down;
            end else if(!b_down)begin
                welcome_clear_active<=0;welcome_clear_cycles<=0;welcome_clear_armed<=1;
            end else if(welcome_clear_active)begin
                if(welcome_clear_cycles+1>=WELCOME_CLEAR_CYCLES)begin
                    history_clear_pending<=1;welcome_clear_active<=0;
                    welcome_clear_cycles<=0;welcome_clear_armed<=0;clear_hold_consumed<=1;
                end else welcome_clear_cycles<=welcome_clear_cycles+1'b1;
            end else if(b_press&&welcome_clear_armed&&!history_clear_pending)begin
                welcome_clear_active<=1;welcome_clear_cycles<=0;welcome_clear_armed<=0;
            end
        end
    end

    recovery_cycle_to_ms #(.DIVISOR(CYCLES_PER_MS)) u_ms_converter(
        .clk(clk),.rst(rst),.start(convert_start),.cycles(convert_cycles),
        .busy(convert_busy),.done(convert_done),.milliseconds(convert_ms));
    function [5:0] question_scene;
        input [2:0] q;
        begin case(q)
            0:question_scene=`SC_T1Q1; 1:question_scene=`SC_T1Q2;
            2:question_scene=`SC_T2NUM; 3:question_scene=`SC_T2SAME;
            default:question_scene=`SC_T3LISTEN;
        endcase end
    endfunction

    function choice_correct_right;
        input [2:0] q;
        begin case(question_set)
            1:choice_correct_right=~q[0]; // A: R,L,R,L
            2:choice_correct_right=(q!=2); // B: R,R,L,R
            default:choice_correct_right=q[0]; // original: L,R,L,R
        endcase end
    endfunction
    // One registered event-classification stage breaks timestamp subtraction
    // and threshold comparison away from score/FSM priority logic. Payloads,
    // source state and timer generation travel with the valid pulse. A pulse
    // from READY, an old scene, an aborted mode or an old timer cannot answer
    // a new question; all reported durations retain the original timestamps.
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            l_press_q<=0;r_press_q<=0;l_release_q<=0;r_release_q<=0;
            go_check_pending_q<=0;go_early_q<=0;go_both_q<=0;
            lp<=0;rp<=0;l_delta_q<=0;r_delta_q<=0;
            l_release_delta_q<=0;r_release_delta_q<=0;
            l_inside_q<=0;r_inside_q<=0;
            l_release_max_q<=0;r_release_max_q<=0;
            l_release_target_q<=0;r_release_target_q<=0;
            l_release_complete_q<=0;
            press_state_q<=BOOT;release_state_q<=BOOT;press_state_hot_q<=encode_state(BOOT);
            press_window_tag_q<=0;release_hold_tag_q<=0;
            press_l_sync_q<=0;press_r_sync_q<=0;press_invalid_q<=0;
            release_l_sync_q<=0;release_r_sync_q<=0;release_r_down_q<=0;
        end else begin
            go_check_pending_q<=state_hot[2] && media_accepted && scene_go && media_presented;
            go_both_q<=patient_eligible && both_raw;
            go_early_q<=patient_eligible && (l_down || r_down ||
                (lpp && $signed(lc-time_cycles)<0) || (rpp && $signed(rc-time_cycles)<0));
            l_press_q<=patient_eligible && l_press_raw;r_press_q<=patient_eligible && r_press_raw;
            l_release_q<=patient_eligible && l_release_raw;r_release_q<=patient_eligible && r_release_raw;
            lp<=lp_raw;rp<=rp_raw;
            l_delta_q<=lp_raw-window_start;r_delta_q<=rp_raw-window_start;
            l_inside_q<=(lp_raw-window_start)<RESPONSE_CYCLES;
            r_inside_q<=(rp_raw-window_start)<RESPONSE_CYCLES;
            l_release_delta_q<=lr_raw-hold_start_cycles;
            r_release_delta_q<=rr_raw-hold_start_cycles;
            l_release_max_q<=(lr_raw-hold_start_cycles)<=HOLD_MAX_CYCLES;
            r_release_max_q<=(rr_raw-hold_start_cycles)<=HOLD_MAX_CYCLES;
            l_release_target_q<=(lr_raw-hold_start_cycles)>=HOLD_TARGET_CYCLES;
            r_release_target_q<=(rr_raw-hold_start_cycles)>=HOLD_TARGET_CYCLES;
            l_release_complete_q<=(lr_raw-hold_start_cycles)>=HOLD_COMPLETE_CYCLES;
            press_state_q<=state;release_state_q<=state;press_state_hot_q<=state_hot;
            press_window_tag_q<=window_generation;release_hold_tag_q<=hold_generation;
            press_l_sync_q<=l_sync_down;press_r_sync_q<=r_sync_down;
            press_invalid_q<=invalid_overlap;
            release_l_sync_q<=l_sync_down;release_r_sync_q<=r_sync_down;
            release_r_down_q<=r_down;
        end
    end
    function [5:0] next_scene;
        input [5:0] scene_id;
        begin case(scene_id)
            `SC_LEARNKEY:next_scene=`SC_LEARNHLD;
            `SC_LEARNHLD:next_scene=`SC_LEARNVIS;
            `SC_LEARNVIS:next_scene=`SC_READY;
            `SC_EDUMOVE:next_scene=`SC_EDUPAIN;
            `SC_EDUPAIN:next_scene=`SC_EDUNAUS;
            `SC_EDUNAUS:next_scene=`SC_EDUFOOD;
            `SC_EDUFOOD:next_scene=`SC_EDUMOVE;
            default:next_scene=scene_id;
        endcase end
    endfunction
    function [5:0] previous_scene;
        input [5:0] scene_id;
        begin case(scene_id)
            `SC_LEARNKEY:previous_scene=`SC_LEARNKEY;
            `SC_LEARNHLD:previous_scene=`SC_LEARNKEY;
            `SC_LEARNVIS:previous_scene=`SC_LEARNHLD;
            `SC_READY:previous_scene=`SC_LEARNVIS;
            `SC_EDUMOVE:previous_scene=`SC_EDUFOOD;
            `SC_EDUPAIN:previous_scene=`SC_EDUMOVE;
            `SC_EDUNAUS:previous_scene=`SC_EDUPAIN;
            `SC_EDUFOOD:previous_scene=`SC_EDUNAUS;
            default:previous_scene=scene_id;
        endcase end
    endfunction
    always @(posedge clk or posedge rst) begin
        if(rst) begin scene_next<=`SC_WELCOME;scene_previous<=`SC_WELCOME;end
        else begin scene_next<=next_scene(media_scene);scene_previous<=previous_scene(media_scene);end
    end
    // Every new show() clears accepted before a command can handshake. Thus
    // PAGE presentation is eligible no earlier than the next cycle, and this
    // independent observation has the same presented/done semantics. It does
    // not need the score/hold/error priority mux used by show()/replace_page().
    always @(posedge clk or posedge rst) begin
        if(rst) page_seen<=0;
        else if(!media_accepted) page_seen<=0;
        else if(media_presented) page_seen<=1;
    end
    task save_round_report;
        begin
            if(active_mode!=0 && !practice_active && !practice_alarm && !report_round_saved && |report_started) begin
                report_generated<=1;report_round_saved<=1;
            end
        end
    endtask
    task show_core;
        input [5:0] scene_id; input [7:0] after_state;input [1:0] effect;
        input normal_teaching_handoff;
        begin
            media_scene<=scene_id; media_cmd_valid<=1; media_accepted<=0;
            
            if(scene_id>=`SC_EDUMOVE&&scene_id<=`SC_EDUFOOD)last_education_scene<=scene_id;
            page_skip_used<=skip_audio_wait;
            media_effect<=normal_teaching_handoff?EFFECT_DIRECT:
                (scene_id==`SC_T4GO ?EFFECT_DIRECT:
                ((scene_report||media_scene==`SC_PACURSLT)?EFFECT_DIRECT:
                ((((scene_id>=`SC_T1Q1 && scene_id<=`SC_T6PAIN)||
                    (scene_id>=`SC_PACUCALL&&scene_id<=`SC_PACULLEG)||scene_id==`SC_PACURLEG)) ? 2'd3:
                ((scene_id>=`SC_LEARNKEY && scene_id<=`SC_READY) ? EFFECT_FADE:
                 ((scene_id>=`SC_EDUMOVE && scene_id<=`SC_EDUFOOD) ? EFFECT_WIPE:effect)))));
            case(scene_id)
                `SC_EDUPAIN:media_wipe_direction<=1;
                `SC_EDUNAUS:media_wipe_direction<=2;
                `SC_EDUFOOD:media_wipe_direction<=3;
                default:media_wipe_direction<=0;
            endcase
            scene_welcome<=scene_id==`SC_WELCOME;
            scene_go<=scene_id==`SC_T4GO;scene_wait<=scene_id==`SC_T4WAIT;
            scene_hold<=scene_id==`SC_T5HOLD;scene_pain<=scene_id==`SC_T6PAIN;
            scene_learning<=scene_id>=`SC_LEARNKEY && scene_id<=`SC_READY;
            scene_learning_advance<=scene_id<`SC_READY;
            scene_education<=scene_id>=`SC_EDUMOVE && scene_id<=`SC_EDUFOOD;
            scene_report<=scene_id==`SC_RESULTS;
            if (active_mode[0]) begin
                if (scene_id==`SC_PACUCALL || scene_id==`SC_PACUREP) report_started[0]<=1;
                if (scene_id==`SC_PACULARM || scene_id==`SC_PACURARM ||
                    scene_id==`SC_PACULLEG || scene_id==`SC_PACURLEG) report_started[1]<=1;
            end else if (active_mode[1]) begin
                case(scene_id)
                    `SC_T1Q1:report_started[0]<=1;
                    `SC_T2NUM:report_started[1]<=1;
                    `SC_T3LISTEN:report_started[2]<=1;
                    `SC_T4WAIT:report_started[3]<=1;
                    `SC_T5HOLD:report_started[4]<=1;
                    `SC_T6PAIN:report_started[5]<=1;
                    default:begin end
                endcase
            end
            resume_state<=after_state;resume_hot<=encode_state(after_state);begin /* transition is defined in canonical generated network */ end 
            release_prompt<=0; invalid_overlap<=0;
            if(scene_id==`SC_PACURSLT || scene_id==`SC_RESULTS)
                save_round_report;
        end
    endtask
    // Common show side effects stay in one task. Source identity is a
    // constant argument of this command, never an NBA flag from this cycle.
    task show;
        input [5:0] scene_id;input [7:0] after_state;input [1:0] effect;
        begin show_core(scene_id,after_state,effect,1'b0);end
    endtask
    task show_teaching;
        input [5:0] scene_id;input [7:0] after_state;
        begin
            practice_handoff_pending<=1;
            practice_handoff_scene<=scene_id;
            show_core(scene_id,after_state,EFFECT_DIRECT,1'b1);
        end
    endtask
    // FEEDBACK_WAIT can only navigate among accepted-answer successors.
    // T3->WAIT now enters this path; GO onset, teaching, education and welcome do not.
    // Do not route those impossible side effects through this state's CE.
    task show_feedback;
        begin
            media_scene<=feedback_next_scene;media_cmd_valid<=1;media_accepted<=0;
            page_skip_used<=skip_audio_wait;
            media_effect<=feedback_next_scene==`SC_T4GO ?EFFECT_DIRECT:
                (((feedback_next_scene>=`SC_T1Q1&&feedback_next_scene<=`SC_T6PAIN)||
                 (feedback_next_scene>=`SC_PACUCALL&&feedback_next_scene<=`SC_PACULLEG)||
                 feedback_next_scene==`SC_PACURLEG)?2'd3:feedback_next_effect);
            media_wipe_direction<=0;
            scene_welcome<=0;scene_go<=feedback_next_scene==`SC_T4GO;
            scene_wait<=feedback_next_scene==`SC_T4WAIT;scene_learning<=0;scene_education<=0;
            scene_hold<=feedback_next_scene==`SC_T5HOLD;scene_pain<=feedback_next_scene==`SC_T6PAIN;
            scene_learning_advance<=feedback_next_scene<`SC_READY;
            scene_report<=feedback_next_scene==`SC_RESULTS;
            if(active_mode[0])begin
                if(feedback_next_scene==`SC_PACULARM||feedback_next_scene==`SC_PACURARM||
                   feedback_next_scene==`SC_PACULLEG||feedback_next_scene==`SC_PACURLEG)report_started[1]<=1;
            end else if(active_mode[1])begin
                case(feedback_next_scene)
                    `SC_T2NUM:report_started[1]<=1;
                    `SC_T3LISTEN:report_started[2]<=1;
                    `SC_T4WAIT:report_started[3]<=1;
                    `SC_T5HOLD:report_started[4]<=1;
                    `SC_T6PAIN:report_started[5]<=1;
                    default:begin end
                endcase
            end
            resume_state<=feedback_next_resume;resume_hot<=encode_state(feedback_next_resume);begin /* transition is defined in canonical generated network */ end 
            release_prompt<=0;invalid_overlap<=0;
            if(feedback_next_scene==`SC_PACURSLT||feedback_next_scene==`SC_RESULTS)save_round_report;
        end
    endtask
    task replace_page;
        input [5:0] scene_id; input [7:0] after_state;input [1:0] effect;
        begin
            media_cancel<=1; media_cmd_valid<=0; media_accepted<=0;
            queued_scene<=scene_id; queued_resume<=after_state;queued_effect<=(scene_report||media_scene==`SC_PACURSLT)?EFFECT_DIRECT:effect; begin /* transition is defined in canonical generated network */ end 
            
            release_prompt<=0;
        end
    endtask
    task clear_ward;
        begin
            t1_correct<=0; t2_correct<=0; t1_unanswered<=0; t2_unanswered<=0;
            t3_result<=0; rt_ms<=0; rt_cycles<=0; rt_status<=0;
            hold_ms<=0; hold_status<=0; pain<=0; result_valid<=0;
            retry<=0; question<=0; invalid_overlap<=0; release_prompt<=0;
            retest_dispatched<=0;
            report_started<=0;report_outcome<=1;
            report_round_saved<=0;
            education_voice_seen<=0;
            page_skip_used<=0;
        end
    endtask
    task start_practice;
        input pacu_context;
        begin
            practice_pacu<=pacu_context;practice_active<=0;practice_handoff_pending<=0;practice_return_scene<=media_scene;
            practice_quiet_start<=time_cycles;practice_phase<=0;
            practice_progress<=0;practice_l_feedback<=0;practice_r_feedback<=0;
            if(!practice_initialized)begin
                practice_step<=0;practice_errors<=0;practice_alarm<=0;
                practice_initialized<=1;
            end else if(!pacu_context)begin
                case(media_scene)
                    `SC_LEARNKEY:begin
                        practice_step<=practice_passed[0] ? 1:0;
                        practice_errors<=practice_passed[0] ? practice_error_bank[1]:practice_error_bank[0];
                    end
                    `SC_LEARNHLD:begin practice_step<=2;practice_errors<=practice_error_bank[2];end
                    default:begin practice_step<=4;practice_errors<=practice_error_bank[4];end
                endcase
            end
            begin /* transition is defined in canonical generated network */ end 
        end
    endtask
    task accept_interaction;
        input right_key;
        begin
            accepted_seq<=accepted_seq+1'b1;accepted_valid<=1;
            accepted_identity<={question_set,media_scene};
            accepted_l<=!right_key;accepted_r<=right_key;
        end
    endtask
    // A request remains stable until a matching final-pixel UART event has
    // returned. The timer starts on that return, never on packet publication.
    task arm_visual;
        input [1:0] kind,mask;
        begin /* Dedicated visual register bank decodes the accepted edge. */ end
    endtask
    task defer_show;
        input [5:0] target;input [7:0] after_state;input [1:0] effect,mask;
        begin begin /* transition is defined in canonical generated network */ end end
    endtask
    task practice_alarm_page;
        begin
            practice_handoff_pending<=0;
            practice_alarm<=1;practice_phase<=6;practice_progress<=0;
            practice_l_feedback<=0;practice_r_feedback<=0;
            replace_page(`SC_PACUALRM,PRACT_ALARM,EFFECT_DIRECT);
        end
    endtask
    task practice_failed;
        begin
            practice_progress<=0;practice_l_feedback<=0;practice_r_feedback<=0;
            release_prompt<=1;invalid_overlap<=0;
            if(practice_errors>=3)begin
                practice_errors<=4;practice_error_bank[practice_step]<=4;practice_alarm_page;
            end else begin
                practice_errors<=practice_errors+1'b1;practice_phase<=5;
                practice_error_bank[practice_step]<=practice_errors+1'b1;
                arm_visual(2'd2,{r_event_sync||r_press_raw||practice_r_feedback,l_event_sync||l_press_raw||practice_l_feedback});
                begin /* transition is defined in canonical generated network */ end 
            end
        end
    endtask
    task practice_succeeded;
        begin
            practice_passed[practice_step]<=1;
            accept_interaction(practice_r_feedback);
            arm_visual(2'd1,{practice_r_feedback,practice_l_feedback});
            practice_phase<=4;release_prompt<=0;begin /* transition is defined in canonical generated network */ end 
        end
    endtask
    task suspend_ward;
        begin alarm_active<=1; show(`SC_RESULTS,PAUSE,EFFECT_DIRECT); end
    endtask
    task finish_choice;
        input answer_right;
        begin
            accept_interaction(answer_right);
            if (question<2 && answer_right==choice_correct_right(question)) t1_correct<=t1_correct+1'b1;
            if (question>=2 && question<4 && answer_right==choice_correct_right(question)) t2_correct<=t2_correct+1'b1;
            retry<=0;
            case(question)
                0:begin question<=1; defer_show(`SC_T1Q2,CHOICE_RELEASE,EFFECT_FADE,{answer_right,!answer_right}); end
                1:begin result_valid[0]<=1; question<=2; defer_show(`SC_T2NUM,CHOICE_RELEASE,EFFECT_FADE,{answer_right,!answer_right}); end
                2:begin question<=3; defer_show(`SC_T2SAME,CHOICE_RELEASE,EFFECT_FADE,{answer_right,!answer_right}); end
                3:begin result_valid[1]<=1; question<=4; defer_show(`SC_T3LISTEN,CHOICE_RELEASE,EFFECT_FADE,{answer_right,!answer_right}); end
                default:begin t3_result<=retry ? 2:1; result_valid[2]<=1; defer_show(`SC_T4WAIT,T4_PREP_END,EFFECT_FADE,{answer_right,!answer_right}); end
            endcase
        end
    endtask
    function [5:0] limb_scene;
        input [1:0] index;
        begin case(index)
            0:limb_scene=`SC_PACULARM;1:limb_scene=`SC_PACURARM;
            2:limb_scene=`SC_PACULLEG;default:limb_scene=`SC_PACURLEG;
        endcase end
    endfunction
    function [1:0] activity_score;
        input [3:0] count;
        begin activity_score=(count==4) ? 2:((count>=2) ? 1:0);end
    endfunction

    // A case(state) branch already proves its current state. Qualify captured
    // events against that branch's CONSTANT source code, instead of first
    // comparing two variable state buses and feeding that result through a
    // context mux followed by the same FSM decode. This preserves every
    // source-state/generation rejection and captured-vs-live level choice.
    // These local helpers are evaluated only in case(source). Captured state
    // and tags copy unconditionally each clock. A window-generation change
    // also changes state, except PAGE/report PRESENTED (kept explicitly).
    // Every hold-generation change also changes state. Thus a same-source
    // local event already proves the corresponding tag; generic/report paths
    // retain their independent tag checks. No timestamp or event clock moves.
    function local_l_press;
        input [7:0] source;
        begin local_l_press=l_press_q && (|(press_state_hot_q & encode_state(source))) &&
            (source!=PAGE || press_window_tag_q==window_generation);end
    endfunction
    function local_r_press;
        input [7:0] source;
        begin local_r_press=r_press_q && (|(press_state_hot_q & encode_state(source))) &&
            (source!=PAGE || press_window_tag_q==window_generation);end
    endfunction
    // The hot state and both numeric event identities are captured on the
    // same edge, unconditionally, in the original event capture process.
    // Reuse that hot snapshot for release ownership instead of re-decoding
    // the eight-bit numeric copy. No event/timestamp clock edge is changed.
    function local_l_release;
        input [7:0] source;
        begin local_l_release=l_release_q && (|(press_state_hot_q & encode_state(source)));end
    endfunction
    function local_r_release;
        input [7:0] source;
        begin local_r_release=r_release_q && (|(press_state_hot_q & encode_state(source)));end
    endfunction
    function local_l_sync;
        input [7:0] source;
        begin
            if(local_l_press(source)||local_r_press(source))local_l_sync=press_l_sync_q;
            else if(local_l_release(source)||local_r_release(source))local_l_sync=release_l_sync_q;
            else local_l_sync=l_sync_down;
        end
    endfunction
    function local_r_sync;
        input [7:0] source;
        begin
            if(local_l_press(source)||local_r_press(source))local_r_sync=press_r_sync_q;
            else if(local_l_release(source)||local_r_release(source))local_r_sync=release_r_sync_q;
            else local_r_sync=r_sync_down;
        end
    endfunction
    function local_r_down;
        input [7:0] source;
        begin local_r_down=(local_l_release(source)||local_r_release(source)) ? release_r_down_q:r_down;end
    endfunction
    function local_invalid;
        input [7:0] source;
        begin local_invalid=(local_l_press(source)||local_r_press(source)) ? press_invalid_q:invalid_overlap;end
    endfunction
    function local_both;
        input [7:0] source;
        begin local_both=local_l_sync(source)&&local_r_sync(source);end
    endfunction

    
    // One shared, registered launch pulse isolates patient-key qualification
    // from all countdown reset enables. Both FSM and timer retire it on the
    // same edge; OFF/error still have priority and no old pulse is reused.
    always @(posedge clk or posedge rst) begin
        if(rst) rest_new_round<=0;
        else rest_new_round<=patient_eligible && state_hot[29] &&
            press_state_hot_q[29] && press_window_tag_q==window_generation &&
            ((l_press_q && !press_r_sync_q) || (r_press_q && !press_l_sync_q));
    end
    
    // This divider starts on the actual first education presentation. Neither
    // a page change nor KEY2 resets it. All division/modulo above is constant
    // elaboration arithmetic; the running countdown has only counters.
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            education_countdown_active<=0;retest_due<=0;retest_seconds<=0;
            retest_prescaler<=0;retest_ms_left<=0;retest_second_ms_left<=0;
        end else if(RETEST_INTERVAL_MS==0 || active_mode!=2 || !sw2_on || media_error || state_hot[34] || (rest_new_round && !patient_inhibit)) begin
            education_countdown_active<=0;retest_due<=0;retest_seconds<=0;
            retest_prescaler<=0;retest_ms_left<=0;retest_second_ms_left<=0;
        end else if(education_first_presented && !education_countdown_active && !retest_due) begin
            education_countdown_active<=1;retest_due<=0;
            retest_seconds<=RETEST_INITIAL_SECONDS>65535 ? 16'hffff:RETEST_INITIAL_SECONDS;
            retest_prescaler<=0;retest_ms_left<=RETEST_INTERVAL_MS;
            retest_second_ms_left<=RETEST_FIRST_SECOND_MS;
        end else if(education_countdown_active) begin
            if(retest_prescaler==CYCLES_PER_MS-1) begin
                retest_prescaler<=0;
                if(retest_ms_left==1) begin
                    education_countdown_active<=0;retest_due<=1;retest_seconds<=0;
                    retest_ms_left<=0;retest_second_ms_left<=0;
                end else begin
                    retest_ms_left<=retest_ms_left-1'b1;
                    if(retest_second_ms_left==1) begin
                        retest_second_ms_left<=1000;
                        // Saturate display without shortening the real timer.
                        if(retest_ms_left<=65535000 && retest_seconds!=0) retest_seconds<=retest_seconds-1'b1;
                    end else retest_second_ms_left<=retest_second_ms_left-1'b1;
                end
            end else retest_prescaler<=retest_prescaler+1'b1;
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) report_input_armed<=0;
        else if(!report_visible || !patient_eligible) report_input_armed<=0;
        else if(released) report_input_armed<=1;
    end
    always @(posedge clk or posedge rst) begin
        if(rst) skip_navigation_armed<=0;
        else if((!state_hot[2] && !state_hot[27]) || !media_accepted || !page_seen || !patient_eligible)
            skip_navigation_armed<=0;
        else if(released) skip_navigation_armed<=1;
        else if(both_raw) skip_navigation_armed<=0;
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            window_timeout_tag<=0;barrier_timeout_tag<=0;hold_timeout_tag<=0;
            page_timeout_tag<=0;practice_feedback_timeout_tag<=0;practice_feedback_expired_q<=0;
            practice_quiet_expired_q<=0;response_expired_qualified_q<=0;response_expired_state_q<=BOOT;visual_expired_q<=0;feedback_timeout_q<=0;
            visual_age_q<=0;visual_age_seq_q<=0;visual_age_seen_q<=0;release_watchdog_q<=0;
            response_expired_q<=0;response_deadline_q<=0;pain_retry_expired_q<=0;
            barrier_expired_q<=0;hold_expired_q<=0;hold_target_q<=0;
            results_expired_q<=0;education_expired_q<=0;
        end else begin
            window_timeout_tag<=window_generation;
            barrier_timeout_tag<=barrier_generation;
            hold_timeout_tag<=hold_generation;
            page_timeout_tag<=page_generation;
            practice_feedback_timeout_tag<=practice_feedback_generation;
            practice_quiet_expired_q<=state_hot[35] && practice_audio_quiet &&
                time_cycles-practice_quiet_start>=PRACTICE_AUDIO_GUARD_CYCLES;
            response_expired_qualified_q<=response_expired_q && window_flags_valid;
            response_expired_state_q<=state;
            practice_feedback_expired_q<=time_cycles-practice_feedback_start>=PRACTICE_FEEDBACK_CYCLES;
            visual_age_q<=time_cycles-(feedback_seen?visual_visible_start:visual_request_start);
            visual_age_seq_q<=feedback_seq;visual_age_seen_q<=feedback_seen;
            visual_expired_q<=feedback_seen&&visual_age_seen_q&&visual_age_seq_q==feedback_seq&&
                feedback_kind!=0&&visual_age_q>=visual_duration;
            feedback_timeout_q<=feedback_kind!=0&&!feedback_seen&&visual_age_seq_q==feedback_seq&&
                visual_age_q>=CYCLES_PER_MS*FEEDBACK_CONFIRM_TIMEOUT_MS;
            response_expired_q<=response_expired_now;
            response_deadline_q<=elapsed>=RESPONSE_CYCLES;
            pain_retry_expired_q<=elapsed>=RESPONSE_CYCLES+HOLD_MAX_CYCLES+CONFIRM_TAIL;
            barrier_expired_q<=time_cycles-barrier_start>=RESPONSE_CYCLES;
            release_watchdog_q<=time_cycles-barrier_start>=CYCLES_PER_MS*PRACTICE_RELEASE_MS;
            hold_expired_q<=hold_expired_now;
            hold_target_q<=held>=HOLD_TARGET_CYCLES;
            results_expired_q<=elapsed>=RESULTS_CYCLES;
            // Qualify at the existing timeout register, before PAGE state selection.
            // Only an actually presented education page owns this deadline.
            education_expired_q<=scene_education && page_seen &&
                time_cycles-page_start>=EDU_CYCLES;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            begin /* transition is defined in canonical generated network */ end  active_mode<=0; last_report_mode<=0; mode_rearmed<=0; time_cycles<=0;
            report_outcome<=0;report_started<=0;report_generated<=0;report_round_saved<=0;
            startup_qualifier<=0;retest_dispatched<=0;
            question_set<=0;practice_active<=0;practice_pacu<=0;practice_finished<=0;
            practice_handoff_pending<=0;practice_handoff_scene<=0;
            practice_initialized<=0;practice_step<=0;practice_phase<=0;practice_errors<=0;
            practice_progress<=0;practice_l_feedback<=0;practice_r_feedback<=0;practice_alarm<=0;
            practice_passed<=0;accepted_seq<=0;accepted_valid<=0;
            education_voice_seen<=0;
            page_skip_used<=0;
            accepted_identity<=0;accepted_l<=0;accepted_r<=0;media_wipe_direction<=0;
            for(practice_bank_index=0;practice_bank_index<6;practice_bank_index=practice_bank_index+1)
                practice_error_bank[practice_bank_index]<=0;
            practice_quiet_start<=0;practice_feedback_start<=0;practice_feedback_generation<=0;
            
            
            practice_return_scene<=0;last_education_scene<=`SC_EDUMOVE;
            media_cmd_valid<=0; media_scene<=`SC_WELCOME; media_cancel<=0;media_skip_request<=0;media_effect<=EFFECT_DIRECT;
            scene_welcome<=1;scene_go<=0;scene_wait<=0;scene_hold<=0;scene_pain<=0;
            scene_learning<=0;scene_learning_advance<=1;scene_education<=0;scene_report<=0;
            media_accepted<=0; resume_state<=WELCOME;resume_hot<=encode_state(WELCOME);
            queued_scene<=0; queued_resume<=0;queued_effect<=EFFECT_DIRECT; page_start<=0;
            alarm_active<=0; fault_code<=0; pacu_p<=0; pacu_a<=0; pacu_valid<=0;
            nurse_enabled<=0;limb_index<=0;limb_count<=0;limb_answers<=0;limb_valid<=0;
            t1_correct<=0; t2_correct<=0; t3_result<=0; t1_unanswered<=0; t2_unanswered<=0;
            rt_ms<=0; rt_cycles<=0; rt_status<=0; hold_ms<=0; hold_status<=0;
            pain<=0; result_valid<=0; retry<=0; question<=0; pain_right<=0;
            invalid_overlap<=0; release_prompt<=0;
            convert_start<=0;convert_hold<=0;convert_seen_busy<=0;convert_cycles<=0;pending_hold_status<=0;
            window_start<=0; barrier_start<=0; hold_start_cycles<=0;
            window_generation<=0;barrier_generation<=0;hold_generation<=0;
            page_generation<=0;
        end else begin
                report_generated<=0;
            if(practice_handoff_pending&&media_accepted&&media_presented&&
               media_scene==practice_handoff_scene)begin
                practice_active<=0;
                if(practice_handoff_scene==`SC_READY||practice_handoff_scene==`SC_PACUCALL)practice_finished<=1;
                practice_l_feedback<=0;practice_r_feedback<=0;
                practice_handoff_pending<=0;
            end
            
            // An ordinary DONE is the real final voice-frame event. Once
            // SKIP has ever been enabled during this transaction, only the
            // explicit true-voice status may prove its narration complete.
            if((media_cmd_valid||media_accepted)&&skip_audio_wait)page_skip_used<=1;
            // A press accepted on its down edge may remain visible while the
            // next image loads. Once that physical key is released, its lamp
            // cannot be re-lit by an unarmed later press of the same key.
            if(!l_down || !patient_eligible || both_raw || media_cancel ||
                active_mode==0 || state_hot[34] || state_hot[33])accepted_l<=0;
            if(!r_down || !patient_eligible || both_raw || media_cancel ||
                active_mode==0 || state_hot[34] || state_hot[33])accepted_r<=0;
            // Pauses caused by unanswered input/release faults may display an
            // alarm rather than a report. Preserve their partial round once.
            if((state_hot[33] || state_hot[34]) && active_mode!=0) save_round_report;
            time_cycles<=time_cycles+1'b1;media_skip_request<=0;
            if(startup_qualifier<DEBOUNCE_CYCLES+4)startup_qualifier<=startup_qualifier+1'b1; media_cancel<=0;convert_start<=0;
            if (media_cmd_valid && media_cmd_ready) begin
                media_cmd_valid<=0; media_accepted<=1;
            end
            // Current mode switch OFF is highest priority. Completed records stay.
            if ((active_mode[0] && !sw1_on) || (active_mode[1] && !sw2_on)) begin
                save_round_report;
                if (report_outcome==1 && !report_round_saved && |report_started &&
                    ((active_mode[0] && !(&pacu_valid)) ||
                     (active_mode[1] && !(&result_valid)))) report_outcome<=4;
                if (active_mode[1]) begin
                    if (!result_valid[3] && (state_hot[15] || state_hot[16] ||
                        ((state_hot[30] || state_hot[31]) && !convert_hold) ||
                        (state_hot[2] && (scene_wait || scene_go)))) rt_status<=6;
                    if (!result_valid[4] && (state_hot[17] || state_hot[18] || state_hot[19] || state_hot[32] ||
                        ((state_hot[30] || state_hot[31]) && convert_hold))) hold_status<=6;
                    if (!result_valid[5] && (state_hot[20] || state_hot[21] || state_hot[22] || state_hot[23])) pain<=7;
                end
                active_mode<=0; mode_rearmed<=0; alarm_active<=0; nurse_enabled<=0;retest_dispatched<=0;
                accepted_valid<=0;
                practice_active<=0;practice_finished<=0;practice_initialized<=0;practice_alarm<=0;practice_handoff_pending<=0;
                replace_page(`SC_WELCOME,WELCOME,EFFECT_DIRECT);
            end else if ((media_error||feedback_timeout_q||state_encoding_fault) && !state_hot[34]) begin
                save_round_report;
                report_outcome<=3;
                fault_code<=4; alarm_active<=1; media_cancel<=1;retest_dispatched<=0;
                practice_active<=0;practice_finished<=0;practice_initialized<=0;practice_alarm<=0;practice_handoff_pending<=0;
                accepted_valid<=0;
                media_cmd_valid<=0; media_accepted<=0; begin /* transition is defined in canonical generated network */ end  release_prompt<=0;
                if (!result_valid[3] && (state_hot[16] || state_hot[15] ||
                    ((state_hot[30] || state_hot[31]) && !convert_hold) ||
                    (state_hot[2] && (scene_wait || scene_go)))) rt_status<=5;
                if (!result_valid[4] && (state_hot[17] || state_hot[18] || state_hot[19] || state_hot[32] ||
                    ((state_hot[30] || state_hot[31]) && convert_hold) ||
                    (state_hot[2] && scene_hold))) hold_status<=5;
                if (!result_valid[5] && (state_hot[20] || state_hot[21] || state_hot[22] ||
                    (state_hot[2] && scene_pain))) pain<=6;
            end else if (active_mode[1] && retest_due && !retest_dispatched && !state_hot[34]) begin
                // Replace even an in-flight KEY2 cancellation with the due
                // reminder. Send one cancel, then let the media path drain.
                retest_dispatched<=1;replace_page(`SC_REST,REST_RELEASE,EFFECT_WIPE);
            end else if (report_advance) begin
                replace_page(`SC_EDUMOVE,EDU_END,(!patient_inhibit && report_manual_advance_q) ? EFFECT_FADE:EFFECT_WIPE);
            end else if (active_mode==0 && mode_rearmed && sw1_on && !sw2_on && !state_hot[3]) begin
                active_mode<=1; last_report_mode<=1; fault_code<=0; alarm_active<=0; pacu_valid<=0;
                report_outcome<=1;report_started<=0;
                report_round_saved<=0;
                pacu_p<=0;pacu_a<=0;limb_index<=0;limb_count<=0;limb_answers<=0;limb_valid<=0;nurse_enabled<=0;retry<=0;
                question_set<=0;practice_initialized<=0;practice_finished<=0;practice_active<=0;practice_alarm<=0;
                practice_passed<=0;accepted_valid<=0;
                education_voice_seen<=0;
                for(practice_bank_index=0;practice_bank_index<6;practice_bank_index=practice_bank_index+1)
                    practice_error_bank[practice_bank_index]<=0;
                replace_page(`SC_PACUGUID,P_GUID_END,EFFECT_FADE);
            end else if (active_mode==0 && mode_rearmed && sw2_on && !sw1_on && !state_hot[3]) begin
                active_mode<=2; last_report_mode<=2; fault_code<=0; alarm_active<=0; clear_ward;
                question_set<=0;practice_initialized<=0;practice_finished<=0;practice_active<=0;practice_alarm<=0;
                practice_passed<=0;accepted_valid<=0;
                education_voice_seen<=0;
                for(practice_bank_index=0;practice_bank_index<6;practice_bank_index=practice_bank_index+1)
                    practice_error_bank[practice_bank_index]<=0;
                replace_page(`SC_LEARNKEY,LEARN_END,EFFECT_FADE);
            end else if(history_exit===1'b1 && active_mode==0 && !sw1 && !sw2) begin
                // Top supplies already-qualified switches. Use their current
                // values here: the local filters may still hold history's
                // forced OFF levels when one switch remains on at exit.
                // Re-enter the normal command/ACK/presentation/done path even
                // if history cancelled an unfinished welcome or review page.
                replace_page(`SC_WELCOME,WELCOME,EFFECT_DIRECT);
            end else begin
                if (active_mode==0 && startup_qualifier>=DEBOUNCE_CYCLES+4 && !sw1_on && !sw2_on) mode_rearmed<=1;
                if (active_mode==0 && sw1_on && sw2_on) fault_code<=1;
                case(1'b1) // synthesis parallel_case
                state_hot[0]:show(`SC_WELCOME,WELCOME,EFFECT_DIRECT);
                state_hot[1]:begin
                    // Nurse review after OFF: no restart, no score clearing.
                    if(b_release && last_report_mode!=0 && !scene_welcome && !clear_hold_consumed && !welcome_clear_complete_now) begin
                        if(scene_welcome)
                            show(last_report_mode==1 ? `SC_PACURSLT:`SC_RESULTS,WELCOME,EFFECT_FADE);
                        else show(`SC_WELCOME,WELCOME,EFFECT_FADE);
                    end
                end
                state_hot[3]:begin
                    if(active_mode[1]&&queued_scene>=`SC_EDUMOVE&&queued_scene<=`SC_EDUFOOD&&b_release)begin
                        queued_scene<=`SC_RELAX;queued_resume<=RELAX_ACTIVE;queued_effect<=EFFECT_DIRECT;
                        if(media_cmd_ready)show(`SC_RELAX,RELAX_ACTIVE,EFFECT_DIRECT);
                    end else if(active_mode[1]&&queued_scene>=`SC_EDUMOVE&&queued_scene<=`SC_EDUFOOD&&patient_eligible&&
                        ((local_r_press(CANCEL_WAIT)&&!local_l_sync(CANCEL_WAIT))||(local_l_press(CANCEL_WAIT)&&!local_r_sync(CANCEL_WAIT))))begin
                        queued_scene<=local_r_press(CANCEL_WAIT)?previous_scene(queued_scene):next_scene(queued_scene);queued_effect<=EFFECT_DIRECT;
                        if(media_cmd_ready)show(local_r_press(CANCEL_WAIT)?previous_scene(queued_scene):next_scene(queued_scene),EDU_END,EFFECT_DIRECT);
                    end else if(active_mode[1]&&b_release&&queued_scene>=`SC_LEARNKEY&&queued_scene<=`SC_READY)begin
                        queued_scene<=previous_scene(queued_scene);queued_effect<=EFFECT_FADE;
                        if(media_cmd_ready)show(previous_scene(queued_scene),queued_resume,EFFECT_FADE);
                    end else if(media_cmd_ready)show(queued_scene,queued_resume,queued_effect);
                end
                state_hot[2]:begin
                    if (media_accepted && media_presented) begin
                        page_start<=time_cycles;page_generation<=~page_generation;
                        if(scene_report && resume_state==RESULTS_END) begin
                            window_start<=time_cycles;window_generation<=~window_generation;
                        end
                    end
                    if (media_accepted && scene_go && media_presented) begin
                        window_start<=time_cycles;window_generation<=~window_generation; begin /* transition is defined in canonical generated network */ end 
                        // Onset validity retires next cycle; timer starts this cycle.
                    end else if (media_accepted && education_page_complete && !scene_go) begin
                        if(scene_education && media_scene_done && !page_skip_used && !skip_audio_wait)begin
                            case(media_scene)
                                `SC_EDUMOVE:education_voice_seen[0]<=1;
                                `SC_EDUPAIN:education_voice_seen[1]<=1;
                                `SC_EDUNAUS:education_voice_seen[2]<=1;
                                `SC_EDUFOOD:education_voice_seen[3]<=1;
                                default:begin end
                            endcase
                        end
                        begin /* transition is defined in canonical generated network */ end  barrier_start<=time_cycles;barrier_generation<=~barrier_generation;
                    end
                    // Return is a new scene transaction, never an independent audio advance.
                    if (active_mode==0 && skip_audio_wait && b_release && last_report_mode!=0 && !scene_welcome && !clear_hold_consumed &&
                        media_accepted && page_seen) begin
                        // Welcome/review keeps KEY2's established toggle even
                        // when its narration has not reached WELCOME yet.
                        replace_page(scene_welcome ? (last_report_mode==1 ? `SC_PACURSLT:`SC_RESULTS):`SC_WELCOME,WELCOME,EFFECT_FADE);
                    end else if (active_mode[1] && b_release) begin
                        // KEY2 may arrive in the first PAGE cycle, before the
                        // navigation stage retires. Decode only its payload;
                        // the state decision uses the same-transaction flags.
                        if (scene_learning) replace_page(previous_scene(media_scene),LEARN_END,EFFECT_FADE);
                        else if (scene_education) replace_page(`SC_RELAX,RELAX_ACTIVE,EFFECT_DIRECT);
                    end else if(active_mode[1]&&scene_education&&media_accepted&&page_seen&&skip_navigation_armed&&patient_eligible&&
                        ((local_r_press(PAGE)&&!local_l_sync(PAGE))||(local_l_press(PAGE)&&!local_r_sync(PAGE))))begin
                        replace_page(local_r_press(PAGE)?scene_previous:scene_next,EDU_END,EFFECT_DIRECT);
                    end else if(skip_audio_wait && media_accepted &&
                        page_seen && skip_navigation_armed &&
                        patient_eligible &&
                        ((local_l_press(PAGE) && !local_r_sync(PAGE)) ||
                         (local_r_press(PAGE) && !local_l_sync(PAGE)))) begin
                        if(active_mode[1] && (scene_education || (scene_learning_advance && PRACTICE_ENABLE==0))) begin
                            // Optional manual advance preserves ordinary
                            // narrated teaching and the independent countdown.
                            replace_page(scene_next,scene_learning ? LEARN_END:EDU_END,EFFECT_FADE);
                        end else if(!scene_go && !scene_wait) begin
                            // Finish only the media barrier. Its original
                            // resume state retains each page's key semantics:
                            // guide -> call, welcome/review -> welcome, alarm ->
                            // pause, PACU report -> report. T4 WAIT/GO keep the
                            // full-preload and actual-presentation contracts.
                            media_skip_request<=1;
                        end
                    end
                end
                state_hot[4]:begin
                    retry<=0;
                    if(PRACTICE_ENABLE!=0 && !practice_finished)start_practice(1'b1);
                    else show_teaching(`SC_PACUCALL,P_CALL_RELEASE);
                end
                state_hot[5]:begin
                    release_prompt<=!released;
                    if (released) begin window_start<=time_cycles;window_generation<=~window_generation; begin /* transition is defined in canonical generated network */ end  release_prompt<=0; end
                    else if (barrier_expired) begin fault_code<=2;report_outcome<=3; alarm_active<=1; begin /* transition is defined in canonical generated network */ end  end
                end
                state_hot[6]:begin
                    if (patient_eligible && local_both(P_CALL)) invalid_overlap<=1;
                    if (released) invalid_overlap<=0;
                    if (!patient_inhibit && !local_invalid(P_CALL) && !local_both(P_CALL) && ((local_l_press(P_CALL) && l_inside && !local_r_sync(P_CALL)) || (local_r_press(P_CALL) && r_inside && !local_l_sync(P_CALL)))) begin
                        accept_interaction(local_r_press(P_CALL));
                        pacu_p<=retry ? 1:2;pacu_valid[0]<=1;retry<=0;limb_index<=0;
                        defer_show(`SC_PACULARM,P_LIMB_RELEASE,EFFECT_FADE,{local_r_press(P_CALL),!local_r_press(P_CALL)});
                    end else if (expired) begin
                        if (!retry) begin retry<=1; show(`SC_PACUREP,P_CALL_RELEASE,EFFECT_WIPE); end
                        else begin pacu_p<=0; pacu_valid[0]<=1;report_outcome<=2; alarm_active<=1; show(`SC_PACUALRM,PAUSE,EFFECT_DIRECT); end
                    end
                end
                state_hot[7]:begin
                    release_prompt<=!released;
                    if(released)begin window_start<=time_cycles;window_generation<=~window_generation;begin /* transition is defined in canonical generated network */ end invalid_overlap<=0;release_prompt<=0;end
                    else if(barrier_expired)begin fault_code<=2;report_outcome<=3;alarm_active<=1;show(`SC_PACUALRM,PAUSE,EFFECT_DIRECT);end
                end
                state_hot[8]:begin
                    if(patient_eligible && local_both(P_LIMB))invalid_overlap<=1;
                    if(released)invalid_overlap<=0;
                    if(!patient_inhibit&&!local_invalid(P_LIMB)&&!local_both(P_LIMB)&&((local_l_press(P_LIMB)&&l_inside&&!local_r_sync(P_LIMB))||(local_r_press(P_LIMB)&&r_inside&&!local_l_sync(P_LIMB))))begin
                        accept_interaction(local_r_press(P_LIMB));
                        // Patient self-report: L yes, R no, four independent limbs.
                        limb_answers[limb_index]<=local_l_press(P_LIMB);limb_valid[limb_index]<=1;
                        if(local_l_press(P_LIMB))limb_count<=limb_count+1'b1;
                        retry<=0;
                        if(limb_index==3)begin
                            pacu_a<=activity_score({1'b0,limb_count}+(local_l_press(P_LIMB) ? 4'd1:4'd0));
                            pacu_valid[1]<=1;defer_show(`SC_PACURSLT,P_RESULTS,EFFECT_FADE,{local_r_press(P_LIMB),!local_r_press(P_LIMB)});
                        end else begin limb_index<=limb_index+1'b1;defer_show(limb_scene(limb_index+1'b1),P_LIMB_RELEASE,EFFECT_FADE,{local_r_press(P_LIMB),!local_r_press(P_LIMB)});end
                    end else if(expired)begin
                        if(!retry)begin retry<=1;show(limb_scene(limb_index),P_LIMB_RELEASE,EFFECT_WIPE);end
                        else begin report_outcome<=2;alarm_active<=1;show(`SC_PACUALRM,PAUSE,EFFECT_DIRECT);end
                    end
                end
                state_hot[9]:begin end
                state_hot[10]:begin
                    if(PRACTICE_ENABLE!=0 &&
                        ((media_scene==`SC_LEARNKEY && !practice_passed[1]) ||
                         (media_scene==`SC_LEARNHLD && !practice_passed[2]) ||
                         (media_scene==`SC_LEARNVIS && !practice_passed[4])))start_practice(1'b0);
                    else if (scene_learning_advance) show_teaching(scene_next,LEARN_END);
                    else begin begin /* transition is defined in canonical generated network */ end  barrier_start<=time_cycles;barrier_generation<=~barrier_generation; end
                end
                state_hot[11]:begin
                    if (b_release) replace_page(`SC_LEARNVIS,LEARN_END,EFFECT_FADE);
                    else if (released) begin begin /* transition is defined in canonical generated network */ end  window_start<=time_cycles;window_generation<=~window_generation; end
                end
                state_hot[12]:begin
                    if (b_release) replace_page(`SC_LEARNVIS,LEARN_END,EFFECT_FADE);
                    // The release barrier and source-state/generation tags
                    // establish freshness; this page waits without an age limit.
                    else if (!patient_inhibit && ((local_l_press(READY_INPUT) && !local_r_sync(READY_INPUT)) || (local_r_press(READY_INPUT) && !local_l_sync(READY_INPUT)))) begin
                        accept_interaction(local_r_press(READY_INPUT));
                        question<=0; retry<=0; show(`SC_T1Q1,CHOICE_RELEASE,EFFECT_FADE);
                    end
                end
                state_hot[13]:begin
                    release_prompt<=!released;
                    if (released) begin window_start<=time_cycles;window_generation<=~window_generation; invalid_overlap<=0; begin /* transition is defined in canonical generated network */ end  release_prompt<=0; end
                    else if (barrier_expired) begin fault_code<=2;report_outcome<=3; alarm_active<=1; begin /* transition is defined in canonical generated network */ end  end
                end
                state_hot[14]:begin
                    if (patient_eligible && local_both(CHOICE)) invalid_overlap<=1;
                    if (released) invalid_overlap<=0;
                    if (!patient_inhibit && !local_both(CHOICE) && !local_invalid(CHOICE) && local_l_press(CHOICE) && l_inside && !local_r_sync(CHOICE)) finish_choice(1'b0);
                    else if (!patient_inhibit && !local_both(CHOICE) && !local_invalid(CHOICE) && local_r_press(CHOICE) && r_inside && !local_l_sync(CHOICE)) finish_choice(1'b1);
                    else if (expired) begin
                        if (!retry) begin retry<=1; show(question_scene(question),CHOICE_RELEASE,EFFECT_WIPE); end
                        else begin
                            if (question<2) t1_unanswered<=t1_unanswered+1'b1;
                            else if (question<4) t2_unanswered<=t2_unanswered+1'b1;
                            else begin t3_result<=3; result_valid[2]<=1; end
                            report_outcome<=2;
                            alarm_active<=1; show(`SC_PACUALRM,PAUSE,EFFECT_DIRECT);
                        end
                    end
                end
                state_hot[15]:begin
                    if (released || !patient_eligible) show(`SC_T4GO,T4_INPUT,EFFECT_DIRECT);
                    else begin rt_status<=3; suspend_ward; end
                end
                state_hot[16]:begin
                    if (!patient_inhibit && go_check_pending_q && go_both_q) begin rt_status<=4; suspend_ward; end
                    else if (!patient_inhibit && go_check_pending_q && go_early_q) begin rt_status<=3; suspend_ward; end
                    else if (patient_eligible && (local_both(T4_INPUT) || (local_l_press(T4_INPUT) && local_r_sync(T4_INPUT)) || (local_r_press(T4_INPUT) && local_l_sync(T4_INPUT)))) begin rt_status<=4; suspend_ward; end
                    else if (!patient_inhibit && ((local_l_press(T4_INPUT) && $signed(l_delta_q)<0) || (local_r_press(T4_INPUT) && $signed(r_delta_q)<0))) begin rt_status<=3; suspend_ward; end
                    else if (!patient_inhibit && ((local_l_press(T4_INPUT) && l_inside) || (local_r_press(T4_INPUT) && r_inside))) begin
                        accept_interaction(local_r_press(T4_INPUT));
                        arm_visual(2'd1,{local_r_press(T4_INPUT),!local_r_press(T4_INPUT)});
                        
                        rt_cycles<=local_l_press(T4_INPUT) ? l_delta_q:r_delta_q;
                        convert_cycles<=local_l_press(T4_INPUT) ? l_delta_q:r_delta_q;
                        convert_hold<=0;convert_seen_busy<=0;begin /* transition is defined in canonical generated network */ end 
                    end else if (expired) begin rt_status<=2;report_outcome<=2; suspend_ward; end
                end
                state_hot[17]:begin
                    release_prompt<=!released;
                    if (released) begin window_start<=time_cycles;window_generation<=~window_generation; begin /* transition is defined in canonical generated network */ end  pain_right<=0; release_prompt<=0; end
                    else if (barrier_expired) begin hold_status<=4; suspend_ward; end
                end
                state_hot[18]:begin
                    if (patient_eligible && local_both(HOLD_START)) invalid_overlap<=1;
                    if (released) invalid_overlap<=0;
                    if (!patient_inhibit && local_l_press(HOLD_START) && l_inside && !local_r_sync(HOLD_START) && !local_invalid(HOLD_START)) begin
                        hold_start_cycles<=lp;hold_generation<=~hold_generation; begin /* transition is defined in canonical generated network */ end  pain_right<=0;
                    end else if (expired) begin hold_status<=3;report_outcome<=2; suspend_ward; end
                end
                state_hot[19]:begin
                    if (patient_inhibit) begin begin /* transition is defined in canonical generated network */ end release_prompt<=1;invalid_overlap<=0;end
                    else begin
                    if (hold_target_reached) release_prompt<=1;
                    if (local_r_sync(HOLD_ACTIVE) || local_r_down(HOLD_ACTIVE)) begin hold_status<=4; suspend_ward; end
                    else if (local_l_release(HOLD_ACTIVE)) begin
                        if (l_release_max_q) begin
                            accept_interaction(1'b0);
                            arm_visual(2'd1,2'b01);
                            
                            convert_cycles<=l_release_delta_q;
                            pending_hold_status<=l_release_complete_q ? (l_release_target_q ? 1:2):7;
                            convert_hold<=1;convert_seen_busy<=0;begin /* transition is defined in canonical generated network */ end 
                        end else begin hold_status<=4; suspend_ward; end
                    end else if (hold_expired) begin hold_status<=4; suspend_ward; end
                    end
                end
                state_hot[32]:begin
                    if (released && patient_eligible) begin
                        release_prompt<=0;
                        if (!response_deadline) begin /* transition is defined in canonical generated network */ end 
                        else begin hold_status<=4; suspend_ward; end
                    end else if (pain_retry_expired) begin hold_status<=4; suspend_ward; end
                end
                state_hot[20]:begin
                    release_prompt<=!released;
                    if (released) begin window_start<=time_cycles;window_generation<=~window_generation; begin /* transition is defined in canonical generated network */ end  release_prompt<=0; end
                    else if (barrier_expired) begin pain<=6; suspend_ward; end
                end
                state_hot[21]:begin
                    if (patient_eligible && (local_both(PAIN_START) || (local_l_press(PAIN_START) && local_r_sync(PAIN_START)) || (local_r_press(PAIN_START) && local_l_sync(PAIN_START)))) begin begin /* transition is defined in canonical generated network */ end  end
                    else if (!patient_inhibit && ((local_l_press(PAIN_START) && l_inside) || (local_r_press(PAIN_START) && r_inside))) begin
                        pain_right<=local_r_press(PAIN_START); hold_start_cycles<=local_r_press(PAIN_START) ? rp:lp;hold_generation<=~hold_generation; begin /* transition is defined in canonical generated network */ end 
                    end else if (expired) begin pain<=5;report_outcome<=2; suspend_ward; end
                end
                state_hot[22]:begin
                    if (patient_inhibit) begin begin /* transition is defined in canonical generated network */ end release_prompt<=1;invalid_overlap<=0;end
                    else begin
                    if (hold_target_reached) release_prompt<=1;
                    if ((!pain_right && local_r_sync(PAIN_ACTIVE)) || (pain_right && local_l_sync(PAIN_ACTIVE))) begin begin /* transition is defined in canonical generated network */ end  release_prompt<=1; end
                    else if ((!pain_right && local_l_release(PAIN_ACTIVE)) || (pain_right && local_r_release(PAIN_ACTIVE))) begin
                        if (pain_right ? r_release_max_q:l_release_max_q) begin
                            accept_interaction(pain_right);
                            if (pain_right) pain<=(r_release_target_q ? 4:2);
                            else pain<=(l_release_target_q ? 3:1);
                            result_valid[5]<=1; defer_show(`SC_RESULTS,RESULTS_END,EFFECT_FADE,{pain_right,!pain_right});
                        end else begin pain<=6; suspend_ward; end
                    end else if (hold_expired) begin pain<=6; suspend_ward; end
                    end
                end
                state_hot[23]:begin
                    if (released && patient_eligible) begin
                        release_prompt<=0;
                        if (!response_deadline) begin /* transition is defined in canonical generated network */ end 
                        else begin pain<=6; suspend_ward; end
                    end else if (pain_retry_expired) begin pain<=6; suspend_ward; end
                end
                state_hot[24]:begin begin /* transition is defined in canonical generated network */ end  barrier_start<=time_cycles;barrier_generation<=~barrier_generation; end
                state_hot[25]:begin
                    if (released) invalid_overlap<=0;
                end
                state_hot[26]:begin
                    if (!page_seen) begin fault_code<=3;report_outcome<=3; begin /* transition is defined in canonical generated network */ end  alarm_active<=1; end
                    else begin /* transition is defined in canonical generated network */ end 
                end
                state_hot[27]:begin
                    if(media_voice_complete===1'b1)begin
                        case(media_scene)
                            `SC_EDUMOVE:education_voice_seen[0]<=1;
                            `SC_EDUPAIN:education_voice_seen[1]<=1;
                            `SC_EDUNAUS:education_voice_seen[2]<=1;
                            `SC_EDUFOOD:education_voice_seen[3]<=1;
                            default:begin end
                        endcase
                    end
                    if (b_release) replace_page(`SC_RELAX,RELAX_ACTIVE,EFFECT_DIRECT);
                    else if (skip_navigation_armed && patient_eligible &&
                        ((local_r_press(EDU_ACTIVE) && !local_l_sync(EDU_ACTIVE)) ||
                         (local_l_press(EDU_ACTIVE) && !local_r_sync(EDU_ACTIVE))))
                        replace_page(local_r_press(EDU_ACTIVE)?scene_previous:scene_next,EDU_END,EFFECT_DIRECT);
                    else if (education_expired)replace_page(scene_next,EDU_END,EFFECT_WIPE);
                end
                state_hot[43]:begin
                    if(b_release)replace_page(last_education_scene,EDU_END,EFFECT_DIRECT);
                end
                state_hot[28]:if (released) begin begin /* transition is defined in canonical generated network */ end  window_start<=time_cycles;window_generation<=~window_generation; end
                state_hot[29]:begin
                    if (rest_new_round && !patient_inhibit) begin
                        question_set<=question_set==2 ? 0:question_set+1'b1;
                        clear_ward; show(`SC_T1Q1,CHOICE_RELEASE,EFFECT_FADE);
                    end
                end
                state_hot[35]:begin
                    // The top supplies quiet only after a matching media-IDLE
                    // status. Keep original teaching visible until it settles.
                    if(!practice_audio_quiet)practice_quiet_start<=time_cycles;
                    else if(practice_quiet_expired_q)begin
                        practice_active<=1;
                        if(practice_alarm)begin practice_phase<=6;practice_alarm_page;end
                        else begin practice_phase<=0;begin /* transition is defined in canonical generated network */ end barrier_start<=time_cycles;barrier_generation<=~barrier_generation;end
                    end
                end
                state_hot[36]:begin
                    practice_progress<=0;practice_l_feedback<=0;practice_r_feedback<=0;
                    release_prompt<=!released;
                    if(!practice_pacu && b_release)begin
                        practice_active<=0;practice_handoff_pending<=0;replace_page(media_scene,LEARN_END,EFFECT_FADE);
                    end else if(release_watchdog)practice_alarm_page;
                    else if(released && patient_eligible)begin
                        practice_phase<=1;release_prompt<=0;invalid_overlap<=0;
                        window_start<=time_cycles;window_generation<=~window_generation;begin /* transition is defined in canonical generated network */ end 
                    end
                end
                state_hot[37]:begin
                    if(!practice_pacu && b_release)begin
                        practice_active<=0;practice_handoff_pending<=0;replace_page(media_scene,LEARN_END,EFFECT_FADE);
                    end else if(!patient_eligible)begin
                        practice_phase<=0;begin /* transition is defined in canonical generated network */ end barrier_start<=time_cycles;barrier_generation<=~barrier_generation;release_prompt<=1;
                    end else if(!practice_pacu&&practice_step==4)begin
                        if(cue_pass)begin
                            practice_succeeded;accept_interaction(cue_right);
                            practice_l_feedback<=!cue_right;practice_r_feedback<=cue_right;
                        end else if(cue_fail||expired)practice_failed;
                    end else if(local_both(PRACT_PRESS) || local_invalid(PRACT_PRESS))practice_failed;
                    else if(local_l_press(PRACT_PRESS) || local_r_press(PRACT_PRESS))begin
                        if((local_l_press(PRACT_PRESS)&&!l_inside) || (local_r_press(PRACT_PRESS)&&!r_inside))practice_failed;
                        else if((practice_step==0 || practice_step==2) && local_r_press(PRACT_PRESS))practice_failed;
                        else if(practice_step==1 && local_l_press(PRACT_PRESS))practice_failed;
                        else begin
                            practice_l_feedback<=local_l_press(PRACT_PRESS);
                            practice_r_feedback<=local_r_press(PRACT_PRESS);
                            pain_right<=local_r_press(PRACT_PRESS);
                            hold_start_cycles<=local_l_press(PRACT_PRESS) ? lp:rp;
                            hold_generation<=~hold_generation;practice_progress<=0;
                            practice_phase<=2;begin /* transition is defined in canonical generated network */ end 
                        end
                    end else if(expired)practice_failed;
                end

                state_hot[38]:begin
                    if(!practice_pacu && b_release)begin
                        practice_active<=0;practice_handoff_pending<=0;replace_page(media_scene,LEARN_END,EFFECT_FADE);
                    end else if(!patient_eligible)begin
                        practice_progress<=0;practice_l_feedback<=0;practice_r_feedback<=0;
                        practice_phase<=0;begin /* transition is defined in canonical generated network */ end barrier_start<=time_cycles;barrier_generation<=~barrier_generation;release_prompt<=1;
                    end else if((practice_l_feedback && local_r_sync(PRACT_HELD)) ||
                                (practice_r_feedback && local_l_sync(PRACT_HELD)))practice_failed;
                    else if((practice_l_feedback && local_l_release(PRACT_HELD)) ||
                            (practice_r_feedback && local_r_release(PRACT_HELD)))begin
                        if(practice_step==2)begin
                            if(l_release_target_q && l_release_max_q)begin practice_progress<=100;practice_succeeded;end
                            else practice_failed;
                        end else if(practice_l_feedback ? l_release_target_q:r_release_target_q)practice_failed;
                        else practice_succeeded;
                    end else if(hold_expired)practice_failed;
                    else if(practice_step==2)begin
                        if(hold_target_reached)begin practice_phase<=3;practice_progress<=100;release_prompt<=1;end
                    end
                end
                state_hot[39]:begin
                    if(!practice_pacu && b_release)begin
                        practice_active<=0;practice_handoff_pending<=0;replace_page(media_scene,LEARN_END,EFFECT_FADE);
                    end else if(visual_expired)begin
                        
                        if((practice_pacu && practice_step==1) || (!practice_pacu && practice_step==4))begin
                            practice_handoff_pending<=1;
                            practice_handoff_scene<=practice_pacu?`SC_PACUCALL:`SC_READY;
                            if(practice_pacu)show_teaching(`SC_PACUCALL,P_CALL_RELEASE);
                            else show_teaching(`SC_READY,LEARN_END);
                        end else if(!practice_pacu && (practice_step==1 || practice_step==2))begin
                            practice_handoff_pending<=1;
                            practice_handoff_scene<=practice_step==1?`SC_LEARNHLD:`SC_LEARNVIS;
                            show_teaching(practice_step==1 ? `SC_LEARNHLD:`SC_LEARNVIS,LEARN_END);
                        end else begin
                            practice_step<=practice_step+1'b1;
                            practice_errors<=0;practice_progress<=0;practice_phase<=0;
                            practice_l_feedback<=0;practice_r_feedback<=0;begin /* transition is defined in canonical generated network */ end barrier_start<=time_cycles;barrier_generation<=~barrier_generation;
                        end
                    end
                end
                state_hot[40]:begin
                    if(!practice_pacu && b_release)begin
                        practice_active<=0;practice_handoff_pending<=0;replace_page(media_scene,LEARN_END,EFFECT_FADE);
                    end else if(visual_expired && released && patient_eligible)begin
                        
                        practice_phase<=0;begin /* transition is defined in canonical generated network */ end barrier_start<=time_cycles;barrier_generation<=~barrier_generation;
                    end
                end
                state_hot[41]:begin
                    release_prompt<=!released;
                    if(b_release)begin
                        practice_alarm<=0;practice_errors<=0;practice_error_bank[practice_step]<=0;
                        practice_active<=0;practice_handoff_pending<=0;
                        replace_page(practice_return_scene,practice_pacu?P_GUID_END:LEARN_END,EFFECT_DIRECT);
                    end
                end
                state_hot[42]:begin
                    if(practice_feedback_expired)begin
                        practice_active<=0;practice_l_feedback<=0;practice_r_feedback<=0;
                        if(practice_pacu)show_teaching(`SC_PACUCALL,P_CALL_RELEASE);
                        else begin
                            show_teaching(`SC_READY,LEARN_END);
                        end
                    end
                end
                state_hot[30]:begin
                    if(!convert_busy) begin convert_start<=1;convert_seen_busy<=0;begin /* transition is defined in canonical generated network */ end end
                end
                state_hot[31]:begin
                    if(convert_busy) convert_seen_busy<=1;
                    if(convert_done && convert_seen_busy) begin
                        if(convert_hold) begin
                            // A brief attempt keeps its measured duration and
                            // explicit incomplete status, then continues T6.
                            hold_ms<=convert_ms;hold_status<=pending_hold_status;result_valid[4]<=pending_hold_status!=7;
                            begin /* transition is defined in canonical generated network */ end 
                        end else begin
                            rt_ms<=convert_ms;rt_status<=1;result_valid[3]<=1;
                            begin /* transition is defined in canonical generated network */ end 
                        end
                    end
                end
                state_hot[44]:begin
                    if(visual_expired)show_feedback;
                end
                state_hot[33]:begin release_prompt<=l_down || r_down; end
                state_hot[34]:begin
                    // Idle media faults have an explicit visible exit and a
                    // manual retry. Mode selection also remains available.
                    if (active_mode==0 && b_release) begin
                        fault_code<=0;alarm_active<=0;replace_page(media_scene,WELCOME,EFFECT_DIRECT);
                    end
                end
                default:begin fault_code<=15;report_outcome<=3; begin /* transition is defined in canonical generated network */ end  alarm_active<=1; end
                endcase
            end
        end
    end
endmodule


`default_nettype wire
