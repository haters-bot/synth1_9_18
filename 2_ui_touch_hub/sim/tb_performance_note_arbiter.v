`timescale 1ns/1ps
module tb_performance_note_arbiter;
reg clk=0,rst_n=0,score_valid=0,remote_valid=0,touch_valid=0;
reg score_on=0,remote_on=0,touch_on=0,gate=0;
reg [6:0] score_note=0,remote_note=0,touch_note=0;
wire note_valid,note_ready,note_on,overflow,serial,uart_ready;
wire [6:0] note_number,note_velocity;
always #10 clk=~clk;
performance_note_arbiter dut(
 .clk(clk),.rst_n(rst_n),.score_valid(score_valid),.score_on(score_on),.score_note(score_note),.score_velocity(7'd100),
 .remote_valid(remote_valid),.remote_on(remote_on),.remote_note(remote_note),.remote_velocity(7'd80),
 .touch_valid(touch_valid),.touch_on(touch_on),.touch_note(touch_note),.touch_velocity(7'd60),
 .note_valid(note_valid),.note_ready(note_ready),.note_on(note_on),.note_number(note_number),.note_velocity(note_velocity),.overflow(overflow));
assign note_ready=uart_ready && gate;
midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(6250000)) tx(
 .clk(clk),.rst_n(rst_n),.note_on_req(note_valid && note_on && gate),.note_off_req(note_valid && !note_on && gate),
 .note_number(note_number),.note_velocity(note_velocity),.cc_req(1'b0),.cc_param_id(8'd0),.cc_val(7'd0),
 .sysex_req(1'b0),.sysex_msgs(48'd0),.uart_tx(serial),.tx_busy(),.note_ready(uart_ready));
reg [14:0] stalled;reg was_stalled=0;integer transferred=0;
always @(posedge clk)if(rst_n)begin
 if(was_stalled && (!note_valid || {note_on,note_number,note_velocity}!==stalled))$fatal(1,"Payload/valid changed under backpressure");
 was_stalled=note_valid && !note_ready;
 if(was_stalled)stalled={note_on,note_number,note_velocity};
 if(note_valid && note_ready)transferred=transferred+1;
end
integer received=0,sa=0,ra=0,ta=0,idx,source,base,velocity;
reg [7:0] b0,b1,b2;
task byte_rx;output [7:0] b;integer k;begin
 @(negedge serial);#80;
 for(k=0;k<8;k=k+1)begin #160;b[k]=serial;end
 #160;if(serial!==1)$fatal(1,"UART stop bit");
end endtask
initial forever begin
 byte_rx(b0);byte_rx(b1);byte_rx(b2);
 if(b1<60)begin source=0;idx=sa;sa=sa+1;base=21;velocity=100;end
 else if(b1<90)begin source=1;idx=ra;ra=ra+1;base=60;velocity=80;end
 else begin source=2;idx=ta;ta=ta+1;base=90;velocity=60;end
 if(idx>=12 || b1!=base+idx/2 || b0!=(idx%2==0 ? 8'h90 : 8'h80) || b2!=(idx%2==0 ? velocity : 0))
  $fatal(1,"Serialized source=%0d index=%0d got=%h %h %h",source,idx,b0,b1,b2);
 received=received+1;
end
integer i;
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 // Stall a remote event, then let the higher-priority score queue become nonempty.
 remote_valid=1;remote_on=1;remote_note=60;
 @(negedge clk);remote_valid=0;
 repeat(2)@(negedge clk);score_valid=1;score_on=1;score_note=21;
 @(negedge clk);score_valid=0;
 repeat(3)@(negedge clk);gate=1;touch_valid=1;touch_on=1;touch_note=90;
 @(negedge clk);touch_valid=0;
 for(i=1;i<12;i=i+1)begin
  score_valid=1;remote_valid=1;touch_valid=1;
  score_on=i%2==0;remote_on=i%2==0;touch_on=i%2==0;
  score_note=21+i/2;remote_note=60+i/2;touch_note=90+i/2;
  @(negedge clk);
 end
 score_valid=0;remote_valid=0;touch_valid=0;
 wait(received==36);repeat(20)@(negedge clk);
 if(overflow || transferred!=36 || sa!=12 || ra!=12 || ta!=12)$fatal(1,"Collision coverage");
 // A real overload must be visible, while existing queued payload stays stable.
 gate=0;repeat(3)@(negedge clk);
 // 16 queue entries plus one elastic output slot are accepted while stalled.
 for(i=0;i<18;i=i+1)begin score_valid=1;score_note=21;@(negedge clk);end
 score_valid=0;@(negedge clk);
 if(!overflow)$fatal(1,"Queue overload silently ignored");
 $display("PASS: 36 simultaneous three-source events through production MIDI UART, preserved per-source On/Off order, UART backpressure stability and explicit overflow");
 $finish;
end
initial begin #2000000;$fatal(1,"Note arbiter watchdog");end
endmodule
