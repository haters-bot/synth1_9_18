`timescale 1ns/1ps

module tb_wavetable_phase_warp;

    reg  [7:0] raw_address;
    reg  [1:0] warp_mode;
    reg  [6:0] warp_amount;
    wire [7:0] warped_address;
    integer errors;
    integer address_index;

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

        // 关闭模式与PWM深度0都必须逐地址保持原波表。
        for (address_index = 0; address_index < 256;
             address_index = address_index + 1) begin
            raw_address = address_index[7:0];
            warp_mode = 2'd0;
            warp_amount = 7'd127;
            expect_address(address_index[7:0]);

            warp_mode = 2'd1;
            warp_amount = 7'd0;
            expect_address(address_index[7:0]);
        end

        // 最大PWM深度保持单调，并把方波翻转点推近3/4周期。
        warp_mode = 2'd1;
        warp_amount = 7'd127;
        raw_address = 8'd0;   expect_address(8'd0);
        raw_address = 8'd64;  expect_address(8'd127);
        raw_address = 8'd128; expect_address(8'd254);
        raw_address = 8'd255; expect_address(8'd255);

        // Sync深度0为1倍，最大深度为8倍并按8位地址自然回绕。
        warp_mode = 2'd2;
        warp_amount = 7'd0;
        raw_address = 8'd31; expect_address(8'd31);
        warp_amount = 7'd127;
        raw_address = 8'd1;  expect_address(8'd8);
        raw_address = 8'd31; expect_address(8'd248);
        raw_address = 8'd32; expect_address(8'd0);

        if (errors == 0)
            $display("PASS: PWM and Sync address mapping");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
