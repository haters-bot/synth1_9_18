`timescale 1ns/1ps
// Production F15 UART/parser -> panel controls -> session -> decoder -> full
// renderer -> Note arbiter -> actual 31250-baud MIDI output. Clock is scaled
// to 500 kHz for simulation; both UARTs retain 32 us wire bit periods.
module tb_performance_calibration;
 reg clk=0,rst_n=0,rx=1,tick=0,tv=0,td=0,vs=0;
 always #1000 clk=~clk;
 reg [13:0] x=0,y=0;
 wire [7:0] kb;wire kv,nv,non;wire [6:0] nn,nvel;
 performance_uart_rx #(.CLK_FREQ(500000),.BAUD(31250)) rx_uart(
  .clk(clk),.rst_n(rst_n),.uart_rx(rx),.byte_data(kb),.byte_valid(kv),.framing_error());
 keyboard_midi_parser parser(.clk(clk),.rst_n(rst_n),.byte_data(kb),.byte_valid(kv),
  .note_event_valid(nv),.note_event_on(non),.note_event_note(nn),.note_event_velocity(nvel));
 reg pv=0;reg [7:0] kind=0,seq=0;reg [6:0] length=0;reg [511:0] payload=0;
 wire cv;wire [7:0] ck;wire [6:0] cl;wire [511:0] cp;
 wire reply_valid;wire [7:0] reply_type;wire [6:0] reply_length;wire [511:0] reply_payload;
 wire [6:0] base;wire [2:0] cal;wire [15:0] epoch;
 wire invalid,notes_busy,tx_busy,up,busy,score_running,score_error,decoder_error;
 wire lplay,lpause,lstop,lrecord,lcal,page_active;
 wire clear_events,event_push,event_on,start,stop,pause,remote,remote_on;
 wire [31:0] event_time,duration;wire [6:0] event_note,event_velocity,remote_note,remote_vel;
 wire mode_valid;wire [1:0] mode,local_mode;
 wire note_valid,note_on,tx_ready;wire [6:0] note,vel;
 reg gate=1,record_busy=0;
 performance_touch_controls #(.CONTACT_TIMEOUT_CYCLES(64)) controls(
  .clk(clk),.rst_n(rst_n),.page_active(page_active),.touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),
  .play(lplay),.pause_toggle(lpause),.stop(lstop),.record_toggle(lrecord),.calibrate(lcal));
 performance_phone_session #(.MAX_EVENTS(16),.CALIBRATION_ENABLE(1)) session(
  .clk(clk),.rst_n(rst_n),.tick_1ms(tick),.packet_valid(pv),.packet_type(kind),.packet_sequence(seq),
  .packet_length(length),.packet_payload(payload),.packet_signature({8'd0,seq}),.fast_baud(1'b0),.ultra_baud(1'b0),
  .local_calibrate(lcal),.calibration_idle(!notes_busy && !tx_busy),
  .physical_note_valid(nv),.physical_note_on(non),.physical_note(nn),.physical_velocity(nvel),
  .calibrated_base_note(base),.calibration_state(cal),.calibration_epoch(epoch),.invalidate_score(invalid),
  .command_valid(cv),.command_type(ck),.command_length(cl),.command_payload(cp),
  .decoder_error(decoder_error),.score_error(score_error),.score_running(score_running),
  .record_active(1'b0),.record_busy(record_busy),.record_start_accepted(1'b0),.record_start_rejected(1'b0),
  .backend_available(1'b1),.audio_link_up(1'b1),.record_status(4'd4),.stored_frames(32'd0),
  .upload_active(up),.export_busy(busy),.reply_valid(reply_valid),.reply_ready(1'b1),
  .reply_type(reply_type),.reply_length(reply_length),.reply_payload(reply_payload),
  .read_ready(1'b0),.read_data_valid(1'b0),.read_error(1'b0),.read_data(32'd0),.read_data_index(32'd0));
 performance_command_decoder #(.MAX_EVENTS(16)) decoder(
  .clk(clk),.rst_n(rst_n),.tick_1ms(tick),.invalidate_score(invalid),
  .packet_valid(cv),.packet_type(ck),.packet_length(cl),.packet_payload(cp),
  .local_play(lplay && cal==2 && !up),.local_pause_toggle(lpause),.local_stop(lstop),.local_record_toggle(1'b0),
  .local_mode_valid(mode_valid),.local_mode(local_mode),.performance_mode(mode),
  .record_start_accepted(1'b0),.record_start_rejected(1'b0),.record_active(1'b0),.record_busy(1'b0),.record_done(1'b0),
  .clear_events(clear_events),.event_push(event_push),.event_time_ms(event_time),.event_note(event_note),
  .event_velocity(event_velocity),.event_on(event_on),.start_pulse(start),.stop_pulse(stop),.pause_state(pause),
  .manual_valid(remote),.manual_on(remote_on),.manual_note(remote_note),.manual_velocity(remote_vel),
  .song_duration_ms(duration),.protocol_error(decoder_error));
 ui_top_renderer #(.PERFORMANCE_RUNTIME_BASE(1),.PERFORMANCE_MAX_EVENTS(16),
  .PERFORMANCE_USE_NOTE_READY(1),.TOUCH_CONTACT_TIMEOUT_CYCLES(100000)) dut(
  .clk(clk),.rst_n(rst_n),.in_hsync(1'b0),.in_vsync(vs),.in_den(1'b0),.in_pixel_x(14'd0),.in_pixel_y(14'd0),
  .ui_touch_valid(tv),.ui_touch_down(td),.ui_touch_x(x),.ui_touch_y(y),
  .performance_base_note(base),.performance_calibration_state(cal),.performance_invalidate(invalid),
  .performance_notes_busy(notes_busy),.performance_page_active(page_active),
  .performance_tick_1ms(tick),.performance_clear_events(clear_events),.performance_event_push(event_push),
  .performance_event_time_ms(event_time),.performance_event_note(event_note),.performance_event_velocity(event_velocity),
  .performance_event_on(event_on),.performance_start(start),.performance_stop(stop),.performance_pause(pause),
  .performance_mode(mode),.performance_local_mode_valid(mode_valid),.performance_local_mode(local_mode),
  .performance_duration_ms(duration),.performance_gateway_up_in(1'b1),.performance_recording_in(1'b0),.performance_record_status_in(4'd4),
  .performance_remote_note_valid(remote),.performance_remote_note_on(remote_on),.performance_remote_note(remote_note),.performance_remote_velocity(remote_vel),
  .performance_physical_note_valid(nv),.performance_physical_note_on(non),.performance_physical_note(nn),.performance_physical_velocity(nvel),
  .performance_note_ready(tx_ready && gate),.performance_note_valid(note_valid),.performance_note_on(note_on),
  .performance_note_number(note),.performance_note_velocity(vel),.performance_score_error_out(score_error),.performance_running_out(score_running));
 wire tx;
 midi_uart_tx #(.CLK_FREQ(500000),.BAUD(31250)) tx_uart(.clk(clk),.rst_n(rst_n),
  .note_on_req(note_valid && note_on && gate),.note_off_req(note_valid && !note_on && gate),.note_number(note),.note_velocity(vel),
  .cc_req(1'b0),.cc_param_id(8'd0),.cc_val(7'd0),.sysex_req(1'b0),.sysex_msgs(48'd0),
  .note_ready(tx_ready),.uart_tx(tx),.tx_busy(tx_busy));
 integer replies=0,observed=0;reg [511:0] ack;reg [23:0] messages[0:127];
 always @(posedge clk)if(reply_valid)begin
  if(reply_type!=8'h70 || reply_length!=26)$fatal(1,"calibration ACK schema");
  ack=reply_payload;replies=replies+1;
 end
 task byte_rx(output reg [7:0] b);integer i;begin
  @(negedge tx);#16000;for(i=0;i<8;i=i+1)begin #32000;b[i]=tx;end
  #32000;if(tx!==1)$fatal(1,"serial stop");
 end endtask
 reg [7:0] b0,b1,b2;
 initial forever begin
  byte_rx(b0);byte_rx(b1);byte_rx(b2);messages[observed]={b0,b1,b2};
  $display("UART: %02h %02h %02h",b0,b1,b2);observed=observed+1;
 end
 task step;begin @(negedge clk);end endtask
 task touch(input integer px,py,input bit down);begin step;x=px;y=py;td=down;tv=1;step;tv=0;repeat(3)step;end endtask
 task click(input integer px,py);begin touch(px,py,1);touch(0,0,0);end endtask
 task request(input [7:0] k,input integer n,code);integer target;begin
  step;kind=k;length=n;seq=seq+1;target=replies+1;pv=1;step;pv=0;
  wait(replies==target);step;
  if(ack[7:0]!=code)$fatal(1,"command %02h status=%d expected=%d",k,ack[7:0],code);
  repeat(5)step;
 end endtask
 task hello(input integer nonce);begin payload=nonce;request(1,4,0);end endtask
 task byte_send(input [7:0] b);integer i;begin
  step;rx=0;#32000;for(i=0;i<8;i=i+1)begin rx=b[i];#32000;end rx=1;#32000;
 end endtask
 task physical(input [7:0] status,input integer n,v);begin byte_send(status);byte_send(n);byte_send(v);repeat(5)step;end endtask
 task arm;begin click(900,150);wait(cal==1);repeat(3)step;end endtask
 task check_status(input integer expected_base,expected_state);begin
  payload=0;request(2,0,0);
  if(ack[183:176]!=1 || ack[191:184]!=expected_state || ack[207:192]!=epoch || ack[87:80]!=expected_base || ack[95:88]!=32)
   $fatal(1,"STATUS base/calibration/epoch mismatch");
  if(ack[23]!=(expected_state==2))$fatal(1,"calibrated flag");
 end endtask
 task begin_song(input integer count,input [15:0] e,input integer code);begin
  payload=0;request(8'h10,0,0);payload=0;payload[31:0]=500;payload[47:32]=count;payload[63:48]=e;
  request(8'h11,8,code);
 end endtask
 task upload_song(input integer n);begin
  begin_song(2,epoch,0);
  payload=0;payload[63:0]={8'd0,8'd1,8'd100,n[7:0],32'd10};
  payload[127:64]={8'd0,8'd0,8'd0,n[7:0],32'd400};request(8'h12,16,0);payload=0;request(8'h13,0,0);
 end endtask
 task advance(input integer n);integer i;begin
  for(i=0;i<n;i=i+1)begin tick=1;step;tick=0;repeat(8)step;end
 end endtask
 integer bank,expected_base,seen_before,nonce=100;reg [15:0] old_epoch;
 initial begin
  repeat(5)step;rst_n=1;repeat(10)step;
  click(650,20);vs=1;repeat(10)step;vs=0;repeat(20)step;
  if(!page_active)$fatal(1,"performance page navigation");
  hello(nonce);begin_song(2,epoch,7);request(8'h20,0,7);
  physical(8'h90,41,100);if(cal!=0)$fatal(1,"unarmed calibration");
  arm;physical(8'h80,41,64);physical(8'h90,41,0);if(cal!=1)$fatal(1,"Off/velocity zero calibrated");
  payload=0;payload[7:0]=41;payload[15:8]=100;payload[23:16]=1;request(8'h30,3,7);
  if(cal!=1)$fatal(1,"phone note calibrated");
  physical(8'h90,89,100);if(cal!=3)$fatal(1,"unsafe 0x59 accepted");
  for(bank=0;bank<4;bank=bank+1)begin
   expected_base=41+12*bank;
   arm;physical(8'h90,expected_base,100);if(cal!=2 || base!=expected_base)$fatal(1,"safe bank capture");
   check_status(expected_base,2);old_epoch=epoch;
   // Identical HELLO retry must be fresh STATUS, without resetting calibration.
   payload=nonce;request(1,4,0);if(cal!=2 || epoch!=old_epoch || ack[191:184]!=2)$fatal(1,"HELLO retry invalidated or stale ACK");
   begin_song(2,epoch-1,7);upload_song(expected_base+31);
   record_busy=1;click(900,150);if(cal!=2)$fatal(1,"record busy arm");record_busy=0;
   payload=0;request(8'h23,1,0);seen_before=observed;request(8'h20,0,0);advance(15);
   wait(observed==seen_before+1);repeat(5)step;
   if(messages[seen_before]!=={8'h90,expected_base[7:0]+8'd31,8'd100})$fatal(1,"dynamic audition pitch");
   if(dut.performance_guide_keys!==32'h80000000 || dut.performance_led_guide_keys!==24'h040000 || dut.performance_led_guide_keys[23:19]!=0)
    $fatal(1,"dynamic guide/19 white LED mapping");
   // Reconnect while audition holds a Note: send Off using OLD absolute pitch.
   gate=0;nonce=nonce+1;hello(nonce);repeat(180)step;
   if(cal!=0 || session.loaded || score_running || dut.performance_guide_keys!=0)$fatal(1,"reconnect did not invalidate score");
   click(900,150);repeat(100)step;if(cal!=4)$fatal(1,"calibration did not wait for backpressure cleanup");
   physical(8'h90,41,100);if(cal!=4 || base!=expected_base)$fatal(1,"base changed seen_before old Note Off");
   gate=1;wait(observed==seen_before+2);wait(cal==1);
   if(messages[seen_before+1]!=={8'h80,expected_base[7:0]+8'd31,8'd0})$fatal(1,"cleanup released wrong pitch");
   physical(8'h90,expected_base,100);if(cal!=2)$fatal(1,"recapture");
   check_status(expected_base,2);if(ack[19] || ack[79:64]!=0)$fatal(1,"old score reactivated");
   // Same runtime origin drives physical-key masks and local touch Notes.
   physical(8'h90,expected_base,100);if(dut.performance_physical_keys!==1)$fatal(1,"physical origin");
   physical(8'h80,expected_base,0);seen_before=observed;
   click(20,500);wait(observed==seen_before+2);
   if(messages[seen_before]!=={8'h90,expected_base[7:0],8'd100} || messages[seen_before+1]!=={8'h80,expected_base[7:0],8'd0})$fatal(1,"touch origin");
   repeat(10)step;
   // A new HELLO must require a fresh explicit panel calibration even when idle.
   nonce=nonce+1;hello(nonce);check_status(expected_base,0);
  end
  arm;physical(8'h90,77,100);upload_song(79);
  payload=1;request(8'h23,1,0);seen_before=observed;request(8'h20,0,0);advance(30);
  if(dut.performance_song_time_ms!=10)$fatal(1,"follow wait");
  physical(8'h90,78,100);advance(10);if(dut.performance_song_time_ms!=10)$fatal(1,"wrong key advanced");
  physical(8'h90,79,100);advance(10);if(dut.u_performance_scheduler.read_ptr!=1 || dut.performance_guide_keys[2]!==1)$fatal(1,"correct dynamic follow key");
  if(observed!=seen_before)$fatal(1,"physical follow emitted UI notes");
  $display("PASS: real 31250 F15 -> explicit panel calibration -> STATUS/nonce/epoch -> runtime renderer/follow/19 LEDs/touch/audition; four safe banks, unsafe/Off/phone rejection, reconnect invalidation, old-pitch Note Off under backpressure");$finish;
 end
 initial begin #200000000;$fatal(1,"calibration watchdog");end
endmodule
