`timescale 1ns/1ps
module tb_ribbon_calibrated;
reg clk=0,rst_n=0,valid=0; reg [2:0] channel=0; reg signed [23:0] sample=0;
wire ready,ev,on; wire [2:0] source; wire [14:0] pitch; wire [6:0] velocity;
integer i,j,errors=0; reg [14:0] last_pitch; reg seen;
ribbon_pitch_processor #(.CHANNEL_COUNT(4),.CALIBRATED_REVERSED(1)) dut(
.clk(clk),.rst_n(rst_n),.sample_valid(valid),.sample_channel(channel),.sample_data(sample),.sample_ready(ready),
.event_valid(ev),.event_ready(1'b1),.event_on(on),.event_source(source),.event_pitch_q8(pitch),.event_velocity(velocity));
always #10 clk=~clk;
always @(posedge clk) if(ev && on) begin last_pitch=pitch;seen=1;end
task send; input signed [23:0] x; begin while(!ready) @(negedge clk); @(negedge clk);sample=x;valid=1;@(negedge clk);valid=0;end endtask
function [23:0] left; input integer c; begin case(c) 0:left=3989622;1:left=3969489;2:left=3920835;default:left=3598713;endcase end endfunction
function [23:0] right; input integer c; begin case(c) 0:right=1568670;1:right=1538471;2:right=1444518;default:right=1353921;endcase end endfunction
initial begin
for(i=0;i<4;i=i+1) begin
rst_n=0;seen=0;repeat(4) @(negedge clk); rst_n=1;channel=i;
for(j=0;j<12;j=j+1) send(left(i));repeat(5) @(negedge clk);
if(!seen || last_pitch != ((24+12*i)*256)) begin $display("ERROR left ch%0d pitch%0d",i,last_pitch);errors=errors+1;end
for(j=0;j<80;j=j+1) send(right(i));repeat(5) @(negedge clk);
if(last_pitch < ((48+12*i)*256-8) || last_pitch > ((48+12*i)*256+8)) begin $display("ERROR right ch%0d pitch%0d",i,last_pitch);errors=errors+1;end
end
if(errors==0) $display("PASS: four reversed calibrated endpoints");else $display("FAIL: %0d",errors);
$finish;end
endmodule
