`default_nettype none
`timescale 1ns/1ps
// sector adapter: fixed-length and CRC16 errors prevent publication.
module recovery_sector_adapter #(
    parameter integer TIMEOUT_CYCLES = 200000000
)(
    input wire clk, input wire rst,
    input wire sector_req, input wire [31:0] sector_lba,
    output wire sector_ready,
    output wire sector_byte_valid, output wire [7:0] sector_byte,
    output wire [8:0] sector_byte_index,
    output reg sector_done, output reg [7:0] sector_error,
    input wire sd_init_done,
    output reg sd_sec_read, output reg [31:0] sd_sec_read_addr,
    input wire [7:0] sd_sec_read_data,
    input wire sd_sec_read_data_valid, input wire sd_sec_read_end,
    input wire sd_sec_read_error
);

reg active, locked_fault;
reg [9:0] count;
reg [31:0] watchdog;
// Continuous values retain the original net initializer expressions.


    
    
    
    assign sector_ready = sd_init_done && !active && !locked_fault && !sector_done;
    assign sector_byte_valid = active && sd_sec_read_data_valid && count < 512;
    assign sector_byte = sd_sec_read_data;
    assign sector_byte_index = count[8:0];
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active<=0; locked_fault<=0; count<=0; watchdog<=0;
            sd_sec_read<=0; sd_sec_read_addr<=0; sector_done<=0; sector_error<=0;
        end else begin
            sector_done<=0;
            if (!active) begin
                sd_sec_read<=0;
                if (sector_req && sector_ready) begin
                    active<=1; count<=0; watchdog<=0; sector_error<=0;
                    sd_sec_read_addr<=sector_lba; sd_sec_read<=1;
                end
            end else begin
                watchdog<=watchdog+1;
                if (sd_sec_read_data_valid) begin
                    // The official core has accepted the level request by this point.
                    sd_sec_read<=0;
                    if (count<513) count<=count+1;
                end
                if (sd_sec_read_end) begin
                    sd_sec_read<=0; active<=0; sector_done<=1;
                    if (sd_sec_read_error) sector_error<=8'h13;
                    else if (count + (sd_sec_read_data_valid ? 10'd1 : 10'd0) != 512)
                        sector_error<=8'h12;
                end else if (watchdog>=TIMEOUT_CYCLES-1) begin
                    sd_sec_read<=0; active<=0; sector_done<=1; sector_error<=8'h11;
                    // Do not accept a new owner while an unacknowledged old SD operation may return.
                    locked_fault<=1;
                end
            end
        end
    end
endmodule

`default_nettype wire
