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
wire [2:0] u1;
wire [2:0] u2;
wire [2:0] u3;
wire [2:0] u4;
wire [2:0] u5;
wire [2:0] u6;
wire [3:0] p12;
wire [3:0] p34;
wire [3:0] p56;
wire [4:0] p1234;
wire [4:0] units;
wire [6:0] wide_units;
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
assign u1 = valid[0]?(t1>=2?3'd4:t1==1?3'd2:3'd0):3'd0;
assign u2 = valid[1]?(t2>=2?3'd4:t2==1?3'd2:3'd0):3'd0;
assign u3 = valid[2]&&(t3==1||t3==2)?3'd3:3'd0;
assign u4 = valid[3]&&reaction_status==1?(reaction<=500?3'd3:reaction<=1000?3'd2:3'd1):3'd0;
assign u5 = valid[4]&&(hold_status==1||hold_status==2)?(hold>=3000?3'd3:hold>=2000?3'd2:3'd0):3'd0;
assign u6 = valid[5]&&pain>=1&&pain<=4?3'd3:3'd0;
assign p12 = {1'b0,u1}+{1'b0,u2};
assign p34 = {1'b0,u3}+{1'b0,u4};
assign p56 = {1'b0,u5}+{1'b0,u6};
assign p1234 = {1'b0,p12}+{1'b0,p34};
assign units = p1234+{1'b0,p56};
assign wide_units = {2'b00,units};

 
 
 
 
 // All six published contributions are exact multiples of five.
 // Sum their bounded units with a balanced tree, then restore the scale once.
 // No register, eligibility predicate, boundary or score value changes.
 
 
 
 
 
 
 
 
 
 
 
 
 assign total_score=(wide_units<<2)+wide_units;
endmodule

`default_nettype wire
