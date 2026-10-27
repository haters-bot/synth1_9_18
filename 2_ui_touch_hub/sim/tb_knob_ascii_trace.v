`timescale 1ns/1ps
module tb_knob_ascii_trace;
    reg clk=0,rst_n=0,kv=0,kcw=1,bv=0,lu=0,lchip=0,lup=0;
    reg [7:0] kid=0,bid=0;
    reg [1:0] ba=0;
    wire tx;
    integer bit_i,tx_falls=0; reg [7:0] rx;
    always #500 clk=~clk;
    knob_ascii_trace #(.CLK_FREQ(1000000),.BAUD(100000),.FIFO_BITS(3)) dut(
        .clk(clk),.rst_n(rst_n),.knob_valid(kv),.knob_id(kid),.knob_cw(kcw),
        .button_valid(bv),.button_id(bid),.button_action(ba),
        .link_valid(lu),.link_chip(lchip),.link_up(lup),.uart_tx(tx));
    always @(negedge tx) if(rst_n) begin
        tx_falls=tx_falls+1;
        #5000;
        for(bit_i=0;bit_i<8;bit_i=bit_i+1) begin #10000;rx[bit_i]=tx;end
        #10000;
        if(rx==10) $display(""); else $write("%c",rx);
    end
    initial begin
        #2000;rst_n=1;#2000;
        lu=1;lchip=0;lup=1;kv=1;kid=8'h17;kcw=1;bid=8'h17;bv=1;ba=1;
        @(posedge clk);#1;lu=0;kv=0;bv=0;
        #300000;kv=1;kid=8'h27;kcw=0;@(posedge clk);#1;kv=0;
        #300000;lu=1;lchip=1;lup=0;@(posedge clk);#1;lu=0;
        #20000000;
        $display("ASCII output started %0d UART bytes",tx_falls);
        if(tx_falls==0) $fatal(1,"UART emitted no start bits");
        if(dut.count!=0 || dut.msg_active) $fatal(1,"ASCII event queue did not drain");
        bit_i=tx_falls;#2000000;
        if(tx_falls!=bit_i) $fatal(1,"Idle SPI status produced periodic UART output");
        $display("PASS: ASCII knob/link event formatter, no periodic output");
        $finish;
    end
    initial begin #50000000;$fatal(1,"UART trace timeout");end
endmodule
