// Double-buffered occupancy plot of measured (left,right) PCM pairs.
// No synthetic ellipse: mono duplication produces an actual diagonal.
module audio_phase_plot(
 input wire clk,rst_n,link_up,pair_valid,
 input wire signed [15:0] left_sample,right_sample,
 input tri0 [1:0] gain_x,gain_y,
 input wire [12:0] read_address,
 output reg pixel,
 output reg ready
);
 reg memory[0:16383];
 reg write_bank,display_bank,clearing;
 reg [12:0] clear_address;
 reg [10:0] count;
 reg [2:0] decimate;
 reg [3:0] applied_gains;
 `include "audio_plot_gain.vh"
 wire signed [15:0] plot_l=plot_gain(left_sample,gain_x),plot_r=plot_gain(right_sample,gain_y);
 wire [6:0] point_x=plot_l[15:9]+7'd64;
 wire [5:0] point_y=6'd31-plot_r[15:10];
 wire [13:0] write_address={write_bank,clearing ? clear_address : {point_y,point_x}};
 wire write_enable={gain_x,gain_y}==applied_gains && (clearing || (pair_valid && decimate==7));
 always @(posedge clk)begin
  if(rst_n && link_up && write_enable)memory[write_address]<=!clearing;
  pixel<=memory[{display_bank,read_address}];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   write_bank<=0;display_bank<=1;clearing<=1;clear_address<=0;
   count<=0;decimate<=0;ready<=0;applied_gains<={gain_x,gain_y};
  end else if(!link_up)begin
   write_bank<=0;display_bank<=1;clearing<=1;clear_address<=0;
   count<=0;decimate<=0;ready<=0;applied_gains<={gain_x,gain_y};
  end else if({gain_x,gain_y}!=applied_gains)begin
   applied_gains<={gain_x,gain_y};write_bank<=0;display_bank<=1;ready<=0;
   clearing<=1;clear_address<=0;count<=0;decimate<=0;
  end else if(clearing)begin
   clear_address<=clear_address+1'b1;
   if(clear_address==8191)begin clearing<=0;count<=0;decimate<=0;end
  end else if(pair_valid)begin
   decimate<=decimate+1'b1;count<=count+1'b1;
   if(count==2047)begin
    display_bank<=write_bank;write_bank<=!write_bank;ready<=1;
    clearing<=1;clear_address<=0;
   end
  end
 end
endmodule
