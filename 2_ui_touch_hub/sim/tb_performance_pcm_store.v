`timescale 1ns/1ps
module tb_performance_pcm_store;
parameter SRC_HALF=10,MEM_HALF=7;
reg rst_n=0,src_clk=0,mem_clk=0,start=0,finish=0,source_error_in=0;
reg [28:0] base_addr=64,region_end_addr=16384;
reg [31:0] capacity_frames=100,frame_index=0,frame_data=0,read_index=0;
reg frame_valid=0,read_valid=0,read_data_ready=0,init_done=1,req_ready=0;
wire start_accepted,start_rejected,frame_ready,busy,done,storage_error,protocol_error,command_error;
wire [31:0] accepted_frames,stored_frames,read_data,read_data_index;
wire read_ready,read_data_valid,read_error,backend_available;
wire req_valid,req_write;wire [28:0] req_addr;wire [255:0] req_wdata;
wire [31:0] req_wmask;
reg model_rsp_valid=0,model_rsp_write=0,model_rsp_error=0;
reg [255:0] model_rsp_rdata=0;
reg immediate=0;
wire rsp_valid=immediate ? req_valid && req_ready : model_rsp_valid;
wire rsp_write=immediate ? req_write : model_rsp_write;
wire rsp_error=immediate ? 1'b0 : model_rsp_error;
reg [255:0] memory[0:2047];
wire [255:0] rsp_rdata=immediate ? memory[req_addr>>3] : model_rsp_rdata;
performance_pcm_store #(.FIFO_ADDR_BITS(2),.RESPONSE_TIMEOUT(500)) dut(.*);
always #(SRC_HALF)src_clk=~src_clk;
initial begin #3;forever #(MEM_HALF)mem_clk=~mem_clk;end

// Independent variable-latency DDR transaction model. Write acknowledgements
// occur after applying byte masks, never at frontend/FIFO acceptance.
reg model_pending=0,pending_write=0,pending_error=0;
reg [28:0] pending_addr=0;
reg [255:0] pending_data=0;
reg [31:0] pending_mask=0;
reg [31:0] random_state=32'h91a523c7;
integer delay_cycles=0,stall_cycles=0,error_write=-1,write_requests=0,requests=0;
integer byte_index,initialize;
reg suppress_response=0;
reg fail_read=0,wrong_response_kind=0;
initial for(initialize=0;initialize<2048;initialize=initialize+1)
 memory[initialize]={8{32'hdeadbeef}};
always @(negedge mem_clk)begin
 random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
 if(stall_cycles>0)stall_cycles=stall_cycles-1;
 req_ready=rst_n && init_done && !model_pending && stall_cycles==0 && random_state[2:0]!=0;
end
always @(posedge mem_clk)begin
 model_rsp_valid<=0;
 if(!rst_n)begin model_pending<=0;write_requests<=0;requests<=0;end
 else begin
  if(model_pending && !suppress_response)begin
   if(delay_cycles>0)delay_cycles<=delay_cycles-1;
   else begin
    model_pending<=0;model_rsp_valid<=1;model_rsp_write<=pending_write ^ wrong_response_kind;model_rsp_error<=pending_error;
    model_rsp_rdata<=memory[pending_addr>>3];
    if(pending_write && !pending_error)
     for(byte_index=0;byte_index<32;byte_index=byte_index+1)
      if(!pending_mask[byte_index])memory[pending_addr>>3][byte_index*8+:8]<=pending_data[byte_index*8+:8];
   end
  end
  if(req_valid && req_ready)begin
   if(req_addr[2:0]!=0 || req_addr>=16384)$fatal(1,"DDR request out of reserved region/alignment");
   requests<=requests+1;
   if(req_write)write_requests<=write_requests+1;
   if(immediate)begin
    if(req_write)for(byte_index=0;byte_index<32;byte_index=byte_index+1)
     if(!req_wmask[byte_index])memory[req_addr>>3][byte_index*8+:8]<=req_wdata[byte_index*8+:8];
   end else begin
    model_pending<=1;pending_write<=req_write;pending_addr<=req_addr;
    pending_data<=req_wdata;pending_mask<=req_wmask;delay_cycles<=random_state[5:3];
    pending_error<=req_write ? write_requests==error_write : fail_read;
   end
  end
 end
end
// Every field of an outstanding request must hold until the backend is ready.
reg request_stalled=0;reg [317:0] stalled_request;
always @(posedge mem_clk)begin
 if(!rst_n)request_stalled=0;
 else begin
  if(request_stalled && req_valid && {req_write,req_addr,req_wmask,req_wdata}!==stalled_request)
   $fatal(1,"DDR request changed under backpressure");
  request_stalled=req_valid && !req_ready;
  stalled_request={req_write,req_addr,req_wmask,req_wdata};
 end
end

integer done_count=0,start_count=0;
always @(posedge src_clk)if(rst_n)begin
 if(done)done_count=done_count+1;
 if(start_accepted)start_count=start_count+1;
end
task step;begin @(negedge src_clk);end endtask
task reset_all;
begin
 rst_n=0;start=0;finish=0;source_error_in=0;frame_valid=0;read_valid=0;read_data_ready=0;
 init_done=1;suppress_response=0;error_write=-1;immediate=0;stall_cycles=0;fail_read=0;wrong_response_kind=0;
 repeat(8)step;rst_n=1;repeat(12)step;
 done_count=0;start_count=0;
 if(!backend_available)$fatal(1,"Memory readiness did not cross clocks");
end endtask
reg [31:0] seed=0;
function [31:0] pattern;
 input [31:0] index;
 begin pattern=(index*32'h9e3779b9)^seed^32'h80007fff;end
endfunction
task begin_record;
 input integer capacity;
 begin
  seed=seed+32'h1020304;capacity_frames=capacity;base_addr=64;region_end_addr=16384;
  start=1;step;start=0;step;
  if(!busy)$fatal(1,"Valid recording start rejected");
  // Descriptor inputs are not held after start: the DUT must latch them.
  capacity_frames=0;base_addr=128;region_end_addr=0;
 end
endtask
task send;
 input integer index;
 integer guard;
 begin
  guard=0;while(!frame_ready && guard<10000)begin step;guard=guard+1;end
  if(!frame_ready)$fatal(1,"Frame input remained blocked index=%0d state=%0d error=%b/%b",index,dut.src_state,storage_error,protocol_error);
  frame_valid=1;frame_index=index;frame_data=pattern(index);step;frame_valid=0;
 end
endtask
task wait_done;
 integer guard;
 begin
  guard=0;while(busy && guard<15000)begin step;guard=guard+1;end
  repeat(3)step;
  if(busy || done_count!=1)$fatal(1,"Missing/duplicate store completion busy=%b done=%0d",busy,done_count);
  done_count=0;
 end
endtask
task read_one;
 input [31:0] index;input error_expected;
 integer guard,n;
 reg [64:0] held;
 begin
  guard=0;while(!read_ready && guard<1000)begin step;guard=guard+1;end
  if(!read_ready)$fatal(1,"Read not ready");
  read_valid=1;read_index=index;step;read_valid=0;
  guard=0;while(!read_data_valid && guard<3000)begin step;guard=guard+1;end
  if(!read_data_valid || read_error!==error_expected || read_data_index!==index)
   $fatal(1,"Read status/index mismatch %0d",index);
  if(!error_expected && read_data!==pattern(index))
   $fatal(1,"PCM readback mismatch index=%0d got=%h expected=%h",index,read_data,pattern(index));
  held={read_error,read_data_index,read_data};
  for(n=0;n<3;n=n+1)begin
   step;if(!read_data_valid || {read_error,read_data_index,read_data}!==held)$fatal(1,"Read response changed under backpressure");
  end
  read_data_ready=1;step;read_data_ready=0;repeat(2)step;
 end
endtask
task record_and_check;
 input integer length;
 integer index,tail;
 begin
  begin_record(length+1);
  for(index=0;index<length;index=index+1)send(index);
  finish=1;step;finish=0;wait_done;
  if(storage_error || protocol_error || accepted_frames!=length || stored_frames!=length)
   $fatal(1,"Recording count/error mismatch len=%0d accepted=%0d stored=%0d",length,accepted_frames,stored_frames);
  for(index=0;index<length;index=index+1)read_one(index,0);
  read_one(length,1);read_one(32'he0000000,1);
  // Fill tail with sentinels before a dedicated partial-block test below.
 end
endtask
integer i,n,requests_before;
initial begin
 reset_all;
 // Invalid descriptors cannot erase metadata or issue memory transactions.
 base_addr=65;region_end_addr=16384;capacity_frames=8;start=1;step;start=0;step;
 if(busy || !command_error || requests!=0)$fatal(1,"Misaligned descriptor accepted");
 base_addr=64;region_end_addr=72;capacity_frames=9;start=1;step;start=0;step;
 if(busy || requests!=0)$fatal(1,"Capacity crosses reserved region");
 init_done=0;repeat(5)step;base_addr=64;region_end_addr=16384;capacity_frames=8;start=1;step;start=0;step;
 if(busy || backend_available)$fatal(1,"Uninitialized DDR accepted start");
 init_done=1;repeat(6)step;
 // Every possible partial tail plus a longer wraparound recording.
 for(n=0;n<=17;n=n+1)record_and_check(n);
 record_and_check(63);record_and_check(64);record_and_check(65);
 record_and_check(2053);
 // Inspect final mask independently, preserving bytes beyond the last frame.
 memory[8]={8{32'hdeadbeef}};begin_record(8);send(0);send(1);send(2);
 finish=1;step;finish=0;wait_done;
 for(i=3;i<8;i=i+1)if(memory[8][i*32+:32]!==32'hdeadbeef)$fatal(1,"Partial tail overwrote unrecorded PCM");
 for(i=0;i<3;i=i+1)read_one(i,0);
 // Capacity auto-finish and illegal restart while busy preserve the stream.
 begin_record(17);start=1;step;start=0;
 if(!command_error)$fatal(1,"Busy restart not reported");
 for(i=0;i<17;i=i+1)send(i);wait_done;
 if(stored_frames!=17 || storage_error)$fatal(1,"Exact capacity completion failed");
 for(i=0;i<17;i=i+1)read_one(i,0);
 // A full CDC FIFO must backpressure without losing/reordering frames.
 stall_cycles=200;begin_record(100);
 for(i=0;i<80;i=i+1)send(i);
 finish=1;step;finish=0;wait_done;
 if(stored_frames!=80 || storage_error)$fatal(1,"CDC stall lost PCM");
 for(i=0;i<80;i=i+1)read_one(i,0);
 // Same-cycle request/response is legal on both reads and writes.
 immediate=1;record_and_check(19);immediate=0;
 fail_read=1;read_one(3,1);fail_read=0;read_one(3,0);
 wrong_response_kind=1;read_one(5,1);wrong_response_kind=0;read_one(5,0);
 // Calibration loss invalidates stored metadata even between transactions.
 init_done=0;repeat(5)step;init_done=1;repeat(6)step;read_one(0,1);
 // A discontinuous frame index terminates an incomplete recording explicitly.
 begin_record(100);send(0);send(2);wait_done;
 if(!protocol_error || stored_frames!=1)$fatal(1,"Index discontinuity not reported");
 read_one(0,1);
 begin_record(100);send(0);send(1);source_error_in=1;step;source_error_in=0;wait_done;
 if(!protocol_error || stored_frames!=2)$fatal(1,"Capture loss reported as complete audio");
 read_one(0,1);
 // Backend write error must never become successful EOF or readable song.
 error_write=write_requests;begin_record(100);
 for(i=0;i<8;i=i+1)send(i);
 finish=1;step;finish=0;wait_done;
 if(!storage_error || stored_frames!=0)$fatal(1,"Write error reported as success");
 read_one(0,1);error_write=-1;
 record_and_check(9);
 // Missing response: quarantine, terminate, and do not retry automatically.
 suppress_response=1;begin_record(100);
 for(i=0;i<8;i=i+1)send(i);
 finish=1;step;finish=0;wait_done;
 if(!storage_error || backend_available || stored_frames!=0)$fatal(1,"Timeout did not quarantine DDR");
 requests_before=requests;suppress_response=0;repeat(30)step;
 if(requests!=requests_before || !storage_error)$fatal(1,"Late response triggered retry/success");
 reset_all;record_and_check(11);
 // Reset both clock domains with a transaction in flight; no stale EOF/data.
 suppress_response=1;begin_record(100);for(i=0;i<8;i=i+1)send(i);
 repeat(20)step;reset_all;record_and_check(13);
 // Loss of initialization while a request waits also quarantines the port.
 stall_cycles=100;begin_record(100);for(i=0;i<8;i=i+1)send(i);
 repeat(12)step;init_done=0;wait_done;
 if(!storage_error || backend_available)$fatal(1,"DDR calibration loss not reported");
 $display("PASS: PCM DDR transport clocks=%0d/%0d, all tail masks, 2053-frame readback, FIFO wrap/stall, capacity, errors, timeout quarantine and reset",SRC_HALF,MEM_HALF);
 $finish;
end
initial begin #30000000;$fatal(1,"PCM store watchdog");end
endmodule
