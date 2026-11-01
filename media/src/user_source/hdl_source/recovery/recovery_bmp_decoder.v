`default_nettype none
`timescale 1ns/1ps
// Fixed 640x480 BMP24 loader.


// valid/ready pixel handshake, frame_done and error codes define completion.
// Accepted pixels are emitted in file (bottom-up) order; the frozen writer's
// WRITE_V_FLIP performs the single vertical flip, exactly as before.
//   31 signature, 32 DIB/size/orientation, 33 planes/bpp/compression,
//   37 offset/length/EOF, 38 upstream error.
module recovery_bmp_decoder #(parameter WIDTH=640,HEIGHT=480)(
 input wire clk,rst,start,input wire [31:0]file_size,input wire byte_valid,input wire [7:0]byte_data,
 output wire byte_ready,input wire file_done,input wire [7:0]upstream_error,
 output reg header_ok,pixel_valid,output reg[23:0]pixel_rgb,
 input wire pixel_ready,output reg frame_done,output reg[7:0]error
);

localparam integer PAYLOAD=WIDTH*HEIGHT*3;
localparam integer MAX_OFFSET=4096;
localparam integer MAX_BYTES=MAX_OFFSET+PAYLOAD;
localparam [2:0] IDLE=0,HEAD=1,CHECK=2,SKIP=3,DATA=4,FINISH=5,FAILED=6;
reg[2:0]state;
reg[31:0]size_saved;
reg[19:0]position,last_position;
// the 54-byte header has a local decoder. The full file
// counter and all 32-bit numeric fields retain their original checks.
reg[5:0]header_pos;
reg[12:0]pixel_offset;
reg[1:0]channel;
reg[7:0]blue,green;
reg eof_seen,file_length_error;
reg header_file_size_error,header_signature_error,header_dimensions_error;
reg header_format_error,header_offset_error;
wire consume;
// Numeric fields remain full32 bit; constants are checked byte-by-byte.
reg [31:0] bmp_declared_size,bmp_data_offset,bmp_image_size;
reg signature_bad,dimensions_bad,format_bad;
// Continuous values retain the original net initializer expressions.
assign consume = byte_valid&&byte_ready;
always @(posedge clk or posedge rst)begin
 if(rst)header_pos<=0;
 else if(start)header_pos<=0;
 else if(state==HEAD&&consume)header_pos<=header_pos+1'b1;
end

 generate if(WIDTH!=640||HEIGHT!=480)begin:g_invalid_geometry
  C28_BMP_MUST_BE_640x480_BMP24 invalid_parameter_configuration();
 end endgenerate
            // 921600, no row padding
 
       // 925696 < 2^20
 
 
 
 
 
 
 // Only the red byte of a pixel waits for the held output pixel.
 assign byte_ready=state==HEAD||(state==SKIP&&position<pixel_offset)||
  (state==DATA&&(channel!=2||!pixel_valid));
 
 task fail;input[7:0]code;begin error<=code;pixel_valid<=0;state<=FAILED;end endtask
 // All checked constant bytes accumulate their original error category.
 // Numeric fields are fully overwritten before byte53 validation; no second
 // header copy or reset fanout is required. Accepted-byte cadence is unchanged.
 always @(posedge clk)if(state==HEAD&&byte_valid)begin
  case(header_pos)
   2:bmp_declared_size[0+:8]<=byte_data;
   3:bmp_declared_size[8+:8]<=byte_data;
   4:bmp_declared_size[16+:8]<=byte_data;
   5:bmp_declared_size[24+:8]<=byte_data;
   10:bmp_data_offset[0+:8]<=byte_data;
   11:bmp_data_offset[8+:8]<=byte_data;
   12:bmp_data_offset[16+:8]<=byte_data;
   13:bmp_data_offset[24+:8]<=byte_data;
   34:bmp_image_size[0+:8]<=byte_data;
   35:bmp_image_size[8+:8]<=byte_data;
   36:bmp_image_size[16+:8]<=byte_data;
   37:bmp_image_size[24+:8]<=byte_data;
   default:;
  endcase
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin signature_bad<=0;dimensions_bad<=0;format_bad<=0;end
  else if(start)begin signature_bad<=0;dimensions_bad<=0;format_bad<=0;end
  else if(state==HEAD&&byte_valid)begin
   case(header_pos)
    0:if(byte_data!=8'h42)signature_bad<=1;
    1:if(byte_data!=8'h4d)signature_bad<=1;
    14:if(byte_data!=8'd40)dimensions_bad<=1;
    18:if(byte_data!=8'h80)dimensions_bad<=1;
    19:if(byte_data!=8'h02)dimensions_bad<=1;
    22:if(byte_data!=8'he0)dimensions_bad<=1;
    23:if(byte_data!=8'h01)dimensions_bad<=1;
    15,16,17,20,21,24,25:if(byte_data!=0)dimensions_bad<=1;
    26:if(byte_data!=1)format_bad<=1;
    28:if(byte_data!=24)format_bad<=1;
    27,29,30,31,32,33:if(byte_data!=0)format_bad<=1;
    default:;
   endcase
  end
 end
 // Header validation still occurs at original byte53 edge, with original error priority.
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;header_ok<=0;pixel_valid<=0;pixel_rgb<=0;frame_done<=0;error<=0;
   size_saved<=0;position<=0;last_position<=0;pixel_offset<=0;channel<=0;blue<=0;green<=0;
   eof_seen<=0;file_length_error<=0;
   header_file_size_error<=0;header_signature_error<=0;header_dimensions_error<=0;
   header_format_error<=0;header_offset_error<=0;
  end else begin
   header_ok<=0;frame_done<=0;
   if(pixel_valid&&pixel_ready)pixel_valid<=0;
   // Header fields end at byte 37; byte 53 is not read. Full 32-bit fields
   // are compared before any counter is narrowed.
   if(state==HEAD&&byte_valid&&header_pos==53)begin
    header_file_size_error<=size_saved>MAX_BYTES;
    header_signature_error<=signature_bad;
    // Signed negative height is a large unsigned value and fails here.
    header_dimensions_error<=dimensions_bad;
    header_format_error<=format_bad;
    header_offset_error<=bmp_data_offset<54||bmp_data_offset>MAX_OFFSET||bmp_declared_size!=size_saved||
     bmp_data_offset+PAYLOAD!=size_saved||(bmp_image_size!=0&&bmp_image_size!=PAYLOAD);
   end
   // The first error code is retained; length checks are idle after FAILED.
   file_length_error<=file_done&&state!=IDLE&&state!=FAILED&&
    ((consume&&position!=last_position)||(!consume&&{12'd0,position}!=size_saved));
   if(file_done)eof_seen<=1;
   if(consume)position<=position+1'b1;
   if(start)begin
    state<=HEAD;size_saved<=file_size;last_position<=file_size[19:0]-1'b1;position<=0;
    error<=0;pixel_valid<=0;eof_seen<=0;file_length_error<=0;channel<=0;
   end
   else if(upstream_error!=0&&state!=IDLE)fail(8'h38);
   else if(file_length_error)fail(8'h37);
   // EOF before a complete header/pixel stream (e.g. 53-byte file) is a
   // bounded length error rather than an indefinite wait.
   else if(eof_seen&&!consume&&(state==HEAD||state==SKIP||state==DATA))fail(8'h37);
   else case(state)
    HEAD:if(byte_valid&&header_pos==53)state<=CHECK;
    CHECK:begin
     if(header_file_size_error)fail(8'h37);
     else if(header_signature_error)fail(8'h31);
     else if(header_dimensions_error)fail(8'h32);
     else if(header_format_error)fail(8'h33);
     else if(header_offset_error)fail(8'h37);
     else begin pixel_offset<=bmp_data_offset;channel<=0;header_ok<=1;state<=SKIP;end
    end
    SKIP:if(position==pixel_offset)state<=DATA;
    DATA:if(consume)begin
     case(channel)
      0:begin blue<=byte_data;channel<=1;end
      1:begin green<=byte_data;channel<=2;end
      default:begin pixel_rgb<={byte_data,green,blue};pixel_valid<=1;channel<=0;end
     endcase
     if(position==last_position)state<=FINISH;
    end
    // Final pixel accepted and EOF observed before completion. The writer's
    // FIFO drain / SDRAM write-finish / frame-boundary commit remain separate.
    FINISH:if(eof_seen&&!pixel_valid)begin frame_done<=1;state<=IDLE;end
    FAILED:begin pixel_valid<=0;if(eof_seen)state<=IDLE;end
    default:;
   endcase
  end
 end
endmodule
`default_nettype wire
