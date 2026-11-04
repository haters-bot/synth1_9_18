`timescale 1ns/1ps
module tb_modulation_overlay;
    reg clk=0,rst_n=0;
    reg [13:0] x=0,y=0;
    reg [105:0] sources=0;
    reg [423:0] depths=0;
    reg [370:0] preview=0;
    reg armed=0,dragging=0;
    reg [5:0] hover=63,selected=63;
    reg [1:0] tab=0;
    reg [13:0] tx=980,ty=485;
    wire hit;
    wire [23:0] rgb;
    integer i,j,src;
    reg [23:0] expected_color;
    `include "mod_targets.vh"
    always #8 clk=~clk;
    modulation_overlay dut(.clk(clk),.rst_n(rst_n),.in_x(x),.in_y(y),
        .sources(sources),.depths(depths),.preview_values(preview),.armed(armed),.dragging(dragging),
        .hover_target(hover),.selected_target(selected),.active_tab(tab),.touch_x(tx),.touch_y(ty),
        .curve_nodes({7{7'd64}}),.out_hit(hit),.out_rgb(rgb));
    task pixel;
        input integer px,py;input expected_hit;input [23:0] expected_rgb;
        begin
            @(negedge clk);x=px;y=py;
            repeat(6) @(negedge clk);
            if(hit!==expected_hit || (expected_hit && rgb!==expected_rgb))
                $fatal(1,"Overlay at %d,%d: hit=%b rgb=%h expected=%b/%h",px,py,hit,rgb,expected_hit,expected_rgb);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;repeat(300) @(negedge clk);
        // Parallel masked cells require geometrically disjoint boxes.
        for(i=0;i<53;i=i+1) for(j=i+1;j<53;j=j+1)
            if(mod_cx(i)-22<=mod_cx(j)+22 && mod_cx(j)-22<=mod_cx(i)+22 &&
               mod_cy(i)-22<=mod_cy(j)+22 && mod_cy(j)-22<=mod_cy(i)+22)
                $fatal(1,"Overlay cell overlap %d,%d",i,j);
        for(i=0;i<53;i=i+1) begin
            src=(i%3)+1;sources[i*2+:2]=src;
            expected_color=src==1 ? 24'h38E8FF : src==2 ? 24'hEEB34D : 24'hDD88FF;
            pixel(mod_cx(i)+22,mod_cy(i)+4,1,expected_color);
            // Full-coverage stroke at the left of the L source label.
            pixel(mod_cx(i)-8,mod_cy(i)-20,1,24'hFFFFFF);
        end
        // Marks persist with no interaction. CLEAR removes them immediately.
        for(i=0;i<53;i=i+1) begin
            sources[i*2+:2]=0;pixel(mod_cx(i)+22,mod_cy(i)+4,0,0);
            dragging=1;hover=i;pixel(mod_cx(i)+22,mod_cy(i)+7,1,24'hFFFFFF);
            dragging=0;hover=63;
        end
        tab=1;dragging=1;repeat(300) @(negedge clk);
        pixel(972,457,1,24'hEEB34D); // flat miniature follows the finger
        pixel(932,449,1,24'hFFFFFF); // miniature boundary
        pixel(975,445,1,24'h15283A); // interior away from the curve
        dragging=0;pixel(10,200,0,0);
        $display("PASS: all 53 persistent LFO mark colors/labels, clear, candidate highlights, disjoint cells and drag miniature");
        $finish;
    end
    initial begin #1000000;$fatal(1,"Overlay timeout");end
endmodule
