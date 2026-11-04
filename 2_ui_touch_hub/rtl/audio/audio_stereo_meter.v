// Independent measured channels, with display-only gain and release animation.
module audio_stereo_meter(
 input wire clk,rst_n,link_up,frame_valid,
 input wire [15:0] rms_l,rms_r,peak_l,peak_r,
 input wire [1:0] gain,
 output wire signed [11:0] db_l,db_r,
 output reg [7:0] width_l,width_r,
 output reg [7:0] hold_width_l,hold_width_r
);
 reg [15:0] held_l,held_r;
 wire [15:0] decay_l=held_l<128 ? 16'd0 : held_l-(held_l>>4);
 wire [15:0] decay_r=held_r<128 ? 16'd0 : held_r-(held_r>>4);
 reg [6:0] count_l,count_r;
 wire signed [11:0] held_db_l,held_db_r;
 reg signed [12:0] level_l,level_r,level_hold_l,level_hold_r;
 reg [7:0] target_l,target_r;
 wire signed [12:0] boost=gain==0 ? 13'sd0 : gain==1 ? 13'sd60 : gain==2 ? 13'sd120 : 13'sd181;
 audio_dbfs_encoder l_rms(.clk(clk),.amplitude(rms_l),.db10(db_l));
 audio_dbfs_encoder r_rms(.clk(clk),.amplitude(rms_r),.db10(db_r));
 audio_dbfs_encoder l_hold(.clk(clk),.amplitude(held_l),.db10(held_db_l));
 audio_dbfs_encoder r_hold(.clk(clk),.amplitude(held_r),.db10(held_db_r));
 function [7:0] bar_width;
  input signed [12:0] level;
  begin bar_width=level<=0 ? 0 : level>=960 ? 160 : level/13'sd6;end
 endfunction
 always @(posedge clk)begin
  level_l<=13'sd960+db_l+boost;level_r<=13'sd960+db_r+boost;
  level_hold_l<=13'sd960+held_db_l+boost;level_hold_r<=13'sd960+held_db_r+boost;
  target_l<=rms_l==0 ? 0 : bar_width(level_l);target_r<=rms_r==0 ? 0 : bar_width(level_r);
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   held_l<=0;held_r<=0;count_l<=0;count_r<=0;
   width_l<=0;width_r<=0;hold_width_l<=0;hold_width_r<=0;
  end else if(!link_up)begin
   held_l<=0;held_r<=0;count_l<=0;count_r<=0;
   width_l<=0;width_r<=0;hold_width_l<=0;hold_width_r<=0;
  end else begin
   hold_width_l<=held_l==0 ? 0 : bar_width(level_hold_l);
   hold_width_r<=held_r==0 ? 0 : bar_width(level_hold_r);
   if(frame_valid)begin
    if(peak_l>=held_l)begin held_l<=peak_l;count_l<=94;end
    else if(count_l!=0)count_l<=count_l-1'b1;
    else held_l<=peak_l>decay_l ? peak_l : decay_l;
    if(peak_r>=held_r)begin held_r<=peak_r;count_r<=94;end
    else if(count_r!=0)count_r<=count_r-1'b1;
    else held_r<=peak_r>decay_r ? peak_r : decay_r;
   end
   // Input statistics publish about every 10.7ms, but the display targets
   // settle a few clocks later. Each statistics frame decays the rendered bars.
   if(target_l>=width_l)width_l<=target_l;
   else if(frame_valid)width_l<=width_l>target_l+2 ? width_l-2 : target_l;
   if(target_r>=width_r)width_r<=target_r;
   else if(frame_valid)width_r<=width_r>target_r+2 ? width_r-2 : target_r;
  end
 end
endmodule
