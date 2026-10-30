`timescale 1ns/1ps

module tb_stereo_pan_path;

    reg clk;
    reg rst_n;
    reg pan_in_valid;
    reg signed [15:0] sample_a;
    reg signed [15:0] sample_b;
    reg [6:0] pan_a;
    reg [6:0] pan_b;
    wire pan_in_ready;
    wire pan_out_valid;
    wire signed [15:0] mid_sample;
    wire signed [15:0] side_sample;
    wire pan_overrun;

    reg output_in_valid;
    reg signed [15:0] output_mid;
    reg signed [15:0] output_side;
    reg [8:0] master_gain;
    reg [6:0] global_pan;
    wire output_in_ready;
    wire output_valid;
    wire signed [15:0] left_sample;
    wire signed [15:0] right_sample;
    wire output_clip;
    wire output_overrun;

    integer errors;

    stereo_pan_mixer u_pan (
        .clk(clk), .rst_n(rst_n),
        .in_valid(pan_in_valid), .sample_a(sample_a), .sample_b(sample_b),
        .pan_a(pan_a), .pan_b(pan_b), .in_ready(pan_in_ready),
        .out_valid(pan_out_valid), .mid_sample(mid_sample),
        .side_sample(side_sample), .out_ready(1'b1),
        .input_overrun(pan_overrun)
    );

    stereo_output_stage u_output (
        .clk(clk), .rst_n(rst_n),
        .in_valid(output_in_valid), .processed_mid(output_mid),
        .side_sample(output_side), .master_gain_q8(master_gain),
        .global_pan(global_pan), .in_ready(output_in_ready),
        .out_valid(output_valid), .left_sample(left_sample),
        .right_sample(right_sample), .clip_pulse(output_clip),
        .input_overrun(output_overrun)
    );

    always #10 clk = ~clk;

    task check_pan;
        input signed [15:0] value_a;
        input signed [15:0] value_b;
        input [6:0] value_pan_a;
        input [6:0] value_pan_b;
        input signed [15:0] expected_mid;
        input signed [15:0] expected_side;
        begin
            while (!pan_in_ready) @(posedge clk);
            sample_a = value_a;
            sample_b = value_b;
            pan_a = value_pan_a;
            pan_b = value_pan_b;
            pan_in_valid = 1'b1;
            @(posedge clk);
            #1 pan_in_valid = 1'b0;
            @(posedge pan_out_valid);
            #1;
            if (mid_sample !== expected_mid || side_sample !== expected_side) begin
                $display("ERROR: pan A=%0d B=%0d got mid=%0d side=%0d expected %0d/%0d",
                         value_pan_a, value_pan_b, mid_sample, side_sample,
                         expected_mid, expected_side);
                errors = errors + 1;
            end
            @(posedge clk);
        end
    endtask

    task check_output;
        input signed [15:0] value_mid;
        input signed [15:0] value_side;
        input [8:0] value_master;
        input [6:0] value_pan;
        input signed [15:0] expected_left;
        input signed [15:0] expected_right;
        begin
            while (!output_in_ready) @(posedge clk);
            output_mid = value_mid;
            output_side = value_side;
            master_gain = value_master;
            global_pan = value_pan;
            output_in_valid = 1'b1;
            @(posedge clk);
            #1 output_in_valid = 1'b0;
            @(posedge output_valid);
            #1;
            if (left_sample !== expected_left || right_sample !== expected_right) begin
                $display("ERROR: global pan=%0d got L=%0d R=%0d expected %0d/%0d",
                         value_pan, left_sample, right_sample,
                         expected_left, expected_right);
                errors = errors + 1;
            end
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        pan_in_valid = 1'b0;
        sample_a = 16'sd0;
        sample_b = 16'sd0;
        pan_a = 7'd64;
        pan_b = 7'd64;
        output_in_valid = 1'b0;
        output_mid = 16'sd0;
        output_side = 16'sd0;
        master_gain = 9'd256;
        global_pan = 7'd64;
        errors = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // 中央声像保持旧单声道求和结果。
        check_pan(16'sd1000, 16'sd2000, 7'd64, 7'd64,
                  16'sd3000, 16'sd0);
        // A硬左、B硬右时，Mid/Side可无损重构1000/2000。
        check_pan(16'sd1000, 16'sd2000, 7'd0, 7'd127,
                  16'sd1500, -16'sd500);

        check_output(16'sd1500, -16'sd500, 9'd256, 7'd64,
                     16'sd1000, 16'sd2000);
        check_output(16'sd1500, -16'sd500, 9'd256, 7'd0,
                     16'sd1000, 16'sd0);
        check_output(16'sd1500, -16'sd500, 9'd256, 7'd127,
                     16'sd0, 16'sd2000);
        check_output(16'sd1500, -16'sd500, 9'd128, 7'd64,
                     16'sd500, 16'sd1000);

        if (pan_overrun || output_overrun) begin
            $display("ERROR: unexpected handshake overrun");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: stereo oscillator pan and global pan path");
        else
            $display("FAIL: %0d stereo pan error(s)", errors);
        $finish;
    end

    initial begin
        #10000;
        $display("FAIL: stereo pan test timed out");
        $finish;
    end

endmodule
