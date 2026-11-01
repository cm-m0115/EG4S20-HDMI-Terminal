`default_nettype none
`timescale 1ns/1ps
// reliable stop-and-wait link. Finite retries, heartbeat, startup drain,
// explicit master session negotiation, sequence deduplication in each direction.
// An ACK means payload received intact, never optical/audio presentation.
module recovery_uart_link #(parameter integer CLK_HZ=100000000,BAUD=115200,
 MASTER=0,MAX_BYTES=168,ACK_MS=120,HELLO_MS=50,HEARTBEAT_MS=100,TIMEOUT_MS=1000)(
 input wire clk,rst,input wire uart_rx,output wire uart_tx,
 input wire send_valid,output wire send_ready,input wire [7:0] send_length,
 input wire [MAX_BYTES*8-1:0] send_data,
 output reg in_valid,output reg [7:0] in_length,
 output wire [MAX_BYTES*8-1:0] in_data,output reg link_up,output reg session_restart
);

localparam [7:0] DATA=1,ACK=2,HELLO=3,HELLO_ACK=4,RESTART=5,PING=6;
localparam integer ACK_CYCLES=(CLK_HZ/1000)*ACK_MS;
localparam integer HELLO_CYCLES=(CLK_HZ/1000)*HELLO_MS;
localparam integer PING_CYCLES=(CLK_HZ/1000)*HEARTBEAT_MS;
localparam integer DEAD_CYCLES=(CLK_HZ/1000)*TIMEOUT_MS;
localparam integer QUIET_CYCLES=CLK_HZ/25;
reg [31:0] uptime,session,alive_count,hello_count,ping_count,retry_count,quiet_count;
reg [15:0] out_seq,in_seq,ack_seq;
reg [7:0] held_length;
reg [MAX_BYTES*8-1:0] held_data;
reg pending,need_send,ack_pending,hello_ack_pending,fresh_session;
reg [2:0] attempts;
wire raw_ready,raw_rx_valid;
wire [7:0] raw_rx_type,raw_rx_length;
wire [31:0] raw_rx_session;
wire [15:0] raw_rx_seq;
wire [MAX_BYTES*8-1:0] raw_rx_data;
reg raw_valid;
reg [7:0] raw_type,raw_length;
reg [31:0] raw_session;
reg [15:0] raw_seq;
reg [MAX_BYTES*8-1:0] raw_data;
// Continuous values retain the original net initializer expressions.


 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 assign send_ready=link_up&&!pending;
 // Only meaningful with in_valid. The CRC staging bus cannot change before
 // at least the next frame header (10 UART bytes); consumers latch next clk.
 assign in_data=raw_rx_data;
 recovery_uart_packet #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.MAX_BYTES(MAX_BYTES),.TX_INPUT_STABLE(1)) u_packet(
  .clk(clk),.rst(rst),.uart_rx(uart_rx),.uart_tx(uart_tx),
  .tx_valid(raw_valid),.tx_ready(raw_ready),.tx_type(raw_type),.tx_session(raw_session),
  .tx_seq(raw_seq),.tx_length(raw_length),.tx_data(raw_data),
  .rx_valid(raw_rx_valid),.rx_type(raw_rx_type),.rx_session(raw_rx_session),
  .rx_seq(raw_rx_seq),.rx_length(raw_rx_length),.rx_data(raw_rx_data));
 // pending/need_send/link_up remain asynchronously cleared. A DATA frame can
 // read this buffer only after a complete send_valid/send_ready capture.
 always @(posedge clk)begin
  if(rst)held_data<=0;
  else if(send_valid&&send_ready)held_data<=send_data;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   uptime<=0;session<=0;alive_count<=0;hello_count<=0;ping_count<=0;retry_count<=0;quiet_count<=0;
   out_seq<=0;in_seq<=0;ack_seq<=0;held_length<=0;pending<=0;need_send<=0;
   ack_pending<=0;hello_ack_pending<=0;fresh_session<=1;attempts<=0;
   raw_valid<=0;raw_type<=0;raw_length<=0;raw_session<=0;raw_seq<=0;raw_data<=0;
   in_valid<=0;in_length<=0;link_up<=0;session_restart<=0;
  end else begin
   uptime<=uptime+1'b1;raw_valid<=0;in_valid<=0;session_restart<=0;
   if(quiet_count<QUIET_CYCLES)quiet_count<=quiet_count+1'b1;
   if(hello_count<HELLO_CYCLES)hello_count<=hello_count+1'b1;
   if(ping_count<PING_CYCLES)ping_count<=ping_count+1'b1;
   if(link_up&&alive_count<DEAD_CYCLES)alive_count<=alive_count+1'b1;
   if(pending&&!need_send&&retry_count<ACK_CYCLES)retry_count<=retry_count+1'b1;
   if(send_valid&&send_ready)begin
    pending<=1;need_send<=1;held_length<=send_length;
    retry_count<=0;attempts<=0;
   end
   if(pending&&!need_send&&retry_count>=ACK_CYCLES)begin
    if(attempts>=4)begin
     link_up<=0;pending<=0;need_send<=0;ack_pending<=0;fresh_session<=1;
     hello_count<=HELLO_CYCLES;quiet_count<=0;alive_count<=0;
    end else begin need_send<=1;retry_count<=0;end
   end
   if(link_up&&alive_count>=DEAD_CYCLES)begin
    link_up<=0;pending<=0;need_send<=0;ack_pending<=0;hello_ack_pending<=0;
    fresh_session<=1;hello_count<=HELLO_CYCLES;quiet_count<=0;alive_count<=0;
   end
   // The raw packet transmitter is one-entry; don't issue in its accept cycle.
   if(raw_ready&&!raw_valid&&quiet_count>=QUIET_CYCLES)begin
    raw_length<=0;raw_data<=0;raw_session<=session;raw_seq<=0;
    if(hello_ack_pending)begin
     raw_valid<=1;raw_type<=HELLO_ACK;hello_ack_pending<=0;ping_count<=0;
    end else if(ack_pending&&link_up)begin
     raw_valid<=1;raw_type<=ACK;raw_seq<=ack_seq;ack_pending<=0;ping_count<=0;
    end else if(!link_up&&hello_count>=HELLO_CYCLES)begin
     raw_valid<=1;raw_type<=MASTER?HELLO:RESTART;hello_count<=0;
     if(MASTER&&fresh_session)begin
      session<=uptime^32'hc16ac16a;raw_session<=uptime^32'hc16ac16a;
      out_seq<=0;in_seq<=0;fresh_session<=0;
     end
    end else if(link_up&&pending&&need_send)begin
     raw_valid<=1;raw_type<=DATA;raw_seq<=out_seq;raw_length<=held_length;raw_data<=held_data;
     need_send<=0;retry_count<=0;attempts<=attempts+1'b1;ping_count<=0;
    end else if(link_up&&ping_count>=PING_CYCLES)begin
     raw_valid<=1;raw_type<=PING;ping_count<=0;
    end
   end
   if(raw_rx_valid)begin
    if(!MASTER&&raw_rx_type==HELLO&&raw_rx_length==0)begin
     begin // HELLO is a drain/rebase barrier, including a peer power restart.
      session<=raw_rx_session;out_seq<=0;in_seq<=0;pending<=0;need_send<=0;
      ack_pending<=0;in_valid<=0;link_up<=1;session_restart<=1;
     end
     hello_ack_pending<=1;alive_count<=0;
    end else if(MASTER&&raw_rx_type==RESTART&&raw_rx_length==0)begin
     if(link_up)begin
      link_up<=0;pending<=0;need_send<=0;ack_pending<=0;hello_ack_pending<=0;
      fresh_session<=1;quiet_count<=0;hello_count<=HELLO_CYCLES;
     end
    end else if(MASTER&&!link_up&&raw_rx_type==HELLO_ACK&&raw_rx_session==session&&raw_rx_length==0)begin
     link_up<=1;alive_count<=0;ping_count<=PING_CYCLES;session_restart<=1;
    end else if(link_up&&raw_rx_session==session)begin
     alive_count<=0;
     if(raw_rx_type==DATA)begin
      if(raw_rx_seq==in_seq)begin
       in_length<=raw_rx_length;in_valid<=1;in_seq<=in_seq+1'b1;
       ack_pending<=1;ack_seq<=raw_rx_seq;
      end else if(raw_rx_seq==in_seq-16'd1)begin ack_pending<=1;ack_seq<=raw_rx_seq;end
     end else if(raw_rx_type==ACK&&pending&&raw_rx_seq==out_seq&&raw_rx_length==0)begin
      pending<=0;need_send<=0;out_seq<=out_seq+1'b1;attempts<=0;retry_count<=0;
     end
    end
   end
  end
 end
`ifdef __ICARUS__
 reg [MAX_BYTES*8-1:0] c27_tx_previous;reg c27_tx_was_active;
 always @(posedge clk)begin
  if(rst)c27_tx_was_active<=0;
  else begin
   if(c27_tx_was_active&&u_packet.tx_active&&raw_data!==c27_tx_previous)
    $fatal(1,"C27 TX stable-input contract violated");
   c27_tx_previous<=raw_data;c27_tx_was_active<=u_packet.tx_active;
  end
 end
`endif
endmodule

`ifdef __ICARUS__
// Simulation-only invariant on the real link/packet boundary. The hardware
// buffer owner is unchanged; this catches cancellation/retry/restart writes.
// (Placed inside a bind-free companion monitor by the test harness below.)
`endif

`default_nettype wire
