// The module's factory UART may be 9600 or configured to 115200. A CRC-valid
// HELLO selects one receiver; never try to reprogram an unidentified module.
module performance_phone_transport #(parameter CLK_HZ=50000000)(
 input wire clk,rst_n,tick_1ms,uart_rx,hold_lock,
 output wire packet_valid,output wire [7:0] packet_type,packet_sequence,
 output wire [6:0] packet_length,output wire [511:0] packet_payload,
 output wire [15:0] packet_signature,
 output reg fast_baud,output reg locked,
 input wire reply_valid,output wire reply_ready,
 input wire [7:0] reply_type,reply_sequence,
 input wire [6:0] reply_length,input wire [511:0] reply_payload,
 output wire uart_tx,output wire tx_busy
);
 wire [1:0] bv,pv;wire [7:0] bd[0:1],pt[0:1],ps[0:1];
 wire [6:0] pl[0:1];wire [511:0] pp[0:1];wire [15:0] pc[0:1];
 wire slow_hello=pv[0] && pt[0]==1,fast_hello=pv[1] && pt[1]==1;
 wire choose_fast=locked ? fast_baud : (!slow_hello && fast_hello);
 assign packet_valid=locked ? pv[fast_baud] : slow_hello || fast_hello;
 assign packet_type=pt[choose_fast];assign packet_sequence=ps[choose_fast];
 assign packet_length=pl[choose_fast];assign packet_payload=pp[choose_fast];
 assign packet_signature=pc[choose_fast];
 reg [13:0] idle_ms;
 genvar n;
 generate for(n=0;n<2;n=n+1)begin: receivers
  performance_uart_rx #(.CLK_FREQ(CLK_HZ),.BAUD(n==0 ? 9600 : 115200)) rx(
   .clk(clk),.rst_n(rst_n),.uart_rx(uart_rx),.byte_valid(bv[n]),.byte_data(bd[n]),.framing_error());
  performance_packet_parser #(.TIMEOUT_CYCLES(CLK_HZ/2)) parser(.clk(clk),.rst_n(rst_n),.byte_valid(bv[n]),.byte_data(bd[n]),
   .packet_valid(pv[n]),.packet_type(pt[n]),.packet_sequence(ps[n]),.packet_length(pl[n]),
   .packet_payload(pp[n]),.packet_crc(pc[n]),.crc_error());
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin locked<=0;fast_baud<=0;idle_ms<=0;end
  else if(packet_valid)begin locked<=1;fast_baud<=choose_fast;idle_ms<=0;end
  else if(tick_1ms)begin
   if(hold_lock || tx_busy)idle_ms<=0;
   else if(idle_ms<10000)idle_ms<=idle_ms+1'b1;
   else locked<=0;
  end
 end
 performance_packet_tx #(.CLK_HZ(CLK_HZ)) tx(.clk(clk),.rst_n(rst_n),.fast_baud(fast_baud),
  .packet_valid(reply_valid),.packet_ready(reply_ready),.packet_type(reply_type),.packet_sequence(reply_sequence),
  .packet_length(reply_length),.packet_payload(reply_payload),.uart_tx(uart_tx),.busy(tx_busy));
endmodule
