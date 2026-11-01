`default_nettype none
// Business clock adapter with 100MHz output and PLL lock observation.
// Only the interface exposes extlock. Original generated IP stays untouched.
// One PLL; B consumes C0=100MHz. Reference sys_pll.v SHA256:
// ea4ed09b2ff026b7b31eb76f51ef5afa388aa552e538e02d013cc8e7464ba563
/************************************************************\
 **     Copyright (c) 2012-2024 Anlogic Inc.
 **  All Right Reserved.\
\************************************************************/
                                                              
                                                         
                                                                                        
                     
                           
                                                              

///////////////////////////////////////////////////////////////////////////////
//	Input frequency:               50.000000MHz
//	Clock multiplication factor: 2
//	Clock division factor:       1
//	Clock information:
//		Clock name	| Frequency 	| Phase shift
//		C0        	| 100.000000MHZ	| 0.0000  DEG  
//		C1        	| 125.000000MHZ	| 0.0000  DEG  
//		C2        	| 125.000000MHZ	| 180.0000 DEG  
///////////////////////////////////////////////////////////////////////////////
`timescale 1 ns / 100 fs

module recovery_master_clock (
  refclk,
  reset,
  clk0_out,
  locked 
);

wire clk1_out;
wire clk2_out;
wire clk0_buf;
wire unused_clkc3,unused_clkc4;
// Continuous values retain the original net initializer expressions.



  input wire refclk;
  input wire reset;
  output wire clk0_out;
  
  output wire locked;
  

  
  

  EG_LOGIC_BUFG bufg_feedback (
    .i(clk0_buf),
    .o(clk0_out) 
  );

  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),
    .FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(4),
    .ICP_CURRENT(29),
    .KVCO(4),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(2),
    .REFCLK_DIV(1),
    .FBCLK_DIV(2),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(10),
    .CLKC0_CPHASE(9),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(8),
    .CLKC1_CPHASE(7),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),
    .CLKC2_DIV(8),
    .CLKC2_CPHASE(3),
    .CLKC2_FPHASE(0) 
  ) pll_inst (
    .refclk(refclk),
    .reset(reset),
    .stdby(1'b0),
    .extlock(locked),
    .load_reg(1'b0),
    .psclk(1'b0),
    .psdown(1'b0),
    .psstep(1'b0),
    .psclksel(3'b000),
    .psdone(),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .\do (),
    .fbclk(clk0_out),
    .clkc({unused_clkc4, unused_clkc3, clk2_out, clk1_out, clk0_buf}) 
  );

endmodule


`default_nettype wire
