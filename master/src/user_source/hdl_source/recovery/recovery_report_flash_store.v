`default_nettype none
`timescale 1ns/1ps
// U33 USER flash only. Two 64KiB banks at the end of the 8MiB device.
// Each page contains one immutable entry: 40 CRC-covered bytes, CRC32,
// and a separately programmed/read-back commit word at offset 60.
// A bank header is committed LAST after migration. The previous bank is
// never erased until the replacement bank has become authoritative.
// Only 32 page indices are cached; the existing history owns report RAM.
module recovery_report_flash_store #(
 parameter integer CLK_HZ=100000000,SPI_CLK_DIV=25,
 parameter integer POWER_UP_CYCLES=1000000,WAKE_CYCLES=300000,
 parameter integer POLL_INTERVAL_CYCLES=100000,
 parameter [23:0] BANK0_BASE=24'h7e0000,BANK1_BASE=24'h7f0000,
 parameter integer BANK_BYTES=65536,
 parameter [31:0] ERASE_TIMEOUT_CYCLES=300000000,
 parameter [31:0] PROGRAM_TIMEOUT_CYCLES=10000000
)(
 input wire clk,rst,report_valid,input wire [183:0] report_record,
 output wire report_ready,output reg report_commit,output wire [183:0] committed_record,
 output reg report_error,input wire clear_request,output reg clear_done,
 output reg restore_valid,output wire [183:0] restore_record,input wire restore_ready,
 output reg storage_ready,storage_fault,write_enabled,output reg [23:0] jedec_id,
 output wire flash_cs_n,flash_sclk,flash_mosi,input wire flash_miso,
 output wire flash_wp_n,flash_hold_n
);

localparam [31:0] MAGIC=32'h43323752,HEADER=32'h43323742,COMMIT=32'hc327a55a;
localparam integer LAST_SLOT=BANK_BYTES/256-1,SECTORS=BANK_BYTES/4096;
localparam [5:0] POWER=0,WAKE=1,ID=2,ID_CHECK=3,SR1=4,SR1_CHECK=5,
  SR2_CHECK=6,HDR0=7,HDR0_CHECK=8,HDR1_CHECK=9,SELECT=10,SCAN=11,
  SCAN_CHECK=12,REST_FETCH=13,REST_WAIT=14,REST_READ=15,REST_SEND=16,
  READY=17,BEGIN_BANK=18,ERASE_NEXT=19,BANK_WR_HEADER=20,
  COPY_FETCH=21,COPY_WAIT=22,COPY_READ=23,COPY_GOT=24,COPY_DONE=25,
  BANK_COMMIT=26,BANK_DONE=27,APPEND=28,APPEND_DONE=29,
  CRC_PREP=30,WREN=31,WEL=32,WEL_CHECK=33,WRITE_LAUNCH=34,
  POLL_DELAY=35,POLL_CHECK=36,VERIFY=37,VERIFY_CHECK=38,
  MARK=39,WRITE_FINISH=40,OP=41,FAULT=42,BOOT_BUSY=43;
localparam integer TIMER_MAX=POWER_UP_CYCLES>WAKE_CYCLES?
  (POWER_UP_CYCLES>POLL_INTERVAL_CYCLES?POWER_UP_CYCLES:POLL_INTERVAL_CYCLES):
  (WAKE_CYCLES>POLL_INTERVAL_CYCLES?WAKE_CYCLES:POLL_INTERVAL_CYCLES);
localparam integer TW=$clog2(TIMER_MAX+2),PW=$clog2(ERASE_TIMEOUT_CYCLES+2),OW=$clog2(PROGRAM_TIMEOUT_CYCLES+2);
reg [5:0] state,op_return,write_return;
reg [TW-1:0] timer;
reg [PW-1:0] poll_elapsed;
reg [OW-1:0] op_watchdog;
reg [23:0] op_address,entry_address,erase_address;
reg [7:0] op_command;
reg op_addr_valid,op_start;
reg [8:0] op_wlen,op_rlen,tx_index,rx_index;
wire spi_busy,spi_done,spi_error,wr_ready,rd_valid;
wire [7:0] rd_data;
reg [23:0] id_shift;
reg [31:0] rx_magic,rx_seq,rx_crc,rx_expected,rx_marker;
reg [7:0] rx_kind,rx_status;
reg [183:0] rx_record;
wire rx_valid;
reg valid0,valid1,blank0,blank1,uncommitted0,uncommitted1;
reg boot_busy_seen,id_retried,scan_sequence_seen;
reg [31:0] gen0,gen1,generation,next_sequence;
reg active_bank,target_bank;
reg [8:0] scan_slot,next_slot,target_slot;
reg [5:0] record_count,restore_left,copy_left;
reg [4:0] oldest,walk_index;
reg [7:0] pages[0:31],page_read;
reg page_we;
reg [4:0] page_waddr;
reg [7:0] page_wdata;
reg [183:0] pending_record;
reg migration_entry;
reg pending_clear,clear_seen,migrating,initializing;
reg [31:0] write_magic,write_seq,write_crc;
reg [7:0] write_kind;
reg [5:0] crc_index;
reg erase_mode,marker_mode,header_uncommitted;
reg [4:0] erase_sector;
wire [23:0] active_base;
wire [23:0] target_base;
wire [31:0] generation_delta;
wire [4:0] append_index;
wire accept_report;
wire accept_clear;
wire [31:0] crc_next;
reg [7:0] tx_data;
wire [7:0] tx_data_next;
reg data_verify_match,marker_verify_match,header_commit_match;
// Continuous values retain the original net initializer expressions.
assign rx_valid = (~rx_crc)==rx_expected&&rx_marker==COMMIT;
assign active_base = active_bank?BANK1_BASE:BANK0_BASE;
assign target_base = target_bank?BANK1_BASE:BANK0_BASE;
assign generation_delta = gen1-gen0;
assign append_index = oldest+record_count[4:0];
assign accept_report = report_valid&&report_ready;
assign accept_clear = state==READY&&write_enabled&&clear_request&&!clear_seen;
assign crc_next = crc32_byte(rx_crc,rd_valid?rd_data:tx_data);
assign tx_data_next = marker_mode?
  (tx_index==0?COMMIT[31:24]:tx_index==1?COMMIT[23:16]:tx_index==2?COMMIT[15:8]:COMMIT[7:0]):payload_byte(tx_index,write_magic,write_seq,write_crc,write_kind,(migration_entry?rx_record:pending_record));

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 always @(posedge clk)begin
  page_read<=pages[walk_index];
  if(page_we)pages[page_waddr]<=page_wdata;
 end
 
 
 
 
 
 
 
 
 
 
 
 assign committed_record=pending_record;assign restore_record=rx_record;
 assign flash_wp_n=1'b1;assign flash_hold_n=1'b1;
 assign report_ready=state==READY&&write_enabled&&!clear_request;
 
 
 function [31:0] crc32_byte;input [31:0] c;input [7:0] d;
  reg [31:0] t;integer k;begin t=c^{24'd0,d};
   for(k=0;k<8;k=k+1)t=t[0]?(t>>1)^32'hedb88320:t>>1;
   crc32_byte=t;end
 endfunction
 // Serial raw shifting avoids a 32x184 asynchronous report mux or duplicate RAM.
 function [7:0] payload_byte;input [8:0] n;input [31:0] m,s,c;input [7:0] k;input [183:0] r;begin
  case(n)
   0:payload_byte=m[31:24];1:payload_byte=m[23:16];
   2:payload_byte=m[15:8];3:payload_byte=m[7:0];
   4:payload_byte=s[31:24];5:payload_byte=s[23:16];
   6:payload_byte=s[15:8];7:payload_byte=s[7:0];
   8:payload_byte=k;
   40:payload_byte=c[31:24];41:payload_byte=c[23:16];
   42:payload_byte=c[15:8];43:payload_byte=c[7:0];
   default:payload_byte=(n>=12&&n<=34&&k==1)?r[183-(n-12)*8-:8]:8'd0;
  endcase
 end endfunction
 
 
 
 // Byte index advances only on write_ready; the SPI byte engine then owns
 // hundreds of clocks. Register the mux before CRC and wire transmission.
 
 always @(posedge clk)begin
  tx_data<=tx_data_next;
  header_commit_match<=rx_magic==HEADER&&rx_seq==generation+1'b1&&rx_kind==0;
  marker_verify_match<=rx_marker==COMMIT&&rx_valid&&rx_magic==write_magic&&
   rx_seq==write_seq&&rx_kind==write_kind&&rx_expected==write_crc;
  data_verify_match<=(~rx_crc)==write_crc&&rx_expected==write_crc&&
   rx_magic==write_magic&&rx_seq==write_seq&&rx_kind==write_kind;
 end
 recovery_flash_spi_master #(.CLK_DIV(SPI_CLK_DIV)) u_spi(
  .clk(clk),.rst(rst),.start(op_start),.command(op_command),
  .address_valid(op_addr_valid),.address(op_address),.write_length(op_wlen),.read_length(op_rlen),
  .write_data(tx_data),.write_valid(1'b1),.write_ready(wr_ready),
  .read_data(rd_data),.read_valid(rd_valid),.busy(spi_busy),.done(spi_done),.error(spi_error),
  .cs_n(flash_cs_n),.sclk(flash_sclk),.mosi(flash_mosi),.miso(flash_miso));
 task launch;input [7:0] cmd;input av;input [23:0] addr;
  input [8:0] wl,rl;input [5:0] ret;begin
   op_command<=cmd;op_addr_valid<=av;op_address<=addr;op_wlen<=wl;op_rlen<=rl;
   tx_index<=0;rx_index<=0;
   rx_crc<=32'hffffffff;
   op_return<=ret;op_start<=1;op_watchdog<=0;state<=OP;
  end endtask
 task fail;begin storage_fault<=1;write_enabled<=0;storage_ready<=1;
  report_error<=1;restore_valid<=0;state<=FAULT;end endtask
 task start_entry;input [23:0] a;input [31:0] m,s;input [7:0] kind;
  input [183:0] raw;input uncommitted;input [5:0] ret;begin
   entry_address<=a;write_magic<=m;write_seq<=s;write_kind<=kind;
   migration_entry<=state==COPY_GOT;crc_index<=0;marker_mode<=0;
   erase_mode<=0;header_uncommitted<=uncommitted;write_return<=ret;state<=WREN;
  end endtask
 always @(posedge clk)begin
  if(accept_report||accept_clear)pending_record<=report_record;
  if(rd_valid)begin
   id_shift<={id_shift[15:0],rd_data};
   if(rx_index<4)rx_magic<={rx_magic[23:0],rd_data};
   if(rx_index>=4&&rx_index<8)rx_seq<={rx_seq[23:0],rd_data};
   if(rx_index==8)rx_kind<=rd_data;
   if(rx_index>=12&&rx_index<=34)rx_record<={rx_record[175:0],rd_data};
   if(rx_index>=40&&rx_index<44)rx_expected<={rx_expected[23:0],rd_data};
   if(rx_index>=60&&rx_index<64)rx_marker<={rx_marker[23:0],rd_data};
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=POWER;op_return<=0;write_return<=0;timer<=0;poll_elapsed<=0;op_watchdog<=0;
   op_address<=0;entry_address<=0;erase_address<=0;op_command<=0;op_addr_valid<=0;
   op_start<=0;op_wlen<=0;op_rlen<=0;tx_index<=0;rx_index<=0;
   rx_crc<=0;rx_status<=0;
   valid0<=0;valid1<=0;blank0<=0;blank1<=0;uncommitted0<=0;uncommitted1<=0;boot_busy_seen<=0;id_retried<=0;scan_sequence_seen<=0;gen0<=0;gen1<=0;generation<=0;next_sequence<=1;
   active_bank<=0;target_bank<=0;scan_slot<=1;next_slot<=1;target_slot<=1;
   record_count<=0;restore_left<=0;copy_left<=0;oldest<=0;walk_index<=0;
   page_we<=0;page_waddr<=0;page_wdata<=0;migration_entry<=0;
   pending_clear<=0;clear_seen<=0;migrating<=0;initializing<=0;
   write_magic<=0;write_seq<=0;write_crc<=0;write_kind<=0;crc_index<=0;
   erase_mode<=0;marker_mode<=0;header_uncommitted<=0;erase_sector<=0;
   report_commit<=0;report_error<=0;clear_done<=0;
   restore_valid<=0;storage_ready<=0;storage_fault<=0;write_enabled<=0;jedec_id<=0;
  end else begin
   op_start<=0;page_we<=0;report_commit<=0;clear_done<=0;report_error<=0;
   if(!clear_request)clear_seen<=0;
   if(wr_ready)tx_index<=tx_index+1'b1;
   if(rd_valid)begin rx_index<=rx_index+1'b1;if(rx_index==0)rx_status<=rd_data;end
   // One byte-serial CRC engine is shared by transmit and readback.
   if((rd_valid&&rx_index<40)||(wr_ready&&!marker_mode&&tx_index<40))begin
    rx_crc<=crc_next;
    if(wr_ready&&tx_index==39)write_crc<=~crc_next;
   end
   // Counts wall-clock cycles including SPI traffic, not only polling delays.
   if(state==OP)op_watchdog<=op_watchdog+1'b1;
   if(state>=POLL_DELAY&&state<=WRITE_FINISH||state==OP&&(op_return==POLL_CHECK||(op_return==SR1_CHECK&&boot_busy_seen))||state==BOOT_BUSY)poll_elapsed<=poll_elapsed+1'b1;
   case(state)
    POWER:if(timer>=(POWER_UP_CYCLES<=1?0:POWER_UP_CYCLES-1))begin timer<=0;launch(8'hab,0,0,0,0,WAKE);end else timer<=timer+1'b1;
    WAKE:if(timer>=(WAKE_CYCLES<=1?0:WAKE_CYCLES-1))begin timer<=0;state<=ID;end else timer<=timer+1'b1;
    ID:launch(8'h9f,0,0,0,3,ID_CHECK);
    ID_CHECK:begin jedec_id<=id_shift;state<=SR1;end
    SR1:launch(8'h05,0,0,0,1,SR1_CHECK);
    SR1_CHECK:if(rx_status[0])begin
      boot_busy_seen<=1;timer<=0;
      if(poll_elapsed>=ERASE_TIMEOUT_CYCLES)fail();else state<=BOOT_BUSY;
     end else if(rx_status[7:2]!=0)fail();
     else if(jedec_id!=24'hef4017&&jedec_id!=24'hef3017)begin
      // Some devices ignore ID during an operation surviving FPGA-only reset.
      // Status polling is read-only; retry ID once after WIP clears.
      if(boot_busy_seen&&!id_retried)begin id_retried<=1;state<=ID;end else fail();
     end else if(jedec_id==24'hef4017)launch(8'h35,0,0,0,1,SR2_CHECK);else state<=HDR0;
    BOOT_BUSY:if(poll_elapsed>=ERASE_TIMEOUT_CYCLES)fail();
     else if(timer>=(POLL_INTERVAL_CYCLES<=1?0:POLL_INTERVAL_CYCLES-1))begin timer<=0;state<=SR1;end else timer<=timer+1'b1;
    SR2_CHECK:if(rx_status[6])fail();else state<=HDR0;
    HDR0:launch(8'h03,1,BANK0_BASE,0,64,HDR0_CHECK);
    HDR0_CHECK:begin valid0<=rx_valid&&rx_magic==HEADER&&rx_kind==0;gen0<=rx_seq;
     blank0<=rx_magic==32'hffffffff&&rx_marker==32'hffffffff;uncommitted0<=rx_marker!=COMMIT;launch(8'h03,1,BANK1_BASE,0,64,HDR1_CHECK);end
    HDR1_CHECK:begin valid1<=rx_valid&&rx_magic==HEADER&&rx_kind==0;gen1<=rx_seq;
     blank1<=rx_magic==32'hffffffff&&rx_marker==32'hffffffff;uncommitted1<=rx_marker!=COMMIT;state<=SELECT;end
    SELECT:begin
     if(valid0||valid1)begin
      active_bank<=valid1&&(!valid0||!generation_delta[31]);
      generation<=valid1&&(!valid0||!generation_delta[31])?gen1:gen0;
      write_enabled<=1;scan_slot<=1;next_slot<=1;state<=SCAN;
     end else if(uncommitted0&&uncommitted1)begin
      // Blank device initialized transactionally. Interrupted first format is
      // recoverable because no committed bank can contain user reports yet.
      target_bank<=0;generation<=0;initializing<=1;state<=BEGIN_BANK;
     end else fail();
    end
    SCAN:launch(8'h03,1,active_base+{scan_slot[7:0],8'd0},0,64,SCAN_CHECK);
    SCAN_CHECK:begin
     // Any partially programmed slot is consumed forever until bank erase.
     if(rx_magic!=32'hffffffff||rx_marker!=32'hffffffff)next_slot<=scan_slot+1'b1;
     if(rx_marker==COMMIT&&!(rx_valid&&rx_magic==MAGIC&&(rx_kind==1||rx_kind==2)))fail();
     else if(rx_valid&&rx_magic==MAGIC&&scan_sequence_seen&&rx_seq!=next_sequence)fail();
     else begin
      if(rx_valid&&rx_magic==MAGIC)begin
       next_sequence<=rx_seq+1'b1;scan_sequence_seen<=1;
       if(rx_kind==2)begin record_count<=0;oldest<=0;end
       else if(rx_kind==1)begin page_we<=1;page_waddr<=append_index;page_wdata<=scan_slot[7:0];
        if(record_count==32)oldest<=oldest+1'b1;else record_count<=record_count+1'b1;end
      end
      if(scan_slot>=LAST_SLOT)begin walk_index<=oldest;restore_left<=record_count;state<=REST_FETCH;end
      else begin scan_slot<=scan_slot+1'b1;state<=SCAN;end
     end
    end
    REST_FETCH:begin walk_index<=oldest;restore_left<=record_count;state<=REST_WAIT;end
    REST_WAIT:if(restore_left==0)begin storage_ready<=1;state<=READY;end else state<=REST_READ;
    REST_READ:launch(8'h03,1,active_base+{page_read,8'd0},0,64,REST_SEND);
    REST_SEND:if(!restore_valid)begin
      if(!rx_valid||rx_magic!=MAGIC||rx_kind!=1)fail();
      else begin restore_valid<=1;end
     end else if(restore_ready)begin
      restore_valid<=0;restore_left<=restore_left-1'b1;walk_index<=walk_index+1'b1;state<=REST_WAIT;end
    READY:begin
     restore_valid<=0;
     if(accept_clear||accept_report)begin
      pending_clear<=clear_request&&!clear_seen;
      if(clear_request)clear_seen<=1;
      if(next_slot>LAST_SLOT)begin target_bank<=~active_bank;initializing<=0;state<=BEGIN_BANK;end
      else state<=APPEND;
     end
    end
    BEGIN_BANK:begin erase_sector<=0;erase_mode<=1;marker_mode<=0;state<=ERASE_NEXT;end
    ERASE_NEXT:begin erase_address<=target_base+{erase_sector,12'd0};erase_mode<=1;
     write_return<=BANK_WR_HEADER;state<=WREN;end
    BANK_WR_HEADER:if(erase_sector+1<SECTORS)begin erase_sector<=erase_sector+1'b1;state<=ERASE_NEXT;end
     else start_entry(target_base,HEADER,generation+1'b1,0,0,1,COPY_FETCH);
    COPY_FETCH:begin copy_left<=record_count;walk_index<=oldest;target_slot<=1;state<=COPY_WAIT;end
    COPY_WAIT:if(copy_left==0)state<=BANK_COMMIT;else state<=COPY_READ;
    COPY_READ:launch(8'h03,1,active_base+{page_read,8'd0},0,64,COPY_GOT);
    COPY_GOT:if(!rx_valid||rx_magic!=MAGIC||rx_kind!=1)fail();
     else start_entry(target_base+{target_slot[7:0],8'd0},MAGIC,rx_seq,1,rx_record,0,COPY_DONE);
    COPY_DONE:begin page_we<=1;page_waddr<=walk_index;page_wdata<=target_slot[7:0];
     copy_left<=copy_left-1'b1;walk_index<=walk_index+1'b1;target_slot<=target_slot+1'b1;state<=COPY_WAIT;end
    BANK_COMMIT:begin entry_address<=target_base;write_return<=BANK_DONE;
     erase_mode<=0;marker_mode<=1;header_uncommitted<=0;state<=WREN;end
    BANK_DONE:begin active_bank<=target_bank;generation<=generation+1'b1;next_slot<=target_slot;
     if(initializing)begin storage_ready<=1;write_enabled<=1;state<=READY;end else state<=APPEND;end
    APPEND:start_entry(active_base+{next_slot[7:0],8'd0},MAGIC,next_sequence,pending_clear?8'd2:8'd1,
     pending_clear?184'd0:pending_record,0,APPEND_DONE);
    APPEND_DONE:begin
     next_slot<=next_slot+1'b1;next_sequence<=next_sequence+1'b1;
     if(pending_clear)begin record_count<=0;oldest<=0;clear_done<=1;end
     else begin page_we<=1;page_waddr<=append_index;page_wdata<=next_slot[7:0];
      if(record_count==32)oldest<=oldest+1'b1;else record_count<=record_count+1'b1;
      report_commit<=1;end
     state<=READY;
    end
    WREN:begin poll_elapsed<=0;timer<=0;launch(8'h06,0,0,0,0,WEL);end
    WEL:launch(8'h05,0,0,0,1,WEL_CHECK);
    WEL_CHECK:if(!rx_status[1])fail();else state<=WRITE_LAUNCH;
    WRITE_LAUNCH:if(erase_mode)launch(8'h20,1,erase_address,0,0,POLL_DELAY);
     else launch(8'h02,1,{entry_address[23:8],marker_mode?8'd60:8'd0},marker_mode?9'd4:9'd44,0,POLL_DELAY);
    POLL_DELAY:if(poll_elapsed>=(erase_mode?ERASE_TIMEOUT_CYCLES:PROGRAM_TIMEOUT_CYCLES))fail();
     else if(timer>=(POLL_INTERVAL_CYCLES<=1?0:POLL_INTERVAL_CYCLES-1))begin timer<=0;launch(8'h05,0,0,0,1,POLL_CHECK);end else timer<=timer+1'b1;
    POLL_CHECK:if(rx_status[0])state<=POLL_DELAY;
     else if(erase_mode)state<=write_return;else state<=VERIFY;
    VERIFY:launch(8'h03,1,entry_address,0,64,VERIFY_CHECK);
    VERIFY_CHECK:begin
     if(marker_mode)begin if((write_return==BANK_DONE?(rx_marker==COMMIT&&rx_valid&&header_commit_match):marker_verify_match))
        state<=write_return;else fail();end
     else if(data_verify_match)begin
      if(header_uncommitted)state<=write_return;else begin marker_mode<=1;state<=WREN;end
     end else fail();
    end
    OP:if(spi_error||op_watchdog>=PROGRAM_TIMEOUT_CYCLES)fail();else if(spi_done)state<=op_return;
    FAULT:begin restore_valid<=0;end
    default:fail();
   endcase
  end
 end
endmodule

// Four immutable pending reports. Worst-case migration erases16 sectors at
// 400ms each, while the fastest normal completed PACU uses five600ms holds.
// Overflow fails explicitly instead of replacing an older uncommitted record.
module recovery_report_pending_queue(
 input wire clk,rst,capture,clear_commit,input wire [183:0] record,
 output wire valid,output wire [183:0] data,input wire ready,output reg overflow
);

(* ram_style="bram" *)reg [183:0] mem[0:3];
reg [1:0] wr,rd;
reg [2:0] count;
reg [183:0] front;
reg [1:0] load_state;
wire take;
wire put;
// Continuous values retain the original net initializer expressions.
assign take = valid&&ready;
assign put = capture&&(count<4||take);

 
 
 
 
 
 assign valid=count!=0&&load_state==2;
 assign data=front;
 always @(posedge clk)begin
  if(put)mem[wr]<=record;
  if(load_state==1)front<=mem[rd];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin wr<=0;rd<=0;count<=0;overflow<=0;load_state<=0;end
  else if(clear_commit)begin wr<=0;rd<=0;count<=0;overflow<=0;load_state<=0;end
  else begin
   case({put,take})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:begin end endcase
   if(capture&&!put)overflow<=1;
   if(put)wr<=wr+1'b1;
   if(take)begin rd<=rd+1'b1;load_state<=0;end
   else if(load_state==0&&count!=0)load_state<=1;
   else if(load_state==1)load_state<=2;
  end
 end
endmodule

`default_nettype wire
