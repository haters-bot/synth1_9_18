`timescale 1ns/1ps
module tb_performance_audio_export;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,tick_1ms=0,start=0;
 reg [31:0] offset=0,stored_frames=8192,generation=17;
 reg [15:0] count=0;reg stereo=1,backend_available=1;
 wire busy,done;wire [7:0] error;
 wire read_valid;reg read_ready=0;wire [31:0] read_index;
 reg read_data_valid=0,read_error=0;reg [31:0] read_data=0,read_data_index=0;
 wire read_data_ready,packet_valid;reg packet_ready=0;
 wire [6:0] packet_length;wire [511:0] packet_payload;
 performance_audio_export dut(.*);
 reg [31:0] pcm[0:8191],gold[0:681];
 integer cycle=0,delay=0,seen=0,expect_index=0,checks=0,i;
 reg pending=0,inject_error=0,drop_response=0;
 reg [31:0] pending_index;
 reg signed [15:0] l,r,got_l,got_r;
 reg signed [16:0] mono;
 always @(negedge clk)begin
  cycle=cycle+1;read_ready=!pending && cycle%7!=0;packet_ready=cycle%11<4;
  read_data_valid=0;
  if(pending)begin
   if(delay>0)delay=delay-1;
   else if(!drop_response)begin
    read_data_valid=1;read_error=inject_error;read_data_index=pending_index;read_data=pcm[pending_index];pending=0;
   end
  end
 end
 always @(posedge clk)begin
  if(read_valid && read_ready)begin pending=1;pending_index=read_index;delay=cycle%5+1;end
  if(packet_valid && packet_ready)begin
   if(packet_payload[31:0]!=expect_index || packet_payload[79:48]!=generation ||
      packet_payload[47:40]!=(stereo ? 2 : 1))$fatal(1,"header mismatch");
   if(packet_payload[39:32]==0 || packet_payload[39:32]>(stereo ? 13 : 27))$fatal(1,"count mismatch");
   if(packet_length!=10+packet_payload[39:32]*(stereo ? 4 : 2))$fatal(1,"length mismatch");
   for(i=0;i<packet_payload[39:32];i=i+1)begin
    l=gold[expect_index][15:0];r=gold[expect_index][31:16];
    if(stereo)begin
     got_l=packet_payload[80+i*32+:16];got_r=packet_payload[96+i*32+:16];
     if(got_l!==l || got_r!==r)$fatal(1,"FIR stereo frame %0d got %0d/%0d expected %0d/%0d",expect_index,got_l,got_r,l,r);
    end else begin
     mono=$signed({l[15],l})+$signed({r[15],r});got_l=packet_payload[80+i*16+:16];
     if(got_l!==mono[16:1])$fatal(1,"FIR mono frame %0d",expect_index);
    end
    checks=checks+1;expect_index=expect_index+1;seen=seen+1;
   end
  end
 end
 task run_block(input integer at,n,ch,expected_error);
  begin
   @(negedge clk);offset=at;count=n;stereo=ch==2;seen=0;expect_index=at;start=1;
   @(negedge clk);start=0;
   wait(done);#1;
   if(error!=expected_error)$fatal(1,"error got %0d expected %0d",error,expected_error);
   if(expected_error==0 && seen!=n)$fatal(1,"short output %0d/%0d",seen,n);
   repeat(4)@(negedge clk);
  end
 endtask
 initial begin
  $readmemh("pcm.hex",pcm);$readmemh("gold.hex",gold);
  repeat(4)@(negedge clk);rst_n=1;
  run_block(0,150,2,0);run_block(17,29,2,0);run_block(137,100,1,0);
  run_block(333,27,1,0);run_block(0,1,2,0);run_block(681,1,2,0);
  run_block(682,1,2,4);run_block(0,0,1,4);run_block(0,1025,1,4);
  backend_available=0;run_block(0,1,1,4);backend_available=1;
  inject_error=1;run_block(0,1,1,5);inject_error=0;run_block(17,29,2,0);
  $display("PASS: %0d exact FIR stereo/mono samples, history reset/retry, ring wrap, saturation, DDR latency/backpressure and errors",checks);$finish;
 end
 initial begin #30000000;$fatal(1,"export timeout");end
endmodule
