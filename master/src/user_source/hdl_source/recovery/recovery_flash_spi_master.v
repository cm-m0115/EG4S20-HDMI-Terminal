`default_nettype none
`timescale 1ns/1ps
// Mode-0 byte stream master. SPI SCLK is a divided registered output; it is
// never used as an internal fabric clock. The owner presents write bytes with
// ready/valid and receives each returned byte as a one-cycle valid event.
module recovery_flash_spi_master #(
    parameter integer CLK_DIV = 25,
    parameter integer CS_HIGH_CYCLES = 10
) (
    input wire clk,input wire rst,
    input wire start,input wire [7:0] command,
    input wire address_valid,input wire [23:0] address,
    input wire [8:0] write_length,input wire [8:0] read_length,
    input wire [7:0] write_data,input wire write_valid,output wire write_ready,
    output reg [7:0] read_data,output reg read_valid,
    output reg busy,output reg done,output reg error,
    output reg cs_n,output wire sclk,output wire mosi,input wire miso
);

localparam [3:0] IDLE=0,CMD_ISSUE=1,CMD_WAIT=2,ADDR_ISSUE=3,ADDR_WAIT=4,
        WRITE_DATA=5,WRITE_WAIT=6,READ_ISSUE=7,READ_WAIT=8,FINISH=9,REARM=10;
localparam integer AW=(CLK_DIV<=2)?1:$clog2(CLK_DIV);
localparam integer CW=CS_HIGH_CYCLES<=1?1:$clog2(CS_HIGH_CYCLES+1);
reg [3:0] state;
reg [CW-1:0] deselect_count;
reg [7:0] command_q,byte_tx;
reg [23:0] address_q;
reg address_valid_q;
reg [8:0] write_left,read_left;
reg [1:0] address_index;
reg byte_start;
wire byte_busy,byte_done;
wire [7:0] byte_rx;
wire [7:0] address_byte;
// Continuous values retain the original net initializer expressions.
assign address_byte = (address_index==0)?address_q[23:16]:
        (address_index==1)?address_q[15:8]:address_q[7:0];

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    assign write_ready=(state==WRITE_DATA)&&!byte_busy;

    recovery_flash_spi_byte #(.CLK_DIV(CLK_DIV)) u_byte(
        .clk(clk),.rst_n(!rst),.start(byte_start),.tx_byte(byte_tx),.miso(miso),
        .busy(byte_busy),.done(byte_done),.rx_byte(byte_rx),.sclk(sclk),.mosi(mosi));

    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=IDLE;deselect_count<=0;command_q<=0;address_q<=0;address_valid_q<=0;
            write_left<=0;read_left<=0;address_index<=0;byte_tx<=8'hff;byte_start<=0;
            read_data<=0;read_valid<=0;busy<=0;done<=0;error<=0;cs_n<=1;
        end else begin
            byte_start<=0;read_valid<=0;done<=0;
            case(state)
                IDLE:begin
                    cs_n<=1;busy<=0;
                    if(start)begin
                        if(CLK_DIV<2)begin error<=1;done<=1;state<=REARM;end
                        else begin
                            command_q<=command;address_q<=address;address_valid_q<=address_valid;
                            write_left<=write_length;read_left<=read_length;address_index<=0;
                            cs_n<=0;busy<=1;error<=0;state<=CMD_ISSUE;
                        end
                    end
                end
                CMD_ISSUE:if(!byte_busy)begin byte_tx<=command_q;byte_start<=1;state<=CMD_WAIT;end
                CMD_WAIT:if(byte_done)begin
                    if(address_valid_q)begin address_index<=0;state<=ADDR_ISSUE;end
                    else if(write_left!=0)state<=WRITE_DATA;
                    else if(read_left!=0)state<=READ_ISSUE;
                    else state<=FINISH;
                end
                ADDR_ISSUE:if(!byte_busy)begin byte_tx<=address_byte;byte_start<=1;state<=ADDR_WAIT;end
                ADDR_WAIT:if(byte_done)begin
                    if(address_index==2)begin
                        if(write_left!=0)state<=WRITE_DATA;
                        else if(read_left!=0)state<=READ_ISSUE;
                        else state<=FINISH;
                    end else begin address_index<=address_index+1'b1;state<=ADDR_ISSUE;end
                end
                WRITE_DATA:begin
                    if(write_left==0)begin
                        if(read_left!=0)state<=READ_ISSUE;else state<=FINISH;
                    end else if(write_valid&&write_ready)begin
                        byte_tx<=write_data;byte_start<=1;write_left<=write_left-1'b1;state<=WRITE_WAIT;
                    end
                end
                WRITE_WAIT:if(byte_done)begin
                    if(write_left!=0)state<=WRITE_DATA;
                    else if(read_left!=0)state<=READ_ISSUE;
                    else state<=FINISH;
                end
                READ_ISSUE:if(!byte_busy)begin byte_tx<=8'hff;byte_start<=1;state<=READ_WAIT;end
                READ_WAIT:if(byte_done)begin
                    read_data<=byte_rx;read_valid<=1;
                    if(read_left<=1)begin read_left<=0;state<=FINISH;end
                    else begin read_left<=read_left-1'b1;state<=READ_ISSUE;end
                end
                // CS high is an interface requirement, not an owner courtesy.
                // Keep busy and defer DONE until ten100MHz clocks elapsed.
                // The next launch therefore cannot be lost in REARM.
                FINISH:begin cs_n<=1;busy<=1;deselect_count<=0;state<=REARM;end
                REARM:begin
                    cs_n<=1;busy<=1;
                    if(deselect_count>=CS_HIGH_CYCLES-1&&!start)begin
                        busy<=0;done<=1;state<=IDLE;
                    end else if(deselect_count<CS_HIGH_CYCLES)deselect_count<=deselect_count+1'b1;
                end
                default:begin cs_n<=1;busy<=0;error<=1;done<=1;state<=REARM;end
            endcase
        end
    end
endmodule

module recovery_flash_spi_byte #(
    parameter integer CLK_DIV=25
) (
    input wire clk,input wire rst_n,input wire start,input wire [7:0] tx_byte,input wire miso,
    output reg busy,output reg done,output reg [7:0] rx_byte,output reg sclk,output reg mosi
);

localparam [1:0] IDLE=0,RUN=1,END_BYTE=2;
localparam integer DW=(CLK_DIV<=2)?1:$clog2(CLK_DIV);
reg [1:0] state;
reg [DW-1:0] div_count;
reg [2:0] bit_count;
reg [7:0] tx_shift,rx_shift;
// Continuous values retain the original net initializer expressions.


    
    
    
    
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;div_count<=0;bit_count<=0;tx_shift<=8'hff;rx_shift<=0;rx_byte<=0;
            busy<=0;done<=0;sclk<=0;mosi<=1;
        end else begin
            done<=0;
            case(state)
                IDLE:begin
                    busy<=0;sclk<=0;div_count<=0;bit_count<=0;
                    if(start)begin busy<=1;tx_shift<=tx_byte;rx_shift<=0;mosi<=tx_byte[7];state<=RUN;end
                end
                RUN:begin
                    busy<=1;
                    if(!sclk&&div_count==0&&bit_count!=0)mosi<=tx_shift[7];
                    if(div_count==CLK_DIV-1)begin
                        div_count<=0;
                        if(!sclk)begin
                            sclk<=1;rx_shift<={rx_shift[6:0],miso};
                            if(bit_count==7)rx_byte<={rx_shift[6:0],miso};
                        end else begin
                            sclk<=0;
                            if(bit_count==7)state<=END_BYTE;
                            else begin bit_count<=bit_count+1'b1;tx_shift<={tx_shift[6:0],1'b0};end
                        end
                    end else div_count<=div_count+1'b1;
                end
                END_BYTE:begin busy<=0;done<=1;sclk<=0;mosi<=1;state<=IDLE;end
                default:begin state<=IDLE;busy<=0;sclk<=0;mosi<=1;end
            endcase
        end
    end
endmodule

`default_nettype wire
