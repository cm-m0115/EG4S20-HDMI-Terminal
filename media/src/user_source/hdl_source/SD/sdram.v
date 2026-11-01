`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: anlgoic
// Author: 	xg 
// description:  top module
//////////////////////////////////////////////////////////////////////////////////

`define DEBUG

`include "../user_source/hdl_source/include/global_def.v"

module sdram #(parameter REFRESH_PERIOD_CLOCKS=1000, REFRESH_DRAIN_CLOCKS=32, REFRESH_GUARD_CLOCKS=16)(
    `ifdef SIMULATION
	output					SDRAM_CLK,
	output					SDR_CKE,
	output					SDR_RAS,
	output					SDR_CAS,
	output					SDR_WE,
	output	[`BA_WIDTH-1:0]	SDR_BA,
	output	[`ROW_WIDTH-1:0]SDR_ADDR,
	output	[`DM_WIDTH-1:0]	SDR_DM,
	inout	[`DATA_WIDTH-1:0]	SDR_DQ,	
	`endif
    input   					Clk,
    input						Clk_sft,
    input						Rst,
    
    output 						Sdr_init_done,
    output						Sdr_init_ref_vld,
    output						Sdr_busy,
    output wire Sdr_refresh_fault,
    
    input						App_wr_en,
	input [`ADDR_WIDTH-1:0]		App_wr_addr,  	
	input [`DM_WIDTH-1:0]		App_wr_dm,
	input [`DATA_WIDTH-1:0]		App_wr_din,	//synthesis keep
    
    input 						App_rd_en,
	input [`ADDR_WIDTH-1:0]		App_rd_addr,
	output 						Sdr_rd_en,
	output [`DATA_WIDTH-1:0]	Sdr_rd_dout	//synthesis keep
    
    
    
);
`ifndef SIMULATION
wire  			SDRAM_CLK;
wire SDR_CKE;
wire 			SDR_RAS;
wire  			SDR_CAS;
wire  			SDR_WE;
wire  [`BA_WIDTH-1:0]	SDR_BA; 
wire  [`ROW_WIDTH-1:0]	SDR_ADDR;
wire  [`DATA_WIDTH-1:0]	SDR_DQ ;
wire  [`DM_WIDTH-1:0]	SDR_DM; 
`endif

// external refresh arbitration owns the deadline. No input word
// is masked: the frame schedulers finish in-flight bursts and defer new ones.
wire core_init_done,core_ref_vld,core_busy,refresh_block,refresh_request;
wire refresh_fault;
assign Sdr_refresh_fault=refresh_fault;
assign Sdr_init_done=core_init_done;
assign Sdr_init_ref_vld=core_ref_vld|refresh_block;
assign Sdr_busy=core_busy|refresh_block;
sdram_refresh_arbiter #(.PERIOD_CLOCKS(REFRESH_PERIOD_CLOCKS),
 .DRAIN_CLOCKS(REFRESH_DRAIN_CLOCKS),.GUARD_CLOCKS(REFRESH_GUARD_CLOCKS)) refresh_control(
 .clk(Clk),.rst(Rst),.init_done(core_init_done),
 .traffic_active(App_wr_en|App_rd_en|Sdr_rd_en|core_busy|core_ref_vld),
 .ref_valid(core_ref_vld),.block_new_burst(refresh_block),
 .request(refresh_request),.fault(refresh_fault));
sdr_as_ram  #( .self_refresh_open(1'b0))
	u2_ram( 
		.Sdr_clk(Clk),
		.Sdr_clk_sft(Clk_sft),
		.Rst(Rst),
			  			  
		.Sdr_init_done(core_init_done),
		.Sdr_init_ref_vld(core_ref_vld),
		.Sdr_busy(core_busy),
		
		.App_ref_req(refresh_request),
		
        .App_wr_en(App_wr_en), 
        .App_wr_addr(App_wr_addr),  	
		.App_wr_dm(App_wr_dm),
		.App_wr_din(App_wr_din),

		.App_rd_en(App_rd_en),
		.App_rd_addr(App_rd_addr),
		.Sdr_rd_en	(Sdr_rd_en),
		.Sdr_rd_dout(Sdr_rd_dout),
	
		.SDRAM_CLK(SDRAM_CLK),
		.SDR_RAS(SDR_RAS),
		.SDR_CAS(SDR_CAS),
		.SDR_WE(SDR_WE),
		.SDR_BA(SDR_BA),
		.SDR_ADDR(SDR_ADDR),
		.SDR_DM(SDR_DM),
		.SDR_DQ(SDR_DQ)	
	);


assign SDR_CKE=1'b1;

`ifndef SIMULATION
	EG_PHY_SDRAM_2M_32 sdram(
		.clk(SDRAM_CLK),
		.ras_n(SDR_RAS),
		.cas_n(SDR_CAS),
		.we_n(SDR_WE),
		.addr(SDR_ADDR[10:0]),
		.ba(SDR_BA),
		.dq(SDR_DQ),
		.cs_n(1'b0),
		.dm0(SDR_DM[0]),
		.dm1(SDR_DM[1]),
		.dm2(SDR_DM[2]),
		.dm3(SDR_DM[3]),
		.cke(1'b1)
		);
`endif

endmodule 
// refresh is an admission barrier, never a word-level data gate.
// Deadlines run independently of completion. A due request is retained through
// busy traffic; schedulers see block_new_burst and finish their current packet.
// Both valid edges are required before service is considered complete.
module sdram_refresh_arbiter #(
 parameter PERIOD_CLOCKS=1000,DRAIN_CLOCKS=32,GUARD_CLOCKS=16,TIMEOUT_CLOCKS=2048
)(
 input clk,rst,init_done,traffic_active,ref_valid,
 output block_new_burst,request,output reg fault
);
 localparam RUN=0,DRAIN=1,PULSE=2,WAIT_RISE=3,WAIT_FALL=4,GUARD=5,FAULT=6;
 reg[2:0]state;
 // size counters to their configured terminal values.
 // This preserves the same deadline/drain/guard/timeout cycles while saving
 // unused high bits in the resource-limited design.
 function integer count_bits;
  input integer clocks;
  integer remaining;
  begin
   remaining=clocks-1;count_bits=0;
   while(remaining>0)begin count_bits=count_bits+1;remaining=remaining>>1;end
   if(count_bits<1)count_bits=1;
  end
 endfunction
 localparam PERIOD_BITS=count_bits(PERIOD_CLOCKS);
 localparam DRAIN_BITS=count_bits(DRAIN_CLOCKS);
 localparam GUARD_BITS=count_bits(GUARD_CLOCKS);
 localparam WAIT_BITS=count_bits(TIMEOUT_CLOCKS);
 reg[PERIOD_BITS-1:0]period_count;
 reg[DRAIN_BITS-1:0]drain_count;
 reg[GUARD_BITS-1:0]guard_count;
 reg[WAIT_BITS-1:0]wait_count;
 reg pending;
 wire due=(period_count==PERIOD_CLOCKS-1);
 assign block_new_burst=!init_done|pending|(state!=RUN);
 assign request=(state==PULSE);
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=RUN;period_count<=0;drain_count<=0;guard_count<=0;wait_count<=0;
   pending<=0;fault<=0;
  end else if(!init_done)begin
   state<=RUN;period_count<=0;drain_count<=0;guard_count<=0;wait_count<=0;
   pending<=0;fault<=0;
  end else begin
   if(due)period_count<=0;else period_count<=period_count+1'b1;
   if(due)pending<=1;else if(state==PULSE)pending<=0;
   case(state)
    RUN:begin
     drain_count<=0;guard_count<=0;wait_count<=0;
     if(pending)state<=DRAIN;
    end
    DRAIN:begin
     // Includes busy cycles: a stuck client must not defeat the refresh bound.
     if(wait_count==TIMEOUT_CLOCKS-1)begin state<=FAULT;fault<=1;end
     else begin
      wait_count<=wait_count+1'b1;
      if(traffic_active)drain_count<=0;
     else if(drain_count==DRAIN_CLOCKS-1)begin state<=PULSE;drain_count<=0;end
      else drain_count<=drain_count+1'b1;
     end
    end
    PULSE:begin state<=WAIT_RISE;wait_count<=0;end
    WAIT_RISE:begin
     if(ref_valid)begin state<=WAIT_FALL;wait_count<=0;end
     else if(wait_count==TIMEOUT_CLOCKS-1)begin state<=FAULT;fault<=1;end
     else wait_count<=wait_count+1'b1;
    end
    WAIT_FALL:begin
     if(!ref_valid)begin state<=GUARD;guard_count<=0;end
     else if(wait_count==TIMEOUT_CLOCKS-1)begin state<=FAULT;fault<=1;end
     else wait_count<=wait_count+1'b1;
    end
    GUARD:begin
     if(ref_valid)begin state<=WAIT_FALL;wait_count<=0;guard_count<=0;end
     else if(guard_count==GUARD_CLOCKS-1)begin state<=RUN;guard_count<=0;end
     else guard_count<=guard_count+1'b1;
    end
    FAULT:begin state<=FAULT;fault<=1;end
    default:begin state<=FAULT;fault<=1;end
   endcase
  end
 end
endmodule
