`default_nettype none
`timescale 1ns/1ps
// bundled-data command/response bridge. Only one commit outstanding.
// Both resets MUST be asserted together. Payload registers are held until the
// opposite-domain toggle acknowledgement; add corresponding physical CDC constraints.
// The memory reader remains the unmodified official frame_read_write hierarchy.
// Source protects both old active and requested bank until the response returns.
module recovery_frame_commit #(
    parameter integer ADDRESS_SETUP_CYCLES = 2,
    parameter integer TRANSITION_ENABLE = 0,
    parameter integer TRANSITION_FRAMES = 16,
    parameter integer TRANSITION_FRAME_PIXELS = 307200,
    parameter integer REQUEST_EFFECT_ENABLE = 0,
    parameter integer WIPE_WIDTH = 640,
    parameter integer THEMED_TRANSITION_ENABLE = 0
) (
    input wire src_clk,
    input wire src_rst,
    input wire [7:0] current_epoch,
    input wire cancel,
    input wire commit_valid,
    output wire commit_ready,
    input wire [1:0] commit_bank,
    input wire [5:0] commit_scene,
    input wire [7:0] commit_epoch,
    input wire [1:0] commit_effect,
    input wire [1:0] commit_direction,
    output wire [3:0] protect_mask,
    output reg [1:0] active_bank,
    output reg presented,
    output reg present_error,
    output reg [1:0] presented_bank,
    output reg [5:0] presented_scene,
    output reg [7:0] presented_epoch,
    output wire busy,

    input wire pixel_clk,
    input wire pixel_rst,
    input wire video_read_req,
    output reg video_read_ack,
    output reg frame_read_req,
    input wire mem_read_ack,
    output reg [1:0] reader_bank,
    input wire axis_user,
    input wire axis_valid,
    input wire axis_ready,
    input wire pixel_fault,
    output reg pixel_presented,
    output reg [5:0] pixel_scene,
    output reg [7:0] pixel_epoch,
    output reg pixel_display_valid,
    // Early physical-canvas identity: successful memory ACK in blanking,
    // before the first RGB pixel. This never advances PRESENTED/GO timing.
    output reg canvas_prepare,output reg canvas_valid,
    output reg [5:0] canvas_scene,output reg [7:0] canvas_epoch,
    output wire [8:0] transition_gain,
    output wire [9:0] transition_reveal_width,
    output wire transition_wipe_active,
    output wire [1:0] transition_direction
);

localparam [2:0] C_IDLE=0, C_WAIT_FRAME=1, C_WAIT_ACK=2, C_WAIT_PRESENT=3, C_WAIT_FADE=4;
localparam [1:0] R_PRESENT=0, R_CANCEL=1, R_ERROR=2;
reg req_toggle;
reg cmd_busy;
reg [1:0] hold_bank;
reg [5:0] hold_scene;
reg [7:0] hold_epoch;
reg [3:0] hold_effect;
reg rsp_sync1, rsp_sync2;
reg cancel_toggle;
reg cancel_busy;
reg cancel_requested;
reg [7:0] cancel_epoch_hold;
reg [7:0] applied_epoch;
reg cancel_ack_sync1, cancel_ack_sync2;
(* ASYNC_REG = "TRUE" *) reg fault_sync1, fault_sync2;
reg fault_seen;
reg fault_toggle;
reg [7:0] fault_epoch_hold;
(* ASYNC_REG = "TRUE" *) reg fault_ack_sync1, fault_ack_sync2;
reg fault_pending;
reg [7:0] fault_pending_epoch;
reg rsp_toggle;
reg [1:0] rsp_status;
reg [1:0] rsp_active_bank;
reg [1:0] rsp_bank;
reg [5:0] rsp_scene;
reg [7:0] rsp_epoch;
reg cancel_ack_toggle;
reg req_sync1, req_sync2, req_seen;
reg cancel_sync1, cancel_sync2, cancel_seen;
reg mem_ack_sync1, mem_ack_sync2;
reg [7:0] accepted_epoch;
reg cancel_wait;
reg [2:0] command_state;
reg [1:0] local_bank;
reg [5:0] local_scene;
reg [7:0] local_epoch;
reg [3:0] local_effect;
reg [1:0] physical_bank;
reg read_active;
reg read_seen;
reg read_for_command;
reg command_read_fault;
reg visual_pending;
reg [5:0] visual_scene;
reg [7:0] visual_epoch;
integer setup_remaining;
wire new_cancel ;
wire new_command ;
wire [7:0] visible_fault_epoch ;
wire command_cancelled ;
reg transition_armed, transition_used, frame_req_previous;
wire frame_boundary ;
wire transition_needed ;
wire fade_start ;
wire raw_sof ;
wire fade_busy, fade_allow_switch, fade_done, fade_error;
// Continuous values retain the original net initializer expressions.
assign new_cancel =  cancel_sync2 != cancel_seen;
assign new_command =  req_sync2 != req_seen;
assign visible_fault_epoch =  new_cancel ? cancel_epoch_hold : accepted_epoch;
assign command_cancelled =  cancel_wait || new_cancel || local_epoch != accepted_epoch;
assign frame_boundary =  video_read_req && !frame_req_previous;
assign transition_needed =  TRANSITION_ENABLE != 0 &&
        (transition_armed ? transition_used : (pixel_display_valid &&
         (REQUEST_EFFECT_ENABLE != 0 ? local_effect[1:0]!=2'd0 : transition_scene(local_scene))));
assign fade_start =  command_state == C_WAIT_FRAME && !transition_armed &&
                      transition_needed && !command_cancelled;
assign raw_sof =  command_state == C_WAIT_PRESENT && !command_cancelled &&
                   !pixel_fault && axis_user && axis_valid && axis_ready;

    
    
    // Source-owned mailbox. Stable from request toggle until response toggle.
    
    
    
    
    
    // Direction shares the existing held effect mailbox and its exact SDC
    // wildcard. Both are stable until the original response acknowledgement.
    
    
    // Independent cancellation mailbox can interrupt a waiting commit.
    
    
    
    
    
    
    // Independent held fault mailbox; never shares the commit response payload.
    
    
    
    
    
    
    

    // Pixel-owned response payload, held through the next source request.
    
    
    
    
    
    
    

    assign commit_ready = !src_rst && !cmd_busy && !cancel_busy &&
                          !cancel_requested && !cancel && current_epoch == applied_epoch;
    assign busy = cmd_busy || cancel_busy || cancel_requested || current_epoch != applied_epoch;
    // Even an uninitialized screen reserves bank0, as the reader may fetch it.
    assign protect_mask = (4'b0001 << active_bank) |
                          (cmd_busy ? (4'b0001 << hold_bank) : 4'b0000) |
                          ((commit_valid && commit_ready) ? (4'b0001 << commit_bank) : 4'b0000);

    always @(posedge src_clk or posedge src_rst) begin
        if (src_rst) begin
            req_toggle<=0; cmd_busy<=0; hold_bank<=0; hold_scene<=0; hold_epoch<=0;
            hold_effect<=0;
            rsp_sync1<=0; rsp_sync2<=0; active_bank<=0;
            presented<=0; present_error<=0; presented_bank<=0; presented_scene<=0; presented_epoch<=0;
            cancel_toggle<=0; cancel_busy<=0; cancel_requested<=0;
            cancel_epoch_hold<=0; applied_epoch<=0; cancel_ack_sync1<=0; cancel_ack_sync2<=0;
            fault_sync1<=0; fault_sync2<=0; fault_seen<=0;
        end else begin
            rsp_sync1<=rsp_toggle; rsp_sync2<=rsp_sync1;
            cancel_ack_sync1<=cancel_ack_toggle; cancel_ack_sync2<=cancel_ack_sync1;
            fault_sync1<=fault_toggle; fault_sync2<=fault_sync1;
            presented<=0; present_error<=0;
            if (cancel) cancel_requested<=1;
            if (!cancel_busy && (cancel_requested || cancel || current_epoch != applied_epoch)) begin
                cancel_epoch_hold<=current_epoch;
                cancel_toggle<=~cancel_toggle;
                cancel_busy<=1;
                cancel_requested<=0;
            end else if (cancel_busy && cancel_ack_sync2 == cancel_toggle) begin
                cancel_busy<=0;
                applied_epoch<=cancel_epoch_hold;
            end
            if (cmd_busy && rsp_sync2 == req_toggle) begin
                cmd_busy<=0;
                active_bank<=rsp_active_bank;
                presented_bank<=rsp_bank;
                presented_scene<=rsp_scene;
                presented_epoch<=rsp_epoch;
                // A response from a cancelled generation still updates bank
                // ownership but can never advance the assessment FSM.
                if (!cancel && !cancel_requested && !cancel_busy && rsp_epoch == current_epoch) begin
                    if (rsp_status == R_PRESENT) presented<=1;
                    if (rsp_status == R_ERROR) present_error<=1;
                end
            end
            if (fault_sync2 != fault_seen) begin
                // This independent mailbox reports a NEW real fault in the
                // physical picture selected by the reader, not an obsolete
                // application completion. Source cancellation can advance its
                // epoch before the pixel synchronizer sees it, so presentation
                // epoch filtering here would discard a genuine visible fault.
                // Hold it through cancellation retirement; only command
                // responses above use the obsolete-transaction epoch filter.
                if (!cancel && !cancel_requested && !cancel_busy && current_epoch == applied_epoch) begin
                    fault_seen<=fault_sync2;
                    present_error<=1;
                end
            end
            if (commit_valid && commit_ready) begin
                hold_bank<=commit_bank; hold_scene<=commit_scene; hold_epoch<=commit_epoch;
                hold_effect<={THEMED_TRANSITION_ENABLE!=0?commit_direction:2'd0,commit_effect};
                req_toggle<=~req_toggle;
                cmd_busy<=1;
            end
        end
    end

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    // A cancelled application event cannot rewind a physical frame fetch.
    // Keep its visual identity until that complete bank's accepted SOF. This
    // is independent of the response mailbox, which may already retire CANCEL.
    
    
    
    
    
    
    // A fresh physical fault belongs to the current displayed ownership even
    // when KEY2 retains a complete picture from an earlier presentation epoch.
    // Cancellation received on this exact edge takes precedence over the old
    // accepted_epoch register value.
    
    
    // only the locally latched command payload chooses an effect.
    // No additional mailbox or asynchronous multi-bit parameter is introduced.
    function transition_scene;
        input [5:0] scene;
        begin
            transition_scene = (scene >= 6'd9 && scene <= 6'd11) ||
                               (scene >= 6'd23 && scene <= 6'd26);
        end
    endfunction
    
    
    
    
    
    
    generate if (TRANSITION_ENABLE != 0) begin : g_transition
        recovery_image_transition #(.FADE_FRAMES(TRANSITION_FRAMES),
            .FRAME_PIXELS(TRANSITION_FRAME_PIXELS), .EFFECT_SELECT_ENABLE(REQUEST_EFFECT_ENABLE),
            .WIPE_WIDTH(WIPE_WIDTH),.EASING_ENABLE(THEMED_TRANSITION_ENABLE),
            .DIRECTION_ENABLE(THEMED_TRANSITION_ENABLE)) u_fade(
            .clk(pixel_clk), .rst(pixel_rst), .start(fade_start),
            .abort(new_cancel || pixel_fault ||
                   (axis_valid && !axis_ready)), .frame_boundary(frame_boundary),
            .fetched(raw_sof && transition_used), .axis_user(axis_user),
            .axis_valid(axis_valid), .axis_ready(axis_ready),
            .effect(local_effect[1:0]),.direction(local_effect[3:2]),
            .active_direction(transition_direction),.reveal_width(transition_reveal_width),
            .wipe_active(transition_wipe_active),
            .gain(transition_gain), .allow_switch(fade_allow_switch),
            .busy(fade_busy), .done(fade_done), .error(fade_error));
    end else begin : g_bypass
        assign transition_gain = 9'd256;
        assign transition_reveal_width = WIPE_WIDTH;
        assign transition_wipe_active = 1'b0;
        assign transition_direction = 2'd0;
        assign fade_busy = 1'b0;
        assign fade_allow_switch = 1'b1;
        assign fade_done = 1'b0;
        assign fade_error = 1'b0;
    end endgenerate

    // Return the actual selected physical bank even on cancellation. A switch
    // after a memory read request is irreversible for that frame; ownership must
    // not revert speculatively to the old bank while the new one is being read.
    task respond;
        input [1:0] status;
        input [1:0] selected_bank;
        begin
            rsp_status<=status;
            rsp_active_bank<=selected_bank;
            rsp_bank<=local_bank;
            rsp_scene<=local_scene;
            rsp_epoch<=local_epoch;
            rsp_toggle<=req_seen;
            command_state<=C_IDLE;
        end
    endtask

    always @(posedge pixel_clk or posedge pixel_rst) begin
        if (pixel_rst) begin
            req_sync1<=0; req_sync2<=0; req_seen<=0;
            cancel_sync1<=0; cancel_sync2<=0; cancel_seen<=0;
            mem_ack_sync1<=0; mem_ack_sync2<=0;
            accepted_epoch<=0; cancel_wait<=0; cancel_ack_toggle<=0;
            command_state<=C_IDLE; local_bank<=0; local_scene<=0; local_epoch<=0;
            local_effect<=0;
            transition_armed<=0; transition_used<=0; frame_req_previous<=0;
            reader_bank<=0; physical_bank<=0;
            video_read_ack<=0; frame_read_req<=0;
            read_active<=0; read_seen<=0; read_for_command<=0; command_read_fault<=0; setup_remaining<=0;
            visual_pending<=0; visual_scene<=0; visual_epoch<=0;
            rsp_toggle<=0; rsp_status<=R_CANCEL; rsp_active_bank<=0;
            rsp_bank<=0; rsp_scene<=0; rsp_epoch<=0;
            pixel_presented<=0; pixel_scene<=0; pixel_epoch<=0; pixel_display_valid<=0;
            canvas_prepare<=0;canvas_valid<=0;canvas_scene<=0;canvas_epoch<=0;
            fault_toggle<=0; fault_epoch_hold<=0; fault_ack_sync1<=0; fault_ack_sync2<=0;
            fault_pending<=0; fault_pending_epoch<=0;
        end else begin
            req_sync1<=req_toggle; req_sync2<=req_sync1;
            frame_req_previous<=video_read_req;
            cancel_sync1<=cancel_toggle; cancel_sync2<=cancel_sync1;
            mem_ack_sync1<=mem_read_ack; mem_ack_sync2<=mem_ack_sync1;
            fault_ack_sync1<=fault_seen; fault_ack_sync2<=fault_ack_sync1;
            if (fault_pending && fault_ack_sync2 == fault_toggle) begin
                fault_epoch_hold<=fault_pending_epoch;
                fault_toggle<=~fault_toggle;
                fault_pending<=0;
            end
            // Keep a fresh physical fault independently of a response that may
            // be suppressed by an epoch cancellation, including during fade-in.
            if (pixel_display_valid && (pixel_fault || (axis_valid && !axis_ready) ||
                (command_state == C_WAIT_FADE && fade_error)) &&
                command_state != C_WAIT_ACK && command_state != C_WAIT_PRESENT) begin
                pixel_display_valid<=0;
                fault_pending<=1;
                fault_pending_epoch<=visible_fault_epoch;
            end
            pixel_presented<=0;
            canvas_prepare<=0;
            if(pixel_fault||(axis_valid&&!axis_ready))canvas_valid<=0;
            if (visual_pending) begin
                if (pixel_fault || (axis_valid && (!axis_ready || !axis_user))) begin
                    visual_pending<=0;
                    pixel_display_valid<=0;
                    // Preserve the real fault. Cancellation only suppresses
                    // the obsolete assessment event; it never hides bad pixels.
                    if (command_state != C_WAIT_PRESENT || command_cancelled) begin
                        fault_pending<=1;
                        fault_pending_epoch<=visible_fault_epoch;
                    end
                end else if (axis_user && axis_valid && axis_ready) begin
                    pixel_scene<=visual_scene;
                    pixel_epoch<=visual_epoch;
                    pixel_display_valid<=1;
                    visual_pending<=0;
                end
            end
            if (command_state == C_WAIT_ACK && (pixel_fault || axis_valid))
                command_read_fault<=1;
            if (!video_read_req) begin read_seen<=0; video_read_ack<=0; end
            if (new_cancel) begin
                cancel_seen<=cancel_sync2;
                accepted_epoch<=cancel_epoch_hold;
                cancel_wait<=1;
            end
            if (cancel_wait && command_state == C_IDLE && !fade_busy) begin
                cancel_ack_toggle<=cancel_seen;
                cancel_wait<=0;
            end

            if (new_command && command_state == C_IDLE && !fade_busy) begin
                local_bank<=hold_bank; local_scene<=hold_scene; local_epoch<=hold_epoch;
                local_effect<=hold_effect;
                req_seen<=req_sync2;
                command_state<=C_WAIT_FRAME;
                transition_armed<=0; transition_used<=0;
            end
            if (command_state == C_WAIT_FRAME && !transition_armed) begin
                transition_armed<=1; transition_used<=transition_needed;
            end
            if (command_state == C_WAIT_FRAME && command_cancelled)
                respond(R_CANCEL, physical_bank);
            if (command_state == C_WAIT_PRESENT) begin
                if (command_cancelled) begin
                    respond(R_CANCEL, physical_bank);
                end else if (pixel_fault || (axis_valid && (!axis_ready || !axis_user))) begin
                    respond(R_ERROR, physical_bank);
                    pixel_display_valid<=0;
                end else if (axis_user && axis_valid && axis_ready) begin
                    if (transition_used) command_state<=C_WAIT_FADE;
                    else begin respond(R_PRESENT, physical_bank); pixel_presented<=1; end
                    pixel_scene<=local_scene;
                    pixel_epoch<=local_epoch;
                    pixel_display_valid<=1;
                end
            end

            // A raw fetched SOF updates visual identity but does not release
            // page audio/timers while black or partially faded. The independent
            // effect proves a complete accepted full-bright frame before DONE.
            if (command_state == C_WAIT_FADE) begin
                if (command_cancelled) respond(R_CANCEL, physical_bank);
                else if (pixel_fault || (axis_valid && !axis_ready) || fade_error) begin
                    respond(R_ERROR, physical_bank);
                    pixel_display_valid<=0;
                end else if (fade_done) begin
                    respond(R_PRESENT, physical_bank);
                    pixel_presented<=1;
                end
            end

            // Hold the chosen address ahead of the memory request. Never change
            // it in an active read handshake, including a cancel in that window.
            if (!read_active && !read_seen && video_read_req && !mem_ack_sync2) begin
                read_active<=1;
                read_seen<=1;
                setup_remaining<=ADDRESS_SETUP_CYCLES;
                read_for_command<=0;
                if (command_state == C_WAIT_FRAME && !command_cancelled &&
                    (!transition_needed || fade_allow_switch)) begin
                    reader_bank<=local_bank;
                    read_for_command<=1;
                    command_read_fault<=0;
                    command_state<=C_WAIT_ACK;
                end
            end else if (read_active) begin
                if (!frame_read_req) begin
                    if (setup_remaining == 0) frame_read_req<=1;
                    else setup_remaining<=setup_remaining-1;
                end else if (mem_ack_sync2) begin
                    frame_read_req<=0;
                    video_read_ack<=1;
                    read_active<=0;
                    physical_bank<=reader_bank;
                    if (read_for_command) begin
                        if (!(pixel_fault || command_read_fault || axis_valid)) begin
                            canvas_prepare<=1;canvas_valid<=1;
                            canvas_scene<=local_scene;canvas_epoch<=local_epoch;
                            visual_pending<=1;
                            visual_scene<=local_scene;
                            visual_epoch<=local_epoch;
                        end
                        if (pixel_fault || command_read_fault || axis_valid) begin
                            respond(R_ERROR, reader_bank);
                            pixel_display_valid<=0;
                            if (command_cancelled) begin
                                fault_pending<=1;
                                fault_pending_epoch<=visible_fault_epoch;
                            end
                        end else if (command_cancelled) respond(R_CANCEL, reader_bank);
                        else command_state<=C_WAIT_PRESENT;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
