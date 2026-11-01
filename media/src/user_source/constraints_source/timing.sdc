# derive actual PLL clocks; SD100, MEM40/actual CPHASE12 = 13ns (187.2deg), TD derive187deg, video25, HDMI125, audio unchanged.
# TD get_regs selects logical Q-net names, not mapped *_reg cell names.
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
derive_clocks
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
rename_clock -name {video_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]
# Pixel and 5x clocks are related: no exclusive cut. No whole-domain async cut.
# External SPI timing and embedded SDRAM interface still need vendor/board closure.

# Only asynchronous signal sampling at the first synchronizer stage is excepted.
# Subsequent stages, ordinary synchronous data, local reset release stay timed.
set_false_path -to [get_regs {mem_ready1 wr_ack1 finish1 u_commit/rsp_sync1 u_commit/cancel_ack_sync1 u_commit/req_sync1 u_commit/cancel_sync1 u_commit/mem_ack_sync1 u_commit/fault_sync1 u_commit/fault_ack_sync1 u_status/ack1 u_status/req1 u_I2S_receiver/S_i2s_bclk_1d u_I2S_receiver/S_i2s_lrck_1d u_I2S_receiver/S_i2s_dout_1d u_media/u_pcm/flush_ack1 u_media/u_pcm/done1 u_media/u_pcm/err1 u_media/u_pcm/flush1 u_media/u_pcm/cmd1 u_media/u_pcm/en1 u_media/u_pcm/ready1 frame_read_write_m0/frame_fifo_read_m0/read_req_d0}]
set_max_delay -from [get_regs {u_commit/hold_bank[*] u_commit/hold_scene[*] u_commit/hold_epoch[*]}] -to [get_regs {u_commit/local_bank[*] u_commit/local_scene[*] u_commit/local_epoch[*]}] -datapath_only 20
set_max_delay -from [get_regs {u_commit/cancel_epoch_hold[*]}] -to [get_regs {u_commit/accepted_epoch[*]}] -datapath_only 20
set_max_delay -from [get_regs {u_commit/rsp_active_bank[*] u_commit/rsp_scene[*] u_commit/rsp_epoch[*] u_commit/rsp_status[*] u_commit/fault_epoch_hold[*]}] -to [get_regs {u_commit/active_bank[*] u_commit/presented_scene[*] u_commit/presented_epoch[*] u_commit/presented u_commit/present_error}] -datapath_only 8
set_max_delay -from [get_regs {u_status/hold_data[*]}] -to [get_regs {u_status/dst_data[*]}] -datapath_only 20
set_max_delay -from [get_regs {u_media/u_pcm/expected_samples[*]}] -to [get_regs {u_media/u_pcm/samples_left[*]}] -datapath_only 20
set_max_delay -from [get_regs {u_media/u_pcm/u_pcm_fifo/wg[*]}] -to [get_regs {u_media/u_pcm/u_pcm_fifo/wg1[*]}] -datapath_only 10
set_max_delay -from [get_regs {u_media/u_pcm/u_pcm_fifo/rg[*]}] -to [get_regs {u_media/u_pcm/u_pcm_fifo/rg1[*]}] -datapath_only 10
set_max_delay -from [get_regs {u_commit/reader_bank[*]}] -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/read_addr_index_d0[*]}] -datapath_only 10

# Dedicated asynchronous-assert/synchronous-deassert reset pipelines only.
# The through raw-arst restriction does NOT cut stage0->stage1 data propagation
# or the local reset output feeding ordinary pointers/logic.
set_false_path -through [get_nets {u_media/u_pcm/u_pcm_fifo/arst}] -to [get_regs {u_media/u_pcm/u_pcm_fifo/wr_reset_sync[*] u_media/u_pcm/u_pcm_fifo/rd_reset_sync[*]}]
set_false_path -through [get_nets {u_media/u_audio_reset/arst}] -to [get_regs {u_media/u_audio_reset/sync[*]}]
set_false_path -through [get_nets {rs4/arst rs5/arst}] -to [get_regs {rs4/sync[*] rs5/sync[*]}]

# TD read_sdc accepts literal SDC commands; it does not
# execute Tcl if/foreach bodies. Keep these precise object queries literal.
# Disabled modules match zero objects (verified by optional-off builds);
# never replace them by whole-clock-domain exceptions.
set_false_path -to [get_regs {u_media/u_pcm/g_volume$u_volume_config/req1 u_media/u_pcm/g_volume$u_volume_config/ack1}]
set_max_delay -from [get_regs {u_commit/hold_effect[*]}] -to [get_regs {u_commit/local_effect[*]}] -datapath_only 20
set_max_delay -from [get_regs {u_media/u_pcm/g_volume$u_volume_config/hold_data[*]}] -to [get_regs {u_media/u_pcm/g_volume$u_volume_config/dst_data[*]}] -datapath_only 20

# new held frame-boundary mailboxes and input synchronizers.
# Only the asynchronous sampling register is excepted; later stages stay timed.

# only asynchronous UART input to first sampling FF; later stages stay timed.
# Raw UART only feeds the first sampler (may be packed into PAD IREG).
# The first Q -> subsequent synchronizer stages remains timed.
set_false_path -from [get_ports {uart_rx}]

# held narration identity rides the pre-existing PCM command toggle.
set_max_delay -from [get_regs {u_media/u_pcm/narration_id_hold[*]}] -to [get_regs {u_media/u_pcm/playback_id_audio[*]}] -datapath_only 20
# Actual-sample caption metadata crosses one held request/acknowledge mailbox.
set_false_path -to [get_regs {u_caption_status/req1 u_caption_status/ack1}]
set_max_delay -from [get_regs {u_caption_status/hold_data[*]}] -to [get_regs {u_caption_status/dst_data[*]}] -datapath_only 20

# dedicated display boot/kill held handshakes. Later stages timed.
set_false_path -to [get_regs {u_status/db1 u_status/sba1 u_status/sb1 u_status/dba1 u_status/ka1 u_status/k1}]

# actual-green event: held pixel identity to application, exact endpoints.
set_false_path -to [get_regs {u_ui_event/ack1 u_ui_event/req1}]
# the same 8ns bundled-data bound terminates at the dedicated app
# payload capture; req1/req2 still provide the original two-clock settling.
set_max_delay -from [get_regs {u_ui_event/hold_event[*]}] -to [get_regs {u_ui_event/event_identity[*]}] -datapath_only 8

# all-lock reset: asynchronous assertion only, local deassertion stays timed.
set_false_path -from [get_pins {sys_pll_m0/pll_inst.extlock video_pll_m0/pll_inst.extlock}] -to [get_regs {rs0/sync[*] rs1/sync[*] rs2/sync[*] rs3/sync[*] rs4/sync[*] rs5/sync[*] u_startup_wait/release_sync[*]}]
set_false_path -to [get_regs {refresh_fault_sd[0] refresh_fault_pixel[0]}]
