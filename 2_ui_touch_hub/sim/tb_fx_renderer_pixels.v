`timescale 1ns/1ps
module tb_fx_renderer_pixels;
    reg clk=0,rst_n=0;
    reg [13:0] x=0,y=0;
    reg [132:0] values=0;
    reg [10:0] switches=0;
    wire hit_a,hit_b;
    wire [23:0] rgb_a,rgb_b;
    reg hit_b_delayed,hit_b_d0;
    reg [23:0] rgb_b_delayed,rgb_b_d0;
    integer px,py,s,n,checks=0;
    reg compare=0;
    always #8 clk=~clk;
    always @(posedge clk) begin hit_b_d0<=hit_b;rgb_b_d0<=rgb_b;hit_b_delayed<=hit_b_d0;rgb_b_delayed<=rgb_b_d0;end
    fx_strip_renderer current(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.values(values),.switches(switches),.out_hit(hit_a),.out_rgb(rgb_a));
    fx_strip_renderer_reference reference(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.values(values),.switches(switches),.out_hit(hit_b),.out_rgb(rgb_b));
    always @(negedge clk) if(compare) begin
        if(hit_a!==hit_b_delayed || (hit_a && rgb_a!==rgb_b_delayed))
            $fatal(1,"FX raster mismatch scenario=%d near %d,%d: %b/%h vs delayed %b/%h",s,x,y,hit_a,rgb_a,hit_b_delayed,rgb_b_delayed);
        checks=checks+1;
    end
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        for(s=0;s<4;s=s+1) begin
            compare=0;
            for(n=0;n<19;n=n+1) values[n*7+:7]=s==0 ? 0 : s==1 ? (7*n)%128 : s==2 ? 127 : 64;
            switches=s==0 ? 0 : s==1 ? 11'h7ff : s==2 ? 11'h555 : 11'b00001001111;
            repeat(20) @(negedge clk);
            compare=1;
            for(py=368;py<=693;py=py+1) for(px=420;px<=780;px=px+1) begin
                @(negedge clk);x=px;y=py;
            end
            repeat(5) @(negedge clk);
        end
        compare=0;
        $display("PASS: %0d exact FX output-pixel comparisons across four value/switch scenarios",checks);
        $finish;
    end
    initial begin #20000000;$fatal(1,"FX raster comparison timeout");end
endmodule
