`timescale 1ns/1ps
// Exercise the registered request's ownership independently of UART speed.
module tb_static_sync_staging;
 reg clk=0,rst_n=0,cc_accept=0,uart_busy=1;
 reg [279:0] values=0;
 wire cc_req,done;wire [7:0] id;wire [6:0] val;
 always #10 clk=~clk;
 static_cc_sync #(.COUNT(40)) dut(.clk(clk),.rst_n(rst_n),.values(values),.cc_accept(cc_accept),.uart_busy(uart_busy),
  .cc_req(cc_req),.cc_param_id(id),.cc_val(val),.startup_sync_done(done));
 integer i,count=0,race_slot=12;reg [6:0] previous;
 task wait_request;integer n;begin
  n=0;while(!cc_req && n<100)begin @(negedge clk);n=n+1;end
  if(!cc_req)$fatal(1,"request missing");
 end endtask
 task accept_value(input integer expected_slot,input [6:0] expected_value);begin
  wait_request;
  if(dut.scan!==expected_slot[6:0] || val!==expected_value)
   $fatal(1,"staged mismatch slot=%0d expected=%0d val=%0d expected=%0d",dut.scan,expected_slot,val,expected_value);
  cc_accept=1;@(negedge clk);cc_accept=0;count=count+1;
  if(dut.sent[expected_slot]!==expected_value)$fatal(1,"accepted payload ownership lost");
 end endtask
 initial begin
  for(i=0;i<40;i=i+1)values[i*7+:7]=i+1;
  repeat(4)@(negedge clk);rst_n=1;
  wait_request;
  // The CURRENT startup slot changes repeatedly while its request is stalled.
  repeat(4)@(negedge clk);values[0+:7]=71;
  repeat(4)@(negedge clk);values[0+:7]=99;
  repeat(4)@(negedge clk);accept_value(0,99);
  for(i=1;i<40;i=i+1)begin
   wait_request;
   if(i==race_slot)begin
    // A bank write exactly at acceptance becomes visible after UART samples
    // the old payload. sent[] must record the transmitted value, not this edit.
    previous=val;cc_accept=1;
    @(posedge clk);values[race_slot*7+:7]<=7'd111;
    @(negedge clk);cc_accept=0;count=count+1;
    if(dut.sent[race_slot]!==previous)$fatal(1,"accept-edge edit falsely acknowledged");
   end else accept_value(i,i+1);
  end
  if(done)$fatal(1,"startup completed before UART drained");
  accept_value(race_slot,111);
  repeat(100)@(negedge clk);
  if(cc_req || count!=41 || dut.initial_pending!=0)$fatal(1,"stale replay/duplicate or lost startup value");
  uart_busy=0;repeat(100)@(negedge clk);
  if(!done)$fatal(1,"startup did not finish after drain");
  // Pending live edits survive reset only as the current authoritative bank.
  values[39*7+:7]=93;wait_request;accept_value(39,93);
  repeat(100)@(negedge clk);if(cc_req)$fatal(1,"unchanged live value replayed");
  $display("PASS: stalled CURRENT startup slot refreshes to99; acceptance-edge edit sends old then111 once, exact sent ownership, no stale replay, drain gating and live reconciliation");$finish;
 end
 initial begin #1000000;$fatal(1,"staging watchdog");end
endmodule
