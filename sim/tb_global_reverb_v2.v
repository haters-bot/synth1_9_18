`timescale 1ns/1ps

module tb_global_reverb_v2;

    reg clk;
    reg rst_n;
    reg in_valid;
    reg signed [15:0] sample_in;
    wire in_ready;
    reg [6:0] size_control;
    reg [6:0] decay_control;
    reg [6:0] mix_control;
    wire out_valid;
    wire signed [15:0] sample_out;
    wire input_overrun;

    integer returned_sample;
    integer low_decay_energy;
    integer high_decay_energy;
    integer high_decay_late_energy;
    integer peak_value;
    integer nonzero_tail_count;
    integer latency_clocks;

    global_reverb dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .sample_in(sample_in),
        .in_ready(in_ready),
        .size_control(size_control),
        .decay_control(decay_control),
        .mix_control(mix_control),
        .out_valid(out_valid),
        .sample_out(sample_out),
        .input_overrun(input_overrun)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    function integer absolute_value;
        input integer value;
        begin
            absolute_value = (value < 0) ? -value : value;
        end
    endfunction

    task reset_dut;
        begin
            rst_n = 1'b0;
            in_valid = 1'b0;
            sample_in = 16'sd0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task process_sample;
        input integer input_value;
        output integer output_value;
        integer clocks_waited;
        begin
            @(negedge clk);
            while (!in_ready)
                @(negedge clk);
            sample_in = input_value;
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;
            sample_in = 16'sd0;

            clocks_waited = 0;
            while (!out_valid) begin
                @(negedge clk);
                clocks_waited = clocks_waited + 1;
                if (clocks_waited > 100) begin
                    $display("FAIL: reverb processing timed out");
                    $finish;
                end
            end
            output_value = $signed(sample_out);
            latency_clocks = clocks_waited;
        end
    endtask

    task warm_controls;
        integer i;
        integer discarded;
        begin
            // Mix 每个音频样本变化 1，Decay 每个样本变化 256 Q15。
            // 140 个零样本足以让两个平滑器到达任意目标值。
            for (i = 0; i < 140; i = i + 1)
                process_sample(0, discarded);
        end
    endtask

    task measure_decay_tail;
        input [6:0] decay_value;
        output integer measured_energy;
        output integer measured_peak;
        output integer late_energy;
        integer i;
        integer value;
        integer magnitude;
        begin
            size_control = 7'd64;
            decay_control = decay_value;
            mix_control = 7'd127;
            reset_dut;
            warm_controls;
            process_sample(8000, value);

            measured_energy = 0;
            measured_peak = 0;
            late_energy = 0;
            for (i = 0; i < 18000; i = i + 1) begin
                process_sample(0, value);
                magnitude = absolute_value(value);
                if (magnitude > measured_peak)
                    measured_peak = magnitude;
                if ((i >= 8000) && (i < 16000))
                    measured_energy = measured_energy + magnitude;
                if (i >= 17000)
                    late_energy = late_energy + magnitude;
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        in_valid = 1'b0;
        sample_in = 16'sd0;
        size_control = 7'd0;
        decay_control = 7'd0;
        mix_control = 7'd0;

        // Mix=0 必须保持逐位相同的干声，不能因内部混响状态改变输出。
        reset_dut;
        process_sample(12345, returned_sample);
        if (returned_sample !== 12345) begin
            $display("FAIL: dry bypass mismatch, got %0d", returned_sample);
            $finish;
        end

        // 确认 FDN 延迟区间内确实产生了离散且非零的混响尾音。
        size_control = 7'd0;
        decay_control = 7'd96;
        mix_control = 7'd127;
        reset_dut;
        warm_controls;
        process_sample(12000, returned_sample);
        nonzero_tail_count = 0;
        repeat (2600) begin
            process_sample(0, returned_sample);
            if (returned_sample != 0)
                nonzero_tail_count = nonzero_tail_count + 1;
        end
        if (nonzero_tail_count < 100) begin
            $display("FAIL: reverb tail is too sparse, nonzero=%0d",
                     nonzero_tail_count);
            $finish;
        end

        // 高 Decay 的中后段能量应显著高于低 Decay。
        measure_decay_tail(7'd32, low_decay_energy,
                           peak_value, high_decay_late_energy);
        measure_decay_tail(7'd127, high_decay_energy,
                           peak_value, high_decay_late_energy);

        if (high_decay_energy <= low_decay_energy * 2) begin
            $display("FAIL: decay range is not effective, low=%0d high=%0d",
                     low_decay_energy, high_decay_energy);
            $finish;
        end

        // 最大反馈下不应出现 16 位满幅削顶，也不应发生调度超时。
        if (peak_value >= 32767) begin
            $display("FAIL: maximum decay clipped, peak=%0d", peak_value);
            $finish;
        end
        if (latency_clocks > 40) begin
            $display("FAIL: processing latency is too large: %0d clocks",
                     latency_clocks);
            $finish;
        end
        if (input_overrun) begin
            $display("FAIL: input_overrun was asserted");
            $finish;
        end

        $display("Reverb V2 low-decay energy : %0d", low_decay_energy);
        $display("Reverb V2 high-decay energy: %0d", high_decay_energy);
        $display("Reverb V2 max-decay peak   : %0d", peak_value);
        $display("Reverb V2 processing delay : %0d clocks", latency_clocks);
        $display("PASS: global_reverb V2");
        $finish;
    end

endmodule
