`default_nettype none
`timescale 1ns/1ps
// four logical 640x480x32 frame slots. SD/control clock domain.
// A load completion is trusted only after both decoder_done and the qualified
// frame_write_finish supplied by the integration layer. This module does not
// infer physical SDRAM completion from a decoder EOF.
module frame_bank_manager #(
    parameter integer KEEP_PREVIOUS_ENABLE = 0
) (
    input wire clk,
    input wire rst,
    input wire [7:0] current_epoch,
    input wire cancel,
    input wire load_req,
    input wire [5:0] load_image_id,
    output wire load_req_ready,
    input wire [3:0] protect_mask,
    output reg loader_start,
    output reg [1:0] loader_bank,
    output reg [5:0] loader_image_id,
    output reg [7:0] loader_epoch,
    input wire decoder_done,
    input wire frame_write_finish,
    input wire [7:0] loader_error,
    input wire loader_idle,
    output reg image_ready,
    output reg [1:0] ready_bank,
    output reg [5:0] ready_image_id,
    output reg [7:0] ready_epoch,
    output reg cache_hit,
    output reg [7:0] load_error,
    output reg load_busy,
    output reg [3:0] bank_valid,
    input wire keep_image_valid,
    input wire [5:0] keep_image_id
);

reg [5:0] bank_image [0:3];
reg [1:0] replacement_start;
reg start_guard;
reg decoder_seen;
reg write_seen;
reg discard_load;
reg [7:0] saved_error;
wire [3:0] hit_mask ;
wire [3:0] keep_mask ;
wire [3:0] unprotected ;
wire [3:0] preferred ;
wire [3:0] replaceable ;
wire [3:0] invalid_available ;
wire [3:0] preferred_available ;
reg [3:0] prepared_available,prepared_protect,prepared_valid_banks;
reg [5:0] prepared_keep_id;
reg prepared_keep_valid,prepared;
reg [3:0] preference_protect,preference_valid_banks,preference_keep_mask;
reg [5:0] preference_keep_id;
reg preference_keep_valid,preference_ready;
wire [3:0] preference_unprotected;
wire [3:0] preference_preferred;
wire [3:0] preference_replaceable;
wire [3:0] preference_invalid;
wire [3:0] preference_available;
wire selection_current ;
wire [3:0] available ;
wire hit_found ;
wire free_found ;
wire [1:0] hit_bank;
wire [1:0] free_bank;
wire [3:0] free_onehot;
wire [1:0] replacement_next;
integer j;
wire retire_load ;
wire bad_load ;
wire completed_load ;
wire discarded_load ;
wire start_miss ;
// Continuous values retain the original net initializer expressions.
assign hit_mask =  bank_valid & {
        bank_image[3] == load_image_id, bank_image[2] == load_image_id,
        bank_image[1] == load_image_id, bank_image[0] == load_image_id};
assign keep_mask =  (KEEP_PREVIOUS_ENABLE != 0 && keep_image_valid) ?
        bank_valid & {bank_image[3] == keep_image_id, bank_image[2] == keep_image_id,
                      bank_image[1] == keep_image_id, bank_image[0] == keep_image_id} : 4'b0000;
assign unprotected =  ~protect_mask;
assign preferred =  unprotected & ~keep_mask;
assign replaceable =  (|preferred) ? preferred : unprotected;
assign invalid_available =  replaceable & ~bank_valid;
assign preferred_available =  (|invalid_available) ? invalid_available : replaceable;
assign preference_unprotected = ~preference_protect;
assign preference_preferred = preference_unprotected&~preference_keep_mask;
assign preference_replaceable = (|preference_preferred)?preference_preferred:preference_unprotected;
assign preference_invalid = preference_replaceable&~preference_valid_banks;
assign preference_available = (|preference_invalid)?preference_invalid:preference_replaceable;
assign selection_current =  prepared && prepared_protect==protect_mask &&
        prepared_valid_banks==bank_valid && prepared_keep_valid==keep_image_valid &&
        prepared_keep_id==keep_image_id;
assign available =  (KEEP_PREVIOUS_ENABLE != 0) ? prepared_available : preferred_available;
assign hit_found =  |hit_mask;
assign free_found =  |available;
assign retire_load =  load_busy && loader_idle && !start_guard;
assign bad_load =  discard_load || cancel || current_epoch != loader_epoch || loader_error != 0;
assign completed_load =  retire_load && !bad_load &&
        (decoder_seen || decoder_done) && (write_seen || frame_write_finish);
assign discarded_load =  retire_load && bad_load;
assign start_miss =  !load_busy && load_req && load_req_ready && !hit_found;

    
    
    
    
    
    
    
    
    // Complete previous-page pictures are a soft replacement preference.
    // Active/pending reader ownership remains mandatory; if soft retention
    // would consume the last free slot, drop it rather than blocking T4 GO.
    
    
    
    
    
    
    // ENABLE=1 registers the whole preference/invalid selection before the
    // cyclic encoder. The snapshot barrier forbids using a decision made for
    // an earlier owner, previous-page id or completed-bank set. LOAD_REQ waits
    // one clock after those inputs change; ENABLE=0 keeps the original cycle.
    
    
    
    // first capture the complete ownership/preference inputs. A cancel
    // can change commit ownership combinationally; it must not also traverse
    // both preference reductions before this 100MHz register boundary.
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    

    function [1:0] lowest_bank;
        input [3:0] mask;
        begin
            casez (mask)
                4'b???1: lowest_bank = 2'd0;
                4'b??10: lowest_bank = 2'd1;
                4'b?100: lowest_bank = 2'd2;
                4'b1000: lowest_bank = 2'd3;
                default: lowest_bank = 2'd0;
            endcase
        end
    endfunction
    assign hit_bank = lowest_bank(hit_mask);
    // Select in slot coordinates. Keeping this one-hot avoids encoding a bank,
    // adding the rotation, then decoding that binary result to clear valid.
    assign free_onehot[0] = available[0] &&
        ((replacement_start == 2'd0) ||
         (replacement_start == 2'd1 && !available[1] && !available[2] && !available[3]) ||
         (replacement_start == 2'd2 && !available[2] && !available[3]) ||
         (replacement_start == 2'd3 && !available[3]));
    assign free_onehot[1] = available[1] &&
        ((replacement_start == 2'd1) ||
         (replacement_start == 2'd2 && !available[2] && !available[3] && !available[0]) ||
         (replacement_start == 2'd3 && !available[3] && !available[0]) ||
         (replacement_start == 2'd0 && !available[0]));
    assign free_onehot[2] = available[2] &&
        ((replacement_start == 2'd2) ||
         (replacement_start == 2'd3 && !available[3] && !available[0] && !available[1]) ||
         (replacement_start == 2'd0 && !available[0] && !available[1]) ||
         (replacement_start == 2'd1 && !available[1]));
    assign free_onehot[3] = available[3] &&
        ((replacement_start == 2'd3) ||
         (replacement_start == 2'd0 && !available[0] && !available[1] && !available[2]) ||
         (replacement_start == 2'd1 && !available[1] && !available[2]) ||
         (replacement_start == 2'd2 && !available[2]));
    assign free_bank = {free_onehot[3] | free_onehot[2], free_onehot[3] | free_onehot[1]};
    assign replacement_next = {free_onehot[1] | free_onehot[2], free_onehot[0] | free_onehot[2]};
    assign load_req_ready = !rst && !cancel && !load_busy && loader_idle &&
                            (KEEP_PREVIOUS_ENABLE == 0 || selection_current) &&
                            (hit_found || free_found);

    // Update validity in bank coordinates, not through a whole-bus enable
    // mux. These disjoint retirement/start events retain the original edge
    // and priority, including an epoch change on the completion edge.
    
    
    
    
    
    genvar vb;
    generate for(vb=0;vb<4;vb=vb+1)begin:g_bank_valid
        wire selected_loader = loader_bank == vb;
        wire clear_valid = (discarded_load && selected_loader) || (start_miss && free_onehot[vb]);
        wire set_valid = completed_load && selected_loader;
        always @(posedge clk or posedge rst)
            if(rst)bank_valid[vb]<=1'b0;
            else bank_valid[vb]<=(bank_valid[vb] && !clear_valid) || set_valid;
    end endgenerate

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            prepared_available<=0;prepared_protect<=0;prepared_valid_banks<=0;
            prepared_keep_id<=0;prepared_keep_valid<=0;prepared<=0;
            preference_protect<=0;preference_valid_banks<=0;preference_keep_mask<=0;
            preference_keep_id<=0;preference_keep_valid<=0;preference_ready<=0;
        end else begin
            preference_protect<=protect_mask;preference_valid_banks<=bank_valid;
            preference_keep_mask<=keep_mask;preference_keep_id<=keep_image_id;
            preference_keep_valid<=keep_image_valid;preference_ready<=1;
            prepared_available<=preference_available;
            prepared_protect<=preference_protect;prepared_valid_banks<=preference_valid_banks;
            prepared_keep_id<=preference_keep_id;prepared_keep_valid<=preference_keep_valid;
            prepared<=preference_ready;
        end
    end

    // Saved error is consumed only by an active load. Clearing all idle
    // cycles (including cache-hit requests) gives the same value at every
    // load start, without the deep combinational miss-selection CE path.
    always @(posedge clk or posedge rst)begin
        if(rst)saved_error<=0;
        else if(!load_busy)saved_error<=0;
        else if(!start_guard&&loader_error!=0)saved_error<=loader_error;
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            loader_start <= 1'b0;
            loader_bank <= 0;
            loader_image_id <= 0;
            loader_epoch <= 0;
            image_ready <= 1'b0;
            ready_bank <= 0;
            ready_image_id <= 0;
            ready_epoch <= 0;
            cache_hit <= 1'b0;
            load_error <= 0;
            load_busy <= 1'b0;
            replacement_start <= 2'd1;
            start_guard <= 1'b0;
            decoder_seen <= 1'b0;
            write_seen <= 1'b0;
            discard_load <= 1'b0;

            for (j = 0; j < 4; j = j + 1) bank_image[j] <= 0;
        end else begin
            loader_start <= 1'b0;
            image_ready <= 1'b0;
            cache_hit <= 1'b0;
            load_error <= 0;
            if (load_busy) begin
                start_guard <= 1'b0;
                // The first busy cycle is when loader_start is consumed.
                // Ignore status left over from the preceding loader transaction.
                if (!start_guard) begin
                    if (decoder_done) decoder_seen <= 1'b1;
                    if (frame_write_finish) write_seen <= 1'b1;

                end
                // Cancel/failure is sticky until the writer has quiesced.
                if (cancel || current_epoch != loader_epoch || (!start_guard && loader_error != 0))
                    discard_load <= 1'b1;
                if ((discard_load || cancel || current_epoch != loader_epoch || loader_error != 0) && loader_idle && !start_guard) begin
                    load_busy <= 1'b0;
                    discard_load <= 1'b0;
                    if (loader_error != 0) load_error <= loader_error;
                    else if (saved_error != 0) load_error <= saved_error;
                    // Cancel itself is not a media fault.
                end else if (!(discard_load || cancel || current_epoch != loader_epoch || loader_error != 0) &&
                             (decoder_seen || decoder_done) && (write_seen || frame_write_finish) && loader_idle && !start_guard) begin
                    for (j = 0; j < 4; j = j + 1)
                        if (loader_bank == j) begin
                            bank_image[j] <= loader_image_id;
                        end
                    load_busy <= 1'b0;
                    image_ready <= 1'b1;
                    ready_bank <= loader_bank;
                    ready_image_id <= loader_image_id;
                    ready_epoch <= loader_epoch;
                end
            end else if (load_req && load_req_ready) begin
                ready_image_id <= load_image_id;
                ready_epoch <= current_epoch;
                if (hit_found) begin
                    image_ready <= 1'b1;
                    cache_hit <= 1'b1;
                    ready_bank <= hit_bank;
                end else begin
                    load_busy <= 1'b1;
                    loader_start <= 1'b1;
                    start_guard <= 1'b1;
                    loader_bank <= free_bank;
                    loader_image_id <= load_image_id;
                    loader_epoch <= current_epoch;
                    replacement_start <= replacement_next;
                    decoder_seen <= 1'b0;
                    write_seen <= 1'b0;
                    discard_load <= 1'b0;
        
                end
            end
        end
    end
endmodule

`default_nettype wire
