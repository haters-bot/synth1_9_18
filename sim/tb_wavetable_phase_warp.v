`timescale 1ns/1ps

module tb_wavetable_phase_warp;

    reg  [7:0] raw_address;
    reg  [3:0] warp_mode;
    reg  [6:0] warp_amount;
    wire [7:0] warped_address;
    integer errors;
    integer address_index;
    integer mode_index;

    wavetable_phase_warp dut (
        .raw_address(raw_address),
        .warp_mode(warp_mode),
        .warp_amount(warp_amount),
        .warped_address(warped_address)
    );

    task expect_address;
        input [7:0] expected;
        begin
            #1;
            if (warped_address !== expected) begin
                $display("ERROR: mode=%0d amount=%0d raw=%0d expected=%0d got=%0d",
                         warp_mode, warp_amount, raw_address,
                         expected, warped_address);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;

        // 关闭模式在任意深度下都必须保持原波表。
        for (address_index = 0; address_index < 256;
             address_index = address_index + 1) begin
            raw_address = address_index[7:0];
            warp_mode = 4'd0;
            warp_amount = 7'd127;
            expect_address(address_index[7:0]);
        end

        // 所有已定义模式的深度0都必须严格旁路，避免切换模式时跳音。
        for (mode_index = 1; mode_index <= 11;
             mode_index = mode_index + 1) begin
            for (address_index = 0; address_index < 256;
                 address_index = address_index + 1) begin
                raw_address = address_index[7:0];
                warp_mode = mode_index[3:0];
                warp_amount = 7'd0;
                expect_address(address_index[7:0]);
            end
        end

        // 最大PWM深度保持单调，并把方波翻转点推近3/4周期。
        warp_mode = 4'd1;
        warp_amount = 7'd127;
        raw_address = 8'd0;   expect_address(8'd0);
        raw_address = 8'd64;  expect_address(8'd127);
        raw_address = 8'd128; expect_address(8'd254);
        raw_address = 8'd255; expect_address(8'd255);

        // Sync深度0为1倍，最大深度为8倍并按8位地址自然回绕。
        warp_mode = 4'd2;
        warp_amount = 7'd0;
        raw_address = 8'd31; expect_address(8'd31);
        warp_amount = 7'd127;
        raw_address = 8'd1;  expect_address(8'd8);
        raw_address = 8'd31; expect_address(8'd248);
        raw_address = 8'd32; expect_address(8'd0);

        // Bend三种模式在最大深度下使用不同的分段曲线。
        warp_mode = 4'd3;
        warp_amount = 7'd127;
        raw_address = 8'd0;   expect_address(8'd0);
        raw_address = 8'd127; expect_address(8'd63);
        raw_address = 8'd128; expect_address(8'd64);
        raw_address = 8'd255; expect_address(8'd255);

        warp_mode = 4'd4;
        raw_address = 8'd0;   expect_address(8'd0);
        raw_address = 8'd127; expect_address(8'd190);
        raw_address = 8'd128; expect_address(8'd192);
        raw_address = 8'd255; expect_address(8'd255);

        warp_mode = 4'd5;
        raw_address = 8'd64;  expect_address(8'd32);
        raw_address = 8'd128; expect_address(8'd128);
        raw_address = 8'd192; expect_address(8'd224);

        // Asym只弯曲指定半周，未选中的半周保持原地址。
        warp_mode = 4'd6;
        raw_address = 8'd64;  expect_address(8'd96);
        raw_address = 8'd127; expect_address(8'd127);
        raw_address = 8'd192; expect_address(8'd192);

        warp_mode = 4'd7;
        raw_address = 8'd64;  expect_address(8'd64);
        raw_address = 8'd128; expect_address(8'd128);
        raw_address = 8'd192; expect_address(8'd160);

        warp_mode = 4'd8;
        raw_address = 8'd64;  expect_address(8'd96);
        raw_address = 8'd192; expect_address(8'd160);

        // Flip完全反向读取；Mirror先正向再反向读取同一周期。
        warp_mode = 4'd9;
        raw_address = 8'd0;   expect_address(8'd255);
        raw_address = 8'd64;  expect_address(8'd191);
        raw_address = 8'd255; expect_address(8'd0);

        warp_mode = 4'd10;
        raw_address = 8'd0;   expect_address(8'd0);
        raw_address = 8'd64;  expect_address(8'd128);
        raw_address = 8'd127; expect_address(8'd254);
        raw_address = 8'd128; expect_address(8'd254);
        raw_address = 8'd255; expect_address(8'd0);

        // Quantize最大深度只保留地址最高位。
        warp_mode = 4'd11;
        raw_address = 8'd127; expect_address(8'd0);
        raw_address = 8'd200; expect_address(8'd128);

        // 中间深度必须位于原地址和最大深度目标之间。
        warp_mode = 4'd3;
        warp_amount = 7'd64;
        raw_address = 8'd128; expect_address(8'd96);

        if (errors == 0)
            $display("PASS: all wavetable phase-warp address mappings");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
