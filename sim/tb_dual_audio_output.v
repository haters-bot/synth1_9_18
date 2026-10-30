`timescale 1ns/1ps

// 验证标准I2S与板载PT8211发送器共用同一个帧时序，且PT8211数据格式正确。
module tb_dual_audio_output;

    reg sys_clk;
    reg rst_n;
    reg signed [15:0] left_sample_data;
    reg signed [15:0] right_sample_data;

    wire max_bclk;
    wire max_lrck;
    wire max_din;
    wire max_sample_tick;
    wire max_oversample_tick;
    wire hp_bck;
    wire hp_ws;
    wire hp_din;
    wire hp_sample_tick;
    wire hp_oversample_tick;

    integer errors;
    integer bit_index;

    i2s_tx u_i2s_tx (
        .sys_clk(sys_clk), .rst_n(rst_n),
        .left_sample_data(left_sample_data),
        .right_sample_data(right_sample_data),
        .bclk(max_bclk), .lrck(max_lrck), .sdata(max_din),
        .sample_tick(max_sample_tick),
        .oversample_tick(max_oversample_tick)
    );

    pt8211_tx u_pt8211_tx (
        .sys_clk(sys_clk), .rst_n(rst_n),
        .left_sample_data(left_sample_data),
        .right_sample_data(right_sample_data),
        .bck(hp_bck), .ws(hp_ws), .din(hp_din),
        .sample_tick(hp_sample_tick),
        .oversample_tick(hp_oversample_tick)
    );

    always #10 sys_clk = ~sys_clk;

    // 两个发送器采用相同NCO。任何帧漂移都会使两路采样不同步。
    always @(posedge sys_clk) begin
        #1;
        if (rst_n) begin
            if (max_bclk !== hp_bck
                || max_sample_tick !== hp_sample_tick
                || max_oversample_tick !== hp_oversample_tick) begin
                $display("ERROR: onboard and external DAC timing diverged");
                errors = errors + 1;
            end
        end
    end

    initial begin
        sys_clk = 1'b0;
        rst_n = 1'b0;
        left_sample_data = 16'shA55A;
        right_sample_data = 16'sh3CC3;
        errors = 0;

        repeat (4) @(posedge sys_clk);
        @(negedge sys_clk);
        rst_n = 1'b1;

        // 第一帧锁存测试字，从第二帧开始检查完整的左右声道。
        @(posedge hp_sample_tick);
        @(posedge hp_sample_tick);

        // PT8211的WS低电平为右声道，16位数据按MSB到LSB发送。
        for (bit_index = 15; bit_index >= 0; bit_index = bit_index - 1) begin
            @(posedge hp_bck);
            #1;
            if (hp_ws !== 1'b0 || hp_din !== right_sample_data[bit_index]) begin
                $display("ERROR: PT8211 right bit %0d", bit_index);
                errors = errors + 1;
            end
        end

        // WS高电平发送独立左声道数据。
        for (bit_index = 15; bit_index >= 0; bit_index = bit_index - 1) begin
            @(posedge hp_bck);
            #1;
            if (hp_ws !== 1'b1 || hp_din !== left_sample_data[bit_index]) begin
                $display("ERROR: PT8211 left bit %0d", bit_index);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: simultaneous MAX98357A and onboard PT8211 output");
        else
            $display("FAIL: %0d dual-output error(s)", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: dual audio output test timed out");
        $finish;
    end

endmodule
