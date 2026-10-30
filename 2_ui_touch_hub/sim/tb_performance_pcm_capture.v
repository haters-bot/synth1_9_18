`timescale 1ns/1ps
module tb_performance_pcm_capture;
parameter DEPTH=3;
reg clk=0,rst_n=0,start=0,stop=0,clear=0,link_up=1,stereo_valid=0,write_ready=1;
reg signed [15:0] sample_left=0,sample_right=0;
reg [31:0] capacity_frames=100;
wire write_valid,recording,busy,done,full,overflow,source_error,command_error;
wire [31:0] write_index,write_data,captured_frames,written_frames;
performance_pcm_capture #(.FIFO_DEPTH(DEPTH)) dut(.*);
always #10 clk=~clk;
integer reads=0,expected_reads=0,done_count=0,i;
reg [31:0] expected[0:1000];
reg stall_prev=0;reg [31:0] stalled_data,stalled_index;
always @(posedge clk)begin
 if(rst_n)begin
  if(stall_prev && (!write_valid || write_data!==stalled_data || write_index!==stalled_index))
   $fatal(1,"Write stream changed while stalled");
  if(write_valid && write_ready)begin
   if(reads>=expected_reads || write_index!==reads || write_data!==expected[reads])
    $fatal(1,"PCM order/pair/index mismatch read=%0d index=%0d data=%h",reads,write_index,write_data);
   reads=reads+1;
  end
  stall_prev=write_valid && !write_ready;
  stalled_data=write_data;stalled_index=write_index;
  if(done)done_count=done_count+1;
 end else stall_prev=0;
end
task step;begin @(negedge clk);end endtask
task begin_capture;
 input integer capacity;
 begin
  reads=0;expected_reads=0;done_count=0;capacity_frames=capacity;
  start=1;step;start=0;step;
 end
endtask
task sample;
 input integer l,r; input accepted;
 begin
  sample_left=l;sample_right=r;stereo_valid=1;
  if(accepted)begin expected[expected_reads]={sample_right,sample_left};expected_reads=expected_reads+1;end
  step;stereo_valid=0;
 end
endtask
task drain;
 begin
  write_ready=1;repeat(DEPTH+5)step;
  if(busy || reads!=expected_reads || captured_frames!=expected_reads || written_frames!=expected_reads)
   $fatal(1,"Drain/count mismatch %0d %0d %0d %0d",reads,expected_reads,captured_frames,written_frames);
  if(done_count!=1)$fatal(1,"Done must pulse once after final drain, got %0d",done_count);
 end
endtask
initial begin
 repeat(3)step;rst_n=1;step;
 // No backend capacity or absent I2S cannot pretend to record.
 begin_capture(0);if(recording || !source_error)$fatal(1,"Zero capacity accepted");
 link_up=0;begin_capture(100);if(recording || !source_error)$fatal(1,"Disconnected I2S accepted");link_up=1;
 // Signed extremes, uninterrupted input, FIFO wrapping and ready stalls.
 begin_capture(100);
 for(i=0;i<40;i=i+1)begin sample(i==0 ? -32768 : i*733-12000,i==0 ? 32767 : 16000-i*511,1);end
 write_ready=0;sample(123,-456,1);sample(-789,1000,1);repeat(4)step;
 // Illegal clear/start during capture must preserve queued samples.
 clear=1;step;clear=0;start=1;step;start=0;
 if(!command_error || !recording)$fatal(1,"Busy command was destructive");
 write_ready=1;sample(-1,-2,1);stop=1;step;stop=0;drain;
 // Capacity boundary: last accepted frame is retained; following sample ignored.
 begin_capture(2);write_ready=0;sample(-123,456,1);sample(32767,-32768,1);sample(999,999,0);
 if(recording || !full || overflow)$fatal(1,"Capacity end incorrect");
 drain;
 // FIFO full with a simultaneous dequeue still accepts the new frame.
 begin_capture(100);write_ready=0;
 for(i=0;i<DEPTH;i=i+1)sample(i,-i,1);
 write_ready=1;sample(777,-888,1);stop=1;step;stop=0;drain;
 // First missed sample stops capture and flags loss; never silently skip it.
 begin_capture(100);write_ready=0;
 for(i=0;i<DEPTH;i=i+1)sample(i+500,-i-500,1);
 sample(1234,5678,0);
 if(recording || !overflow)$fatal(1,"Overflow not reported");
 start=1;step;start=0;if(!command_error)$fatal(1,"Restart discarded pending writes");
 drain;
 // Source loss preserves pending PCM and marks the result incomplete.
 begin_capture(100);write_ready=0;sample(-100,100,1);link_up=0;step;
 if(recording || !source_error)$fatal(1,"I2S loss not reported");
 drain;link_up=1;
 // Stop overrides a coincident input frame; empty recording still completes.
 begin_capture(100);stop=1;sample(123,456,0);stop=0;drain;
 clear=1;step;clear=0;step;
 if(captured_frames || written_frames || full || overflow || source_error || command_error)
  $fatal(1,"Idle clear did not reset metadata");
 $display("PASS: PCM capture depth=%0d, exact stereo order, signed samples, backpressure, capacity, overflow, drain, source loss and command priority",DEPTH);
 $finish;
end
initial begin #200000;$fatal(1,"PCM timeout");end
endmodule
