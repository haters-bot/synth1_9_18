// Full-duplex response path. Baud is latched per byte and changes only between
// sessions; no AT traffic or debug text is ever mixed into this UART.
module performance_uart_tx #(parameter CLK_HZ=50000000,ENABLE_230400=0,ENABLE_1M=0)(
 input wire clk,rst_n,fast_baud,turbo_baud,ultra_baud,valid,input wire [7:0] data,
 output wire ready,output reg tx
);
 reg [9:0] shift;
 reg [3:0] bit_index;
 reg [15:0] timer,divider;
 reg busy;
 assign ready=!busy;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin tx<=1;busy<=0;timer<=0;divider<=0;shift<=10'h3ff;bit_index<=0;end
  else if(!busy)begin
   tx<=1;
   if(valid)begin
    divider<=ENABLE_1M && ultra_baud ? CLK_HZ/1000000-1 : ENABLE_230400 && turbo_baud ? CLK_HZ/230400-1 : fast_baud ? CLK_HZ/115200-1 : CLK_HZ/9600-1;
    timer<=ENABLE_1M && ultra_baud ? CLK_HZ/1000000-1 : ENABLE_230400 && turbo_baud ? CLK_HZ/230400-1 : fast_baud ? CLK_HZ/115200-1 : CLK_HZ/9600-1;
    shift<={1'b1,data,1'b0};tx<=0;bit_index<=0;busy<=1;
   end
  end else if(timer!=0)timer<=timer-1'b1;
  else if(bit_index==9)begin busy<=0;tx<=1;end
  else begin
   shift<={1'b1,shift[9:1]};tx<=shift[1];bit_index<=bit_index+1'b1;timer<=divider;
  end
 end
endmodule

module performance_packet_tx #(parameter CLK_HZ=50000000,ENABLE_230400=0,ENABLE_1M=0)(
 input wire clk,rst_n,fast_baud,turbo_baud,ultra_baud,packet_valid,
 output wire packet_ready,
 input wire [7:0] packet_type,packet_sequence,
 input wire [6:0] packet_length,input wire [511:0] packet_payload,
 output wire uart_tx,output wire busy
);
 reg active;
 reg [7:0] kind,sequence_id;
 reg [6:0] length,index;
 reg [511:0] payload;
 reg [15:0] crc;
 wire byte_ready;
 reg [7:0] byte_data;
 assign packet_ready=!active && byte_ready;
 assign busy=active || !byte_ready;
 function [15:0] crc_next;
  input [15:0] c;input [7:0] d;integer n;reg [15:0] v;
  begin v=c^{d,8'd0};for(n=0;n<8;n=n+1)v=v[15] ? (v<<1)^16'h1021 : v<<1;crc_next=v;end
 endfunction
 always @*begin
  case(index)
   0:byte_data=8'ha5;1:byte_data=1;2:byte_data=kind;3:byte_data=sequence_id;
   4:byte_data={1'b0,length};5:byte_data=0;
   default:byte_data=index==length+6 ? crc[7:0] : index==length+7 ? crc[15:8] : payload[(index-6)*8+:8];
  endcase
 end
 performance_uart_tx #(.CLK_HZ(CLK_HZ),.ENABLE_230400(ENABLE_230400),.ENABLE_1M(ENABLE_1M)) bytes(.clk(clk),.rst_n(rst_n),.fast_baud(fast_baud),.turbo_baud(turbo_baud),.ultra_baud(ultra_baud),
  .valid(active),.data(byte_data),.ready(byte_ready),.tx(uart_tx));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;kind<=0;sequence_id<=0;length<=0;index<=0;crc<=16'hffff;end
  else if(packet_valid && packet_ready)begin
   active<=1;kind<=packet_type;sequence_id<=packet_sequence;length<=packet_length;
   payload<=packet_payload;index<=0;crc<=16'hffff;
  end else if(active && byte_ready)begin
   if(index!=0 && index<length+6)crc<=crc_next(crc,byte_data);
   if(index==length+7)active<=0;else index<=index+1'b1;
  end
 end
endmodule
