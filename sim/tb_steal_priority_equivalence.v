`timescale 1ns/1ps
// 对比逐槽线性参考与分组优先器，覆盖首个候选及不足8槽的尾组。
module tb_steal_priority_equivalence #(parameter ENGINES=2, SLOTS=32);
 localparam TOTAL=ENGINES*SLOTS;
 reg clk=0,rst_n=0;
 wire [6:0] count;
 integer i,t,first;
 reg [31:0] rng=32'hb93a61c5;
 reg expected_found,expected_cont;
 reg [6:0] expected_note;
 reg [2:0] expected_source;
 oscillator_task_scheduler #(.ENGINE_COUNT(ENGINES),.SLOTS_PER_ENGINE(SLOTS)) dut (
 .clk(clk),.rst_n(rst_n),.note_event_valid(1'b0),.note_event_on(1'b0),
 .note_event_note(7'd0),.note_event_velocity(7'd0),.unison_count(4'd1),.detune_amount(7'd0),
 .phase_control(7'd0),.rand_control(7'd0),.task_idle_mask({TOTAL{1'b0}}),
 .continuous_event_valid(1'b0),.continuous_event_on(1'b0),.continuous_event_source(3'd0),
 .continuous_event_base_step(32'd0),.continuous_event_velocity(7'd0),
 .task_update_valid(),.task_update_slot(),.task_update_phase_step(),.task_update_base_step(),
 .task_update_detune_unit(),.task_update_detune_magnitude(),.task_update_detune_negative(),
 .task_update_velocity(),.task_update_enable(),.task_update_phase_reset(),
 .task_update_is_continuous(),.task_update_initial_phase(),.scheduler_busy(),
 .active_task_count(count));
 initial begin
  #1;
  for(t=0;t<10000;t=t+1) begin
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   dut.pending_is_continuous=rng[0]; dut.pending_note=rng[7:1]; dut.pending_source=rng[10:8];
   expected_found=0; expected_note=0;expected_cont=0;expected_source=0;first=-1;
   for(i=0;i<TOTAL;i=i+1) begin
    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    dut.slot_active[i]=(t<4) ? (i==(t==0?0:t==1?7:t==2?8:TOTAL-1)) : rng[0];
    dut.slot_continuous[i]=rng[1];dut.slot_note[i]=rng[8:2];dut.slot_source[i]=rng[11:9];
    if (!expected_found && dut.slot_active[i] &&
        ((dut.slot_continuous[i] != dut.pending_is_continuous) ||
         (dut.slot_continuous[i] && dut.slot_source[i] != dut.pending_source) ||
         (!dut.slot_continuous[i] && dut.slot_note[i] != dut.pending_note))) begin
      expected_found=1;expected_note=dut.slot_note[i];expected_cont=dut.slot_continuous[i];expected_source=dut.slot_source[i];first=i;
    end
   end
   #1;
   if ({dut.steal_note_found,dut.steal_note,dut.steal_is_continuous,dut.steal_source} !==
       {expected_found,expected_note,expected_cont,expected_source})
       $fatal(1,"candidate mismatch iter=%0d first=%0d",t,first);
  end
  $display("PASS grouped steal priority: %0d slots, 10000 cases",TOTAL);$finish;
 end
endmodule
