`timescale 1ns/1ps

module tb_global_svf_filter;

    reg clk;
    reg rst_n;
    reg in_valid;
    reg signed [15:0] sample_in;
    reg [1:0] filter_mode;
    reg [6:0] cutoff_control;
    reg [6:0] resonance_control;

    wire in_ready;
    wire out_valid;
    wire signed [15:0] sample_out;
    wire input_overrun;

    integer errors;
    integer sample_index;
    integer latency_cycles;
    integer absolute_output;
    reg signed [15:0] captured_sample;

    global_svf_filter dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .sample_in(sample_in),
        .in_ready(in_ready),
        .filter_mode(filter_mode),
        .cutoff_control(cutoff_control),
        .resonance_control(resonance_control),
        .out_valid(out_valid),
        .sample_out(sample_out),
        .input_overrun(input_overrun)
    );

    always #10 clk = ~clk;

    task process_sample;
        input signed [15:0] value;
        begin
            while (!in_ready)
                @(posedge clk);
            @(negedge clk);
            sample_in = value;
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;

            latency_cycles = 0;
            while (!out_valid && latency_cycles < 40) begin
                @(posedge clk);
                #1;
                latency_cycles = latency_cycles + 1;
            end
            captured_sample = sample_out;
            if (!out_valid || latency_cycles > 20) begin
                $display("ERROR: filter output latency exceeded budget");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        sample_in = 16'sd0;
        filter_mode = 2'd0;
        cutoff_control = 7'd127;
        resonance_control = 7'd0;
        errors = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // 旁路模式必须逐样本精确通过，滤波器状态仍在后台更新。
        process_sample(16'sd12345);
        if (captured_sample !== 16'sd12345) begin
            $display("ERROR: bypass output=%0d expected=12345", captured_sample);
            errors = errors + 1;
        end
        process_sample(-16'sd23456);
        if (captured_sample !== -16'sd23456) begin
            $display("ERROR: negative bypass output=%0d expected=-23456",
                     captured_sample);
            errors = errors + 1;
        end

        // 低通面对直流输入应收敛到输入电平。
        filter_mode = 2'd1;
        cutoff_control = 7'd127;
        resonance_control = 7'd0;
        for (sample_index = 0; sample_index < 160;
             sample_index = sample_index + 1)
            process_sample(16'sd10000);
        if (captured_sample < 16'sd9800 || captured_sample > 16'sd10200) begin
            $display("ERROR: low-pass DC output did not settle: %0d",
                     captured_sample);
            errors = errors + 1;
        end

        // 高通面对稳定直流应衰减到接近0。
        filter_mode = 2'd2;
        for (sample_index = 0; sample_index < 160;
             sample_index = sample_index + 1)
            process_sample(16'sd10000);
        if (captured_sample < -16'sd100 || captured_sample > 16'sd100) begin
            $display("ERROR: high-pass DC rejection failed: %0d",
                     captured_sample);
            errors = errors + 1;
        end

        // 带通同样应拒绝稳定直流。
        filter_mode = 2'd3;
        for (sample_index = 0; sample_index < 80;
             sample_index = sample_index + 1)
            process_sample(16'sd10000);
        if (captured_sample < -16'sd100 || captured_sample > 16'sd100) begin
            $display("ERROR: band-pass DC rejection failed: %0d",
                     captured_sample);
            errors = errors + 1;
        end

        // 约1.1 kHz截止频率应明显抑制每采样翻转的高频信号。
        filter_mode = 2'd1;
        cutoff_control = 7'd64;
        resonance_control = 7'd0;
        for (sample_index = 0; sample_index < 500;
             sample_index = sample_index + 1) begin
            if (sample_index[0])
                process_sample(16'sd10000);
            else
                process_sample(-16'sd10000);
        end
        absolute_output = (captured_sample < 0)
                        ? -captured_sample : captured_sample;
        if (absolute_output > 500) begin
            $display("ERROR: low-pass high-frequency rejection failed: %0d",
                     captured_sample);
            errors = errors + 1;
        end

        // 使用相同状态切换到高通后，高频测试信号应保留主要幅度。
        filter_mode = 2'd2;
        for (sample_index = 0; sample_index < 40;
             sample_index = sample_index + 1) begin
            if (sample_index[0])
                process_sample(16'sd10000);
            else
                process_sample(-16'sd10000);
        end
        absolute_output = (captured_sample < 0)
                        ? -captured_sample : captured_sample;
        if (absolute_output < 8000) begin
            $display("ERROR: high-pass high-frequency pass failed: %0d",
                     captured_sample);
            errors = errors + 1;
        end

        if (input_overrun !== 1'b0) begin
            $display("ERROR: unexpected filter input overrun");
            errors = errors + 1;
        end

        // 忙期间再次给出输入时必须保留粘滞错误标志。
        while (!in_ready)
            @(posedge clk);
        @(negedge clk);
        sample_in = 16'sd1000;
        in_valid = 1'b1;
        repeat (2) @(negedge clk);
        in_valid = 1'b0;
        while (!out_valid)
            @(posedge clk);
        #1;
        if (input_overrun !== 1'b1) begin
            $display("ERROR: busy input did not set input_overrun");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: global SVF bypass, latency, DC, and frequency responses");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
