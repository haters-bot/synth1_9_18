`timescale 1ns/1ps

module tb_global_filter;

    reg clk;
    reg rst_n;
    reg in_valid;
    reg signed [15:0] sample_in;
    reg [2:0] filter_mode;
    reg [14:0] cutoff_control_q8;
    reg [6:0] resonance_control;
    reg [6:0] mix_control;

    wire in_ready;
    wire out_valid;
    wire signed [15:0] sample_out;
    wire input_overrun;

    integer errors;
    integer sample_index;
    integer latency_cycles;
    reg signed [15:0] captured_sample;

    global_filter dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .sample_in(sample_in),
        .in_ready(in_ready),
        .filter_mode(filter_mode),
        .cutoff_control_q8(cutoff_control_q8),
        .resonance_control(resonance_control),
        .mix_control(mix_control),
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
            while (!out_valid && latency_cycles < 50) begin
                @(posedge clk);
                #1;
                latency_cycles = latency_cycles + 1;
            end
            captured_sample = sample_out;
            if (!out_valid || latency_cycles > 25) begin
                $display("ERROR: global filter latency exceeded budget");
                errors = errors + 1;
            end
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        sample_in = 16'sd0;
        filter_mode = 3'd0;
        cutoff_control_q8 = {7'd127, 8'd0};
        resonance_control = 7'd0;
        mix_control = 7'd127;
        errors = 0;

        reset_dut();

        // Mix=0必须逐位输出原声，即使内部选择低通。
        filter_mode = 3'd1;
        cutoff_control_q8 = {7'd32, 8'd0};
        mix_control = 7'd0;
        process_sample(16'sd12345);
        if (captured_sample !== 16'sd12345) begin
            $display("ERROR: dry Mix endpoint failed: %0d", captured_sample);
            errors = errors + 1;
        end

        // Cutoff必须实际改变Comb延迟地址，覆盖低、中、高三个控制点。
        filter_mode = 3'd5;
        resonance_control = 7'd0;
        mix_control = 7'd0;
        cutoff_control_q8 = {7'd0, 8'd0};
        process_sample(16'sd0);
        if (dut.u_global_comb_filter.delay_length_latched !== 12'd2047) begin
            $display("ERROR: Comb Cutoff=0 delay mapping failed: %0d",
                     dut.u_global_comb_filter.delay_length_latched);
            errors = errors + 1;
        end
        if (dut.u_global_comb_filter.delay_fraction_latched !== 8'd0) begin
            $display("ERROR: Comb Cutoff=0 fraction failed: %0d",
                     dut.u_global_comb_filter.delay_fraction_latched);
            errors = errors + 1;
        end
        cutoff_control_q8 = {7'd64, 8'd0};
        process_sample(16'sd0);
        if (dut.u_global_comb_filter.delay_length_latched !== 12'd127) begin
            $display("ERROR: Comb Cutoff=64 delay mapping failed: %0d",
                     dut.u_global_comb_filter.delay_length_latched);
            errors = errors + 1;
        end
        if (dut.u_global_comb_filter.delay_fraction_latched !== 8'd240) begin
            $display("ERROR: Comb Cutoff=64 fraction failed: %0d",
                     dut.u_global_comb_filter.delay_fraction_latched);
            errors = errors + 1;
        end
        cutoff_control_q8 = {7'd127, 8'd0};
        process_sample(16'sd0);
        if (dut.u_global_comb_filter.delay_length_latched !== 12'd8) begin
            $display("ERROR: Comb Cutoff=127 delay mapping failed: %0d",
                     dut.u_global_comb_filter.delay_length_latched);
            errors = errors + 1;
        end
        if (dut.u_global_comb_filter.delay_fraction_latched !== 8'd96) begin
            $display("ERROR: Comb Cutoff=127 fraction failed: %0d",
                     dut.u_global_comb_filter.delay_fraction_latched);
            errors = errors + 1;
        end

        // 半个CC刻度必须落在相邻两组延迟映射之间。
        cutoff_control_q8 = {7'd126, 8'd128};
        process_sample(16'sd0);
        if (dut.u_global_comb_filter.delay_length_mapped_q8
            >= dut.u_global_comb_filter.delay_at_integer_q8
            || dut.u_global_comb_filter.delay_length_mapped_q8
               <= dut.u_global_comb_filter.delay_at_next_q8) begin
            $display("ERROR: fractional Cutoff interpolation failed");
            errors = errors + 1;
        end

        // 最高Cutoff对应8点延迟。Resonance=0时前馈梳状项仍必须存在，
        // 证明Cutoff并不依赖反馈才能改变频率响应。
        reset_dut();
        filter_mode = 3'd5;
        cutoff_control_q8 = {7'd127, 8'd0};
        resonance_control = 7'd0;
        mix_control = 7'd127;
        process_sample(16'sd12000);
        for (sample_index = 1; sample_index < 8;
             sample_index = sample_index + 1)
            process_sample(16'sd0);
        process_sample(16'sd0);
        if (captured_sample < 16'sd3650
            || captured_sample > 16'sd3850) begin
            $display("ERROR: zero-resonance Comb feedforward depth failed: %0d",
                     captured_sample);
            errors = errors + 1;
        end
        process_sample(16'sd0);
        if (captured_sample < 16'sd2150
            || captured_sample > 16'sd2350) begin
            $display("ERROR: fractional Comb second tap failed: %0d",
                     captured_sample);
            errors = errors + 1;
        end

        // 延迟改为127点后，第8个样本不应再出现回声，证明Cutoff确实移动梳齿。
        reset_dut();
        filter_mode = 3'd5;
        cutoff_control_q8 = {7'd64, 8'd0};
        resonance_control = 7'd0;
        mix_control = 7'd127;
        process_sample(16'sd12000);
        for (sample_index = 1; sample_index < 8;
             sample_index = sample_index + 1)
            process_sample(16'sd0);
        process_sample(16'sd0);
        if (captured_sample !== 16'sd0) begin
            $display("ERROR: Comb Cutoff did not move echo position: %0d",
                     captured_sample);
            errors = errors + 1;
        end

        // 提高Resonance后仍应保留正极性的梳状输出。
        cutoff_control_q8 = {7'd127, 8'd0};
        resonance_control = 7'd127;
        for (sample_index = 0; sample_index < 8;
             sample_index = sample_index + 1)
            process_sample(16'sd0);
        if (captured_sample < 16'sd0) begin
            $display("ERROR: positive Comb polarity failed: %0d", captured_sample);
            errors = errors + 1;
        end

        // 中间Mix应按比例减小同一个首回声。
        reset_dut();
        filter_mode = 3'd5;
        cutoff_control_q8 = {7'd127, 8'd0};
        resonance_control = 7'd127;
        mix_control = 7'd64;
        process_sample(16'sd12000);
        for (sample_index = 1; sample_index < 8;
             sample_index = sample_index + 1)
            process_sample(16'sd0);
        process_sample(16'sd0);
        if (captured_sample < 16'sd1800 || captured_sample > 16'sd2000) begin
            $display("ERROR: intermediate Mix scaling failed: %0d",
                     captured_sample);
            errors = errors + 1;
        end

        // 负反馈使用相同延迟，首个回声必须反相。
        reset_dut();
        filter_mode = 3'd6;
        cutoff_control_q8 = {7'd127, 8'd0};
        resonance_control = 7'd127;
        mix_control = 7'd127;
        process_sample(16'sd12000);
        for (sample_index = 1; sample_index < 8;
             sample_index = sample_index + 1)
            process_sample(16'sd0);
        process_sample(16'sd0);
        if (captured_sample > -16'sd1000) begin
            $display("ERROR: negative Comb echo missing: %0d", captured_sample);
            errors = errors + 1;
        end

        // Mix=0在Comb模式下也必须保持精确旁路。
        mix_control = 7'd0;
        process_sample(-16'sd23456);
        if (captured_sample !== -16'sd23456) begin
            $display("ERROR: Comb dry Mix endpoint failed: %0d", captured_sample);
            errors = errors + 1;
        end

        if (input_overrun !== 1'b0) begin
            $display("ERROR: unexpected global filter input overrun");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: global filter Mix and positive/negative Comb responses");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
