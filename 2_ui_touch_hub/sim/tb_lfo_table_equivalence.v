`timescale 1ns/1ps
module tb_lfo_table_equivalence;
    reg clk=0,rst_n=0,step_mode=0;
    reg [48:0] nodes=0;
    reg [8:0] index=0;
    wire [12:0] actual,reference;
    wire [6:0] actual_sample,reference_sample;
    integer s,i,n,a,b,previous,checks=0;
    reg [31:0] random_state=32'h158f713b;
    always #8 clk=~clk;
    lfo_smooth_table dut(.clk(clk),.rst_n(rst_n),.nodes(nodes),.stepped(step_mode),
        .raster_index(index),.preview_index(index),.raster_q6(actual),.preview_value(actual_sample));
    lfo_smooth_table_reference gold(.clk(clk),.rst_n(rst_n),.nodes(nodes),.stepped(step_mode),
        .raster_index(index),.preview_index(index),.raster_q6(reference),.preview_value(reference_sample));
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        for(s=0;s<40;s=s+1) begin
            @(negedge clk);
            for(n=0;n<7;n=n+1) begin
                random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                nodes[n*7+:7]=s==0 ? 0 : s==1 ? 127 : s==2 ? (n%2 ? 127 : 0) : random_state[6:0];
            end
            step_mode=s>=32;
            repeat(500) @(negedge clk);
            previous=0;
            for(i=0;i<=384;i=i+1) begin
                @(negedge clk);index=i;#1;
                if(actual!==reference || actual_sample!==reference_sample)
                    $fatal(1,"Curve pipeline changed Q7.6 output: scenario %d index %d actual %d ref %d",s,i,actual,reference);
                if(!step_mode) begin
                    n=i==384 ? 5 : i/64;
                    a=nodes[n*7+:7];b=nodes[(n+1)*7+:7];
                    if(actual<(a<b ? a : b)*64 || actual>(a>b ? a : b)*64)
                        $fatal(1,"Curve overshoot %d/%d",s,i);
                    if(i%64!=0 && ((b>=a && actual<previous) || (b<=a && actual>previous)))
                        $fatal(1,"Curve nonmonotonic %d/%d",s,i);
                end
                previous=actual;checks=checks+1;
            end
        end
        $display("PASS: %0d bit-exact smooth/stepped curve comparisons, random shapes, extremes and bounded monotonic segments",checks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"Curve equivalence timeout");end
endmodule
