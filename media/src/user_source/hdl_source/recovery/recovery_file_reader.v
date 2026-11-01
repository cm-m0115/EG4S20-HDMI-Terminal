`default_nettype none
`timescale 1ns/1ps
// FAT32 read-only 8.3 reader. A single synchronous-read sector RAM is shared by
// directory parsing and file output; metadata is captured at constant byte offsets.
module recovery_file_reader #(
    parameter integer TIMEOUT_CYCLES=200000000,
    parameter integer MAX_CHAIN_CLUSTERS=65536,
    parameter integer MIN_FAT32_CLUSTERS=65525
)(
    input wire clk, input wire rst, input wire start, input wire cancel,
    input wire [87:0] file_name,
    output wire busy, output reg file_begin, output reg [31:0] file_size,
    output wire byte_valid, output wire [7:0] byte_data, input wire byte_ready,
    output reg file_done, output reg [7:0] error,
    output wire sector_req, output reg [31:0] sector_lba,
    input wire sector_ready, input wire sector_byte_valid,
    input wire [7:0] sector_byte, input wire [8:0] sector_byte_index,
    input wire sector_done, input wire [7:0] sector_error
);

localparam IDLE=0, REQ=1, WAIT_SEC=2, BOOT0=3, BPB=4, LAYOUT=5,
      DIR=6, DIR_NEXT=7, FAT_PARSE=8, DATA=9, DATA_NEXT=10, FINISH=11,
      DIR_PRIME=12, DATA_PRIME=13, MBR_SELECT=14,MBR_DECIDE=15,LAY_OVER=16,LAY_FREE=17,LAY_SHIFT=18,LAY_LIMIT=19,LAY_CHECK=20,LAY_GO=21,CLUSTER_SHIFT=22,CLUSTER_BASE=23,CLUSTER_READ=24,
      MBR_SUM=25,MBR_CHECK=26,DIR_ENTRY_CHECK=27,LAY_VALIDATE=28,DIR_CAPTURE=29,FAT_CHECK=30,DIR_ENTRY_GO=31,
      SEC_CHECK=32,BPB_DECIDE=33;
reg [33:0] state_hot;
reg [5:0] state;
reg [4:0] after_read,fat_return,cluster_return;
// S4 resource extension: span -> free -> need have disjoint init lives.
reg [32:0] layout_work,overhead_r,clusters_r,volume_end_r;
// layout root and runtime cluster chains have disjoint lives.
// Each step still truncates to 32 bits on the same original FSM edge.
reg [31:0] work_lba;
reg [7:0] cluster_sector;
reg [7:0] block_mem[0:511];
reg [7:0] ram_byte;
reg [7:0] directory_byte;
reg ram_last,ram_entry_first,ram_entry_last,ram_name_byte;
reg [4:0] ram_entry_offset;
reg directory_last,directory_first,directory_entry_last,directory_name_byte;
reg [4:0] directory_offset;
reg mbr_bad;
reg sector_capture_bad,bpb_format_bad,bpb_range_bad,bpb_flags_bad;
reg [7:0] sector_capture_error;
reg capture_boot,capture_fat;
reg layout_bounds_bad,layout_root_bad,layout_volume_bad;
reg fat_eoc,fat_cluster_bad,fat_chain_bad,entry_bad;
reg [8:0] pos, fat_offset;
reg [9:0] capture_count;
reg capture_bad, cancel_pending;
reg [31:0] timer;
reg [87:0] name_latched, name_shift;
reg name_init,name_advance;
reg entry_match, entry_valid;
reg [31:0] entry_cluster, entry_size;
reg [31:0] part_lba, part_sectors;
// BPB fields remain immutable after successful BPB_DECIDE until next start.
// Direct aliases remove redundant configuration copies, not validation.
wire [31:0] total_sectors, fat_size, root_cluster;
wire [15:0] reserved;
wire [7:0] spc, fat_count;
reg [2:0] spc_shift;
reg active_fat;
reg [31:0] fat_base, data_base, cluster_max;
reg [31:0] current_cluster, chain_count, remaining, fat_entry;
reg [7:0] sector_in_cluster;
reg [7:0] boot_jump,bpb_spc,bpb_fats;
reg [15:0] signature,bpb_bps,bpb_reserved,bpb_root_entries,bpb_total16,bpb_fat16,bpb_flags,bpb_version;
reg [31:0] bpb_total,bpb_fatsize,bpb_root;
reg [7:0] partition_type[0:3];
// Sequential MBR byte capture retains only the first FAT32 entry.
// Original type scan and MBR decision cycles are unchanged.
reg [31:0] first_partition_start,first_partition_size;
reg partition_found;
reg [1:0] first_partition_slot;
reg [2:0] partition_index;
reg [32:0] partition_end;
integer k;
wire [32:0] fat_span;
wire [32:0] overhead;
wire [32:0] clusters_calc;
wire [31:0] next_cluster;
wire [31:0] finished_entry_size;
// Continuous values retain the original net initializer expressions.
assign spc=bpb_spc;
assign reserved=bpb_reserved;
assign fat_count=bpb_fats;
assign total_sectors=bpb_total;
assign fat_size=bpb_fatsize;
assign root_cluster=bpb_root;
assign fat_span = (fat_count==2)?{fat_size,1'b0}:{1'b0,fat_size};
assign overhead = fat_span+reserved;
assign clusters_calc = ({1'b0,total_sectors}-overhead)>>spc_shift;
assign next_cluster = {4'd0,fat_entry[27:0]};
assign finished_entry_size = {directory_byte,entry_size[23:0]};

    
    // Direct state flags remove the binary decode / next-state mux loop.
    // Public FAT/byte handshakes and every transition edge remain unchanged.
    
    // Numeric observation is registered as before, so hierarchical legacy
    // test waits do not react to delta-cycle glitches of a combinational
    // encoder. It has no functional consumers or production output and is
    // removed by synthesis; all control uses state_hot below.
    
    function [33:0] encode_state;
        input [5:0] value;
        begin encode_state=34'd1<<value;end
    endfunction
    task set_state;
        input [5:0] value;
        begin state<=value;state_hot<=encode_state(value);end
    endtask
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    always @(posedge clk or posedge rst)begin
        if(rst)begin name_init<=0;name_advance<=0;end
        else begin
            name_init<=state_hot[DIR_CAPTURE]&&!cancel&&ram_entry_first&&ram_byte!=0;
            name_advance<=state_hot[DIR_CAPTURE]&&!cancel&&!ram_entry_first&&!ram_entry_last&&ram_name_byte;
        end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)name_shift<=0;
        else if(name_init)name_shift<={name_latched[79:0],8'd0};
        else if(name_advance)name_shift<={name_shift[79:0],8'd0};
    end

    
    
    
    
    
    
    
    
    
    
    // Boot-sector fields. Their write addresses are constants, not RAM read muxes.
    
    
    
    
    
    
    
    
    
    
    
    
    
    assign busy=!state_hot[IDLE];
    assign sector_req=state_hot[REQ] && !cancel && !cancel_pending;
    assign byte_valid=state_hot[DATA] && remaining!=0 && !cancel;
    assign byte_data=ram_byte;
    // Exactly one RAM write and one synchronous read port. No reset of the array.
    always @(posedge clk) begin
        if(state_hot[WAIT_SEC] && sector_byte_valid && capture_count<512 &&
           sector_byte_index==capture_count[8:0]) block_mem[sector_byte_index]<=sector_byte;
        ram_byte<=block_mem[pos];
        // These tags have the same address and latency as the synchronous RAM
        // byte, including the PRIME cycle after a position/sector change.
        ram_last<=pos==9'd511;
        ram_entry_first<=pos[4:0]==5'd0;
        ram_entry_last<=pos[4:0]==5'd31;
        ram_name_byte<=pos[4:0]<=5'd10;
        ram_entry_offset<=pos[4:0];
    end
    function [2:0] cluster_shift;
        input [7:0] s;
        begin
            case(s) 2:cluster_shift=1;4:cluster_shift=2;8:cluster_shift=3;
              16:cluster_shift=4;32:cluster_shift=5;64:cluster_shift=6;
              128:cluster_shift=7;default:cluster_shift=0;endcase
        end
    endfunction
    task read_block;
        input [31:0] lba; input [4:0] next_state;
        begin sector_lba<=lba;after_read<=next_state;timer<=0;set_state(REQ);end
    endtask
    task read_cluster;
        input [31:0] c;input [7:0] offset;input [4:0] next_state;
        begin work_lba<=c-2;cluster_sector<=offset;cluster_return<=next_state;set_state(CLUSTER_SHIFT);end
    endtask
    task fail;
        input [7:0] e;
        begin error<=e;set_state(FINISH);end
    endtask
    task read_fat;
        input [4:0] return_state;
        begin
            fat_offset<={current_cluster[6:0],2'b00};fat_return<=return_state;
            read_block(fat_base+(current_cluster>>7),FAT_PARSE);
        end
    endtask
    // Complete ordered sectors are checked before any MBR cache is used.
    always @(posedge clk or posedge rst)begin
      if(rst)begin partition_found<=0;first_partition_slot<=0;end
      else if(state_hot[REQ]&&sector_ready&&!cancel)partition_found<=0;
      else if(capture_boot&&sector_byte_valid&&sector_byte_index[8:6]==3'b111&&
              sector_byte_index[3:0]==4'd2&&!partition_found&&
              (sector_byte==8'h0b||sector_byte==8'h0c))begin
        partition_found<=1;first_partition_slot<=sector_byte_index[5:4];
      end
    end
    // No reset needed: all eight numeric bytes precede valid MBR_SELECT.
    always @(posedge clk)if(capture_boot&&sector_byte_valid&&partition_found&&
      sector_byte_index[8:6]==3'b111&&sector_byte_index[5:4]==first_partition_slot)begin
      case(sector_byte_index[3:0])
        6:first_partition_start[7:0]<=sector_byte;
        7:first_partition_start[15:8]<=sector_byte;
        8:first_partition_start[23:16]<=sector_byte;
        9:first_partition_start[31:24]<=sector_byte;
        10:first_partition_size[7:0]<=sector_byte;
        11:first_partition_size[15:8]<=sector_byte;
        12:first_partition_size[23:16]<=sector_byte;
        13:first_partition_size[31:24]<=sector_byte;
        default:;
      endcase
    end

    // Capturing headers removes many asynchronous reads from the 512-byte RAM.
    always @(posedge clk or posedge rst) begin
      if(rst) begin
        boot_jump<=0;signature<=0;bpb_bps<=0;bpb_spc<=0;bpb_reserved<=0;bpb_fats<=0;
        bpb_root_entries<=0;bpb_total16<=0;bpb_fat16<=0;bpb_total<=0;bpb_fatsize<=0;
        bpb_flags<=0;bpb_version<=0;bpb_root<=0;fat_entry<=0;
        for(k=0;k<4;k=k+1) begin partition_type[k]<=0;end
      end else if(sector_byte_valid) begin
        // The owner/type qualifications are registered at the REQ handshake.
        // This avoids decoded FSM fanout in every boot/FAT byte write enable.
        if(capture_boot) begin
          case(sector_byte_index)
            0:boot_jump<=sector_byte;
            11:bpb_bps[7:0]<=sector_byte;12:bpb_bps[15:8]<=sector_byte;
            13:bpb_spc<=sector_byte;14:bpb_reserved[7:0]<=sector_byte;15:bpb_reserved[15:8]<=sector_byte;
            16:bpb_fats<=sector_byte;17:bpb_root_entries[7:0]<=sector_byte;18:bpb_root_entries[15:8]<=sector_byte;
            19:bpb_total16[7:0]<=sector_byte;20:bpb_total16[15:8]<=sector_byte;
            22:bpb_fat16[7:0]<=sector_byte;23:bpb_fat16[15:8]<=sector_byte;
            32:bpb_total[7:0]<=sector_byte;33:bpb_total[15:8]<=sector_byte;
            34:bpb_total[23:16]<=sector_byte;35:bpb_total[31:24]<=sector_byte;
            36:bpb_fatsize[7:0]<=sector_byte;37:bpb_fatsize[15:8]<=sector_byte;
            38:bpb_fatsize[23:16]<=sector_byte;39:bpb_fatsize[31:24]<=sector_byte;
            40:bpb_flags[7:0]<=sector_byte;41:bpb_flags[15:8]<=sector_byte;
            42:bpb_version[7:0]<=sector_byte;43:bpb_version[15:8]<=sector_byte;
            44:bpb_root[7:0]<=sector_byte;45:bpb_root[15:8]<=sector_byte;
            46:bpb_root[23:16]<=sector_byte;47:bpb_root[31:24]<=sector_byte;
            510:signature[7:0]<=sector_byte;511:signature[15:8]<=sector_byte;
          endcase
          for(k=0;k<4;k=k+1) begin
            if(sector_byte_index==450+k*16) partition_type[k]<=sector_byte;
          end
        end
        if(capture_fat) begin
          if(sector_byte_index==fat_offset) fat_entry[7:0]<=sector_byte;
          if(sector_byte_index==fat_offset+1) fat_entry[15:8]<=sector_byte;
          if(sector_byte_index==fat_offset+2) fat_entry[23:16]<=sector_byte;
          if(sector_byte_index==fat_offset+3) fat_entry[31:24]<=sector_byte;
        end
      end
    end
    always @(posedge clk or posedge rst) begin
      if(rst) begin
        set_state(IDLE);after_read<=IDLE;cluster_return<=0;layout_work<=0;overhead_r<=0;clusters_r<=0;volume_end_r<=0;work_lba<=0;cluster_sector<=0;file_begin<=0;file_done<=0;error<=0;file_size<=0;
        sector_lba<=0;capture_count<=0;capture_bad<=0;cancel_pending<=0;timer<=0;
        name_latched<=0;entry_match<=0;entry_valid<=0;entry_cluster<=0;entry_size<=0;
        part_lba<=0;part_sectors<=0;
        spc_shift<=0;active_fat<=0;
        fat_base<=0;data_base<=0;cluster_max<=0;current_cluster<=0;chain_count<=0;
        remaining<=0;sector_in_cluster<=0;pos<=0;fat_offset<=0;fat_return<=0;partition_index<=0;partition_end<=0;
        directory_byte<=0;capture_boot<=0;capture_fat<=0;
        directory_last<=0;directory_first<=0;directory_entry_last<=0;directory_name_byte<=0;directory_offset<=0;mbr_bad<=0;
        sector_capture_bad<=0;sector_capture_error<=0;bpb_format_bad<=0;bpb_range_bad<=0;bpb_flags_bad<=0;
        layout_bounds_bad<=0;layout_root_bad<=0;layout_volume_bad<=0;
        fat_eoc<=0;fat_cluster_bad<=0;fat_chain_bad<=0;entry_bad<=0;
      end else begin
        file_begin<=0;file_done<=0;
        case(1'b1) // synthesis parallel_case
          state_hot[IDLE]:if(start&&!cancel) begin
            name_latched<=file_name;error<=0;file_size<=0;cancel_pending<=0;
            part_lba<=0;part_sectors<=0;read_block(0,BOOT0);
          end
          state_hot[REQ]:begin
            timer<=timer+1;
            if(sector_ready&&!cancel) begin
              capture_count<=0;capture_bad<=0;timer<=0;set_state(WAIT_SEC);
              capture_boot<=after_read==BOOT0 || after_read==BPB;
              capture_fat<=after_read==FAT_PARSE;
            end
            else if(timer>=TIMEOUT_CYCLES-1) fail(8'h21);
          end
          state_hot[WAIT_SEC]:begin
            timer<=timer+1;
            if(sector_byte_valid) begin
              if(capture_count>=512 || sector_byte_index!=capture_count[8:0]) capture_bad<=1;
              if(capture_count<513) capture_count<=capture_count+1;
            end
            if(sector_done) begin
              timer<=0;pos<=0;capture_boot<=0;capture_fat<=0;
              // Qualify the exact completion edge, including an optional
              // simultaneous final byte. Decide from held flags next cycle;
              // the count/index comparison no longer fans out through FSM CE.
              sector_capture_error<=sector_error;
              sector_capture_bad<=capture_bad || (sector_byte_valid &&
                (capture_count>=512 || sector_byte_index!=capture_count[8:0])) ||
                (sector_byte_valid?capture_count!=511:capture_count!=512);
              set_state(SEC_CHECK);
            end else if(timer>=TIMEOUT_CYCLES-1) begin capture_boot<=0;capture_fat<=0;fail(8'h21);end
          end
          state_hot[SEC_CHECK]:begin
            if(cancel_pending||cancel) fail(8'h7f);
            else if(sector_capture_error!=0) fail(sector_capture_error);
            else if(sector_capture_bad) fail(8'h22);
            else set_state(after_read);
          end
          state_hot[BOOT0]:begin
            if(signature!=16'haa55) fail(8'h23);
            else if(boot_jump==8'heb||boot_jump==8'he9) set_state(BPB);
            else begin partition_index<=0;set_state(MBR_SELECT);end
          end
          state_hot[MBR_SELECT]:begin
            if(partition_index==4) fail(8'h24);
            else if(partition_type[partition_index[1:0]]==8'h0b || partition_type[partition_index[1:0]]==8'h0c) begin
              // Separate the table mux, 33-bit address sum and validation.
              part_lba<=first_partition_start;part_sectors<=first_partition_size;
              set_state(MBR_SUM);
            end else partition_index<=partition_index+1;
          end
          state_hot[MBR_SUM]:begin partition_end<={1'b0,part_lba}+{1'b0,part_sectors};set_state(MBR_CHECK);end
          state_hot[MBR_CHECK]:begin
            mbr_bad<=part_lba==0 || part_sectors==0 || partition_end>33'h100000000;
            set_state(MBR_DECIDE);
          end
          state_hot[MBR_DECIDE]:begin
            if(mbr_bad) fail(8'h24);
            else read_block(part_lba,BPB);
          end
          state_hot[BPB]:begin
            // Held boot fields feed three local qualification registers.
            // Their result, rather than the wide raw predicate, enables all
            // layout configuration registers on the following edge.
            bpb_format_bad<=signature!=16'haa55 || bpb_bps!=512 || bpb_spc==0 ||
              (bpb_spc&(bpb_spc-1'b1))!=0 || bpb_reserved==0 ||
              (bpb_fats!=1 && bpb_fats!=2) || bpb_root_entries!=0 || bpb_total16!=0 ||
              bpb_fat16!=0;
            bpb_range_bad<=bpb_total==0 || bpb_fatsize==0 || bpb_version!=0 ||
              bpb_root<2 || bpb_root>=32'h0ffffff0;
            bpb_flags_bad<=bpb_flags[7] && {4'd0,bpb_flags[3:0]}>=bpb_fats;
            set_state(BPB_DECIDE);
          end
          state_hot[BPB_DECIDE]:begin
            if(bpb_format_bad||bpb_range_bad||bpb_flags_bad) fail(8'h25);
            else begin
              spc_shift<=cluster_shift(bpb_spc);
              
              active_fat<=bpb_flags[7]&&bpb_flags[0];set_state(LAYOUT);
            end
          end
          state_hot[LAYOUT]:begin layout_work<=fat_span;set_state(LAY_OVER);end
          state_hot[LAY_OVER]:begin overhead_r<=layout_work+reserved;volume_end_r<={1'b0,part_lba}+{1'b0,total_sectors};set_state(LAY_FREE);end
          state_hot[LAY_FREE]:begin layout_work<={1'b0,total_sectors}-overhead_r;data_base<=part_lba+overhead_r[31:0];fat_base<=part_lba+reserved;work_lba<=root_cluster-2;set_state(LAY_SHIFT);end
          state_hot[LAY_SHIFT]:begin clusters_r<=layout_work>>spc_shift;work_lba<=work_lba<<spc_shift;fat_base<=fat_base+(active_fat?fat_size:0);set_state(LAY_LIMIT);end
          state_hot[LAY_LIMIT]:begin cluster_max<=clusters_r[31:0]+1;layout_work<=clusters_r+2;work_lba<=data_base+work_lba;set_state(LAY_CHECK);end
          state_hot[LAY_CHECK]:begin
            layout_bounds_bad<=overhead_r>={1'b0,total_sectors}||clusters_r<MIN_FAT32_CLUSTERS||clusters_r>33'h00fffffee;
            layout_root_bad<=root_cluster>cluster_max||{fat_size,7'd0}<layout_work;
            layout_volume_bad<=volume_end_r>33'h100000000||(part_sectors!=0&&total_sectors>part_sectors);
            set_state(LAY_VALIDATE);
          end
          state_hot[LAY_VALIDATE]:begin if(layout_bounds_bad||layout_root_bad||layout_volume_bad)fail(8'h25);else set_state(LAY_GO);end
          state_hot[LAY_GO]:begin current_cluster<=root_cluster;chain_count<=1;sector_in_cluster<=0;read_block(work_lba,DIR_PRIME);end
          state_hot[CLUSTER_SHIFT]:begin work_lba<=work_lba<<spc_shift;set_state(CLUSTER_BASE);end
          state_hot[CLUSTER_BASE]:begin work_lba<=data_base+work_lba;set_state(CLUSTER_READ);end
          state_hot[CLUSTER_READ]:read_block(work_lba+cluster_sector,cluster_return);
          state_hot[DIR_PRIME]:set_state(DIR_CAPTURE);
          state_hot[DIR_CAPTURE]:begin
            directory_byte<=ram_byte;
            directory_last<=ram_last;directory_first<=ram_entry_first;
            directory_entry_last<=ram_entry_last;directory_name_byte<=ram_name_byte;
            directory_offset<=ram_entry_offset;set_state(DIR);
          end
          state_hot[DIR]:begin
            if(directory_first) begin
              if(directory_byte==0) fail(8'h26);
              else begin
                entry_valid<=directory_byte!=8'he5;entry_match<=directory_byte==name_latched[87:80];
                entry_cluster<=0;entry_size<=0;
                pos<=pos+1;set_state(DIR_PRIME);
              end
            end else if(directory_entry_last) begin
              if(entry_match && entry_valid) begin
                // Capture the final directory byte before fanout to the
                // parser decision and BMP/PCM start/file-size registers.
                entry_size<=finished_entry_size;set_state(DIR_ENTRY_CHECK);
              end else if(directory_last) set_state(DIR_NEXT);
              else begin pos<=pos+1;set_state(DIR_PRIME);end
            end else begin
              if(directory_name_byte) begin
                if(directory_byte!=name_shift[87:80]) entry_match<=0;
                
              end
              case(directory_offset)
                11:if(directory_byte==8'h0f || (directory_byte&8'h18)!=0) entry_valid<=0;
                20:entry_cluster[23:16]<=directory_byte;21:entry_cluster[31:24]<=directory_byte;
                26:entry_cluster[7:0]<=directory_byte;27:entry_cluster[15:8]<=directory_byte;
                28:entry_size[7:0]<=directory_byte;29:entry_size[15:8]<=directory_byte;30:entry_size[23:16]<=directory_byte;
              endcase
              pos<=pos+1;set_state(DIR_PRIME);
            end
          end
          state_hot[DIR_ENTRY_CHECK]:begin
            entry_bad<=entry_size==0 || entry_cluster<2 || entry_cluster>cluster_max || entry_cluster>=32'h0ffffff0;
            set_state(DIR_ENTRY_GO);
          end
          state_hot[DIR_ENTRY_GO]:begin
            if(entry_bad) fail(8'h27);
            else begin
              file_size<=entry_size;remaining<=entry_size;file_begin<=1;
              current_cluster<=entry_cluster;sector_in_cluster<=0;chain_count<=1;
              read_cluster(entry_cluster,0,DATA_PRIME);
            end
          end
          state_hot[DIR_NEXT]:begin
            if(sector_in_cluster+1<spc) begin sector_in_cluster<=sector_in_cluster+1;read_cluster(current_cluster,sector_in_cluster+1,DIR_PRIME);end
            else read_fat(DIR_PRIME);
          end
          state_hot[FAT_PARSE]:begin
            fat_eoc<=next_cluster>=32'h0ffffff8;
            fat_cluster_bad<=next_cluster<2 || next_cluster>=32'h0ffffff0 || next_cluster>cluster_max;
            fat_chain_bad<=next_cluster==current_cluster || chain_count>=MAX_CHAIN_CLUSTERS;
            set_state(FAT_CHECK);
          end
          state_hot[FAT_CHECK]:begin
            if(fat_eoc) fail(fat_return==DIR_PRIME?8'h26:8'h28);
            else if(fat_cluster_bad) fail(8'h29);
            else if(fat_chain_bad) fail(8'h2a);
            else begin current_cluster<=next_cluster;chain_count<=chain_count+1;sector_in_cluster<=0;read_cluster(next_cluster,0,fat_return);end
          end
          state_hot[DATA_PRIME]:set_state(DATA);
          state_hot[DATA]:begin
            if(byte_valid&&byte_ready) begin
              timer<=0;remaining<=remaining-1;
              if(remaining==1) set_state(FINISH);
              else if(ram_last) set_state(DATA_NEXT);
              else begin pos<=pos+1;set_state(DATA_PRIME);end
            end else if(timer>=TIMEOUT_CYCLES-1) fail(8'h2b);
            else timer<=timer+1;
          end
          state_hot[DATA_NEXT]:begin
            if(sector_in_cluster+1<spc) begin sector_in_cluster<=sector_in_cluster+1;read_cluster(current_cluster,sector_in_cluster+1,DATA_PRIME);end
            else read_fat(DATA_PRIME);
          end
          state_hot[FINISH]:begin file_done<=1;set_state(IDLE);cancel_pending<=0;end
          default:fail(8'h2f);
        endcase
        if(cancel && !state_hot[IDLE] && !state_hot[FINISH]) begin
          if(state_hot[WAIT_SEC]&&!sector_done) cancel_pending<=1;
          else fail(8'h7f);
        end
      end
    end
endmodule

`default_nettype wire
