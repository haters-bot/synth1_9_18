`timescale 1ns/1ps
// STATUS replies can be backpressured while a real panel/F15 pulse arrives.
// Those one-cycle events must not depend on the phone session being IDLE.
module tb_performance_calibration_poll;
 reg clk=0,rst_n=0,pv=0,ready=1,local_cal=0,nv=0;
 always #5 clk=~clk;
 reg [7:0] kind=0,seq=0;
 reg [6:0] length=0,note=41;
 reg [511:0] payload=0;
 wire rv,cv,invalid;wire [7:0] rt,ct;wire [6:0] rl,cl,base;
 wire [511:0] rp,cp;wire [2:0] cal;wire [15:0] epoch;
 performance_phone_session #(.CALIBRATION_ENABLE(1)) dut(
  .clk(clk),.rst_n(rst_n),.tick_1ms(1'b0),.packet_valid(pv),
  .packet_type(kind),.packet_sequence(seq),.packet_length(length),
  .packet_payload(payload),.packet_signature({8'd0,seq}),.fast_baud(1'b0),.ultra_baud(1'b0),
  .local_calibrate(local_cal),.calibration_idle(1'b1),
  .physical_note_valid(nv),.physical_note_on(1'b1),.physical_note(note),.physical_velocity(7'd100),
  .calibrated_base_note(base),.calibration_state(cal),.calibration_epoch(epoch),.invalidate_score(invalid),
  .command_valid(cv),.command_type(ct),.command_length(cl),.command_payload(cp),
  .decoder_error(1'b0),.score_error(1'b0),.score_running(1'b0),
  .record_active(1'b0),.record_busy(1'b0),.record_start_accepted(1'b0),.record_start_rejected(1'b0),
  .backend_available(1'b1),.audio_link_up(1'b1),.record_status(4'd4),.stored_frames(32'd0),
  .upload_active(),.export_busy(),.reply_sequence(),.read_valid(),.read_index(),.read_data_ready(),
  .reply_valid(rv),.reply_ready(ready),.reply_type(rt),.reply_length(rl),.reply_payload(rp),
  .read_ready(1'b0),.read_data_valid(1'b0),.read_error(1'b0),.read_data(32'd0),.read_data_index(32'd0));
 task step;begin @(negedge clk);end endtask
 task packet(input [7:0] k,input [6:0] n);begin
  step;kind=k;length=n;seq=seq+1;pv=1;step;pv=0;
 end endtask
 task drain;begin ready=1;wait(dut.state==0);repeat(3)step;end endtask
 task arm;begin step;local_cal=1;step;local_cal=0;wait(cal==1);step;end endtask
 task pulse_note(input [6:0] n);begin note=n;nv=1;step;nv=0;end endtask
 integer i;
 initial begin
  repeat(3)step;rst_n=1;repeat(3)step;
  payload=123;packet(1,4);wait(rv);drain;
  // Do not lose CALIBRATE just because a STATUS response is awaiting UART.
  ready=0;packet(2,0);wait(rv);step;
  local_cal=1;step;local_cal=0;repeat(3)step;
  if(cal!=0)$fatal(1,"calibration changed before queued panel action could drain");
  drain;repeat(80)step;
  if(cal!=1)$fatal(1,"CALIBRATE pulse lost during STATUS reply");
  // F15 Note On must be accepted while the STATUS reply remains stalled.
  ready=0;packet(2,0);wait(rv);step;pulse_note(41);
  if(cal!=2 || base!=41)$fatal(1,"F15 calibration Note lost during STATUS reply");
  drain;
  // Exercise the short CHECK and COMPOSE windows as well as SEND.
  for(i=0;i<2;i=i+1)begin
   arm;packet(2,0);
   if(i==1)step;
   pulse_note(53+12*i);
   if(cal!=2 || base!=53+12*i)$fatal(1,"F15 Note lost during STATUS processing");
   wait(rv);drain;
   packet(2,0);wait(rv);
   if(rp[191:184]!=2 || rp[87:80]!=53+12*i || !rp[23])$fatal(1,"fresh STATUS lost calibrated state");
   drain;
  end
  // A new connection has priority over any calibration from the old session.
  arm;payload=124;packet(1,4);pulse_note(77);wait(rv);drain;
  if(cal!=0)$fatal(1,"new HELLO did not invalidate old-session calibration");
  $display("PASS: panel calibration survives STATUS backpressure; F15 capture survives CHECK/COMPOSE/SEND; fresh STATUS and HELLO invalidation preserved");$finish;
 end
 initial begin #100000;$fatal(1,"calibration poll watchdog");end
endmodule
