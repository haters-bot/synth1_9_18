`timescale 1ns/1ps
module tb_keyboard_midi_uart;
reg clk=0,rst_n=0,rx=1;
wire [7:0] data;wire valid,framing;
wire nv,on;wire [6:0] note,vel;integer count=0,j;
reg [14:0] expected[0:7];
always #10 clk=~clk;
performance_uart_rx #(.CLK_FREQ(50000000),.BAUD(31250)) uart(.clk(clk),.rst_n(rst_n),.uart_rx(rx),.byte_data(data),.byte_valid(valid),.framing_error(framing));
keyboard_midi_parser parser(.clk(clk),.rst_n(rst_n),.byte_data(data),.byte_valid(valid),.note_event_valid(nv),.note_event_on(on),.note_event_note(note),.note_event_velocity(vel));
always @(negedge clk)if(rst_n)begin
 if(framing)$fatal(1,"MIDI UART framing");
 if(nv)begin
  if(count>=8 || {on,note,vel}!==expected[count])$fatal(1,"event %0d got %b/%d/%d",count,on,note,vel);
  count=count+1;
 end
end
task byte_send(input [7:0] b);integer i;begin
 @(negedge clk);rx=0;#32000;
 for(i=0;i<8;i=i+1)begin rx=b[i];#32000;end
 rx=1;#32000;
end endtask
initial begin
 expected[0]={1'b1,7'd29,7'd100};expected[1]={1'b1,7'd30,7'd110};
 expected[2]={1'b0,7'd29,7'd0};expected[3]={1'b0,7'd30,7'd32};
 expected[4]={1'b1,7'd60,7'd127};expected[5]={1'b0,7'd60,7'd0};
 expected[6]={1'b1,7'd100,7'd50};expected[7]={1'b0,7'd100,7'd0};
 repeat(5)@(negedge clk);rst_n=1;#1000;
 byte_send(8'h90);byte_send(29);byte_send(100);
 byte_send(30);byte_send(8'hF8);byte_send(110); // Running Status + realtime.
 byte_send(29);byte_send(0);
 byte_send(8'h80);byte_send(30);byte_send(32);
 byte_send(8'h9F);byte_send(60);byte_send(127);byte_send(60);byte_send(0);
 byte_send(8'hF0);byte_send(60);byte_send(127);byte_send(8'hF7); // SysEx cancels status.
 byte_send(8'hB0);byte_send(24);byte_send(100); // Non-note CC ignored.
 byte_send(8'h91);byte_send(100);byte_send(50);byte_send(100);byte_send(0);
 #1000;if(count!=8)$fatal(1,"missing events %0d",count);
 $display("PASS: physical MIDI 31250 baud 8N1, Running Status/realtime, all channels, Note Off/zero velocity, SysEx/CC isolation");$finish;
end
initial begin #15000000;$fatal(1,"timeout");end
endmodule
