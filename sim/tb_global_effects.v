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
    reg distortion_enable;
    reg [1:0] distortion_type;
    reg [6:0] distortion_drive;
    reg [6:0] distortion_tone;
    reg [6:0] distortion_mix;
    reg chorus_enable;
    reg [6:0] chorus_rate;
    reg [6:0] chorus_depth;
    reg [6:0] chorus_delay;
    reg [6:0] chorus_feedback;
    reg [6:0] chorus_mix;
    reg phaser_enable;
    reg [6:0] phaser_rate;
    reg [6:0] phaser_depth;
    reg [6:0] phaser_center;
    reg [6:0] phaser_feedback;
    reg [6:0] phaser_mix;
    reg compressor_enable;
    reg [6:0] compressor_threshold;
    reg [6:0] compressor_ratio;
    reg [6:0] compressor_attack;
    reg [6:0] compressor_release;
    reg [6:0] compressor_makeup;
    reg [6:0] compressor_mix;
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
        .distortion_enable(distortion_enable),
        .distortion_type(distortion_type),
        .distortion_drive(distortion_drive),
        .distortion_tone(distortion_tone),
        .distortion_mix(distortion_mix),
        .chorus_enable(chorus_enable), .chorus_rate(chorus_rate),
        .chorus_depth(chorus_depth), .chorus_delay(chorus_delay),
        .chorus_feedback(chorus_feedback), .chorus_mix(chorus_mix),
        .phaser_enable(phaser_enable), .phaser_rate(phaser_rate),
        .phaser_depth(phaser_depth), .phaser_center(phaser_center),
        .phaser_feedback(phaser_feedback), .phaser_mix(phaser_mix),
        .compressor_enable(compressor_enable),
        .compressor_threshold(compressor_threshold),
        .compressor_ratio(compressor_ratio),
        .compressor_attack(compressor_attack),
        .compressor_release(compressor_release),
        .compressor_makeup(compressor_makeup),
        .compressor_mix(compressor_mix),
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
        distortion_enable = 1'b0;
        distortion_type = 2'd0;
        distortion_drive = 7'd32;
        distortion_tone = 7'd127;
        distortion_mix = 7'd127;
        chorus_enable = 1'b0;
        chorus_rate = 7'd0;
        chorus_depth = 7'd0;
        chorus_delay = 7'd0;
        chorus_feedback = 7'd0;
        chorus_mix = 7'd127;
        phaser_enable = 1'b0;
        phaser_rate = 7'd0;
        phaser_depth = 7'd0;
        phaser_center = 7'd64;
        phaser_feedback = 7'd0;
        phaser_mix = 7'd127;
        compressor_enable = 1'b0;
        compressor_threshold = 7'd0;
        compressor_ratio = 7'd127;
        compressor_attack = 7'd0;
        compressor_release = 7'd64;
        compressor_makeup = 7'd0;
        compressor_mix = 7'd127;
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

        // 失真在高Drive下应改变中等幅度输入，同时保持16位饱和。
        effect_mode = 2'd0;
        distortion_enable = 1'b1;
        distortion_drive = 7'd96;
        process_sample(16'sd12000, captured_sample);
        if (captured_sample === 16'sd12000) begin
            $display("ERROR: distortion did not change the input");
            errors = errors + 1;
        end
        distortion_enable = 1'b0;

        // Phaser先用零输入完成Mix平滑，再验证全湿路径改变冲激。
        phaser_enable = 1'b1;
        for (sample_index = 0; sample_index < 128;
             sample_index = sample_index + 1)
            process_sample(16'sd0, captured_sample);
        process_sample(16'sd12000, captured_sample);
        if (captured_sample === 16'sd12000) begin
            $display("ERROR: phaser wet path did not change the impulse");
            errors = errors + 1;
        end
        phaser_enable = 1'b0;

        // Chorus最短基础延迟为192点。全湿时冲激应在延迟线返回。
        @(negedge clk);
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        chorus_enable = 1'b1;
        process_sample(16'sd10000, captured_sample);
        for (sample_index = 1; sample_index <= 192;
             sample_index = sample_index + 1)
            process_sample(16'sd0, captured_sample);
        if (captured_sample !== 16'sd10000) begin
            $display("ERROR: chorus delay tap got %0d expected 10000",
                     captured_sample);
            errors = errors + 1;
        end
        chorus_enable = 1'b0;

        // 压缩器连续接收大信号后，稳态输出幅度应明显降低。
        compressor_enable = 1'b1;
        for (sample_index = 0; sample_index < 400;
             sample_index = sample_index + 1)
            process_sample(16'sd25000, captured_sample);
        if (captured_sample >= 16'sd20000) begin
            $display("ERROR: compressor steady output too high: %0d",
                     captured_sample);
            errors = errors + 1;
        end

        if (input_overrun) begin
            $display("ERROR: effects wrapper reported an unexpected overrun");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: complete global effects chain");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
