`timescale 1ns/1ps
module tb_modulation_audio_equivalence;
 `include "audio_capabilities.vh"
 reg clk=0,rst_n=0,tick=0;always #10 clk=~clk;
 reg [370:0] base_values=0;reg [105:0] sources=0;reg [423:0] depths=0;
 reg [20:0] waves=0;wire [370:0] preview,reference;wire valid;
 modulation_preview ui(.clk(clk),.rst_n(rst_n),.nodes(147'd0),.rates(9'd0),.stepped(3'd0),
  .active_tab(2'd0),.active_phase(9'd0),.raster_index(9'd0),.sources(sources),.depths(depths),
  .base_values(base_values),.preview_values(preview));
 // This is the unmodified audio RTL extracted from pinned Git, not a rewritten model.
 lfo_target_router_v2 audio(.clk(clk),.rst_n(rst_n),.sample_tick(tick),.base_values(base_values),
  .sources(sources),.depths(depths),.waves(waves),.mod_values(reference),.output_valid(valid));
 integer w,d,n,b,expected,checks=0;
 initial begin
  force ui.samples=waves;
  repeat(4)@(negedge clk);rst_n=1;
  for(w=0;w<128;w=w+1)for(d=-127;d<=127;d=d+1)begin
   waves={w[6:0],w[6:0],w[6:0]};
   for(n=0;n<53;n=n+1)begin
    case(n%4)0:b=127;1:b=64;2:b=0;3:b=(n+w+d+256)%128;endcase
    base_values[n*7+:7]=b;sources[n*2+:2]=(n%3)+1;depths[n*8+:8]=d;
   end
   @(negedge clk);tick=1;@(negedge clk);tick=0;
   wait(valid);repeat(5)@(negedge clk);
   for(n=0;n<53;n=n+1)begin
    b=base_values[n*7+:7];expected=b+((d*w)>>>7);
    if(expected<0)expected=0;else if(expected>127)expected=127;
    if(reference[n*7+:7]!==expected[6:0])$fatal(1,"audio reference/math n=%0d b=%0d d=%0d w=%0d got=%0d expected=%0d",n,b,d,w,reference[n*7+:7],expected);
    if(audio_lfo_connected(n))begin
     if(preview[n*7+:7]!==reference[n*7+:7])$fatal(1,"audio/UI n=%0d b=%0d d=%0d w=%0d got=%0d ref=%0d",n,base_values[n*7+:7],d,w,preview[n*7+:7],reference[n*7+:7]);
     checks=checks+1;
    end else if(preview[n*7+:7]!==base_values[n*7+:7])$fatal(1,"NC preview did not retain base");
   end
  end
  release ui.samples;
  $display("PASS: %0d connected target values vs unmodified audio router; all 255 signed depths x 128 waves, bases 0/64/127/variable, all banks, 29 NC base-only",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"equivalence watchdog");end
endmodule
