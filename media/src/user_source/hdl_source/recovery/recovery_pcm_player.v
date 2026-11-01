`default_nettype none
`timescale 1ns/1ps
// FAT byte stream -> FPGA sample-index mix -> 16-bit mono+retirement FIFO ->
// original 64-bit/channel I2S timing. Ordinary mono bypass stays cycle-exact.
// play_done means the last valid stereo frame has completed at the source,
// not that the display's loudspeaker has emitted its last sound.
module recovery_pcm_player #(
    parameter integer FIFO_ADDR_BITS=13,
    parameter integer PREFILL_SAMPLES=2048,
    parameter integer VOLUME_ENABLE=0
)(
    input wire clk, input wire rst, input wire audio_mclk, input wire audio_rst,
    input wire start, input wire cancel, input wire [31:0] file_size,
    input wire byte_valid, input wire [7:0] byte_data, output wire byte_ready,
    input wire file_done, input wire play_enable,
    output wire busy, output reg pcm_ready, output reg play_done, output reg [7:0] error,
    output reg i2s_bclk, output reg i2s_lrck, output reg i2s_dout,
    input wire [8:0] volume_gain,
    input wire [5:0] narration_id,
    output reg [5:0] playback_id_audio,
    output reg [7:0] playback_generation_audio,
    output reg [15:0] playback_ticks_audio,
    output reg playback_running_audio,
    // one file carries [voice16,music16] pairs; ordinary mono is exact legacy.
    input wire paired_mode,input wire music_only,input wire [31:0] voice_sample_count,
    output reg voice_done,output wire voice_active,output wire music_active
);

localparam IDLE=0, FLUSH_HIGH=1, FLUSH_LOW=2, LOAD=3, DRAIN=4, STOPPING=5, EOF_CHECK=6;
reg [2:0] state;
reg flush_req, start_pending;
reg [31:0] size_latched, expected_samples, received_bytes, written_samples;
reg [7:0] low_byte;
reg [1:0] byte_phase;
reg [23:0] packed_bytes;
reg paired_hold,music_only_hold;
reg [31:0] voice_last_byte_hold;
reg [31:0] last_file_byte_hold;
reg input_available,frame_voice_marker;
reg voice_has_tail;
wire low_pending;
reg sample_accepted, prefill_met;
reg [31:0] prefill_limit;
reg command_toggle;
reg [5:0] narration_id_hold;
reg [7:0] playback_subsample;
(* ASYNC_REG="TRUE" *) reg flush_ack1,flush_ack2;
(* ASYNC_REG="TRUE" *) reg done1,done2,err1,err2;
reg done_seen,err_seen,voice_retired_clk;
wire fifo_full,fifo_empty;
wire [16:0] fifo_data;
wire [FIFO_ADDR_BITS:0] wr_level,rd_level;
wire frame_byte_last;
wire frame_accepted;
wire stream_mix;
reg mix_pending,voice_received;
reg [16:0] pending_sample;
reg mix_raw_valid,mix_product_valid;
reg signed [15:0] mix_voice_raw,mix_music_raw;
reg [5:0] mix_gain_raw;
reg mix_without_voice_raw,mix_raw_tag,mix_product_tag;
reg signed [23:0] voice_product_reg;
reg signed [22:0] music_product_reg;
wire mix_inflight;
reg [31:0] frames_remaining;
reg [5:0] music_gain;
reg [9:0] ramp_count;
wire fifo_write;
wire voice_marker;
wire [31:0] fifo_payload;
wire [16:0] fifo_input;
wire fifo_read;
reg flush_audio;
(* ASYNC_REG="TRUE" *) reg flush1,flush2,cmd1,cmd2,en1,en2,ready1,ready2;
reg cmd_seen,active_audio,playing_audio;
reg [31:0] samples_left;
reg look_valid,read_pending;
reg [16:0] look_sample;
wire music_only_audio;
reg frame_voice_last,voice_retired_audio;
reg [23:0] current_sample;
reg [15:0] shift_reg;
reg [5:0] bit_count;
reg frame_valid,frame_last;
reg done_toggle,error_toggle;
wire sample_boundary;
wire [15:0] volume_sample;
wire signed [15:0] voice_component;
wire signed [15:0] music_component;
wire signed [23:0] voice_wide;
wire signed [23:0] voice_product;
wire signed [6:0] signed_music_gain;
wire signed [22:0] music_product;
wire signed [24:0] mixed_product;
wire signed [24:0] mixed_scaled;
wire [15:0] mixed_sample;
wire [15:0] volume_input;
// Continuous values retain the original net initializer expressions.
assign low_pending = byte_phase[0];
assign frame_byte_last = paired_hold ? byte_phase==3 : byte_phase==1;
assign frame_accepted = byte_valid && byte_ready && frame_byte_last;
assign stream_mix = paired_hold||music_only_hold;
assign mix_inflight = mix_raw_valid||mix_product_valid||mix_pending;
assign fifo_write = !cancel&&(stream_mix ? mix_pending:frame_accepted);
assign voice_marker = frame_voice_marker;
assign fifo_payload = paired_hold ? {byte_data,packed_bytes} : {16'd0,byte_data,low_byte};
assign fifo_input = stream_mix ? pending_sample:{voice_marker,fifo_payload[15:0]};
assign music_only_audio = playback_id_audio==6'd50;
assign sample_boundary = i2s_bclk && bit_count==6'd63 && i2s_lrck;
assign voice_component = mix_voice_raw;
assign music_component = mix_music_raw;
assign voice_wide = {{8{voice_component[15]}},voice_component};
assign voice_product = (voice_wide<<<8)-(voice_wide<<<5);
assign signed_music_gain = $signed({1'b0,mix_gain_raw});
assign music_product = music_component*signed_music_gain;
assign mixed_product = {voice_product_reg[23],voice_product_reg}+
     {{2{music_product_reg[22]}},music_product_reg};
assign mixed_scaled = mixed_product>>>8;
assign mixed_sample = mixed_scaled>25'sd32767 ? 16'h7fff :
     mixed_scaled< -25'sd32768 ? 16'h8000 : mixed_scaled[15:0];
assign volume_input = look_sample[15:0];

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    // invariant remaining=expected_samples-accepted mixed frames (mod 2^32).
    // Load with the held command; the per-frame gain path reads a register.
    
    
    
    
    // Only the retirement marker crosses with the mixed FIFO word. Pure music
    // uses reserved held identity50 through the existing constrained mailbox.
    // Precompute inclusive byte index once per command. Do not put a 32-bit
    // subtractor between the held voice count and every FIFO tag RAM write.
    
    
    
    
    assign busy=state!=IDLE;
    // Conservative source activity includes prefill/flush; no false quiet window.
    assign voice_active=busy&&!music_only_hold&&!voice_retired_clk;
    assign music_active=busy&&(paired_hold||music_only_hold);
    assign byte_ready=state==LOAD && input_available && (!frame_byte_last || (!fifo_full&&(!stream_mix||!mix_inflight))) && !cancel;
    recovery_async_fifo #(.WIDTH(17),.ADDR_BITS(FIFO_ADDR_BITS)) u_pcm_fifo(
        .arst(rst|audio_rst|flush_req),.wr_clk(clk),.wr_en(fifo_write),.wr_data(fifo_input),
        .full(fifo_full),.wr_level(wr_level),.rd_clk(audio_mclk),.rd_en(fifo_read),
        .rd_data(fifo_data),.empty(fifo_empty),.rd_level(rd_level));

    
    
    
    
    
    
    // Reserved identity50 crosses the already constrained identity mailbox.
    // Decode only after playback_id_audio has been captured in this domain.
    
    
    
    // Each 64-bit channel slot contains 16 sample bits and 48 fixed zero bits.
    // Shift only the sample; zero-fill shifts keep the original slot timing.
    
    
    
    
    // Configuration crosses as one held request/acknowledge packet and is
    // accepted only at the left/right pair's original sample load boundary.
    // The validity bit preserves unity during reset/mailbox initialization.
    
    
    // Fixed voice 224/256, slowly varying music 0..48/256. Full signed width
    // and saturation precede the existing total-volume path and stereo latch.
    
    
    
    
    
    
    
    
    
    // Runtime mix is produced by FPGA in clk/file-stream domain, then held
    // through the unchanged async FIFO. Total volume remains sample-boundary
    // dynamic in audio_mclk, immediately before the original serializer.
    
    generate if(VOLUME_ENABLE!=0)begin:g_volume
        wire [9:0] volume_packet;
        wire [8:0] audio_gain=volume_packet[9]?volume_packet[8:0]:9'd256;
        recovery_status_mailbox #(.WIDTH(10)) u_volume_config(
            .src_clk(clk),.src_rst(rst),.src_data({1'b1,volume_gain}),
            .dst_clk(audio_mclk),.dst_rst(audio_rst),.frame_boundary(sample_boundary),
            .dst_data(volume_packet),.src_settled(),.src_echo());
        recovery_pcm_volume u_volume(
            .sample_in(volume_input),.gain(audio_gain),.sample_out(volume_sample));
    end else begin:g_volume_bypass
        // Legacy benches and integrations do not need to connect volume_gain.
        assign volume_sample=volume_input;
    end endgenerate
    assign fifo_read=active_audio && !flush2 && !look_valid && !read_pending && !fifo_empty;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE; flush_req<=1; start_pending<=0; size_latched<=0; expected_samples<=0;
            received_bytes<=0; written_samples<=0; low_byte<=0;byte_phase<=0;packed_bytes<=0;
            paired_hold<=0;music_only_hold<=0;voice_last_byte_hold<=0;voice_has_tail<=0;
            last_file_byte_hold<=0;input_available<=0;frame_voice_marker<=0;
            mix_pending<=0;pending_sample<=0;voice_received<=0;frames_remaining<=0;music_gain<=0;ramp_count<=0;
            mix_raw_valid<=0;mix_product_valid<=0;mix_voice_raw<=0;mix_music_raw<=0;mix_gain_raw<=0;
            mix_without_voice_raw<=0;mix_raw_tag<=0;mix_product_tag<=0;voice_product_reg<=0;music_product_reg<=0;
            sample_accepted<=0; prefill_met<=0; prefill_limit<=0;
            command_toggle<=0; pcm_ready<=0; play_done<=0; error<=0;
            flush_ack1<=0; flush_ack2<=0; done1<=0; done2<=0; err1<=0; err2<=0;
            done_seen<=0; err_seen<=0; narration_id_hold<=0;
            voice_retired_clk<=0;voice_done<=0;
        end else begin
            flush_ack1<=flush_audio; flush_ack2<=flush_ack1;
            done1<=done_toggle; done2<=done1; err1<=error_toggle; err2<=err1;
            play_done<=0;voice_done<=0;
            // Three file-clock stages isolate sector RAM -> multiplier ->
            // add/saturate -> FIFO. One in-flight frame reserves its FIFO slot;
            // all new-format gains/tags belong to the accepted sample index.
            mix_raw_valid<=0;mix_product_valid<=mix_raw_valid;mix_pending<=mix_product_valid;
            if(mix_raw_valid)begin
                voice_product_reg<=mix_without_voice_raw ? 24'sd0:voice_product;
                music_product_reg<=music_product;mix_product_tag<=mix_raw_tag;
            end
            if(mix_product_valid)pending_sample<={mix_product_tag,mixed_sample};
            if(frame_accepted&&stream_mix)begin
                mix_voice_raw<=fifo_payload[15:0];
                mix_music_raw<=paired_hold ? fifo_payload[31:16]:fifo_payload[15:0];
                mix_gain_raw<=music_gain;mix_without_voice_raw<=music_only_hold;
                mix_raw_tag<=voice_marker;mix_raw_valid<=1;
                frames_remaining<=frames_remaining-1'b1;
                if(voice_marker)voice_received<=1;
                if(frames_remaining<=32'd9600)begin
                    if(ramp_count>=199)begin ramp_count<=0;if(music_gain!=0)music_gain<=music_gain-1'b1;end
                    else ramp_count<=ramp_count+1'b1;
                end else if(!voice_received&&!music_only_hold)begin
                    if(music_gain<16)begin
                        if(ramp_count>=899)begin ramp_count<=0;music_gain<=music_gain+1'b1;end
                        else ramp_count<=ramp_count+1'b1;
                    end else ramp_count<=0;
                end else if(music_gain<48)begin
                    if(ramp_count>=(music_only_hold?299:449))begin ramp_count<=0;music_gain<=music_gain+1'b1;end
                    else ramp_count<=ramp_count+1'b1;
                end else ramp_count<=0;
            end
            // Ordinary mono keeps its original handshake/FIFO write edge.
            // New mixed formats qualify only their actual pipelined RAM write.
            sample_accepted<=fifo_write;
            if(state==LOAD || state==EOF_CHECK || state==DRAIN) begin
                if(sample_accepted) written_samples<=written_samples+1;
                prefill_met<=(written_samples!=0 && written_samples>=prefill_limit);
                if(prefill_met) pcm_ready<=1;
            end else begin
                sample_accepted<=0;
                prefill_met<=0;
            end
            case(state)
              IDLE: begin
                  pcm_ready<=0;
                  if(start && !cancel) begin
                      error<=0; received_bytes<=0; written_samples<=0;byte_phase<=0;packed_bytes<=0;
                      paired_hold<=paired_mode===1'b1;music_only_hold<=music_only===1'b1;voice_retired_clk<=0;
                      mix_pending<=0;voice_received<=0;frames_remaining<=(paired_mode===1'b1)?file_size>>2:file_size>>1;music_gain<=0;ramp_count<=0;
                      mix_raw_valid<=0;mix_product_valid<=0;frame_voice_marker<=0;
                      // Held until the existing command toggle is sampled in audio domain.
                      narration_id_hold<=(music_only===1'b1)?6'd50:(narration_id<=6'd49)?narration_id:6'd0;
                      size_latched<=file_size; expected_samples<=(paired_mode===1'b1)?file_size>>2:file_size>>1;
                      last_file_byte_hold<=file_size-1'b1;input_available<=file_size!=0;
                      voice_last_byte_hold<=(paired_mode===1'b1)?
                       (voice_sample_count<<2)-1'b1:file_size-1'b1;
                      voice_has_tail<=(paired_mode===1'b1)&&voice_sample_count<(file_size>>2);
                      prefill_limit<=(((paired_mode===1'b1)?file_size>>2:file_size>>1)<PREFILL_SAMPLES)?
                       ((paired_mode===1'b1)?file_size>>2:file_size>>1):PREFILL_SAMPLES;
                      flush_req<=1; start_pending<=1; state<=FLUSH_HIGH;
                      if(file_size==0 || file_size[0] || ((paired_mode===1'b1)&&
                       (file_size[1]||voice_sample_count==0||voice_sample_count>(file_size>>2))))
                       begin error<=8'h41; start_pending<=0; end
                  end
              end
              FLUSH_HIGH: if(flush_ack2) begin flush_req<=0; state<=FLUSH_LOW; end
              FLUSH_LOW: if(!flush_ack2) begin
                  done_seen<=done2; err_seen<=err2;
                  if(start_pending) begin command_toggle<=~command_toggle; state<=LOAD; end
                  else state<=IDLE;
              end
              LOAD: begin
                  if(byte_valid && byte_ready) begin
                      received_bytes<=received_bytes+1;
                      if(received_bytes==last_file_byte_hold)input_available<=0;
                      // Work out this frame's retirement tag at its first byte,
                      // before the mono high-byte/FIFO write edge. No wide
                      // byte-count compare remains on the FIFO tag RAM input.
                      if(byte_phase==0)frame_voice_marker<=!music_only_hold &&
                       (paired_hold ? received_bytes[31:2]==voice_last_byte_hold[31:2]:
                                      received_bytes[31:1]==voice_last_byte_hold[31:1]);
                      case(byte_phase)
                       0:begin low_byte<=byte_data;packed_bytes[7:0]<=byte_data;end
                       1:packed_bytes[15:8]<=byte_data;
                       2:packed_bytes[23:16]<=byte_data;
                      endcase
                      if(frame_byte_last)byte_phase<=0;else byte_phase<=byte_phase+1'b1;
                  end
                  // The last accepted byte is already counted before checking
                  // EOF on the next clock, including simultaneous EOF/data.
                  if(file_done) state<=EOF_CHECK;
              end
              EOF_CHECK: begin
                      if(received_bytes!=size_latched) begin
                          error<=8'h42; pcm_ready<=0; flush_req<=1; start_pending<=0; state<=FLUSH_HIGH;
                          sample_accepted<=0; prefill_met<=0;
                      end else state<=DRAIN;
              end
              DRAIN: begin end
              default: state<=IDLE;
            endcase
            if(done2!=done_seen) begin
                done_seen<=done2;
                if((state==LOAD || state==EOF_CHECK || state==DRAIN) && !cancel) begin
                    if(paired_hold&&!voice_retired_clk&&voice_has_tail)begin
                        // The original reliable done toggle first retires voice,
                        // then retires the complete pair stream (music tail).
                        voice_done<=1;voice_retired_clk<=1;
                    end else begin
                        if(!music_only_hold&&!voice_retired_clk)voice_done<=1;
                        voice_retired_clk<=1;play_done<=1;pcm_ready<=0;state<=IDLE;
                        sample_accepted<=0;prefill_met<=0;
                    end
                end
            end
            if(err2!=err_seen) begin
                err_seen<=err2;
                if(state==LOAD || state==EOF_CHECK || state==DRAIN) begin
                    error<=8'h43; pcm_ready<=0; flush_req<=1; start_pending<=0; state<=FLUSH_HIGH;
                    sample_accepted<=0; prefill_met<=0;
                end
            end
            if(cancel && state!=IDLE) begin
                mix_pending<=0;mix_raw_valid<=0;mix_product_valid<=0;
                pcm_ready<=0; flush_req<=1; start_pending<=0; state<=FLUSH_HIGH;
                sample_accepted<=0; prefill_met<=0;
            end
            if(state==IDLE||state==FLUSH_HIGH||state==FLUSH_LOW)begin
                mix_pending<=0;mix_raw_valid<=0;mix_product_valid<=0;
            end
        end
    end

    always @(posedge audio_mclk or posedge audio_rst) begin
        if(audio_rst) begin
            flush1<=1; flush2<=1; flush_audio<=1; cmd1<=0; cmd2<=0; cmd_seen<=0;
            en1<=0; en2<=0; ready1<=0; ready2<=0;
            active_audio<=0; playing_audio<=0; samples_left<=0;
            look_valid<=0; read_pending<=0; look_sample<=0;
            current_sample<=0; shift_reg<=0; bit_count<=0;
            frame_valid<=0; frame_last<=0; done_toggle<=0; error_toggle<=0;
            voice_retired_audio<=0;frame_voice_last<=0;
            i2s_bclk<=0; i2s_lrck<=0; i2s_dout<=0;
            playback_id_audio<=0; playback_generation_audio<=0;
            playback_ticks_audio<=0; playback_subsample<=0; playback_running_audio<=0;
        end else begin
            flush1<=flush_req; flush2<=flush1; flush_audio<=flush2;
            cmd1<=command_toggle; cmd2<=cmd1;
            en1<=play_enable; en2<=en1; ready1<=pcm_ready; ready2<=ready1;
            i2s_bclk<=~i2s_bclk;
            // Mirror the original serializer: update data on BCLK falling edges,
            // 64 bits per channel, 24 high-order sample bits followed by zero padding.
            if(i2s_bclk) begin
                i2s_dout<=shift_reg[15]; shift_reg<={shift_reg[14:0],1'b0};
                if(bit_count==63) begin
                    bit_count<=0;
                    if(!i2s_lrck) begin
                        i2s_lrck<=1; shift_reg<=current_sample[23:8];
                    end else begin
                        i2s_lrck<=0; current_sample<=0; shift_reg<=0; frame_valid<=0;frame_voice_last<=0;
                        if(frame_valid&&frame_voice_last)begin
                            // Non-final voice marker retires through the existing done CDC.
                            if(!frame_last)done_toggle<=~done_toggle;
                            voice_retired_audio<=1;playback_running_audio<=0;
                        end
                        if(frame_valid && frame_last) begin
                            done_toggle<=~done_toggle; active_audio<=0; playing_audio<=0;
                            playback_running_audio<=0;
                        end else if(active_audio && en2 && ready2 && !flush2) begin
                            if(look_valid) begin
                                current_sample<={volume_sample,8'd0}; shift_reg<=volume_sample;
                                look_valid<=0; frame_valid<=1; frame_last<=samples_left==1;
                                samples_left<=samples_left-1; playing_audio<=1;
                                frame_voice_last<=look_sample[16];
                                // Observer only: count actual valid mono samples entering I2S.
                                if(!playing_audio)begin
                                    playback_running_audio<=!voice_retired_audio&&!frame_voice_last&&!music_only_audio;
                                    playback_generation_audio<=playback_generation_audio+1'b1;
                                    playback_ticks_audio<=0;playback_subsample<=1;
                                end else if(!voice_retired_audio&&!frame_voice_last&&!music_only_audio)begin
                                    playback_subsample<=playback_subsample+1'b1;
                                    if(playback_subsample==8'hff)playback_ticks_audio<=playback_ticks_audio+1'b1;
                                end
                            end else if(playing_audio) begin
                                error_toggle<=~error_toggle; active_audio<=0; playing_audio<=0;
                                playback_running_audio<=0;
                            end
                        end
                    end
                end else bit_count<=bit_count+1;
            end
            if(fifo_read) read_pending<=1;
            if(read_pending) begin look_sample<=fifo_data; look_valid<=1; read_pending<=0; end
            if(cmd2!=cmd_seen) begin
                cmd_seen<=cmd2; samples_left<=expected_samples; active_audio<=1;
                voice_retired_audio<=0;
                frame_voice_last<=0;
                playback_id_audio<=narration_id_hold;playback_ticks_audio<=0;
                playback_subsample<=0;playback_running_audio<=0;
                playing_audio<=0; look_valid<=0; read_pending<=0; frame_valid<=0; frame_last<=0;
            end
            if(flush2) begin
                playback_running_audio<=0;
                active_audio<=0; playing_audio<=0; look_valid<=0; read_pending<=0;
                current_sample<=0; shift_reg<=0; frame_valid<=0; frame_last<=0;frame_voice_last<=0;voice_retired_audio<=0;
            end
        end
    end
endmodule

`default_nettype wire
