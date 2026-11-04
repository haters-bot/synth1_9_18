`timescale 1ns/1ps
module tb_phone_transport_50m;
 // Production integer dividers (5208 / 434 / 217 clocks per UART bit).
 tb_phone_transport #(.HZ(50000000)) regression();
endmodule
