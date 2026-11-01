`default_nettype none
`timescale 1ns/1ps
// integration: four-slot cache, sequential FAT/BMP/PCM media.
// No TF image reads during PCM playback. T4 preloads GO before WAIT audio.
module recovery_media_controller #(
 parameter integer TIMEOUT_CYCLES=200000000,
 parameter integer IMAGE_WIDTH=640,IMAGE_HEIGHT=480,
 parameter integer REQUEST_EFFECT_ENABLE=0,
 parameter integer KEEP_PREVIOUS_ENABLE=0,
 parameter integer VOLUME_ENABLE=0
)(
 input wire clk,rst,audio_mclk,audio_rst,input wire mem_ready,
 input wire cmd_valid,output wire cmd_ready,input wire [5:0] cmd_scene,input wire cancel,
 input wire [1:0] cmd_question_set,output wire [30:0] caption_audio_data,output wire caption_audio_rst,
 input wire skip_audio_wait,
 input wire skip_page_request,
 output reg scene_done,output reg scene_presented,output reg media_error,
 output reg [7:0] last_error,output reg [5:0] live_scene,output reg [7:0] epoch,
 output reg device_reset,output wire audio_active,output wire [3:0] bank_valid,
 input wire [3:0] protect_mask,
 output wire commit_valid,input wire commit_ready,output wire [1:0] commit_bank,
 output wire [5:0] commit_scene,output wire [7:0] commit_epoch,
 input wire presented,input wire present_error,input wire [5:0] presented_scene,input wire [7:0] presented_epoch,
 output reg write_req,input wire write_req_ack,output wire [1:0] write_bank,
 output wire write_en,output wire [31:0] write_data,input wire write_full,input wire write_finish,
 output wire SD_nCS,SD_DCLK,SD_MOSI,input wire SD_MISO,
 output wire [7:0] debug_state,output wire i2s_bclk,i2s_lrck,i2s_dout,
 input wire [1:0] cmd_effect,output wire [1:0] commit_effect,input wire [8:0] volume_gain,
 output wire voice_active,output wire music_active,output reg voice_complete
);

localparam IDLE=0,LOAD_REQ=1,WAIT_IMAGE=2,COMMIT=3,WAIT_PRESENT=4,
  PRE_REQ=5,PRE_WAIT=6,AUDIO_START=7,AUDIO_READY=8,PLAY=9,CANCEL_WAIT=10,RECOVER=11,AUDIO_FALLBACK_WAIT=12;
localparam [31:0] WATCHDOG_LIMIT=TIMEOUT_CYCLES-1;
// Positive bounded configurations recover before any unused upper bit can
// influence an interface. Keep the full original modulo32 counter for zero,
// one, signed/large parameter edge cases; use 28bits at the production2s limit.
localparam integer WATCHDOG_BITS=(TIMEOUT_CYCLES>1&&TIMEOUT_CYCLES<1073741824)?$clog2(TIMEOUT_CYCLES+1):32;
wire [3:0] state;
reg [12:0] state_hot;
reg [WATCHDOG_BITS-1:0] watchdog;
reg [3:0] reset_count;
reg watchdog_expired;
wire watchdog_increment_expired;
reg [1:0] selected_bank;
reg file_start,file_cancel,file_audio;
reg image_active,write_started,write_ack_seen,decode_seen,write_seen;
reg [5:0] image_target;
reg play_enable;
reg manager_cancel;
reg done_sent;
reg paired_file,music_file,music_track,paired_started;
reg page_skip_latched;
wire teaching_scene,teaching_skip,teaching_retiring;
reg [1:0] live_effect;
reg scene_music_loop,skip_response_scene,scene_no_audio,scene_wait,scene_go;
reg [5:0] live_image_id,live_go_image_id;
reg [5:0] load_target;
reg shown_valid,previous_valid,report_image_valid;
reg [5:0] shown_scene,previous_scene,last_report_scene;
wire load_ready,loader_start,image_ready,cache_hit,load_busy;
wire [1:0] loader_bank,ready_bank;
wire [5:0] loader_image,ready_image;
wire [7:0] loader_epoch,ready_epoch,load_error;
wire file_busy,file_begin,file_done,byte_valid,byte_ready;
wire [7:0] byte_data,file_error;
wire [31:0] file_size;
wire bmp_byte_ready,header_ok,pixel_valid,decoder_done;
wire [23:0] pixel_rgb;
wire [7:0] bmp_error;
wire pcm_byte_ready,pcm_ready,pcm_done,pcm_busy,pcm_voice_done;
wire [7:0] pcm_error;
wire [31:0] voice_samples;
wire optional_music;
wire pair_size_ok;
wire fallback_missing;
wire fallback_format;
wire [87:0] file_name;
wire audio_none;
wire sector_req,sector_ready,sector_valid,sector_done;
wire [31:0] sector_lba;
wire [7:0] sector_byte,sector_error;
wire [8:0] sector_index;
wire sd_init,sd_read,sd_byte_valid,sd_end;
wire [31:0] sd_addr;
wire [7:0] sd_byte;
wire sub_rst;
wire local_audio_rst;
wire do_load;
wire [5:0] target;
wire [5:0] rom_scene;
wire audio_open;
wire [6:0] audio_name_key;
wire [6:0] loader_name_key;
wire [6:0] retained_name_key;
wire [6:0] name_key;
wire [5:0] playback_id_audio;
wire [7:0] playback_generation_audio;
wire [15:0] playback_ticks_audio;
wire playback_running_audio;
wire [5:0] caption_identity;
wire [7:0] loader_error;
wire optional_music_stop;
wire required_file_fault;
wire normal_fault_state;
wire fault_any;
reg navigation_previous_valid,live_welcome_scene,live_report_scene;
reg [5:0] navigation_keep_scene;
wire keep_valid;
wire [5:0] keep_scene;
wire sd_sec_read_error;
// Continuous values retain the original net initializer expressions.
assign watchdog_increment_expired = (WATCHDOG_BITS<32)?
  (watchdog_expired||watchdog==WATCHDOG_LIMIT-32'd1):
  (WATCHDOG_LIMIT==0)?1'b1:((watchdog!=32'hffffffff)&&(watchdog>=WATCHDOG_LIMIT-32'd1));
assign optional_music = music_file;
assign pair_size_ok = !paired_file || (file_size==((voice_samples+32'd240000)<<2));
assign fallback_missing = paired_file&&!paired_started&&(file_error==8'h26||file_error==8'h27);
assign fallback_format = paired_file&&file_begin&&file_audio&&!pair_size_ok;
assign sub_rst = rst|device_reset;
assign do_load = (state_hot[LOAD_REQ]||state_hot[PRE_REQ]);
assign target = load_target;
assign rom_scene = file_audio?live_image_id:image_target;
assign audio_open = state_hot[AUDIO_START]&&!(cmd_valid&&done_sent)&&!file_busy&&!pcm_busy;
// Teaching bit90 means this narration lifecycle has ended, either by natural
// EOF or by explicit user skip AFTER the existing PCM flush handshake. Merely
// enabling KEY1 never completes teaching. Once accepted, a request survives a
// later mode-off until retirement; it is not a request for another transaction.
assign teaching_skip = teaching_scene&&!done_sent&&
  (page_skip_latched||(skip_audio_wait&&skip_page_request===1'b1));
assign teaching_scene = live_scene==6'd1||(live_scene>=6'd9&&live_scene<=6'd11);
// Only an unfinished teaching lifecycle enters CANCEL_WAIT by explicit skip;
// replacements already have done_sent. Global cancel/fault set it as well.
assign teaching_retiring = teaching_scene&&!done_sent;
assign audio_name_key = filename_key(live_image_id,1'b1,paired_file,music_file,music_track);
assign loader_name_key = filename_key(loader_image,1'b0,1'b0,1'b0,1'b0);
assign retained_name_key = filename_key(rom_scene,file_audio,paired_file,music_file,music_track);
assign name_key = audio_open?audio_name_key:loader_start?loader_name_key:retained_name_key;
assign caption_identity = (playback_id_audio==6'd50)?6'd49:playback_id_audio;
assign loader_error = (image_active&&bmp_error!=0)?bmp_error:
  (image_active&&file_busy&&!file_audio&&file_error!=0)?file_error:8'd0;
assign optional_music_stop = (file_error!=0||pcm_error!=0)&&!file_start&&optional_music&&
  (state_hot[AUDIO_READY]||state_hot[PLAY]);
assign required_file_fault = file_error!=0&&!file_start&&!fallback_missing&&
  (file_busy||state_hot[AUDIO_READY]||state_hot[PLAY]);
assign normal_fault_state = !state_hot[IDLE]&&!state_hot[CANCEL_WAIT]&&!state_hot[RECOVER];
assign fault_any = (state_hot[IDLE]&&cmd_valid&&!mem_ready&&watchdog_expired)||
  (!cancel&&(
   (present_error&&!state_hot[CANCEL_WAIT]&&!state_hot[RECOVER])||
   (normal_fault_state&&((loader_error!=0)||
    (!optional_music_stop&&(required_file_fault||(pcm_busy&&pcm_error!=0)||(load_error!=0)||watchdog_expired))))||
   (state_hot[CANCEL_WAIT]&&watchdog_expired)));
assign keep_valid = navigation_previous_valid||
  (live_welcome_scene&&report_image_valid)||live_report_scene||previous_valid;
assign keep_scene = navigation_previous_valid?navigation_keep_scene:
  (live_welcome_scene&&report_image_valid)?last_report_scene:
  live_report_scene?6'd0:previous_scene;

 
 
 // Ordinary control reads registered parallel flags. The unchanged numeric
 // debug state is a parallel OR of those flags, with no binary next-state D
 // mux/register or feedback decode cone.
 
 assign state[0]=state_hot[1]|state_hot[3]|state_hot[5]|state_hot[7]|state_hot[9]|state_hot[11];
 assign state[1]=state_hot[2]|state_hot[3]|state_hot[6]|state_hot[7]|state_hot[10]|state_hot[11];
 assign state[2]=state_hot[4]|state_hot[5]|state_hot[6]|state_hot[7]|state_hot[12];
 assign state[3]=state_hot[8]|state_hot[9]|state_hot[10]|state_hot[11]|state_hot[12];
 
 // Exactly mirror the original unsigned 32-bit >= TIMEOUT_CYCLES-1 test.
 // Predict from the previous value without adding then comparing. The wrap
 // guard preserves every parameter bit pattern, including TIMEOUT_CYCLES=0/1.
 
 
 
 
 
 
 
 
 
 
 
 // Select the load identity at the preceding command/presentation boundary,
 // so the cache's four comparisons do not follow a late PRE_REQ target mux.
 
 function [5:0] material_id;
  input [5:0] logical_scene;input [1:0] question_set;
  begin
   if(logical_scene>=13&&logical_scene<=21)begin
    case(question_set)
     2'd1:material_id=logical_scene+6'd18;
     2'd2:material_id=logical_scene+6'd27;
     default:material_id=logical_scene;
    endcase
   end else material_id=logical_scene;
  end
 endfunction
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 // Only patient response pages unlock early. Automatic narration/education
 // retains its established cadence; the application offers explicit manual
 // teaching navigation when KEY1 has enabled the session option.
 recovery_reset_sync u_audio_reset(audio_mclk,audio_rst|device_reset,local_audio_rst);
 
 
 
 // File start is already registered. Resolve its name at the same earlier
 // edge, using the accepted loader/audio request rather than stale target.
 // AUDIO_START follows the loader block in the original control process,
 // so it retains priority if both requests are presented on one edge.
 
 function [6:0] filename_key;
  input [5:0] id;input audio,paired,music,track;
  begin
   filename_key=(id<6'd50)?{audio,id}:7'd0;
   if(audio&&(music===1'b1))filename_key=(track===1'b1)?7'd51:7'd50;
   else if(audio&&(paired===1'b1))begin
    case(id)
     6'd23:filename_key=7'd52;6'd24:filename_key=7'd53;
     6'd25:filename_key=7'd54;6'd26:filename_key=7'd55;
    endcase
   end
  end
 endfunction
 // Decode the three stable metadata branches in parallel. Late open/loader
 // qualification selects only the completed seven-bit ROM address; it does
 // not feed the filename range, music or paired-stream decode anymore.
 
 
 
 
 recovery_asset_filename_rom u_file_names(.clk(clk),.address(name_key),.file_name(file_name));
 
 
 
 assign caption_audio_data={playback_running_audio,caption_identity,playback_generation_audio,playback_ticks_audio};
 assign caption_audio_rst=local_audio_rst;
 
 // The one-bit fault pulse needs no priority-encoded error-code selection.
 // Keep the original task/branch ordering for every recovery side effect.
 // IDLE timeout precedes global cancel in that process and its pulse survives
 // cancel, while the later global fault branches are suppressed by cancel.
 
 
 
 
 assign cmd_ready=state_hot[IDLE]&&mem_ready&&!file_busy&&!pcm_busy&&!load_busy&&!cancel&&!device_reset;
 assign debug_state={4'd0,state};assign audio_active=pcm_busy;
 assign commit_valid=state_hot[COMMIT]&&!cancel;assign commit_bank=selected_bank;
 assign commit_scene=live_scene;assign commit_epoch=epoch;
 assign commit_effect=scene_go ? 2'd0 : live_effect;
 
 
 function [5:0] navigation_previous;
  input [5:0] scene;begin case(scene)
   6'd9:navigation_previous=6'd9;
   6'd10:navigation_previous=6'd9;
   6'd11:navigation_previous=6'd10;
   6'd12:navigation_previous=6'd11;
   6'd23:navigation_previous=6'd26;
   6'd24:navigation_previous=6'd23;
   6'd25:navigation_previous=6'd24;
   6'd26:navigation_previous=6'd25;
   default:navigation_previous=previous_scene;
  endcase end
 endfunction
 // Retain only existing complete images. No speculative SD request or
 // background writer is introduced, and PCM keeps exclusive SD ownership.
 
 
 assign write_bank=loader_bank;assign write_en=image_active&&write_started&&pixel_valid&&!write_full;
 assign write_data={pixel_rgb,8'd0};
 assign byte_ready=file_audio?pcm_byte_ready:bmp_byte_ready;
 recovery_asset_rom u_names(.scene(rom_scene),.audio_select(file_audio),.file_name(),.audio_none(audio_none),
  .paired_select(paired_file),.music_select(music_file),.music_track(music_track),.voice_samples(voice_samples));
 
sd_card_top u_sd(.clk(clk),.rst(sub_rst),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),
  .sd_init_done(sd_init),.sd_sec_read(sd_read),.sd_sec_read_addr(sd_addr),.sd_sec_read_data(sd_byte),
  .sd_sec_read_error(sd_sec_read_error),.sd_sec_read_data_valid(sd_byte_valid),.sd_sec_read_end(sd_end),.sd_sec_write(1'b0),
  .sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
 recovery_sector_adapter #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_sector(.clk(clk),.rst(sub_rst),
  .sector_req(sector_req),.sector_lba(sector_lba),.sector_ready(sector_ready),.sector_byte_valid(sector_valid),
  .sector_byte(sector_byte),.sector_byte_index(sector_index),.sector_done(sector_done),.sector_error(sector_error),
  .sd_init_done(sd_init),.sd_sec_read(sd_read),.sd_sec_read_addr(sd_addr),.sd_sec_read_data(sd_byte),
  .sd_sec_read_error(sd_sec_read_error),.sd_sec_read_data_valid(sd_byte_valid),.sd_sec_read_end(sd_end));
 recovery_file_reader #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_file(.clk(clk),.rst(sub_rst),.start(file_start),.cancel(file_cancel),
  .file_name(file_name),.busy(file_busy),.file_begin(file_begin),.file_size(file_size),.byte_valid(byte_valid),
  .byte_data(byte_data),.byte_ready(byte_ready),.file_done(file_done),.error(file_error),.sector_req(sector_req),
  .sector_lba(sector_lba),.sector_ready(sector_ready),.sector_byte_valid(sector_valid),.sector_byte(sector_byte),
  .sector_byte_index(sector_index),.sector_done(sector_done),.sector_error(sector_error));
 recovery_bmp_decoder #(.WIDTH(IMAGE_WIDTH),.HEIGHT(IMAGE_HEIGHT)) u_bmp(.clk(clk),.rst(sub_rst),.start(file_begin&&!file_audio),.file_size(file_size),
  .byte_valid(byte_valid&&!file_audio),.byte_data(byte_data),.byte_ready(bmp_byte_ready),
  .file_done(file_done&&!file_audio),.upstream_error(file_audio?8'd0:file_error),.header_ok(header_ok),
  .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_ready(write_started&&!write_full),
  .frame_done(decoder_done),.error(bmp_error));
 recovery_pcm_player #(.VOLUME_ENABLE(VOLUME_ENABLE)) u_pcm(.clk(clk),.rst(sub_rst),.audio_mclk(audio_mclk),.audio_rst(local_audio_rst),
  .start(file_begin&&file_audio&&pair_size_ok),.cancel(file_cancel),.file_size(file_size),.byte_valid(byte_valid&&file_audio),
  .byte_data(byte_data),.byte_ready(pcm_byte_ready),.file_done(file_done&&file_audio),.play_enable(play_enable),
  .busy(pcm_busy),.pcm_ready(pcm_ready),.play_done(pcm_done),.error(pcm_error),
  .i2s_bclk(i2s_bclk),.i2s_lrck(i2s_lrck),.i2s_dout(i2s_dout),.volume_gain(volume_gain),
  .narration_id(live_image_id),.playback_id_audio(playback_id_audio),
  .playback_generation_audio(playback_generation_audio),.playback_ticks_audio(playback_ticks_audio),
  .playback_running_audio(playback_running_audio),.paired_mode(paired_file),.music_only(music_file),
  .voice_sample_count(voice_samples),.voice_done(pcm_voice_done),.voice_active(voice_active),.music_active(music_active));
 frame_bank_manager #(.KEEP_PREVIOUS_ENABLE(KEEP_PREVIOUS_ENABLE)) u_banks(.clk(clk),.rst(sub_rst),.current_epoch(epoch),.cancel(manager_cancel),
  .load_req(do_load&&!cancel),.load_image_id(target),.load_req_ready(load_ready),.protect_mask(protect_mask),
  .loader_start(loader_start),.loader_bank(loader_bank),.loader_image_id(loader_image),.loader_epoch(loader_epoch),
  .decoder_done(decoder_done),.frame_write_finish(write_finish),.loader_error(loader_error),.loader_idle(!image_active),
  .image_ready(image_ready),.ready_bank(ready_bank),.ready_image_id(ready_image),.ready_epoch(ready_epoch),
  .cache_hit(cache_hit),.load_error(load_error),.load_busy(load_busy),.bank_valid(bank_valid),
  .keep_image_valid(keep_valid),.keep_image_id(keep_scene));
 task set_state;input [3:0] next_state;begin
  state_hot<=13'b1<<next_state;
 end endtask
 task fault;input [7:0] code;begin
  last_error<=code;file_cancel<=1;manager_cancel<=1;play_enable<=0;
  voice_complete<=0;page_skip_latched<=0;done_sent<=1;
  epoch<=epoch+1;device_reset<=1;reset_count<=0;image_active<=0;write_req<=0;write_started<=0;write_ack_seen<=0;set_state(RECOVER);
 end endtask
 // The existing latched explicit request is also the retirement ownership
 // bit. Global cancel/fault/new command already clear it; no second lifecycle
 // register or post-case override mux is needed. Only audio states call this.
 task retire_teaching;begin
  file_cancel<=1;play_enable<=0;
  watchdog<=0;watchdog_expired<=(WATCHDOG_LIMIT==0);set_state(CANCEL_WAIT);
 end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin set_state(IDLE);watchdog<=0;watchdog_expired<=(WATCHDOG_LIMIT==0);reset_count<=0;selected_bank<=0;file_start<=0;file_cancel<=0;file_audio<=0;
   image_active<=0;write_started<=0;write_ack_seen<=0;decode_seen<=0;write_seen<=0;image_target<=0;play_enable<=0;done_sent<=0;
   manager_cancel<=0;scene_done<=0;scene_presented<=0;media_error<=0;last_error<=0;live_scene<=0;
   epoch<=0;device_reset<=0;write_req<=0;live_effect<=0;page_skip_latched<=0;
   shown_valid<=0;previous_valid<=0;report_image_valid<=0;
   shown_scene<=0;previous_scene<=0;last_report_scene<=0;live_image_id<=0;live_go_image_id<=0;load_target<=0;
   navigation_previous_valid<=0;navigation_keep_scene<=0;live_welcome_scene<=0;live_report_scene<=0;
   paired_file<=0;music_file<=0;music_track<=0;paired_started<=0;voice_complete<=0;
   scene_music_loop<=0;skip_response_scene<=0;scene_no_audio<=0;scene_wait<=0;scene_go<=0;
  end else begin
   file_start<=0;file_cancel<=0;manager_cancel<=0;scene_done<=0;scene_presented<=0;media_error<=fault_any;
   if(skip_page_request===1'b1&&(!teaching_scene||skip_audio_wait))page_skip_latched<=1;
   if((!state_hot[IDLE]&&!state_hot[RECOVER])||(state_hot[IDLE]&&cmd_valid&&!mem_ready))begin
    if(byte_valid&&byte_ready||decoder_done||write_finish||image_ready||presented)begin
     watchdog<=0;watchdog_expired<=(WATCHDOG_LIMIT==0);
    end else begin watchdog<=watchdog+1;watchdog_expired<=watchdog_increment_expired;end
   end else begin watchdog<=0;watchdog_expired<=(WATCHDOG_LIMIT==0);end
   if(loader_start)begin
    image_active<=1;image_target<=loader_image;file_audio<=0;file_start<=1;
    decode_seen<=0;write_seen<=0;write_started<=0;write_ack_seen<=0;write_req<=0;
   end
   if(image_active)begin
    if(header_ok)write_req<=1;
    if(write_req&&write_req_ack)begin write_req<=0;write_ack_seen<=1;end
    // The frozen writer clears its FIFO throughout ACK. Wait for ACK to fall
    // after withdrawing request before releasing the first pixel.
    if(write_ack_seen&&!write_req_ack)write_started<=1;
    if(decoder_done)decode_seen<=1;
    if(write_finish)write_seen<=1;
    if((decode_seen||decoder_done)&&(write_seen||write_finish)&&!file_busy)begin image_active<=0;write_started<=0;write_ack_seen<=0;end
   end
   case(1'b1) // synthesis parallel_case
    state_hot[IDLE]:begin
     if(cmd_valid&&!mem_ready&&watchdog_expired)fault(8'h64);
     else if(cmd_valid&&cmd_ready)begin
      live_scene<=cmd_scene;last_error<=0;set_state(LOAD_REQ);done_sent<=0;page_skip_latched<=0;
      // Narration and REST retest prompts use their original mono PCM only.
      // RELAX is the sole rest/music page; no paired narration/music is used.
      scene_music_loop<=cmd_scene==6'd49;
      skip_response_scene<=(cmd_scene>=6'd2&&cmd_scene<=6'd6)||
       (cmd_scene>=6'd12&&cmd_scene<=6'd18)||cmd_scene==6'd20||cmd_scene==6'd21||cmd_scene==6'd27||cmd_scene==6'd28;
      scene_no_audio<=cmd_scene==6'd19||cmd_scene==6'd29||cmd_scene==6'd30;
      scene_wait<=cmd_scene==6'd18;scene_go<=cmd_scene==6'd19;
      paired_file<=0;music_file<=cmd_scene==49;
      paired_started<=0;voice_complete<=0;
      live_image_id<=material_id(cmd_scene,cmd_question_set);
      load_target<=material_id(cmd_scene,cmd_question_set);
      live_go_image_id<=material_id(6'd19,cmd_question_set);
      navigation_previous_valid<=(cmd_scene>=9&&cmd_scene<=12)||(cmd_scene>=23&&cmd_scene<=26);
      navigation_keep_scene<=navigation_previous(cmd_scene);
      live_welcome_scene<=cmd_scene==0;live_report_scene<=cmd_scene==8||cmd_scene==22;
      live_effect<=(REQUEST_EFFECT_ENABLE!=0&&cmd_scene!=19)?
       ((cmd_effect!=3||(cmd_scene>=2&&cmd_scene<=6)||cmd_scene==28||
          (cmd_scene>=13&&cmd_scene<=21))?cmd_effect:2'd0):2'd0;
     end
    end
    state_hot[LOAD_REQ]:if(load_ready)set_state(WAIT_IMAGE);
    state_hot[WAIT_IMAGE]:if(image_ready&&ready_epoch==epoch)begin selected_bank<=ready_bank;set_state(COMMIT);end
    state_hot[COMMIT]:if(commit_ready)set_state(WAIT_PRESENT);
    state_hot[WAIT_PRESENT]:if(presented&&presented_epoch==epoch&&presented_scene==live_scene)begin
     scene_presented<=1;
     if(!shown_valid||shown_scene!=live_image_id)begin
      previous_valid<=shown_valid;previous_scene<=shown_scene;
      shown_valid<=1;shown_scene<=live_image_id;
     end
     if(live_report_scene)begin report_image_valid<=1;last_report_scene<=live_scene;end
     if(scene_wait)begin load_target<=live_go_image_id;set_state(PRE_REQ);end
     else if(scene_no_audio)begin scene_done<=1;set_state(IDLE);end
     else set_state(AUDIO_START);
    end
    state_hot[PRE_REQ]:if(load_ready)set_state(PRE_WAIT);
    state_hot[PRE_WAIT]:if(image_ready&&ready_epoch==epoch)set_state(AUDIO_START);
    state_hot[AUDIO_START]:if(teaching_skip)retire_teaching;
     else if(cmd_valid&&done_sent)begin file_cancel<=1;play_enable<=0;set_state(CANCEL_WAIT);end
     else if(!file_busy&&!pcm_busy)begin file_audio<=1;file_start<=1;set_state(AUDIO_READY);end
    state_hot[AUDIO_READY]:if(teaching_skip)retire_teaching;
     else if(cmd_valid&&done_sent)begin file_cancel<=1;play_enable<=0;set_state(CANCEL_WAIT);end
     else if(pcm_ready)begin
     play_enable<=1;set_state(PLAY);
     if(music_file&&!done_sent)begin scene_done<=1;done_sent<=1;voice_complete<=1;end
     if(!teaching_scene&&skip_audio_wait&&(skip_response_scene||page_skip_latched||skip_page_request===1'b1))begin scene_done<=1;done_sent<=1;end
    end
    state_hot[PLAY]:begin
     if(teaching_skip)retire_teaching;
     else begin
     if(pcm_voice_done)begin
      voice_complete<=1;
      if(!done_sent)begin scene_done<=1;done_sent<=1;end
     end
     if(pcm_done)begin
      play_enable<=0;
      if(scene_music_loop)begin
       // Music EOF is never another business DONE. One shared FAT owner is
       // reused after EOF; short silent loop/switch gaps are intentional.
       if(!done_sent&&!music_file)begin scene_done<=1;done_sent<=1;voice_complete<=1;end
       paired_file<=0;music_file<=1;paired_started<=0;music_track<=~music_track;set_state(AUDIO_START);
      end else begin if(!done_sent)scene_done<=1;voice_complete<=1;set_state(IDLE);end
     end
     else if(cmd_valid&&done_sent)begin
      // A replacement has not handshaken yet. Cancel the old PCM/FAT owner
      // at its existing sample boundary, then hold ready low until it drains.
      // Complete cached images and T4 GO prefetch remain valid in this epoch.
      file_cancel<=1;play_enable<=0;watchdog<=0;watchdog_expired<=(WATCHDOG_LIMIT==0);set_state(CANCEL_WAIT);
     end else if(!teaching_scene&&skip_audio_wait&&(skip_response_scene||page_skip_latched||skip_page_request===1'b1)&&!done_sent)begin
      scene_done<=1;done_sent<=1;
     end
     end
    end
    state_hot[CANCEL_WAIT]:if(!file_busy&&!pcm_busy&&!image_active&&!load_busy)begin
     if(teaching_retiring)begin
      voice_complete<=1;
      scene_done<=1;done_sent<=1;
     end
     page_skip_latched<=0;set_state(IDLE);
    end
    state_hot[AUDIO_FALLBACK_WAIT]:if(!file_busy&&!pcm_busy)set_state(AUDIO_START);
    state_hot[RECOVER]:begin
     if(device_reset)begin
      if(reset_count==15)begin device_reset<=0;reset_count<=0;end
      else reset_count<=reset_count+1;
     end else if(!file_busy&&!pcm_busy&&mem_ready)set_state(IDLE);
    end
   endcase
   if(file_begin&&file_audio&&paired_file&&pair_size_ok)paired_started<=1;
   // Only missing/invalid unopened pairs fall back to the untouched narration.
   // Once a pair starts, a read error also corrupts required voice and is fatal.
   if(state_hot[AUDIO_READY]&&(fallback_missing||fallback_format))begin
    file_cancel<=1;play_enable<=0;paired_file<=0;paired_started<=0;
    watchdog<=0;watchdog_expired<=(WATCHDOG_LIMIT==0);set_state(AUDIO_FALLBACK_WAIT);
   end
   // On ordinary cancellation let a valid image load drain completely. Partial
   // failed loads instead use a bounded media/SDRAM-path reset, invalidating cache.
   if(cancel&&!state_hot[RECOVER])begin
    page_skip_latched<=0;done_sent<=1;
    voice_complete<=0;
    epoch<=epoch+1;manager_cancel<=1;play_enable<=0;
    // loader_start is consumed above on this same edge. That accepted image
    // must drain too; cancelling its FAT start would strand image_active.
    if(!image_active&&!loader_start)file_cancel<=1;
    set_state(CANCEL_WAIT);watchdog<=0;watchdog_expired<=(WATCHDOG_LIMIT==0);scene_done<=0;scene_presented<=0;
   end else if(present_error&&!state_hot[CANCEL_WAIT]&&!state_hot[RECOVER])fault(8'h61);
   else if(!state_hot[IDLE]&&!state_hot[CANCEL_WAIT]&&!state_hot[RECOVER])begin
    if(loader_error!=0)fault(loader_error);
    else if((file_error!=0||pcm_error!=0)&&!file_start&&optional_music&&(state_hot[AUDIO_READY]||state_hot[PLAY]))begin
     // A failed independent music stream is optional; keep page/deadline/keys.
     file_cancel<=1;play_enable<=0;
     if(!done_sent)begin scene_done<=1;done_sent<=1;voice_complete<=1;end
     set_state(CANCEL_WAIT);
    end
    else if(file_error!=0&&!file_start&&!fallback_missing&&
      (file_busy||state_hot[AUDIO_READY]||state_hot[PLAY]))fault(file_error);
    else if(pcm_busy&&pcm_error!=0)fault(pcm_error);
    else if(present_error)fault(8'h61);
    else if(load_error!=0)fault(load_error);
    else if(watchdog_expired)fault(8'h62);
   end else if(state_hot[CANCEL_WAIT]&&watchdog_expired)fault(8'h63);
  end
 end
endmodule

//128x49 synchronous short-name lookup. All original128 constants are checked
//before packing. Each body character has bit7=0 and bit6=~bit5; BMP/PCM needs
//one extension bit. Register the packed word, then restore the same88 bits.
module recovery_asset_filename_rom(input wire clk,input wire [6:0]address,output wire [87:0]file_name);

(* rom_style="bram_9k" *) reg[48:0] names[0:127];
reg[48:0] packed_name;
// Continuous values retain the original net initializer expressions.


 
 
 initial begin
  names[0]=49'h0b8a60679a2c0; //WELCOME BMP
  names[1]=49'h08021aa3aa488; //PACUGUIDBMP
  names[2]=49'h08021aa182618; //PACUCALLBMP
  names[3]=49'h08021aa90a840; //PACUREP BMP
  names[4]=49'h08021aa60291a; //PACULARMBMP
  names[5]=49'h08021aa90291a; //PACURARMBMP
  names[6]=49'h08021aa61828e; //PACULLEGBMP
  names[7]=49'h08021aa09891a; //PACUALRMBMP
  names[8]=49'h08021aa926628; //PACURSLTBMP
  names[9]=49'h060a0a47162b2; //LEARNKEYBMP
  names[10]=49'h060a0a4710608; //LEARNHLDBMP
  names[11]=49'h060a0a472c4a6; //LEARNVISBMP
  names[12]=49'h090a088cc1040; //READY   BMP
  names[13]=49'h0a628e3041040; //T1Q1    BMP
  names[14]=49'h0a628e5041040; //T1Q2    BMP
  names[15]=49'h0a6472a6c1040; //T2NUM   BMP
  names[16]=49'h0a6498268b040; //T2SAME  BMP
  names[17]=49'h0a666129a829c; //T3LISTENBMP
  names[18]=49'h0a68b824a9040; //T4WAIT  BMP
  names[19]=49'h0a6839f041040; //T4GO    BMP
  names[20]=49'h0a6a41e609040; //T5HOLD  BMP
  names[21]=49'h0a6c80249d040; //T6PAIN  BMP
  names[22]=49'h090a9aa6289c0; //RESULTS BMP
  names[23]=49'h0288a9a7ac2c0; //EDUMOVE BMP
  names[24]=49'h0288aa0092740; //EDUPAIN BMP
  names[25]=49'h0288a9c0aa9c0; //EDUNAUS BMP
  names[26]=49'h0288a8c79e240; //EDUFOOD BMP
  names[27]=49'h090a9a9041040; //REST    BMP
  names[28]=49'h08021aa91828e; //PACURLEGBMP
  names[29]=49'h04129a88021aa; //HISTPACUBMP
  names[30]=49'h04129a8b82908; //HISTWARDBMP
  names[31]=49'h0a628e20c1040; //T1Q1A   BMP
  names[32]=49'h0a628e40c1040; //T1Q2A   BMP
  names[33]=49'h0a6472a683040; //T2NUMA  BMP
  names[34]=49'h0a6498268a0c0; //T2SAMEA BMP
  names[35]=49'h0a66626a1c0c0; //T3LSTNA BMP
  names[36]=49'h0a68b824a80c0; //T4WAITA BMP
  names[37]=49'h0a6839e0c1040; //T4GOA   BMP
  names[38]=49'h0a6a41e6080c0; //T5HOLDA BMP
  names[39]=49'h0a6c80249c0c0; //T6PAINA BMP
  names[40]=49'h0a628e2141040; //T1Q1B   BMP
  names[41]=49'h0a628e4141040; //T1Q2B   BMP
  names[42]=49'h0a6472a685040; //T2NUMB  BMP
  names[43]=49'h0a6498268a140; //T2SAMEB BMP
  names[44]=49'h0a66626a1c140; //T3LSTNB BMP
  names[45]=49'h0a68b824a8140; //T4WAITB BMP
  names[46]=49'h0a6839e141040; //T4GOB   BMP
  names[47]=49'h0a6a41e608140; //T5HOLDB BMP
  names[48]=49'h0a6c80249c140; //T6PAINB BMP
  names[49]=49'h090a602c41040; //RELAX   BMP
  names[50]=49'h06aa9921e18c1; //MUSIC01 PCM
  names[51]=49'h06aa9921e1941; //MUSIC02 PCM
  names[52]=49'h029a7ac2be6c1; //EMOVE_M PCM
  names[53]=49'h02a009273e6c1; //EPAIN_M PCM
  names[54]=49'h029c0aa9be6c1; //ENAUS_M PCM
  names[55]=49'h028c79e23e6c1; //EFOOD_M PCM
  names[56]=49'h0b8a60679a2c0; //WELCOME BMP
  names[57]=49'h0b8a60679a2c0; //WELCOME BMP
  names[58]=49'h0b8a60679a2c0; //WELCOME BMP
  names[59]=49'h0b8a60679a2c0; //WELCOME BMP
  names[60]=49'h0b8a60679a2c0; //WELCOME BMP
  names[61]=49'h0b8a60679a2c0; //WELCOME BMP
  names[62]=49'h0b8a60679a2c0; //WELCOME BMP
  names[63]=49'h0b8a60679a2c0; //WELCOME BMP
  names[64]=49'h0b8a60679a2c1; //WELCOME PCM
  names[65]=49'h08021aa3aa489; //PACUGUIDPCM
  names[66]=49'h08021aa182619; //PACUCALLPCM
  names[67]=49'h08021aa90a841; //PACUREP PCM
  names[68]=49'h08021aa60291b; //PACULARMPCM
  names[69]=49'h08021aa90291b; //PACURARMPCM
  names[70]=49'h08021aa61828f; //PACULLEGPCM
  names[71]=49'h08021aa09891b; //PACUALRMPCM
  names[72]=49'h08021aa926629; //PACURSLTPCM
  names[73]=49'h060a0a47162b3; //LEARNKEYPCM
  names[74]=49'h060a0a4710609; //LEARNHLDPCM
  names[75]=49'h060a0a472c4a7; //LEARNVISPCM
  names[76]=49'h090a088cc1041; //READY   PCM
  names[77]=49'h0a628e3041041; //T1Q1    PCM
  names[78]=49'h0a628e5041041; //T1Q2    PCM
  names[79]=49'h0a6472a6c1041; //T2NUM   PCM
  names[80]=49'h0a6498268b041; //T2SAME  PCM
  names[81]=49'h0a666129a829d; //T3LISTENPCM
  names[82]=49'h0a6849c31f041; //T4INFO  PCM
  names[83]=49'h0a6839f041041; //T4GO    PCM
  names[84]=49'h0a6a41e609041; //T5HOLD  PCM
  names[85]=49'h0a6c80249d041; //T6PAIN  PCM
  names[86]=49'h090a9aa6289c1; //RESULTS PCM
  names[87]=49'h0288a9a7ac2c1; //EDUMOVE PCM
  names[88]=49'h0288aa0092741; //EDUPAIN PCM
  names[89]=49'h0288a9c0aa9c1; //EDUNAUS PCM
  names[90]=49'h0288a8c79e241; //EDUFOOD PCM
  names[91]=49'h090a9a9041041; //REST    PCM
  names[92]=49'h08021aa91828f; //PACURLEGPCM
  names[93]=49'h04129a88021aa; //HISTPACUBMP
  names[94]=49'h04129a8b82908; //HISTWARDBMP
  names[95]=49'h0a628e20c1041; //T1Q1A   PCM
  names[96]=49'h0a628e40c1041; //T1Q2A   PCM
  names[97]=49'h0a6472a683041; //T2NUMA  PCM
  names[98]=49'h0a6498268a0c1; //T2SAMEA PCM
  names[99]=49'h0a66626a1c0c1; //T3LSTNA PCM
  names[100]=49'h0a6849c31e0c1; //T4INFOA PCM
  names[101]=49'h0a6839e0c1041; //T4GOA   PCM
  names[102]=49'h0a6a41e6080c1; //T5HOLDA PCM
  names[103]=49'h0a6c80249c0c1; //T6PAINA PCM
  names[104]=49'h0a628e2141041; //T1Q1B   PCM
  names[105]=49'h0a628e4141041; //T1Q2B   PCM
  names[106]=49'h0a6472a685041; //T2NUMB  PCM
  names[107]=49'h0a6498268a141; //T2SAMEB PCM
  names[108]=49'h0a66626a1c141; //T3LSTNB PCM
  names[109]=49'h0a6849c31e141; //T4INFOB PCM
  names[110]=49'h0a6839e141041; //T4GOB   PCM
  names[111]=49'h0a6a41e608141; //T5HOLDB PCM
  names[112]=49'h0a6c80249c141; //T6PAINB PCM
  names[113]=49'h06aa9921e18c1; //MUSIC01 PCM
  names[114]=49'h0b8a60679a2c0; //WELCOME BMP
  names[115]=49'h0b8a60679a2c0; //WELCOME BMP
  names[116]=49'h0b8a60679a2c0; //WELCOME BMP
  names[117]=49'h0b8a60679a2c0; //WELCOME BMP
  names[118]=49'h0b8a60679a2c0; //WELCOME BMP
  names[119]=49'h0b8a60679a2c0; //WELCOME BMP
  names[120]=49'h0b8a60679a2c0; //WELCOME BMP
  names[121]=49'h0b8a60679a2c0; //WELCOME BMP
  names[122]=49'h0b8a60679a2c0; //WELCOME BMP
  names[123]=49'h0b8a60679a2c0; //WELCOME BMP
  names[124]=49'h0b8a60679a2c0; //WELCOME BMP
  names[125]=49'h0b8a60679a2c0; //WELCOME BMP
  names[126]=49'h0b8a60679a2c0; //WELCOME BMP
  names[127]=49'h0b8a60679a2c0; //WELCOME BMP
 end
 always @(posedge clk)packed_name<=names[address];
 genvar letter;
 generate for(letter=0;letter<8;letter=letter+1)begin:restore_ascii
  assign file_name[87-8*letter-:8]={1'b0,~packed_name[48-6*letter],packed_name[48-6*letter-:6]};
 end endgenerate
 assign file_name[23:0]=packed_name[0]?24'h50434d:24'h424d50;
endmodule

`default_nettype wire
