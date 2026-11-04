`timescale 1ns/1ps
// Real UI I2S receiver and PCM recorder/store connected to the teammate's
// unmodified DDR adapter; only the DDR PHY/user-port behavior is modeled.
module tb_performance_record_chain;
parameter FRAMES=137;
reg clk=0,mem_clk=0,rst_n=0,bclk=0,lrc=1,din=0,local_record_toggle=0;
wire start,stop,record_request,start_rejected;wire [3:0] recorder_status;
wire signed [15:0] sample_left,sample_right;
wire stereo_valid,link_up;
wire frame_valid,frame_ready,capture_recording,capture_busy,capture_done;
wire capture_full,capture_overflow,capture_source_error,capture_command_error;
wire [31:0] frame_index,frame_data,captured_frames,capture_written;
wire start_accepted,store_busy,store_done,storage_error,protocol_error,command_error,backend_available;
wire [31:0] accepted_frames,stored_frames;
reg read_valid=0,read_data_ready=0;reg [31:0] read_index=0;
reg export_mode=0,export_start=0;
wire export_read_valid,export_read_ready,export_read_data_ready,export_busy,export_done;
wire [31:0] export_read_index;
wire [7:0] export_error;
wire export_packet_valid;
wire [6:0] export_packet_length;
wire [511:0] export_packet_payload;
integer exported=0;
wire read_ready,read_data_valid,read_error;
wire [31:0] read_data,read_data_index;
wire req_valid,req_ready,req_write,rsp_valid,rsp_write,rsp_error;
wire [28:0] req_addr;wire [255:0] req_wdata,rsp_rdata;wire [31:0] req_wmask;
reg init_done=0;
always #10 clk=~clk;
initial begin #3;forever #5 mem_clk=~mem_clk;end
i2s_visual_rx #(.LINK_TIMEOUT_CYCLES(50000)) rx(
 .clk(clk),.rst_n(rst_n),.i2s_bclk(bclk),.i2s_lrc(lrc),.i2s_din(din),
 .sample(sample_left),.sample_right(sample_right),.stereo_valid(stereo_valid),.link_up(link_up));
performance_recording_subsystem #(.FIFO_ADDR_BITS(2),.RESPONSE_TIMEOUT(10000)) recorder(
 .rst_n(rst_n),.src_clk(clk),.mem_clk(mem_clk),.init_done(init_done),.start(start),.stop(stop),
 .base_addr(29'd64),.region_end_addr(29'd16384),.capacity_frames(FRAMES),
 .link_up(link_up),.stereo_valid(stereo_valid),.sample_left(sample_left),.sample_right(sample_right),
 .recording(capture_recording),.active(store_busy),.done(store_done),.full(capture_full),
 .start_accepted(start_accepted),.start_rejected(start_rejected),
 .capture_error(capture_overflow),.storage_error(storage_error),.protocol_error(protocol_error),.command_error(command_error),
 .captured_frames(captured_frames),.accepted_frames(accepted_frames),.stored_frames(stored_frames),
 .read_valid(export_mode ? export_read_valid : read_valid),.read_ready(read_ready),
 .read_index(export_mode ? export_read_index : read_index),.read_data_valid(read_data_valid),
 .read_data_ready(export_mode ? export_read_data_ready : read_data_ready),.read_data(read_data),.read_data_index(read_data_index),
 .read_error(read_error),.backend_available(backend_available),
 .req_valid(req_valid),.req_ready(req_ready),.req_write(req_write),.req_addr(req_addr),
 .req_wdata(req_wdata),.req_wmask(req_wmask),.rsp_valid(rsp_valid),.rsp_write(rsp_write),
 .rsp_error(rsp_error),.rsp_rdata(rsp_rdata));

performance_audio_export exporter(.clk(clk),.rst_n(rst_n),.tick_1ms(1'b0),.start(export_start),
 .offset(32'd0),.count(FRAMES/12),.stereo(1'b1),.stored_frames(stored_frames),.generation(32'd1),
 .backend_available(backend_available),.busy(export_busy),.done(export_done),.error(export_error),
 .read_valid(export_read_valid),.read_ready(read_ready),.read_index(export_read_index),
 .read_data_valid(export_mode && read_data_valid),.read_error(read_error),.read_data(read_data),
 .read_data_index(read_data_index),.read_data_ready(export_read_data_ready),
 .packet_valid(export_packet_valid),.packet_ready(1'b1),.packet_length(export_packet_length),.packet_payload(export_packet_payload));

performance_command_decoder commands(
 .clk(clk),.rst_n(rst_n),.tick_1ms(1'b0),.packet_valid(1'b0),.packet_type(8'd0),
 .packet_length(7'd0),.packet_payload(512'd0),.local_play(1'b0),.local_pause_toggle(1'b0),
 .local_stop(1'b0),.local_record_toggle(local_record_toggle),
 .record_start_accepted(start_accepted),.record_start_rejected(start_rejected),
 .record_active(capture_recording),.record_busy(store_busy),.record_done(store_done),
 .record_start_pulse(start),.record_stop_pulse(stop),.recording(record_request));
performance_record_status status_dut(
 .clk(clk),.rst_n(rst_n),.start_accepted(start_accepted),.recording(capture_recording),
 .busy(store_busy),.done(store_done),.full(capture_full),.backend_available(backend_available),
 .link_up(link_up),.capture_error(capture_overflow),.storage_error(storage_error),
 .protocol_error(protocol_error),.command_error(command_error),.status(recorder_status));
task toggle_record;begin
 @(negedge clk);local_record_toggle=1;@(negedge clk);local_record_toggle=0;
 repeat(12)@(negedge clk);
end endtask
wire [2:0] mc_cmd;wire mc_cmd_en,mc_wr_data_en,mc_wr_data_end;
wire [28:0] mc_addr;wire [255:0] mc_wr_data;wire [31:0] mc_wr_data_mask;
reg mc_cmd_ready=0,mc_wr_data_rdy=0,mc_rd_data_valid=0,mc_rd_data_end=0;
reg [255:0] mc_rd_data=0;
ddr3_user_port_adapter adapter(
 .clk(mem_clk),.rst_n(rst_n),.init_done(init_done),.req_valid(req_valid),.req_ready(req_ready),
 .req_write(req_write),.req_addr(req_addr),.req_wdata(req_wdata),.req_wmask(req_wmask),
 .rsp_valid(rsp_valid),.rsp_write(rsp_write),.rsp_error(rsp_error),.rsp_rdata(rsp_rdata),
 .mc_cmd_ready(mc_cmd_ready),.mc_cmd(mc_cmd),.mc_cmd_en(mc_cmd_en),.mc_addr(mc_addr),
 .mc_wr_data_rdy(mc_wr_data_rdy),.mc_wr_data(mc_wr_data),.mc_wr_data_en(mc_wr_data_en),
 .mc_wr_data_end(mc_wr_data_end),.mc_wr_data_mask(mc_wr_data_mask),
 .mc_rd_data(mc_rd_data),.mc_rd_data_valid(mc_rd_data_valid),.mc_rd_data_end(mc_rd_data_end));
reg [255:0] memory[0:2047];
reg cmd_have=0,data_have=0,read_pending=0;
reg [28:0] addr_saved,read_addr;
reg [255:0] data_saved;
reg [31:0] mask_saved;
integer cycle=0,latency=0,commands_first=0,data_first=0,word,byte_index;
integer completed_writes=0;
wire command_fire=mc_cmd_en && mc_cmd_ready;
wire data_fire=mc_wr_data_en && mc_wr_data_rdy;
initial for(word=0;word<2048;word=word+1)memory[word]={8{32'hdeadbeef}};
always @(negedge mem_clk)begin
 cycle=cycle+1;
 // Alternate the required handshake order per completed write. Independent
 // time windows alone do not guarantee both orders after a DUT latency change.
 mc_cmd_ready=rst_n && !cmd_have && !read_pending && cycle%11<5 &&
  (mc_cmd==3'b001 || completed_writes%2==0 || data_have);
 mc_wr_data_rdy=rst_n && !data_have && !read_pending && cycle%13>=6 &&
  (completed_writes%2!=0 || cmd_have);
end
always @(posedge mem_clk)begin
 mc_rd_data_valid<=0;mc_rd_data_end<=0;
 if(!rst_n)begin cmd_have<=0;data_have<=0;read_pending<=0;completed_writes<=0;end
 else begin
  if(command_fire)begin
   if(mc_addr[2:0]!=0 || mc_addr>=16384)$fatal(1,"Bad controller address");
   if(mc_cmd==0)begin
    cmd_have<=1;addr_saved<=mc_addr;
    if(!data_have && !data_fire)commands_first=commands_first+1;
   end else if(mc_cmd==1)begin
    if(cmd_have || data_have)$fatal(1,"Read overtook pending write");
    read_pending<=1;read_addr<=mc_addr;latency<=7;
   end else $fatal(1,"Unsupported controller command");
  end
  if(data_fire)begin
   if(!mc_wr_data_end)$fatal(1,"Missing burst end");
   data_have<=1;data_saved<=mc_wr_data;mask_saved<=mc_wr_data_mask;
   if(!cmd_have && !command_fire)data_first=data_first+1;
  end
  if((cmd_have || (command_fire && mc_cmd==0)) && (data_have || data_fire))begin
   completed_writes<=completed_writes+1;
   for(byte_index=0;byte_index<32;byte_index=byte_index+1)
    if(!((data_have ? mask_saved : mc_wr_data_mask) & (32'b1<<byte_index)))
     memory[(cmd_have ? addr_saved : mc_addr)>>3][byte_index*8+:8]<=
      (data_have ? data_saved : mc_wr_data)>>(byte_index*8);
   cmd_have<=0;data_have<=0;
  end
  if(read_pending)begin
   if(latency!=0)latency<=latency-1;
   else begin
    mc_rd_data<=memory[read_addr>>3];mc_rd_data_valid<=1;mc_rd_data_end<=1;read_pending<=0;
   end
  end
 end
end
function [15:0] left_value;input integer index;
 begin left_value=(index*733)^16'h8000;end endfunction
function [15:0] right_value;input integer index;
 begin right_value=(index*977)^16'h7fff;end endfunction
function signed [15:0] golden_export;
 input integer frame,channel;
 integer tap,at;reg signed [47:0] accum;reg signed [15:0] sample,coefficient;
 begin
  accum=0;
  for(tap=0;tap<127;tap=tap+1)begin
   at=frame*12+11-tap;
   sample=at<0 ? 0 : channel ? right_value(at) : left_value(at);
   coefficient=exporter.filter.coefficients[tap];accum=accum+sample*coefficient;
  end
  accum=(accum+16384)>>>15;
  golden_export=accum>32767 ? 32767 : accum< -32768 ? -32768 : accum[15:0];
 end
endfunction
integer export_j;
always @(posedge clk)if(export_packet_valid)begin
 if(export_packet_payload[31:0]!=exported)$fatal(1,"DDR export offset");
 for(export_j=0;export_j<export_packet_payload[39:32];export_j=export_j+1)begin
  if(export_packet_payload[80+export_j*32+:16]!==golden_export(exported,0) ||
     export_packet_payload[96+export_j*32+:16]!==golden_export(exported,1))$fatal(1,"DDR -> FIR mismatch frame %0d",exported);
  exported=exported+1;
 end
end
task pulse_bclk;
 begin #50;bclk=0;#50;bclk=1;#50;bclk=0;end
endtask
task send_slot;
 input channel;input [31:0] value;input previous_lsb;
 integer bit_index;
 begin
  lrc=channel;din=previous_lsb;pulse_bclk;
  for(bit_index=31;bit_index>=0;bit_index=bit_index-1)begin din=value[bit_index];pulse_bclk;end
 end
endtask
integer i,guard,completion_count=0;
always @(posedge clk)if(store_done)completion_count=completion_count+1;
initial begin
 repeat(6)@(negedge clk);rst_n=1;
 repeat(14)@(negedge clk);pulse_bclk;
 repeat(12)@(negedge clk);
 if(!link_up || backend_available)$fatal(1,"Expected unavailable backend");
 toggle_record;
 if(record_request || store_busy || !command_error || recorder_status!=8)
  $fatal(1,"Rejected start did not restore button/status");
 init_done=1;repeat(16)@(negedge clk);
 if(!backend_available)$fatal(1,"Not ready for recording");
 toggle_record;
 if(!capture_recording)$fatal(1,"Start not passed to real capture");
 for(i=0;i<FRAMES;i=i+1)begin
  // Extension words deliberately differ from the final mix: never record them.
  send_slot(0,{left_value(i),16'h1357},i==0 ? 0 : 1);
  send_slot(1,{right_value(i),16'h2469},1);
 end
 guard=0;while(store_busy && guard<10000)begin @(negedge clk);guard=guard+1;end
 repeat(5)@(negedge clk);
 if(record_request || recorder_status!=5)$fatal(1,"Capacity termination did not restore button/show full");
 if(store_busy || completion_count!=1 || storage_error || protocol_error || command_error ||
    capture_overflow || !capture_full || captured_frames!=FRAMES || accepted_frames!=FRAMES || stored_frames!=FRAMES)
  $fatal(1,"Recording chain incomplete count=%0d/%0d/%0d error=%b/%b",captured_frames,accepted_frames,stored_frames,storage_error,protocol_error);
 for(i=0;i<FRAMES;i=i+1)begin
  wait(read_ready);@(negedge clk);read_valid=1;read_index=i;
  @(negedge clk);read_valid=0;wait(read_data_valid);@(negedge clk);
  if(read_error || read_data_index!=i || read_data!=={right_value(i),left_value(i)})
   $fatal(1,"Recorded I2S readback mismatch index=%0d got=%h",i,read_data);
  repeat(4)@(negedge clk);read_data_ready=1;@(negedge clk);read_data_ready=0;
 end
 // Read the same captured I2S recording through the real store/clock crossing
 // and adapter again, now exercising the production offline FIR export path.
 export_mode=1;@(negedge clk);export_start=1;@(negedge clk);export_start=0;
 wait(export_done);#1;
 if(export_error || exported!=FRAMES/12)$fatal(1,"DDR offline export incomplete");
 export_mode=0;repeat(8)@(negedge clk);
 // Full completion must allow the next tap to start; it is not a sticky stop request.
 toggle_record;
 if(!capture_recording || !record_request || recorder_status!=2)$fatal(1,"Restart after full failed");
 toggle_record;
 guard=0;while(store_busy && guard<10000)begin @(negedge clk);guard=guard+1;end
 repeat(6)@(negedge clk);
 if(record_request || store_busy || recorder_status!=4)$fatal(1,"Stop/drain did not show saved");
 toggle_record;
 if(!capture_recording)$fatal(1,"Source-loss test did not start");
 guard=0;while((store_busy || link_up) && guard<70000)begin @(negedge clk);guard=guard+1;end
 repeat(6)@(negedge clk);
 if(record_request || store_busy || recorder_status!=6)$fatal(1,"Source loss request=%b busy=%b status=%0d capture=%b storage=%b protocol=%b",record_request,store_busy,recorder_status,capture_overflow,storage_error,protocol_error);
 pulse_bclk;repeat(12)@(negedge clk);toggle_record;
 if(!capture_recording || !record_request || recorder_status!=2)$fatal(1,"Retry after source recovery failed");
 toggle_record;guard=0;
 while(store_busy && guard<10000)begin @(negedge clk);guard=guard+1;end
 repeat(6)@(negedge clk);
 if(recorder_status!=4)$fatal(1,"Recovered recording did not finish");
 init_done=0;repeat(16)@(negedge clk);
 if(recorder_status!=1)$fatal(1,"Calibration loss retained false saved status");
 if(commands_first==0 || data_first==0)$fatal(1,"Independent DDR handshakes not exercised");
 $display("PASS: %0d distinct VIS V2 I2S pairs -> PCM capture -> clock crossing -> teammate DDR adapter -> masked memory -> exact readback -> %0d golden FIR export frames; rejected-start retry, full/stop/source-loss recovery and real recorder status; command-first=%0d data-first=%0d",FRAMES,exported,commands_first,data_first);
 $finish;
end
initial begin #5000000;$fatal(1,"Record chain watchdog");end
endmodule
