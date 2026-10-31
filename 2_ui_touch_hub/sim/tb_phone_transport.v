`timescale 1ns/1ps
module tb_phone_transport #(parameter HZ=1843200);
 localparam RATE_COUNT=HZ>=10000000?4:3;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,tick_1ms=0,uart_rx=1,hold_lock=0;
 wire packet_valid;wire [7:0] packet_type,packet_sequence;
 wire [6:0] packet_length;wire [511:0] packet_payload;wire [15:0] packet_signature;
 wire fast_baud,turbo_baud,ultra_baud,locked;
 reg reply_valid=0;wire reply_ready;
 reg [7:0] reply_type=8'h70,reply_sequence=0;
 reg [6:0] reply_length=0;reg [511:0] reply_payload=0;
 wire uart_tx,tx_busy;
 performance_phone_transport #(.CLK_HZ(HZ)) dut(.*);
 wire [3:0] rv,rp;wire [7:0] rb[0:3],rt[0:3],rs[0:3];
 wire [6:0] rl[0:3];wire [511:0] rd[0:3];
 genvar n;
 generate for(n=0;n<4;n=n+1)begin: monitor
  performance_uart_rx #(.CLK_FREQ(HZ),.BAUD(n==0?9600:n==1?115200:n==2?230400:1000000)) rx(.clk(clk),.rst_n(rst_n),.uart_rx(uart_tx),.byte_valid(rv[n]),.byte_data(rb[n]),.framing_error());
  performance_packet_parser parser(.clk(clk),.rst_n(rst_n),.byte_valid(rv[n]),.byte_data(rb[n]),
   .packet_valid(rp[n]),.packet_type(rt[n]),.packet_sequence(rs[n]),.packet_length(rl[n]),.packet_payload(rd[n]),.packet_crc(),.crc_error());
 end endgenerate
 integer packets=0,replies=0,which=0,checks=0,k,j;
 always @(posedge clk)begin
  if(packet_valid)packets=packets+1;
  if(rp[which])begin
   if(rt[which]!=reply_type || rs[which]!=reply_sequence || rl[which]!=reply_length)$fatal(1,"reply header");
   for(j=0;j<reply_length;j=j+1)if(rd[which][j*8+:8]!==reply_payload[j*8+:8])$fatal(1,"reply payload");
   replies=replies+1;
  end
 end
 function [15:0] crc_next(input [15:0] crc,input [7:0] value);
  integer bitn;reg [15:0] c;
  begin c=crc^{value,8'd0};for(bitn=0;bitn<8;bitn=bitn+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_next=c;end
 endfunction
 task byte_send(input [7:0] value);
  integer b,clocks;
  begin clocks=HZ/(which==0?9600:which==1?115200:which==2?230400:1000000);uart_rx=0;repeat(clocks)@(negedge clk);
   for(b=0;b<8;b=b+1)begin uart_rx=value[b];repeat(clocks)@(negedge clk);end
   uart_rx=1;repeat(clocks)@(negedge clk);
  end
 endtask
 task frame_send(input [7:0] kind,seq,input integer len,bad);
  reg [15:0] crc;reg [7:0] value;integer at;
  begin
   crc=16'hffff;byte_send(8'ha5);
   for(at=0;at<5+len;at=at+1)begin
    case(at)0:value=1;1:value=kind;2:value=seq;3:value=len;4:value=0;default:value=(at-5)^8'ha5;endcase
    byte_send(value);crc=crc_next(crc,value);
   end
   byte_send(crc[7:0]^(bad?8'h80:0));byte_send(crc[15:8]);repeat(12)@(negedge clk);
  end
 endtask
 task reply_send(input integer len);
  integer target;
  begin
   wait(reply_ready);@(negedge clk);reply_length=len;reply_sequence=reply_sequence+1;
   for(k=0;k<64;k=k+1)reply_payload[k*8+:8]=k^8'ha5;
   target=replies+1;reply_valid=1;@(negedge clk);reply_valid=0;
   wait(replies==target);wait(!tx_busy);repeat(16)@(negedge clk);checks=checks+1;
  end
 endtask
 initial begin
  for(which=0;which<RATE_COUNT;which=which+1)begin
   rst_n=0;repeat(5)@(negedge clk);rst_n=1;packets=0;
   frame_send(8'h20,1,0,0);if(locked || packets!=0)$fatal(1,"non HELLO locked");
   frame_send(1,2,0,1);if(locked || packets!=0)$fatal(1,"bad CRC locked");
   frame_send(1,3,0,0);if(!locked || fast_baud!=(which!=0) || turbo_baud!=(which==2) || ultra_baud!=(which==3) || packets!=1)$fatal(1,"HELLO selection");
   frame_send(8'h12,4,64,0);
   if(packets!=2 || packet_type!=8'h12 || packet_length!=64 || packet_payload[511:504]!=(63^8'ha5))$fatal(1,"64byte receive");
   reply_send(0);reply_send(1);reply_send(64);reply_send(22);
   hold_lock=1;tick_1ms=1;repeat(10010)@(negedge clk);if(!locked)$fatal(1,"lock lost while busy");
   hold_lock=0;repeat(10010)@(negedge clk);if(locked)$fatal(1,"idle did not unlock");tick_1ms=0;
  end
  $display("PASS: %0d UART rates (9600/115200/230400/1000000 when clock permits), HELLO/CRC lock, 64byte bidirectional data, zero/one/64/22byte TX and idle recovery (%0d replies)",RATE_COUNT,checks);$finish;
 end
 initial begin #300000000;$fatal(1,"transport timeout baud=%0d packets=%0d replies=%0d",which,packets,replies);end
endmodule
