`default_nettype none
`timescale 1ns/1ps
// release names, 11-byte FAT short names, first character in MSB.
module recovery_asset_rom(input wire [5:0] scene,input wire audio_select,
 output reg [87:0] file_name,output reg audio_none,
 input wire paired_select,input wire music_select,input wire music_track,output reg [31:0] voice_samples);
 always @* begin
  audio_none=(scene==19||scene==29||scene==30||scene==37||scene==46);file_name="WELCOME BMP";voice_samples=0;
  case(scene)
   6'd0:file_name=audio_select?"WELCOME PCM":"WELCOME BMP";
   6'd1:file_name=audio_select?"PACUGUIDPCM":"PACUGUIDBMP";
   6'd2:file_name=audio_select?"PACUCALLPCM":"PACUCALLBMP";
   6'd3:file_name=audio_select?"PACUREP PCM":"PACUREP BMP";
   6'd4:file_name=audio_select?"PACULARMPCM":"PACULARMBMP";
   6'd5:file_name=audio_select?"PACURARMPCM":"PACURARMBMP";
   6'd6:file_name=audio_select?"PACULLEGPCM":"PACULLEGBMP";
   6'd7:file_name=audio_select?"PACUALRMPCM":"PACUALRMBMP";
   6'd8:file_name=audio_select?"PACURSLTPCM":"PACURSLTBMP";
   6'd9:file_name=audio_select?"LEARNKEYPCM":"LEARNKEYBMP";
   6'd10:file_name=audio_select?"LEARNHLDPCM":"LEARNHLDBMP";
   6'd11:file_name=audio_select?"LEARNVISPCM":"LEARNVISBMP";
   6'd12:file_name=audio_select?"READY   PCM":"READY   BMP";
   6'd13:file_name=audio_select?"T1Q1    PCM":"T1Q1    BMP";
   6'd14:file_name=audio_select?"T1Q2    PCM":"T1Q2    BMP";
   6'd15:file_name=audio_select?"T2NUM   PCM":"T2NUM   BMP";
   6'd16:file_name=audio_select?"T2SAME  PCM":"T2SAME  BMP";
   6'd17:file_name=audio_select?"T3LISTENPCM":"T3LISTENBMP";
   6'd18:file_name=audio_select?"T4INFO  PCM":"T4WAIT  BMP";
   6'd19:file_name=audio_select?"T4GO    PCM":"T4GO    BMP";
   6'd20:file_name=audio_select?"T5HOLD  PCM":"T5HOLD  BMP";
   6'd21:file_name=audio_select?"T6PAIN  PCM":"T6PAIN  BMP";
   6'd22:file_name=audio_select?"RESULTS PCM":"RESULTS BMP";
   6'd23:file_name=audio_select?"EDUMOVE PCM":"EDUMOVE BMP";
   6'd24:file_name=audio_select?"EDUPAIN PCM":"EDUPAIN BMP";
   6'd25:file_name=audio_select?"EDUNAUS PCM":"EDUNAUS BMP";
   6'd26:file_name=audio_select?"EDUFOOD PCM":"EDUFOOD BMP";
   6'd27:file_name=audio_select?"REST    PCM":"REST    BMP";
   6'd28:file_name=audio_select?"PACURLEGPCM":"PACURLEGBMP";
   6'd29:file_name="HISTPACUBMP";
   6'd30:file_name="HISTWARDBMP";
   6'd31:file_name=audio_select?"T1Q1A   PCM":"T1Q1A   BMP";
   6'd32:file_name=audio_select?"T1Q2A   PCM":"T1Q2A   BMP";
   6'd33:file_name=audio_select?"T2NUMA  PCM":"T2NUMA  BMP";
   6'd34:file_name=audio_select?"T2SAMEA PCM":"T2SAMEA BMP";
   6'd35:file_name=audio_select?"T3LSTNA PCM":"T3LSTNA BMP";
   6'd36:file_name=audio_select?"T4INFOA PCM":"T4WAITA BMP";
   6'd37:file_name=audio_select?"T4GOA   PCM":"T4GOA   BMP";
   6'd38:file_name=audio_select?"T5HOLDA PCM":"T5HOLDA BMP";
   6'd39:file_name=audio_select?"T6PAINA PCM":"T6PAINA BMP";
   6'd40:file_name=audio_select?"T1Q1B   PCM":"T1Q1B   BMP";
   6'd41:file_name=audio_select?"T1Q2B   PCM":"T1Q2B   BMP";
   6'd42:file_name=audio_select?"T2NUMB  PCM":"T2NUMB  BMP";
   6'd43:file_name=audio_select?"T2SAMEB PCM":"T2SAMEB BMP";
   6'd44:file_name=audio_select?"T3LSTNB PCM":"T3LSTNB BMP";
   6'd45:file_name=audio_select?"T4INFOB PCM":"T4WAITB BMP";
   6'd46:file_name=audio_select?"T4GOB   PCM":"T4GOB   BMP";
   6'd47:file_name=audio_select?"T5HOLDB PCM":"T5HOLDB BMP";
   6'd48:file_name=audio_select?"T6PAINB PCM":"T6PAINB BMP";
   6'd49:file_name=audio_select?"MUSIC01 PCM":"RELAX   BMP";
   default:begin file_name="WELCOME BMP";audio_none=1;end
  endcase
  case(scene)
   6'd23:voice_samples=32'd418176;
   6'd24,6'd25:voice_samples=32'd399744;
   6'd26:voice_samples=32'd413568;
  endcase
  if(audio_select&&(music_select===1'b1))begin
   file_name=(music_track===1'b1)?"MUSIC02 PCM":"MUSIC01 PCM";audio_none=0;
  end else if(audio_select&&(paired_select===1'b1))begin
   case(scene)
    6'd23:file_name="EMOVE_M PCM";
    6'd24:file_name="EPAIN_M PCM";
    6'd25:file_name="ENAUS_M PCM";
    6'd26:file_name="EFOOD_M PCM";
   endcase
  end
 end
endmodule

`default_nettype wire
