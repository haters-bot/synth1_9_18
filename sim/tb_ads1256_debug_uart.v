`timescale 1ns/1ps
module tb_ads1256_debug_uart;
reg clk=0, rst_n=0, initialized=1, drdy=1, sample_valid=0;
reg [5:0] scanner_state=6'h12; reg [2:0] channel=0; reg [23:0] data=24'h123abc;
wire tx; integer i,j,errors=0; reg [7:0] byte_value;
reg [455:0] expected = {"ADC I1 D1 S12 M0 V1 0:123ABC 1:000000 2:000000 3:000000", 8'h0d, 8'h0a};
ads1256_debug_uart #(.CLK_HZ(1000),.BAUD_RATE(100),.PERIOD_CYCLES(100)) dut (
.clk(clk),.rst_n(rst_n),.initialized(initialized),.drdy(drdy),.scanner_state(scanner_state),
.sample_valid(sample_valid),.sample_channel(channel),.sample_data(data),.midi_overflow(1'b0),.uart_tx(tx));
always #5 clk=~clk;
initial begin
repeat(4) @(negedge clk); rst_n=1; sample_valid=1; @(negedge clk); sample_valid=0;
for(i=0;i<57;i=i+1) begin
 @(negedge tx); #150;
 for(j=0;j<8;j=j+1) begin byte_value[j]=tx; #100; end
 if(byte_value !== expected[455-i*8 -: 8]) begin
 $display("ERROR byte %0d got %h expected %h",i,byte_value,expected[455-i*8 -: 8]); errors=errors+1; end
end
if(errors==0) $display("PASS: complete ADC UART heartbeat and sample data"); else $display("FAIL: %0d",errors);
$finish;end
initial begin #1000000; $display("ERROR timeout"); $finish; end
endmodule
