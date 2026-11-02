`timescale 1ns/1ps
// 对照旧版颤音、滑音及MIDI输出，每个系统时钟逐位比较。
module tb_vibrato_timing_equivalence;
 reg clk=0,rst_n=0,tick=0,nvalid=0,non=0,enable=0,porta=0;
 reg [6:0] note=60,vel=100,rate=127,depth=127,ptime=40;
 wire [92:0] new_out,ref_out;
 reg [31:0] rng=32'had2479b1;
 integer i;
 always #10 clk=~clk;
 performance_pitch_controller dut (
  .clk(clk),.rst_n(rst_n),.sample_tick(tick),.note_event_valid(nvalid),.note_event_on(non),.note_event_note(note),.note_event_velocity(vel),
  .vibrato_enable(enable),.vibrato_rate(rate),.vibrato_depth(depth),.portamento_enable(porta),.portamento_time(ptime),
  .routed_note_event_valid(new_out[92]),.routed_note_event_on(new_out[91]),.routed_note_event_note(new_out[90:84]),.routed_note_event_velocity(new_out[83:77]),
  .glide_override_enable(new_out[76]),.glide_base_step(new_out[75:44]),.vibrato_ratio_delta_q16(new_out[43:31]),
  .debug_current_pitch_q16(),.debug_target_pitch_q16());
 performance_pitch_controller_reference ref_dut (
  .clk(clk),.rst_n(rst_n),.sample_tick(tick),.note_event_valid(nvalid),.note_event_on(non),.note_event_note(note),.note_event_velocity(vel),
  .vibrato_enable(enable),.vibrato_rate(rate),.vibrato_depth(depth),.portamento_enable(porta),.portamento_time(ptime),
  .routed_note_event_valid(ref_out[92]),.routed_note_event_on(ref_out[91]),.routed_note_event_note(ref_out[90:84]),.routed_note_event_velocity(ref_out[83:77]),
  .glide_override_enable(ref_out[76]),.glide_base_step(ref_out[75:44]),.vibrato_ratio_delta_q16(ref_out[43:31]),
  .debug_current_pitch_q16(),.debug_target_pitch_q16());
 always @(posedge clk) if(rst_n) begin
   #1;
   if (new_out[92:31] !== ref_out[92:31]) $fatal(1,"cycle %0d new=%h ref=%h",i,new_out,ref_out);
 end
 initial begin
  #100 rst_n=1;
  for(i=0;i<250000;i=i+1) begin
   @(negedge clk);
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   // 先持续满速运行，覆盖正弦全周期和相位回卷；后切换参数及相邻tick。
   if(i<100000) begin tick=1;enable=1;rate=127;depth=i[6:0];end
   else begin tick=rng[0]|rng[5];enable=rng[3]|rng[8];rate=rng[13:7];depth=rng[20:14];end
   nvalid=(rng[8:0]==0);non=rng[10];note=21+(rng[17:11]%88);vel=rng[24:18];
   porta=rng[25];ptime=rng[6:0];
  end
  @(negedge clk);$display("PASS vibrato and performance controls cycle-equivalent: 250000 cycles");$finish;
 end
endmodule
