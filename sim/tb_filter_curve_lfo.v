`timescale 1ns/1ps

module tb_filter_curve_lfo;

    reg clk;
    reg rst_n;
    reg sample_tick;
    reg parameter_valid;
    reg [6:0] parameter_id;
    reg [13:0] parameter_value;
    reg [14:0] base_cutoff_q8;

    wire [14:0] cutoff_q8;
    wire lfo_enabled;
    wire active_segment;
    wire [23:0] segment_phase;

    integer errors;
    integer index;
    integer boundary_delta;
    reg [14:0] boundary_before;
    reg [14:0] boundary_after;

    filter_curve_lfo dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .sample_tick    (sample_tick),
        .parameter_valid(parameter_valid),
        .parameter_id   (parameter_id),
        .parameter_value(parameter_value),
        .base_cutoff_q8 (base_cutoff_q8),
        .cutoff_q8      (cutoff_q8),
        .lfo_enabled    (lfo_enabled),
        .active_segment (active_segment),
        .segment_phase  (segment_phase)
    );

    always #5 clk = ~clk;

    task write_parameter;
        input [6:0] id;
        input [13:0] value;
        begin
            @(negedge clk);
            parameter_id = id;
            parameter_value = value;
            parameter_valid = 1'b1;
            @(negedge clk);
            parameter_valid = 1'b0;
        end
    endtask

    task pulse_sample;
        begin
            @(negedge clk);
            sample_tick = 1'b1;
            @(negedge clk);
            sample_tick = 1'b0;
            repeat (7) @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_tick = 1'b0;
        parameter_valid = 1'b0;
        parameter_id = 7'd0;
        parameter_value = 14'd0;
        base_cutoff_q8 = {7'd64, 8'd0};
        errors = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // 先写影子寄存器，commit前活动配置不能变化。
        write_parameter(7'd16, 14'd1);
        write_parameter(7'd17, 14'd16383);
        write_parameter(7'd18, 14'd16383);
        write_parameter(7'd19, 14'd4096);
        write_parameter(7'd20, 14'd8192);
        write_parameter(7'd21, 14'd16383);
        write_parameter(7'd22, 14'd8192);
        // 使用两种极端曲率验证端点仍保持连续和零斜率。
        write_parameter(7'd23, 14'd16383);
        write_parameter(7'd24, 14'd0);
        if (lfo_enabled) begin
            $display("ERROR: shadow configuration became active before commit");
            errors = errors + 1;
        end

        write_parameter(7'd25, 14'd1);
        repeat (3) @(posedge clk);
        if (!lfo_enabled) begin
            $display("ERROR: commit did not enable LFO");
            errors = errors + 1;
        end

        // 第一段从0上升到+1；深度和相位均应由FPGA逐样本推进。
        for (index = 0; index < 600; index = index + 1)
            pulse_sample();
        if (segment_phase == 24'd0 || cutoff_q8 <= base_cutoff_q8) begin
            $display("ERROR: FPGA LFO did not advance or modulate cutoff");
            errors = errors + 1;
        end

        // 等待第二段结束并检查周期回绕。三次平滑曲线在端点斜率为0，
        // 因此回绕前后两个样本的Cutoff差值应接近0。
        while (!active_segment)
            pulse_sample();
        while (active_segment)
            pulse_sample();
        boundary_before = cutoff_q8;
        pulse_sample();
        boundary_after = cutoff_q8;
        if (boundary_after >= boundary_before)
            boundary_delta = boundary_after - boundary_before;
        else
            boundary_delta = boundary_before - boundary_after;
        if (boundary_delta > 2) begin
            $display("ERROR: LFO loop boundary jumped by %0d Q7.8 LSB", boundary_delta);
            errors = errors + 1;
        end

        // 关闭后深度在约10 ms内退到0，最终输出回到静态Cutoff。
        write_parameter(7'd16, 14'd0);
        write_parameter(7'd25, 14'd1);
        for (index = 0; index < 300; index = index + 1)
            pulse_sample();
        if (lfo_enabled || cutoff_q8 !== base_cutoff_q8) begin
            $display("ERROR: disabled LFO did not return to base cutoff");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: three-point FPGA filter LFO");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
