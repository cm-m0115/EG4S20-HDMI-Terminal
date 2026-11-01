# B: original 50MHz -> 100MHz PLL parameters unchanged.
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
derive_clocks
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_master_clock/pll_inst.clkc[0]}]
# Only exact first asynchronous stages are excepted; later stages stay timed.
# Every raw pin feeds only first sampling FF(s), as confirmed by mapped fanout.
# TD can pack this first FF into PAD IREG, eliminating logical -to names.
# Restrict by exact raw startpoints; IREG Q -> second FF stays timed.
set_false_path -from [get_ports {uart_rx gpio_presented_in gpio_done_in gpio_link_ready_in sw1 sw2 key1 key2 key3 rst_n sw3 sw4}]
# U33 mode0, 2MHz. All logic remains in sd_card_clk (100MHz).
# MISO launches at the falling external edge, is sampled 25 enables later.
# A finite 200ns FPGA input budget leaves 50ns for output delay, flash tCLQV,
# PCB skew and margin; this is not an asynchronous false path.
set_max_delay 200 -from [get_ports {flash_miso}] -to [get_regs {u_report_flash/u_spi/u_byte/rx_shift[*] u_report_flash/u_spi/u_byte/rx_byte[*]}]
set_min_delay 0 -from [get_ports {flash_miso}] -to [get_regs {u_report_flash/u_spi/u_byte/rx_shift[*] u_report_flash/u_spi/u_byte/rx_byte[*]}]
# Limit registered pad propagation. SPI sequence supplies >=20ns CS setup,
# >=250ns data setup and >50ns deselect; verified separately on final pad paths.
set_max_delay 20 -to [get_ports {flash_sclk flash_mosi flash_cs_n}]
set_min_delay 0 -to [get_ports {flash_sclk flash_mosi flash_cs_n}]
# PLL-lock async assertion only; release/stage data stays timed.
set_false_path -from [get_pins {u_master_clock/pll_inst.extlock}] -to [get_regs {rs0/sync[*]}]
