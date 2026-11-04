`timescale 1ns/1ps
module tb_fx_renderer_pixels;
    reg clk=0,rst_n=0;
    reg [13:0] x=0,y=0;
    reg [132:0] values=0;
    reg [7:0] selected_id=0;
    reg [10:0] switches=0;
    wire hit_a,hit_b;
    wire [23:0] rgb_a,rgb_b;
    integer px,py,s,n,checks=0;
    reg compare=0;
    always #8 clk=~clk;
    fx_strip_renderer current(.selected_id(selected_id),.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.values(values),.switches(switches),.out_hit(hit_a),.out_rgb(rgb_a));
    fx_strip_renderer_reference reference(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),.values(values),.switches(switches),.out_hit(hit_b),.out_rgb(rgb_b));
    always @(negedge clk) if(compare) begin
        if(hit_a!==hit_b || (hit_a && rgb_a!==rgb_b))
            $fatal(1,"FX raster mismatch scenario=%d near %d,%d: %b/%h vs delayed %b/%h",s,x,y,hit_a,rgb_a,hit_b,rgb_b);
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
            for(py=368;py<=693;py=py+3) for(px=420;px<=780;px=px+3) begin
                @(negedge clk);x=px;y=py;
            end
            repeat(5) @(negedge clk);
        end
        compare=0;
        selected_id=8'h66;x=457;y=524;repeat(10)@(negedge clk);
        if(!hit_a || rgb_a!==24'hFFFFFF)$fatal(1,"Reverb focus has no visible white ring");
        selected_id=8'h60;repeat(10)@(negedge clk);
        if(rgb_a!==24'h9FE438)$fatal(1,"Old FX focus did not clear");
        x=461;y=416;repeat(10)@(negedge clk);
        if(!hit_a || rgb_a!==24'hFFFFFF)$fatal(1,"Delay focus has no visible white ring");
        $display("PASS: %0d exact FX output-pixel comparisons across four value/switch scenarios, plus visible Reverb/Delay focus transitions",checks);
        $finish;
    end
    initial begin #20000000;$fatal(1,"FX raster comparison timeout");end
endmodule
