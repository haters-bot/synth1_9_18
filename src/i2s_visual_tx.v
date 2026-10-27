// Visualization return V2: 96 kframes/s, 64 BCLK/frame, standard I2S timing.
// Left slot = {final output L, OSC A}; right = {final output R, OSC B}.
// Both oscillator samples are taken together; the speaker I2S is independent.
module i2s_visual_tx(
 input wire clk,rst_n,
 input wire signed [15:0] final_left,final_right,osc_a,osc_b,
 output wire bclk,
 output reg lrck,sdata
);
 localparam [31:0] PHASE_INC=32'h1F75104E;
 reg [31:0] phase;
 wire [31:0] next_phase=phase+PHASE_INC;
 wire falling=phase[31] && !next_phase[31];
 reg [5:0] bit_index;
 reg [31:0] left_word,right_word;
 assign bclk=phase[31];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;bit_index<=0;left_word<=0;right_word<=0;lrck<=0;sdata<=0;end
  else begin
   phase<=next_phase;
   if(falling)begin
    bit_index<=bit_index+1'b1;
    if(bit_index==0)begin
     lrck<=0;sdata<=right_word[0];
     left_word<={final_left,osc_a};right_word<={final_right,osc_b};
    end else if(bit_index==32)begin lrck<=1;sdata<=left_word[0];end
    else if(bit_index<32)sdata<=left_word[32-bit_index];
    else sdata<=right_word[64-bit_index];
   end
  end
 end
endmodule
