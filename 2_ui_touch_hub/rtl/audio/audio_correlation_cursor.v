// Three arithmetic stages; truncation toward zero matches the signed UI scale.
module audio_correlation_cursor(
 input wire clk,rst_n,link_up,value_valid,
 input wire signed [7:0] correlation,
 output reg [13:0] position,
 output reg position_valid
);
 wire signed [7:0] bounded=correlation>8'sd100 ? 8'sd100 :
                            correlation< -8'sd100 ? -8'sd100 : correlation;
 reg signed [15:0] product;
 reg signed [7:0] quotient;
 reg valid0,valid1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   product<=0;quotient<=0;valid0<=0;valid1<=0;position<=1058;position_valid<=0;
  end else if(!link_up)begin
   product<=0;quotient<=0;valid0<=0;valid1<=0;position<=1058;position_valid<=0;
  end else begin
   valid0<=value_valid;valid1<=valid0;position_valid<=valid1;
   if(value_valid)product<=bounded*16'sd126;
   if(valid0)quotient<=product/16'sd100;
   if(valid1)position<=14'sd1058+{{6{quotient[7]}},quotient};
  end
 end
endmodule
