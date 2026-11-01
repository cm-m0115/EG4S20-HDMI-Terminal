`default_nettype none
`timescale 1ns/1ps
// transparent six-test engineering score, maximum 100.
// This is a device demonstration score, not a validated clinical scale.
// T1/T2: 10 per correct answer (20 each); T3: correct first/retry 15;
// T4: accepted reaction <=500/<=1000/>1000 ms gives 15/10/5;
// T5: valid >=3000/2000..2999 ms gives 15/10; T6: valid pain answer 15.
// Honest pain severity never reduces the score. Missing/invalid tests give 0.
module recovery_ward_score(
 input wire [127:0] report_fields,
 output wire [6:0] total_score
);

wire [5:0] valid;
wire [1:0] t1,t2,t3;
wire [15:0] reaction,hold;
wire [2:0] reaction_status,hold_status,pain;
wire [6:0] s1;
wire [6:0] s2;
wire [6:0] s3;
wire [6:0] s4;
wire [6:0] s5;
wire [6:0] s6;
// Continuous values retain the original net initializer expressions.
assign valid = report_fields[19:14];
assign t1 = report_fields[66:65];
assign t2 = report_fields[64:63];
assign t3 = report_fields[62:61];
assign reaction = report_fields[60:45];
assign hold = report_fields[41:26];
assign reaction_status = report_fields[44:42];
assign hold_status = report_fields[25:23];
assign pain = report_fields[22:20];
assign s1 = valid[0]?(t1>=2?7'd20:t1==1?7'd10:7'd0):7'd0;
assign s2 = valid[1]?(t2>=2?7'd20:t2==1?7'd10:7'd0):7'd0;
assign s3 = valid[2]&&(t3==1||t3==2)?7'd15:7'd0;
assign s4 = valid[3]&&reaction_status==1?(reaction<=500?7'd15:reaction<=1000?7'd10:7'd5):7'd0;
assign s5 = valid[4]&&(hold_status==1||hold_status==2)?(hold>=3000?7'd15:hold>=2000?7'd10:7'd0):7'd0;
assign s6 = valid[5]&&pain>=1&&pain<=4?7'd15:7'd0;

 
 
 
 
 
 
 
 
 
 
 assign total_score=s1+s2+s3+s4+s5+s6;
endmodule

`default_nettype wire
