`timescale 1ns/1ps
module tb_phone_record_resume;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,tick_1ms=0,packet_valid=0;
 reg [7:0] packet_type=0,packet_sequence=0;
 reg [6:0] packet_length=0;reg [511:0] packet_payload=0;
 reg [15:0] packet_signature=0;reg fast_baud=0,turbo_baud=0;
 wire local_calibrate=0,calibration_idle=1,physical_note_valid=0,physical_note_on=0;
 wire [6:0] physical_note=0,physical_velocity=0;
 wire [6:0] calibrated_base_note;
 wire [2:0] calibration_state;wire [15:0] calibration_epoch;wire invalidate_score;
 wire command_valid;wire [7:0] command_type;wire [6:0] command_length;wire [511:0] command_payload;
 wire decoder_error=0,score_error=0,score_running=0;
 reg record_active=0,record_busy=0,record_start_accepted=0,record_start_rejected=0;
 reg backend_available=1,audio_link_up=1;reg [3:0] record_status=4;
 reg [31:0] stored_frames=144;
 wire upload_active,export_busy,recording_discarded,reply_valid;
 reg reply_ready=1;wire [7:0] reply_type,reply_sequence;wire [6:0] reply_length;wire [511:0] reply_payload;
 wire read_valid;wire read_ready=1;wire [31:0] read_index;
 reg read_data_valid=0,read_error=0;reg [31:0] read_data=0,read_data_index=0;wire read_data_ready;
 performance_phone_session #(.CALIBRATION_ENABLE(1)) dut(.*);
 reg [511:0] ack;reg [6:0] ack_length;integer replies=0,audio=0,checks=0,reads=0;
 localparam [127:0] CLAIM_A=128'h102030405060708090a0b0c0d0e0f001,
                    CLAIM_B=128'hffeeddccbbaa99887766554433221199;
 always @(posedge clk)begin
  read_data_valid<=read_valid;
  if(read_valid)begin reads=reads+1;read_data<=32'hfff80008;read_data_index<=read_index;end
  if(reply_valid && reply_ready)begin
   if(reply_type==8'h70)begin ack=reply_payload;ack_length=reply_length;replies=replies+1;end
   else if(reply_type==8'h71)audio=audio+1;else $fatal(1,"unexpected reply");
  end
 end
 task request(input [7:0] kind,input integer len,code,input replay);
  integer target;
  begin
   @(negedge clk);packet_type=kind;packet_length=len;
   if(!replay)begin packet_sequence=packet_sequence+1;packet_signature=packet_signature+1;end
   target=replies+1;packet_valid=1;@(negedge clk);packet_valid=0;
   wait(replies==target);#1;
   if(ack[7:0]!==code || ack[15:8]!==kind || ack_length!==(kind==8'h44 ? 44 : 26))
    $fatal(1,"request %x status %0d length %0d",kind,ack[7:0],ack_length);
   checks=checks+1;repeat(4)@(negedge clk);
  end
 endtask
 task info(input [127:0] claim);
  begin packet_payload=0;packet_payload[127:0]=claim;request(8'h44,16,0,0);end
 endtask
 task read_block;
  begin packet_payload=0;packet_payload[47:32]=3;packet_payload[55:48]=1;request(8'h43,7,0,0);end
 endtask
 task new_take;
  begin @(negedge clk);record_start_accepted=1;@(negedge clk);record_start_accepted=0;end
 endtask
 reg [31:0] gen;
 integer before_reads;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  packet_payload=32'h101;request(1,4,0,0);info(CLAIM_A);
  if(ack[351:224]!==CLAIM_A || ack[215:208]!==1 || ack[223:216]!==0 || ack[63:32]!==144)
   $fatal(1,"first identity/slow baud");
  info(CLAIM_B);if(ack[351:224]!==CLAIM_A)$fatal(1,"reconnect claim replaced recording identity");
  fast_baud=1;info(CLAIM_B);if(ack[223:216]!==1)$fatal(1,"115200 baud code");
  turbo_baud=1;info(CLAIM_B);if(ack[223:216]!==2)$fatal(1,"230400 baud code");
  gen=ack[159:128];packet_payload=32'h202;request(1,4,0,0);info(CLAIM_B);
  if(ack[351:224]!==CLAIM_A || ack[159:128]!==gen)$fatal(1,"HELLO destroyed recording");
  read_block();read_block();if(audio!=2)$fatal(1,"replayed offset not regenerated");
  record_active=1;record_busy=1;request(8'h42,0,2,0);
  packet_payload=CLAIM_B;request(8'h44,16,2,0);
  record_active=0;record_busy=0;info(CLAIM_B);if(ack[351:224]!==CLAIM_A)$fatal(1,"busy attempt destroyed token");
  request(8'h42,0,0,0);gen=ack[159:128];before_reads=reads;
  if(!recording_discarded || ack[63:32]!==0 || ack[31:24]!==0 || dut.recording_token!==0)$fatal(1,"logical clear");
  request(8'h42,0,0,1);if(ack[159:128]!==gen)$fatal(1,"lost clear ACK retry generation");
  request(8'h42,0,0,0);if(ack[159:128]!==gen)$fatal(1,"repeat clear generation");
  info(CLAIM_B);if(ack[351:224]!==0 || ack[63:32]!==0)$fatal(1,"discarded recording reclaimed");
  packet_payload=0;packet_payload[47:32]=3;packet_payload[55:48]=1;request(8'h43,7,4,0);
  if(reads!=before_reads)$fatal(1,"logical clear touched DDR");
  new_take();info(CLAIM_B);
  if(recording_discarded || ack[351:224]!==CLAIM_B || ack[159:128]!==gen+1)$fatal(1,"new recording identity");
  // A local take and INFO CHECK collide: the lifecycle clear must win.
  packet_payload=CLAIM_A;
  @(negedge clk);packet_type=8'h44;packet_length=16;packet_sequence=packet_sequence+1;packet_signature=packet_signature+1;packet_valid=1;
  @(negedge clk);packet_valid=0;record_start_accepted=1;
  @(negedge clk);record_start_accepted=0;
  wait(dut.state==0);info(CLAIM_A);if(ack[351:224]!==CLAIM_A)$fatal(1,"local start/claim collision");
  // Backend loss invalidates the take and cached INFO, including exact retry.
  backend_available=0;repeat(3)@(negedge clk);backend_available=1;
  packet_payload=CLAIM_A;request(8'h44,16,0,1);
  if(ack[351:224]!==0 || ack[63:32]!==0)$fatal(1,"stale cached identity after DDR loss");
  new_take();info(CLAIM_B);if(ack[351:224]!==CLAIM_B)$fatal(1,"new take after backend recovery");
  rst_n=0;repeat(3)@(negedge clk);rst_n=1;info(CLAIM_A);
  if(ack[351:224]!==CLAIM_A || ack[159:128]!==0)$fatal(1,"reset identity did not restart safely");
  packet_payload=0;request(8'h44,16,1,0);request(8'h44,15,1,0);
  $display("PASS: %0d recording identity/baud/reconnect/resume/discard/reset/DDR-loss/lifecycle-race transactions; old ACK lengths preserved, no DDR erase",checks);$finish;
 end
 initial begin #20000000;$fatal(1,"resume test timeout state %0d",dut.state);end
endmodule
