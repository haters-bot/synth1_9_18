`timescale 1ns/1ps
module tb_curve_geometry;
    reg clk=0,rst_n=0;
    reg [6:0] value=0;
    reg [1:0] kind=0;
    integer n,k,prev_x,prev_a,prev_r,prev_y;
    always #8 clk=~clk;
    filter_panel_renderer flt(.clk(clk),.rst_n(rst_n),.in_x(14'd1000),.in_y(14'd150),
        .val_flt_power(1'b1),.val_flt_type(kind),.flt_cutoff(value),.flt_res(value));
    env_panel_renderer env(.clk(clk),.rst_n(rst_n),.in_x(14'd200),.in_y(14'd450),
        .val_env_tab(2'd0),.env_attack(value),.env_hold(value),.env_decay(value),
        .env_sustain(value),.env_release(value));
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        prev_x=0;prev_a=0;prev_r=0;prev_y=1000;
        for(n=0;n<128;n=n+1) begin
            @(negedge clk);value=n;
            repeat(4) @(negedge clk);
            // Integer references use full precision, independent of RTL widths.
            if(flt.calc_x_cut !== 898+n*280/128 || flt.calc_h_peak !== n*44/128)
                $fatal(1,"FILTER coordinate overflow at value %0d: x=%0d h=%0d",n,flt.calc_x_cut,flt.calc_h_peak);
            if(env.len_a !== 20+n*130/128 || env.len_h !== n*60/128 ||
               env.len_d !== 24+n*160/128 || env.len_r !== 24+n*160/128 ||
               env.calc_y_sus !== 568-n*144/128)
                $fatal(1,"ENV coordinate overflow at value %0d",n);
            if(flt.calc_x_cut<prev_x || env.len_a<prev_a || env.len_r<prev_r || env.calc_y_sus>prev_y)
                $fatal(1,"Non-monotonic curve at value %0d",n);
            if(env.s0_pt_r+36>780 || env.calc_y_sus<424 || env.calc_y_sus>568)
                $fatal(1,"Envelope escaped drawing window at value %0d",n);
            prev_x=flt.calc_x_cut;prev_a=env.len_a;prev_r=env.len_r;prev_y=env.calc_y_sus;
            for(k=0;k<4;k=k+1) begin
                kind=k;repeat(2) @(negedge clk);
                if(flt.node_y !== (k==3 ? 162+n*44/128 : 162-n*44/128))
                    $fatal(1,"FILTER node wrong vertical direction at value %0d mode %0d",n,k);
            end
        end
        $display("PASS: all 128 curve values monotonic/in bounds, full precision geometry and all four filter node modes");
        $finish;
    end
endmodule
