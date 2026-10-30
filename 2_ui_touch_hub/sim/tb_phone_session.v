`timescale 1ns/1ps
module tb_phone_session;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,tick_1ms=0,packet_valid=0;
 reg [7:0] packet_type=0,packet_sequence=0;reg [6:0] packet_length=0;
 reg [511:0] packet_payload=0;reg [15:0] packet_signature=0;reg fast_baud=0;
 wire command_valid;wire [7:0] command_type;wire [6:0] command_length;wire [511:0] command_payload;
 wire decoder_error,score_error,score_running;
 reg record_active=0,record_busy=0,record_start_accepted=0,record_start_rejected=0;
 reg backend_available=1,audio_link_up=1;reg [3:0] record_status=4;
 reg [31:0] stored_frames=144;
 wire upload_active,export_busy,reply_valid;reg reply_ready=1;
 wire [7:0] reply_type,reply_sequence;wire [6:0] reply_length;wire [511:0] reply_payload;
 wire read_valid;reg read_ready=1;wire [31:0] read_index;
 reg read_data_valid=0,read_error=0;reg [31:0] read_data=0,read_data_index=0;wire read_data_ready;
 performance_phone_session #(.MAX_EVENTS(16)) dut(.*);
 wire clear_events,event_push,start_pulse,stop_pulse,record_start_pulse,record_stop_pulse,pause_state;
 wire [31:0] event_time_ms;wire [6:0] event_note,event_velocity;wire event_on;
 performance_command_decoder #(.MAX_EVENTS(16)) decoder(.clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),
  .packet_valid(command_valid),.packet_type(command_type),.packet_length(command_length),.packet_payload(command_payload),
  .local_play(1'b0),.local_pause_toggle(1'b0),.local_stop(1'b0),.local_record_toggle(1'b0),
  .record_start_accepted(record_start_accepted),.record_start_rejected(record_start_rejected),
  .record_active(record_active),.record_busy(record_busy),.record_done(1'b0),
  .clear_events(clear_events),.event_push(event_push),.event_time_ms(event_time_ms),.event_note(event_note),
  .event_velocity(event_velocity),.event_on(event_on),.start_pulse(start_pulse),.stop_pulse(stop_pulse),
  .record_start_pulse(record_start_pulse),.record_stop_pulse(record_stop_pulse),.pause_state(pause_state),.protocol_error(decoder_error));
 wire [4:0] loaded_events;
 performance_event_scheduler #(.MAX_EVENTS(16)) scheduler(.clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),
  .clear_events(clear_events),.event_push(event_push),.event_time_ms(event_time_ms),.event_note(event_note),
  .event_velocity(event_velocity),.event_on(event_on),.start(start_pulse),.stop(stop_pulse),.pause(pause_state),
  .running(score_running),.load_error(score_error),.loaded_events(loaded_events));
 integer replies=0,audio_packets=0,starts=0,checks=0;
 reg [7:0] last_status,last_kind;reg [31:0] last_generation;
 always @(posedge clk)begin
  record_start_accepted<=record_start_pulse;
  if(record_start_pulse)begin record_active<=1;record_busy<=1;starts=starts+1;end
  if(record_stop_pulse)begin record_active<=0;record_busy<=0;end
  read_data_valid<=read_valid && read_ready;
  if(read_valid && read_ready)begin read_data_index<=read_index;read_data<=32'hffe00020;end
  if(reply_valid && reply_ready)begin
   if(reply_type==8'h70)begin
    if(reply_sequence!=packet_sequence || reply_length!=22)$fatal(1,"ACK header");
    last_status=reply_payload[7:0];last_kind=reply_payload[15:8];last_generation=reply_payload[159:128];replies=replies+1;
   end else if(reply_type==8'h71)audio_packets=audio_packets+1;else $fatal(1,"reply type");
  end
 end
 task request(input [7:0] kind,input integer length,expected_status,input reg replay);
  integer target;
  begin
   @(negedge clk);packet_type=kind;packet_length=length;
   if(!replay)begin packet_sequence=packet_sequence+1;packet_signature=packet_signature+1;end
   target=replies+1;packet_valid=1;@(negedge clk);packet_valid=0;
   wait(replies==target);#1;
   if(last_status!=expected_status || last_kind!=kind)$fatal(1,"request %x got status %d expected %d",kind,last_status,expected_status);
   checks=checks+1;repeat(4)@(negedge clk);
  end
 endtask
 task begin_song(input integer count);
  begin
   request(8'h10,0,0,0);packet_payload=0;packet_payload[31:0]=500;packet_payload[47:32]=count;request(8'h11,6,0,0);
  end
 endtask
 task batch_good;
  begin packet_payload=0;packet_payload[63:0]={8'd0,8'd1,8'd100,8'd60,32'd100};
   packet_payload[127:64]={8'd0,8'd0,8'd0,8'd60,32'd200};end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  request(1,0,0,0);request(8'h20,0,3,0);
  packet_payload=0;packet_payload[31:0]=500;packet_payload[47:32]=2;request(8'h11,6,2,0);
  begin_song(3);batch_good;request(8'h12,16,0,0);request(8'h12,16,0,1);
  if(loaded_events!=2)$fatal(1,"duplicate wrote score twice");
  request(8'h13,0,3,0);request(8'h20,0,3,0);
  begin_song(2);batch_good;packet_payload[95:64]=50;request(8'h12,16,1,0);
  if(loaded_events!=0)$fatal(1,"invalid batch partially committed");
  begin_song(2);batch_good;packet_payload[39:32]=59;request(8'h12,16,1,0);
  begin_song(2);batch_good;request(8'h12,16,0,0);request(8'h13,0,0,0);request(8'h20,0,0,0);
  if(!score_running)$fatal(1,"score not started");
  request(8'h10,0,2,0);request(8'h22,0,0,0);
  backend_available=0;request(8'h40,0,2,0);backend_available=1;
  audio_link_up=0;request(8'h40,0,2,0);audio_link_up=1;
  request(8'h40,0,0,0);request(8'h40,0,0,1);
  if(starts!=1 || last_generation!=1)$fatal(1,"record retry or generation");
  packet_payload=0;packet_payload[47:32]=3;packet_payload[55:48]=2;request(8'h43,7,2,0);
  request(8'h41,0,0,0);request(8'h43,7,0,0);request(8'h43,7,0,1);
  if(audio_packets!=2)$fatal(1,"export replay");
  packet_payload[31:0]=12;request(8'h43,7,4,0);
  $display("PASS: %0d board ACK/error transactions, real scheduler atomic upload/count/order/range/capacity, duplicate recording and resumable export",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"session timeout state %d",dut.state);end
endmodule
