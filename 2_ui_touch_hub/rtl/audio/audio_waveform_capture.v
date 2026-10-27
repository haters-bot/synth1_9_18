// Triggered 128-point, 8:1 decimated PCM snapshot (10.667 ms at 96 kHz).
// A hidden bank is captured after a rising, hysteretic zero crossing.
// Auto trigger after 128 decimated points prevents stale silence/DC traces.
// The first frame captures immediately, and every disconnect clears validity.
module audio_waveform_capture(
 input wire clk,rst_n,link_up,sample_valid,
 input wire signed [15:0] sample,
 input wire [1:0] time_zoom,
 input wire [6:0] read_address,
 output reg [7:0] plot_sample,plot_previous,
 output reg ready,frame_valid,triggered
);
 reg [7:0] memory[0:255],previous[0:255];
 reg display_bank,capturing,armed,capture_triggered;
 reg [2:0] decimate;
 reg [6:0] write_index,arm_age;
 reg [7:0] last_sample;
 reg [1:0] captured_zoom;
 wire tick=sample_valid&&decimate==(3'd7>>time_zoom);
 wire trigger_now=armed&&sample>=16'sd256;
 wire auto_now=arm_age==127;
 wire write_now=rst_n&&link_up&&tick&&(capturing||trigger_now||auto_now);
 wire [6:0] address=capturing ? write_index : 7'd0;
 always @(posedge clk)begin
  plot_sample<=memory[{display_bank,read_address}];
  plot_previous<=previous[{display_bank,read_address}];
  if(write_now)begin
   memory[{!display_bank,address}]<=sample[15:8];
   previous[{!display_bank,address}]<=address==0 ? sample[15:8] : last_sample;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   captured_zoom<=time_zoom;display_bank<=0;capturing<=1;armed<=0;capture_triggered<=0;
   decimate<=0;write_index<=0;arm_age<=0;last_sample<=0;
   ready<=0;frame_valid<=0;triggered<=0;
  end else if(!link_up || captured_zoom!=time_zoom)begin
   captured_zoom<=time_zoom;
   display_bank<=0;capturing<=1;armed<=0;capture_triggered<=0;
   decimate<=0;write_index<=0;arm_age<=0;last_sample<=0;
   ready<=0;frame_valid<=0;triggered<=0;
  end else begin
   frame_valid<=0;
   if(sample_valid)decimate<=tick ? 3'd0 : decimate+1'b1;
   if(tick)begin
    if(capturing)begin
     last_sample<=sample[15:8];write_index<=write_index+1'b1;
     if(write_index==127)begin
      display_bank<=!display_bank;ready<=1;frame_valid<=1;triggered<=capture_triggered;
      capturing<=0;armed<=0;arm_age<=0;
     end
    end else begin
     if(sample<=-16'sd256)armed<=1;
     if(trigger_now||auto_now)begin
      capturing<=1;write_index<=1;last_sample<=sample[15:8];
      capture_triggered<=trigger_now;armed<=0;arm_age<=0;
     end else arm_age<=arm_age+1'b1;
    end
   end
  end
 end
endmodule
