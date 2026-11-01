// Media memory clock configuration.
// EM638325 specifies4096 AUTOREF commands in64ms.
// Standalone self_refresh_open core: inclusive threshold624 at40MHz.
// Production sdram wrapper disables that timer and owns periodic external REF.
// Production deadline320 clocks=8us includes margin for completing a256word
// burst and quiescence, then waiting for REF completion and recovery.
`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

`define	  SDR_CLK_PERIOD				(1000000000/40000000)
`define   SELF_REFRESH_INTERVAL			((64000000 / (`SDR_CLK_PERIOD) / 4096) - 1)

