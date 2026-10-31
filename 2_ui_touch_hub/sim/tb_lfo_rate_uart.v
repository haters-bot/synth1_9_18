`timescale 1ns/1ps
// Named to use the isolated RTL/.vo runner. All edits are real touch packets.
module tb_lfo_route_probe;
 reg clk=0,rst_n=0,touch_valid=0,touch_down=0;
 reg [15:0] raw_x=0,raw_y=0;
 wire uart_tx,sysex_req,config_busy,uart_busy;wire [47:0] sysex_msgs;
 wire [1:0] active_tab;wire [2:0] rate_index,all_steps,all_once;wire [8:0] all_rates;
 lfo_route_probe dut(.*);
 always #10 clk=~clk;
 reg [7:0] sb;reg [47:0] frame=0;
 reg [47:0] last_mode[0:2],last_sync=0;
 integer i,bytes=0,commits=0,frames=0,b,c,k,target,before_commit,z,checks=0;
 reg [7:0] expected_value;reg [47:0] expected_frame;
 reg [47:0] previous_frame=0,previous_previous_frame=0;
 reg [47:0] committed_mode=0,committed_sync=0;
 integer byte_log;
 initial byte_log=$fopen("lfo_uart_frames.hex","w");
 function [63:0] hz(input integer index);
  case(index)
   0:hz="0.25";1:hz="0.5";2:hz="1";3:hz="2";
   4:hz="4";5:hz="8";6:hz="16";7:hz="32";
  endcase
 endfunction
 initial forever begin
  @(negedge uart_tx);#100;
  for(i=0;i<8;i=i+1)begin #200;sb[i]=uart_tx;end
  #200;if(uart_tx!==1)$fatal(1,"UART stop");
  frame={frame[39:0],sb};bytes=bytes+1;
  if(bytes==6)begin
   bytes=0;frames=frames+1;
   $fdisplay(byte_log,"%012h",frame);
   if(frame[47:32]!==16'hF07D || frame[7:0]!==8'hF7)$fatal(1,"frame %h",frame);
   if(frame[31:24]>=69 && frame[31:24]<=71)begin
    last_mode[frame[31:24]-69]=frame;
    $display("UART: mode bytes=%h live_rates=%h",frame,all_rates);
`ifdef GATE_PROBE
    $display("CHECK: q_rates=%h sh_rates=%h",dut.\sx/q_rates ,dut.\sx/sh_rates );
`endif
   end
   if(frame[31:24]==72)last_sync=frame;
   if(frame==48'hF07D7E0000F7)begin
    commits=commits+1;committed_mode=previous_previous_frame;committed_sync=previous_frame;
   end
   previous_previous_frame=previous_frame;previous_frame=frame;
  end
 end
 task packet(input integer px,py,input bit down);
  begin
   @(negedge clk);raw_x=(px*65536+5119)/5120;raw_y=(py*65536+4914)/4915;
   touch_down=down;touch_valid=1;
   @(negedge clk);touch_valid=0;repeat(10)@(negedge clk);
  end
 endtask
 task click(input integer px,py);begin packet(px,py,1);packet(0,0,0);end endtask
 task drain;
  integer wait_cycles;
  begin
   repeat(200)@(negedge clk);wait_cycles=0;
   while((config_busy || uart_busy || sysex_req) && wait_cycles<60000)begin
    @(negedge clk);wait_cycles=wait_cycles+1;
   end
   if(config_busy || uart_busy || sysex_req)$fatal(1,"transport did not drain");
   repeat(20)@(negedge clk);
  end
 endtask
 initial begin
  #1000;repeat(8)@(negedge clk);rst_n=1;
  wait(commits==1);drain;
  if(all_rates!==9'b010010010)$fatal(1,"boot editor rates");
  if(last_mode[0]!==48'hF07D450002F7)$fatal(1,"boot mode: live index2 sent %h",last_mode[0]);
  for(b=0;b<3;b=b+1)begin
   click(b==0 ? 850 : b==1 ? 930 : 1015,385);drain;
   // Four Stepped/Once combinations, each with a complete 8-step UI cycle.
   for(c=0;c<4;c=c+1)begin
    if(all_steps[b]!==c[0])begin click(c[0]?1140:860,575);drain;end
    if(all_once[b]!==c[1])begin click(1000,620);drain;end
    for(k=0;k<8;k=k+1)begin
     target=(k+3)%8; // First check is exactly the user's 2-Hz case.
     z=0;
     while(rate_index!=target && z<8)begin click(860,620);drain;z=z+1;end
     if(rate_index!==target[2:0])$fatal(1,"UI cannot reach bank%0d rate_index%0d",b,target);
     // Unchanged state still must match its last committed frame.
     expected_value=target | (c[0]?8:0) | (c[1]?16:0);
     expected_frame={16'hF07D,8'h45+b[7:0],8'h00,expected_value,8'hF7};
     $display("CHECK: LFO%0d UI=%0sHz rate_index=%0d stepped=%0d once=%0d mode_value=%0d bytes=%h",b+1,hz(target),rate_index,c[0],c[1],expected_value,last_mode[b]);
     if(all_rates[b*3+:3]!==target[2:0] || last_mode[b]!==expected_frame)
      $fatal(1,"mode encoding mismatch expected %h",expected_frame);
     if(last_sync!=={24'hF07D48,8'h00,8'd4+b[7:0],8'hF7})$fatal(1,"restart bank mismatch %h",last_sync);
     if(committed_mode!==expected_frame || committed_sync!==last_sync)
      $fatal(1,"batch must end with mode -> correct restart -> Commit");
     checks=checks+1;
    end
   end
  end
  if(checks!=96)$fatal(1,"incomplete mode coverage");
  $display("PASS: 96 real-touch rate/mode combinations, three banks, restart and Commit; frames=%0d",frames);$finish;
 end
 initial begin #30000000;$fatal(1,"rate test timeout");end
endmodule
