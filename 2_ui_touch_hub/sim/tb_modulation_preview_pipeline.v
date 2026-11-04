`timescale 1ns/1ps
module tb_modulation_preview_pipeline;
 `include "audio_capabilities.vh"
 reg clk=0,rst_n=0;
 always #10 clk=~clk;
 reg [146:0] nodes={{7{7'd119}},{7{7'd64}},{7{7'd21}}};
 reg [8:0] rates=9'b111_110_101;
 reg [2:0] stepped=0;
 reg [1:0] active_tab=0;
 reg [8:0] active_phase=0,raster_index=0;
 reg [105:0] sources=0;
 reg [423:0] depths=0;
 reg [370:0] base_values=0;
 wire [370:0] preview_values;wire [12:0] raster_q6;
 modulation_preview #(.PREVIEW_BASE_TICKS(128)) dut(.*);
 wire [26:0] captured_phases={dut.curves[2].preview_phase,dut.curves[1].preview_phase,dut.curves[0].preview_phase};
 reg [26:0] expected_phases;
 integer warm=0,checks=0,i,round_index,dep,source_id,value,expected;
 always @(posedge clk)if(rst_n)begin
  expected_phases={dut.render_active_tab==2 ? active_phase : dut.phase[2],
                   dut.render_active_tab==1 ? active_phase : dut.phase[1],
                   dut.render_active_tab==0 ? active_phase : dut.phase[0]};
  warm=warm+1;
  #1;
  if(captured_phases!==expected_phases)$fatal(1,"preview phase/tab pipeline mixed banks");
  if(warm>800)begin
   if(dut.samples!=={7'd119,7'd64,7'd21})$fatal(1,"preview bank sample register changed constant curves");
   if(raster_q6!==(dut.render_active_tab==0 ? 13'd1344 : dut.render_active_tab==1 ? 13'd4096 : 13'd7616))
    $fatal(1,"preview pipelining changed raster curve selection/value");
  end
 end
 task varying_phases(input integer cycles);
  integer j;
  begin for(j=0;j<cycles;j=j+1)begin
   @(negedge clk);active_phase=$urandom_range(0,511);raster_index=$urandom_range(0,511);
   active_tab=j%3;stepped=j[2:0];
  end end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;varying_phases(900);
  for(round_index=0;round_index<24;round_index=round_index+1)begin
   for(i=0;i<53;i=i+1)begin
    sources[i*2+:2]=(i+round_index)%4;
    depths[i*8+:8]=(i*17+round_index*13)%255-127;
    base_values[i*7+:7]=(i*3+round_index)%128;
   end
   varying_phases(70);
   for(i=0;i<53;i=i+1)begin
    source_id=(i+round_index)%4;dep=(i*17+round_index*13)%255-127;
    value=source_id==1 ? 21 : source_id==2 ? 64 : 119;
    expected=(i*3+round_index)%128;
    if(source_id!=0 && audio_lfo_connected(i)) expected=expected+((dep*value)>>>7);
    if(expected<0)expected=0;else if(expected>127)expected=127;
    if(preview_values[i*7+:7]!==expected[6:0])
     $fatal(1,"preview target=%0d source=%0d depth=%0d got=%0d expected=%0d",i,source_id,dep,preview_values[i*7+:7],expected);
    checks=checks+1;
   end
  end
  $display("PASS: %0d independent 53-target signed-depth/base-value checks, three registered preview phases/samples, fast tab/phase changes and unchanged raster values",checks);
  $finish;
 end
 initial begin #1000000;$fatal(1,"preview pipeline watchdog");end
endmodule
