`timescale 1ns/1ps

module tb_global_effects;
    reg clk;
    reg rst_n;
    reg in_valid;
    reg signed [15:0] sample_in;
    reg [1:0] effect_mode;
    reg [6:0] delay_time;
    reg [6:0] delay_feedback;
    reg [6:0] delay_mix;
    reg [6:0] reverb_size;
    reg [6:0] reverb_decay;
    reg [6:0] reverb_mix;
    wire in_ready;
    wire out_valid;
    wire signed [15:0] sample_out;
    wire input_overrun;

    integer errors;
    integer sample_index;
    integer reverb_nonzero_count;
    reg signed [15:0] captured_sample;

    always #10 clk = ~clk;

    global_effects dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .sample_in(sample_in), .in_ready(in_ready),
        .effect_mode(effect_mode),
        .delay_time(delay_time), .delay_feedback(delay_feedback),
        .delay_mix(delay_mix), .reverb_size(reverb_size),
        .reverb_decay(reverb_decay), .reverb_mix(reverb_mix),
        .out_valid(out_valid), .sample_out(sample_out),
        .input_overrun(input_overrun)
    );

    task process_sample;
        input signed [15:0] value;
        output signed [15:0] result;
        begin
            while (!in_ready)
                @(posedge clk);
            @(negedge clk);
            sample_in = value;
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;
            while (!out_valid)
                @(posedge clk);
            #1 result = sample_out;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        sample_in = 16'sd0;
        effect_mode = 2'd0;
        delay_time = 7'd0;
        delay_feedback = 7'd64;
        delay_mix = 7'd127;
        reverb_size = 7'd0;
        reverb_decay = 7'd0;
        reverb_mix = 7'd127;
        errors = 0;
        reverb_nonzero_count = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // 旁路必须逐位保持输入，即使两个效果核心仍在后台更新。
        process_sample(16'sd12345, captured_sample);
        if (captured_sample !== 16'sd12345) begin
            $display("ERROR: bypass got %0d expected 12345", captured_sample);
            errors = errors + 1;
        end

        // 重新复位清空有效计数。最短Delay为480个96 kHz样本，即5 ms。
        @(negedge clk);
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        effect_mode = 2'd1;
        process_sample(16'sd10000, captured_sample);
        if (captured_sample !== 16'sd0) begin
            $display("ERROR: delay emitted data before history was valid");
            errors = errors + 1;
        end
        for (sample_index = 1; sample_index <= 480;
             sample_index = sample_index + 1) begin
            process_sample(16'sd0, captured_sample);
            if (sample_index < 480 && captured_sample !== 16'sd0) begin
                $display("ERROR: early delay sample at index %0d", sample_index);
                errors = errors + 1;
            end
        end
        if (captured_sample !== 16'sd10000) begin
            $display("ERROR: 5 ms delay tap got %0d expected 10000",
                     captured_sample);
            errors = errors + 1;
        end
        for (sample_index = 1; sample_index <= 480;
             sample_index = sample_index + 1)
            process_sample(16'sd0, captured_sample);
        if (captured_sample !== 16'sd4375) begin
            $display("ERROR: feedback echo got %0d expected 4375",
                     captured_sample);
            errors = errors + 1;
        end

        // Reverb最短梳状线为1277点。冲激经过梳状和全通网络后应产生尾音。
        @(negedge clk);
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        effect_mode = 2'd2;
        process_sample(16'sd16000, captured_sample);
        for (sample_index = 1; sample_index <= 1320;
             sample_index = sample_index + 1) begin
            process_sample(16'sd0, captured_sample);
            if (captured_sample != 16'sd0)
                reverb_nonzero_count = reverb_nonzero_count + 1;
        end
        if (reverb_nonzero_count == 0) begin
            $display("ERROR: Schroeder reverb produced no impulse tail");
            errors = errors + 1;
        end

        if (input_overrun) begin
            $display("ERROR: effects wrapper reported an unexpected overrun");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: global delay, Schroeder reverb, and bypass");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
