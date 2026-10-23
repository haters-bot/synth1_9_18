`timescale 1ns/1ps

module tb_filter_curve_lfo;

    reg clk;
    reg rst_n;
    reg sample_tick;
    reg parameter_valid;
    reg [6:0] parameter_id;
    reg [13:0] parameter_value;

    wire signed [14:0] curve_value_q13;
    wire curve_value_valid;
    wire lfo_enabled;
    wire active_segment;
    wire [23:0] segment_phase;

    reg direct_lfo_valid;
    reg signed [14:0] direct_lfo_q13;
    reg signed [14:0] direct_lfo_1_q13;
    reg signed [14:0] direct_lfo_2_q13;
    reg [2:0] filter_mode;
    reg [6:0] base_osc_a_wt;
    reg [6:0] base_osc_a_warp;
    reg [6:0] base_osc_a_level;
    reg [6:0] base_osc_b_wt;
    reg [6:0] base_osc_b_warp;
    reg [6:0] base_osc_b_level;
    reg [6:0] base_pan;
    reg [14:0] base_filter_cutoff_q8;
    reg [6:0] base_filter_resonance;
    reg [6:0] base_filter_mix;

    wire [6:0] mod_osc_a_wt;
    wire [6:0] mod_osc_a_warp;
    wire [6:0] mod_osc_a_level;
    wire [6:0] mod_osc_b_wt;
    wire [6:0] mod_osc_b_warp;
    wire [6:0] mod_osc_b_level;
    wire [6:0] mod_pan;
    wire [14:0] mod_filter_cutoff_q8;
    wire [6:0] mod_filter_resonance;
    wire [6:0] mod_filter_mix;
    wire route_overrun;

    integer errors;
    integer sample_index;
    integer valid_count;

    always #5 clk = ~clk;

    curve_lfo_core u_curve_lfo_core (
        .clk             (clk),
        .rst_n           (rst_n),
        .sample_tick     (sample_tick),
        .parameter_valid (parameter_valid),
        .parameter_id    (parameter_id),
        .parameter_value (parameter_value),
        .lfo_value_q13   (curve_value_q13),
        .lfo_value_valid (curve_value_valid),
        .lfo_enabled     (lfo_enabled),
        .active_segment  (active_segment),
        .segment_phase   (segment_phase)
    );

    lfo_modulation_router u_lfo_modulation_router (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .lfo_value_valid          (direct_lfo_valid),
        .lfo_value_q13            (direct_lfo_q13),
        .lfo_1_value_q13          (direct_lfo_1_q13),
        .lfo_2_value_q13          (direct_lfo_2_q13),
        .parameter_valid          (parameter_valid),
        .parameter_id             (parameter_id),
        .parameter_value          (parameter_value),
        .filter_mode              (filter_mode),
        .base_osc_a_wt            (base_osc_a_wt),
        .base_osc_a_warp          (base_osc_a_warp),
        .base_osc_a_level         (base_osc_a_level),
        .base_osc_b_wt            (base_osc_b_wt),
        .base_osc_b_warp          (base_osc_b_warp),
        .base_osc_b_level         (base_osc_b_level),
        .base_pan                 (base_pan),
        .base_filter_cutoff_q8    (base_filter_cutoff_q8),
        .base_filter_resonance    (base_filter_resonance),
        .base_filter_mix          (base_filter_mix),
        .mod_osc_a_wt             (mod_osc_a_wt),
        .mod_osc_a_warp           (mod_osc_a_warp),
        .mod_osc_a_level          (mod_osc_a_level),
        .mod_osc_b_wt             (mod_osc_b_wt),
        .mod_osc_b_warp           (mod_osc_b_warp),
        .mod_osc_b_level          (mod_osc_b_level),
        .mod_pan                  (mod_pan),
        .mod_filter_cutoff_q8     (mod_filter_cutoff_q8),
        .mod_filter_resonance     (mod_filter_resonance),
        .mod_filter_mix           (mod_filter_mix),
        .route_overrun            (route_overrun)
    );

    always @(posedge clk) begin
        if (curve_value_valid)
            valid_count <= valid_count + 1;
    end

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

    task configure_route;
        input [2:0] index;
        input enable;
        input [3:0] destination;
        input [13:0] depth_offset_binary;
        input [1:0] source;
        begin
            write_parameter(7'd26, {11'd0, index});
            write_parameter(7'd27, enable ? 14'd1 : 14'd0);
            write_parameter(7'd28, {10'd0, destination});
            write_parameter(7'd29, depth_offset_binary);
            write_parameter(7'd30, {12'd0, source});
        end
    endtask

    task pulse_sample;
        begin
            @(negedge clk);
            sample_tick = 1'b1;
            @(negedge clk);
            sample_tick = 1'b0;
            repeat (18) @(posedge clk);
        end
    endtask

    task route_sample;
        input signed [14:0] value_0;
        input signed [14:0] value_1;
        input signed [14:0] value_2;
        begin
            @(negedge clk);
            direct_lfo_q13 = value_0;
            direct_lfo_1_q13 = value_1;
            direct_lfo_2_q13 = value_2;
            direct_lfo_valid = 1'b1;
            @(negedge clk);
            direct_lfo_valid = 1'b0;
            repeat (12) @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_tick = 1'b0;
        parameter_valid = 1'b0;
        parameter_id = 7'd0;
        parameter_value = 14'd0;
        direct_lfo_valid = 1'b0;
        direct_lfo_q13 = 15'sd0;
        direct_lfo_1_q13 = 15'sd0;
        direct_lfo_2_q13 = 15'sd0;
        filter_mode = 3'd0;
        base_osc_a_wt = 7'd64;
        base_osc_a_warp = 7'd64;
        base_osc_a_level = 7'd100;
        base_osc_b_wt = 7'd20;
        base_osc_b_warp = 7'd30;
        base_osc_b_level = 7'd80;
        base_pan = 7'd64;
        base_filter_cutoff_q8 = {7'd32, 8'd0};
        base_filter_resonance = 7'd10;
        base_filter_mix = 7'd127;
        errors = 0;
        valid_count = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // 配置曲线源：两段快速往返，端点为 -1、+1、-1。
        write_parameter(7'd16, 14'd1);
        write_parameter(7'd17, 14'd16383);
        write_parameter(7'd18, 14'd16383);
        write_parameter(7'd20, 14'd0);
        write_parameter(7'd21, 14'd16383);
        write_parameter(7'd22, 14'd0);
        write_parameter(7'd23, 14'd8192);
        write_parameter(7'd24, 14'd8192);

        // 三条路由：A WT 正向、A Warp 反向、Cutoff 正向。
        configure_route(3'd0, 1'b1, 4'd1, 14'd16383, 2'd0);
        configure_route(3'd1, 1'b1, 4'd2, 14'd0, 2'd0);
        configure_route(3'd2, 1'b1, 4'd8, 14'd16383, 2'd0);
        configure_route(3'd3, 1'b1, 4'd4, 14'd16383, 2'd1);
        configure_route(3'd4, 1'b1, 4'd6, 14'd16383, 2'd2);
        write_parameter(7'd25, 14'd1);

        // 直接给路由器半幅正值，验证方向、Q7.8 Cutoff 和限幅。
        route_sample(15'sd4096, -15'sd2048, 15'sd1024);
        if (mod_osc_a_wt !== 7'd127 || mod_osc_a_warp !== 7'd0) begin
            $display("ERROR: route polarity or saturation is wrong: wt=%0d warp=%0d",
                     mod_osc_a_wt, mod_osc_a_warp);
            errors = errors + 1;
        end
        if (mod_filter_cutoff_q8 !== 15'd24574) begin
            $display("ERROR: cutoff Q7.8 route got %0d expected 24574",
                     mod_filter_cutoff_q8);
            errors = errors + 1;
        end
        if (mod_osc_b_wt !== 7'd0 || mod_osc_b_level !== 7'd95) begin
            $display("ERROR: per-route LFO source selection is wrong: b_wt=%0d b_level=%0d",
                     mod_osc_b_wt, mod_osc_b_level);
            errors = errors + 1;
        end
        if (mod_filter_resonance !== base_filter_resonance
            || mod_filter_mix !== base_filter_mix) begin
            $display("ERROR: unassigned destinations did not preserve base values");
            errors = errors + 1;
        end

        // Comb 模式保持原有约 70/127 的 Cutoff LFO 深度限制。
        filter_mode = 3'd5;
        route_sample(15'sd4096, -15'sd2048, 15'sd1024);
        if (mod_filter_cutoff_q8 !== 15'd17212) begin
            $display("ERROR: comb depth scaling got %0d expected 17212",
                     mod_filter_cutoff_q8);
            errors = errors + 1;
        end

        // 曲线源应自行推进，并在约 5.33 ms 后完成启用淡入。
        for (sample_index = 0; sample_index < 540;
             sample_index = sample_index + 1)
            pulse_sample();
        if (!lfo_enabled || valid_count != 540 || segment_phase == 24'd0
            || curve_value_q13 == 15'sd0) begin
            $display("ERROR: curve LFO did not advance correctly");
            errors = errors + 1;
        end

        // 关闭后同样平滑退回零，不修改任何参数基础值。
        write_parameter(7'd16, 14'd0);
        write_parameter(7'd25, 14'd1);
        for (sample_index = 0; sample_index < 540;
             sample_index = sample_index + 1)
            pulse_sample();
        if (lfo_enabled || curve_value_q13 !== 15'sd0) begin
            $display("ERROR: disabled curve LFO did not return to zero");
            errors = errors + 1;
        end

        if (route_overrun) begin
            $display("ERROR: modulation router exceeded its cycle budget");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: generic curve LFO and eight-slot modulation router");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
