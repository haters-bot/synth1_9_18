// Exercise the real host packet buffer before usb_touch_intake's decoder.
// Only the physical USB engine's byte interface is driven by this test.
`timescale 1ns/1ps
module tb_usb_host_report_path;
    reg clk_usb=0, clk_pixel=0, rst_n=0;
    always #8.333 clk_usb=~clk_usb;
    always #8 clk_pixel=~clk_pixel;
    wire dp,dm,valid,down;
    wire [15:0] x,y;
    wire [63:0] report_data;
    usb_touch_intake dut(
        .clk_usb(clk_usb),.rst_usb_n(rst_n),.usb_dp(dp),.usb_dm(dm),
        .clk_pixel(clk_pixel),.pixel_rst_n(rst_n),
        .touch_valid(valid),.touch_x(x),.touch_y(y),.touch_state(down),
        .dbg_report(report_data),.usb_connected(),.usb_dev_type(),
        .usb_conn_err(),.touch_activity(),.dbg_regs(),.dbg_pkt_cnt()
    );
    reg rx_ready=0,rx_start=0,rx_strobe=0;
    reg [7:0] rx_byte=0;
    reg connected=0;
    integer i;
    integer count=0;
    always @(posedge clk_pixel) if(valid)count=count+1;

    task packet;
        input integer size;
        input [63:0] first_contact;
        begin
            @(negedge clk_usb);rx_start=1;
            @(negedge clk_usb);rx_start=0;rx_ready=1;
            for(i=0;i<size+2;i=i+1)begin
                @(negedge clk_usb);rx_strobe=1;
                if(i<8)rx_byte=first_contact>>(8*i);
                else if(i<size)rx_byte=0;
                else rx_byte=8'hA5; // CRC tail must never replace payload
                @(negedge clk_usb);rx_strobe=0;
            end
            @(negedge clk_usb);rx_ready=0;
            repeat(12)@(negedge clk_pixel);
        end
    endtask
    initial begin
        force dut.u_usb_hid_host.ukprdy=rx_ready;
        force dut.u_usb_hid_host.ukpstart=rx_start;
        force dut.u_usb_hid_host.ukpstb=rx_strobe;
        force dut.u_usb_hid_host.ukpdat=rx_byte;
        force dut.u_usb_hid_host.connected=connected;
        force dut.u_usb_hid_host.hid_device=1'b1;
        force dut.u_usb_hid_host.typ_next=2'd3;
        force dut.u_usb_hid_host.connerr=1'b0;
        repeat(5)@(negedge clk_usb);rst_n=1;
        connected=1;
        repeat(8)@(negedge clk_usb);
        packet(8,64'h0000_1400_0800_4B00);
        if(!down||x!=16'h0800||y!=16'h1400)begin
            $display("[FAIL] 8-byte host path: down=%b x=%h y=%h report=%h",down,x,y,report_data);$fatal(1);
        end
        $display("[PASS] 8-byte host packet reaches decoder");
        packet(16,64'h0000_1600_0A00_4B00);
        if(!down||x!=16'h0A00||y!=16'h1600)begin
            $display("[FAIL] 16-byte packet damaged first contact");$fatal(1);
        end
        $display("[PASS] 16-byte packet ignores CRC beyond capture window");
        packet(32,64'h0000_1700_0B00_4B00);
        if(!down||x!=16'h0B00||y!=16'h1700)begin
            $display("[FAIL] 32-byte packet damaged first contact");$fatal(1);
        end
        $display("[PASS] 32-byte packet preserves its first contact");
        packet(64,64'h0000_1800_0C00_4B00);
        if(!down||x!=16'h0C00||y!=16'h1800)begin
            $display("[FAIL] 64-byte host path: down=%b x=%h y=%h report=%h",down,x,y,report_data);$fatal(1);
        end
        $display("[PASS] 64-byte host packet preserves its first contact");
        packet(64,64'h0000_1800_0C00_0000);
        if(down||x!=16'h0C00||y!=16'h1800)begin
            $display("[FAIL] Long release packet: down=%b x=%h y=%h",down,x,y);$fatal(1);
        end
        $display("[PASS] Release reaches decoder with retained coordinates");
        $display("ALL USB HOST REPORT PATH TESTS PASSED");$finish;
    end
    initial begin #100000;$fatal(1,"Timeout");end
endmodule
