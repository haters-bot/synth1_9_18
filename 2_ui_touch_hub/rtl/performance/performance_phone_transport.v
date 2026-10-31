// The module UART may be 9600, 115200, 230400 or 1000000. A CRC-valid
// HELLO selects one receiver; never try to reprogram an unidentified module.
module performance_phone_transport #(parameter CLK_HZ=50000000)(
 input wire clk,rst_n,tick_1ms,uart_rx,hold_lock,
 output wire packet_valid,output wire [7:0] packet_type,packet_sequence,
 output wire [6:0] packet_length,output wire [511:0] packet_payload,
 output wire [15:0] packet_signature,
 output reg fast_baud,output reg turbo_baud,output reg ultra_baud,output reg locked,
 input wire reply_valid,output wire reply_ready,
 input wire [7:0] reply_type,reply_sequence,
 input wire [6:0] reply_length,input wire [511:0] reply_payload,
 output wire uart_tx,output wire tx_busy
);
 wire [3:0] bv,pv;wire [7:0] bd[0:3],pt[0:3],ps[0:3];
 wire [6:0] pl[0:3];wire [511:0] pp[0:3];wire [15:0] pc[0:3];
 wire slow_hello=pv[0] && pt[0]==1,fast_hello=pv[1] && pt[1]==1;
 wire turbo_hello=pv[2] && pt[2]==1,ultra_hello=pv[3] && pt[3]==1;
 wire [1:0] choice=locked ? (ultra_baud ? 3 : turbo_baud ? 2 : fast_baud ? 1 : 0) :
                           slow_hello ? 0 : fast_hello ? 1 : turbo_hello ? 2 : 3;
 assign packet_valid=locked ? (ultra_baud ? pv[3] : turbo_baud ? pv[2] : fast_baud ? pv[1] : pv[0]) : slow_hello || fast_hello || turbo_hello || ultra_hello;
 assign packet_type=choice==3 ? pt[3] : choice==2 ? pt[2] : choice==1 ? pt[1] : pt[0];
 assign packet_sequence=choice==3 ? ps[3] : choice==2 ? ps[2] : choice==1 ? ps[1] : ps[0];
 assign packet_length=choice==3 ? pl[3] : choice==2 ? pl[2] : choice==1 ? pl[1] : pl[0];
 assign packet_payload=choice==3 ? pp[3] : choice==2 ? pp[2] : choice==1 ? pp[1] : pp[0];
 assign packet_signature=choice==3 ? pc[3] : choice==2 ? pc[2] : choice==1 ? pc[1] : pc[0];
 reg [13:0] idle_ms;
 genvar n;
 generate for(n=0;n<4;n=n+1)begin: receivers
  performance_uart_rx #(.CLK_FREQ(CLK_HZ),.BAUD(n==0 ? 9600 : n==1 ? 115200 : n==2 ? 230400 : 1000000)) rx(
   .clk(clk),.rst_n(rst_n),.uart_rx(uart_rx),.byte_valid(bv[n]),.byte_data(bd[n]),.framing_error());
  performance_packet_parser #(.TIMEOUT_CYCLES(CLK_HZ/2)) parser(.clk(clk),.rst_n(rst_n),.byte_valid(bv[n]),.byte_data(bd[n]),
   .packet_valid(pv[n]),.packet_type(pt[n]),.packet_sequence(ps[n]),.packet_length(pl[n]),
   .packet_payload(pp[n]),.packet_crc(pc[n]),.crc_error());
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin locked<=0;fast_baud<=0;turbo_baud<=0;ultra_baud<=0;idle_ms<=0;end
  else if(packet_valid)begin locked<=1;fast_baud<=choice!=0;turbo_baud<=choice==2;ultra_baud<=choice==3;idle_ms<=0;end
  else if(tick_1ms)begin
   if(hold_lock || tx_busy)idle_ms<=0;
   else if(idle_ms<10000)idle_ms<=idle_ms+1'b1;
   else locked<=0;
  end
 end
 performance_packet_tx #(.CLK_HZ(CLK_HZ),.ENABLE_230400(1),.ENABLE_1M(1)) tx(.clk(clk),.rst_n(rst_n),.fast_baud(fast_baud),.turbo_baud(turbo_baud),.ultra_baud(ultra_baud),
  .packet_valid(reply_valid),.packet_ready(reply_ready),.packet_type(reply_type),.packet_sequence(reply_sequence),
  .packet_length(reply_length),.packet_payload(reply_payload),.uart_tx(uart_tx),.busy(tx_busy));
endmodule
