`timescale 1ns/1ps

module tb_i2s_tx;

    reg sys_clk;
    reg rst_n;
    reg signed [15:0] left_sample_data;
    reg signed [15:0] right_sample_data;

    wire bclk;
    wire lrck;
    wire sdata;
    wire sample_tick;
    wire oversample_tick;

    integer errors;
    integer bit_index;

    i2s_tx dut (
        .sys_clk        (sys_clk),
        .rst_n          (rst_n),
        .left_sample_data (left_sample_data),
        .right_sample_data(right_sample_data),
        .bclk           (bclk),
        .lrck           (lrck),
        .sdata          (sdata),
        .sample_tick    (sample_tick),
        .oversample_tick(oversample_tick)
    );

    always #10 sys_clk = ~sys_clk;

    initial begin
        sys_clk     = 1'b0;
        rst_n       = 1'b0;
        left_sample_data  = 16'shA55A;
        right_sample_data = 16'sh3CC3;
        errors      = 0;

        repeat (4) @(posedge sys_clk);
        @(negedge sys_clk);
        rst_n = 1'b1;

        // 第一帧锁存测试字，第二帧开始检查完整的左右声道数据。
        @(posedge sample_tick);
        @(posedge sample_tick);

        // LRCK切换到左声道后的第一个BCLK仍承载上一右声道的LSB。
        @(posedge bclk);
        #1;
        if ((lrck !== 1'b0) || (sdata !== right_sample_data[0])) begin
            $display("ERROR: I2S left-channel delay bit is incorrect");
            errors = errors + 1;
        end

        // 标准I2S左声道：延迟一拍后按照MSB到LSB发送。
        for (bit_index = 15; bit_index >= 0; bit_index = bit_index - 1) begin
            @(posedge bclk);
            #1;
            if (sdata !== left_sample_data[bit_index]) begin
                $display("ERROR: left bit %0d expected %0b got %0b",
                         bit_index, left_sample_data[bit_index], sdata);
                errors = errors + 1;
            end

            if (lrck !== ((bit_index == 0) ? 1'b1 : 1'b0)) begin
                $display("ERROR: LRCK timing failed at left bit %0d", bit_index);
                errors = errors + 1;
            end
        end

        // 右声道按照MSB到LSB发送独立数据。
        for (bit_index = 15; bit_index >= 0; bit_index = bit_index - 1) begin
            @(posedge bclk);
            #1;
            if (sdata !== right_sample_data[bit_index]) begin
                $display("ERROR: right bit %0d expected %0b got %0b",
                         bit_index, right_sample_data[bit_index], sdata);
                errors = errors + 1;
            end

            if (lrck !== ((bit_index == 0) ? 1'b0 : 1'b1)) begin
                $display("ERROR: LRCK timing failed at right bit %0d", bit_index);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: standard 16-bit stereo I2S alignment");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: I2S transmitter test timed out");
        $finish;
    end

endmodule
