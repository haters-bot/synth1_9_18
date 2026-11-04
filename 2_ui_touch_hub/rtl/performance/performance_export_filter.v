// Offline 96k -> 8k export FIR, 127 Hamming-windowed taps, Fc=3kHz.
// One time-multiplexed MAC per channel. RAM has no reset; history_count masks
// unwritten samples so reconnect/retry starts deterministically from zero.
module performance_export_filter(
 input wire clk,rst_n,clear,in_valid,in_emit,
 output wire in_ready,
 input wire signed [15:0] in_left,in_right,
 output reg out_valid,input wire out_ready,
 output reg signed [15:0] out_left,out_right
);
 reg signed [15:0] memory_l[0:127],memory_r[0:127],coefficients[0:127];
 `include "performance_export_coeffs.vh"
 reg [6:0] write_ptr,read_ptr,tap,history_count;
 reg signed [15:0] sample_l,sample_r,coefficient;
 reg signed [31:0] product_l,product_r;
 reg signed [47:0] accum_l,accum_r;
 reg [1:0] state;
 localparam IDLE=0,FETCH=1,MULTIPLY=2,ADD=3;
 assign in_ready=state==IDLE && !out_valid;
 wire signed [47:0] sum_l=accum_l+{{16{product_l[31]}},product_l};
 wire signed [47:0] sum_r=accum_r+{{16{product_r[31]}},product_r};
 function signed [15:0] rounded;
  input signed [47:0] value;reg signed [47:0] v;
  begin v=(value+48'sd16384)>>>15;
   rounded=v>32767 ? 16'sh7fff : v< -32768 ? 16'sh8000 : v[15:0];
  end
 endfunction
 always @(posedge clk)begin
  sample_l<=memory_l[read_ptr];sample_r<=memory_r[read_ptr];coefficient<=coefficients[tap];
  if(in_valid && in_ready)begin memory_l[write_ptr]<=in_left;memory_r[write_ptr]<=in_right;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   write_ptr<=0;read_ptr<=0;tap<=0;history_count<=0;state<=IDLE;out_valid<=0;
   accum_l<=0;accum_r<=0;product_l<=0;product_r<=0;out_left<=0;out_right<=0;
  end else if(clear)begin
   write_ptr<=0;read_ptr<=0;tap<=0;history_count<=0;state<=IDLE;out_valid<=0;
   accum_l<=0;accum_r<=0;product_l<=0;product_r<=0;
  end else begin
   if(out_valid && out_ready)out_valid<=0;
   case(state)
    IDLE:if(in_valid && in_ready)begin
     write_ptr<=write_ptr+1'b1;if(history_count<127)history_count<=history_count+1'b1;
     if(in_emit)begin read_ptr<=write_ptr;tap<=0;accum_l<=0;accum_r<=0;state<=FETCH;end
    end
    FETCH:state<=MULTIPLY;
    MULTIPLY:begin
     product_l<=tap<history_count ? sample_l*coefficient : 32'sd0;
     product_r<=tap<history_count ? sample_r*coefficient : 32'sd0;state<=ADD;
    end
    ADD:begin
     if(tap==126)begin out_left<=rounded(sum_l);out_right<=rounded(sum_r);out_valid<=1;state<=IDLE;end
     else begin accum_l<=sum_l;accum_r<=sum_r;read_ptr<=read_ptr-1'b1;tap<=tap+1'b1;state<=FETCH;end
    end
   endcase
  end
 end
endmodule
