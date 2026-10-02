`timescale 1ns/1ps

module tb_top_midi_input;

    // 仿真中提高串口速率，缩短运行时间；RTL默认值仍为标准MIDI 31250 bit/s。
    localparam integer TEST_UART_BAUD = 2500000;
    localparam integer CLKS_PER_BIT   = 50000000 / TEST_UART_BAUD;

    reg sys_clk;
    reg rst_n;
    reg uart_rx;

    wire HP_BCK;
    wire HP_WS;
    wire HP_DIN;
    wire PA_EN;

    integer errors;
    integer update_count;
    integer check_index;
    integer observed_active_count;
    reg [7:0] update_slot_log [0:15];
    reg [6:0] update_note_log [0:15];
    reg       update_enable_log [0:15];
    reg       update_reset_log [0:15];

    top #(
        .UART_BAUD_RATE(TEST_UART_BAUD)
    ) dut (
        .sys_clk(sys_clk),
        .rst_n  (rst_n),
        .uart_rx(uart_rx),
        .HP_BCK (HP_BCK),
        .HP_WS  (HP_WS),
        .HP_DIN (HP_DIN),
        .PA_EN  (PA_EN)
    );

    always #10 sys_clk = ~sys_clk;

    always @(posedge sys_clk) begin
        #1;
        if (dut.voice_update_valid) begin
            update_slot_log[update_count]   = dut.voice_update_slot;
            update_note_log[update_count]   = dut.voice_update_note;
            update_enable_log[update_count] = dut.voice_update_enable;
            update_reset_log[update_count]  = dut.voice_update_phase_reset;
            update_count = update_count + 1;
        end
    end

    task send_uart_byte;
        input [7:0] value;
        integer bit_number;
        begin
            @(negedge sys_clk);
            uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);

            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                uart_rx = value[bit_number];
                repeat (CLKS_PER_BIT) @(negedge sys_clk);
            end

            uart_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);
        end
    endtask

    task expect_update;
        input integer log_index;
        input [7:0] expected_slot;
        input [6:0] expected_note;
        input expected_enable;
        input expected_reset;
        begin
            if (update_slot_log[log_index] !== expected_slot
                || update_note_log[log_index] !== expected_note
                || update_enable_log[log_index] !== expected_enable
                || update_reset_log[log_index] !== expected_reset) begin
                $display("ERROR: update %0d got slot=%0d note=%0d enable=%0d reset=%0d",
                         log_index,
                         update_slot_log[log_index],
                         update_note_log[log_index],
                         update_enable_log[log_index],
                         update_reset_log[log_index]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        sys_clk      = 1'b0;
        rst_n        = 1'b0;
        uart_rx      = 1'b1;
        errors       = 0;
        update_count = 0;

        repeat (6) @(posedge sys_clk);
        @(negedge sys_clk);
        rst_n = 1'b1;
        repeat (6) @(posedge sys_clk);

        // Note On: MIDI 60，力度100，应占用槽位0并复位相位。
        send_uart_byte(8'h90);
        send_uart_byte(8'h3C);
        send_uart_byte(8'h64);

        // Running Status：省略第二个状态字节，MIDI 64应占用槽位1。
        send_uart_byte(8'h40);
        send_uart_byte(8'h50);

        // 实时Clock消息可以插入数据字节之间，且不破坏Running Status。
        send_uart_byte(8'h43);
        send_uart_byte(8'hF8);
        send_uart_byte(8'h60);

        // Note On velocity=0等价于Note Off，应让槽位0进入Release。
        send_uart_byte(8'h3C);
        send_uart_byte(8'h00);

        // 显式Note Off让槽位1进入Release。
        send_uart_byte(8'h80);
        send_uart_byte(8'h40);
        send_uart_byte(8'h00);

        // 超出88键查表范围的音符应被忽略。
        send_uart_byte(8'h90);
        send_uart_byte(8'h05);
        send_uart_byte(8'h64);

        repeat (20) @(posedge sys_clk);

        if (update_count !== 5) begin
            $display("ERROR: expected 5 voice updates, got %0d", update_count);
            errors = errors + 1;
        end

        expect_update(0, 8'd0, 7'd60, 1'b1, 1'b1);
        expect_update(1, 8'd1, 7'd64, 1'b1, 1'b1);
        expect_update(2, 8'd2, 7'd67, 1'b1, 1'b1);
        expect_update(3, 8'd0, 7'd60, 1'b0, 1'b0);
        expect_update(4, 8'd1, 7'd64, 1'b0, 1'b0);

        if (dut.u_oscillator_tdm_bank.GEN_ENGINE[0]
                .u_oscillator_tdm_core.enable_state[2] !== 1'b1
            || dut.u_midi_voice_allocator.slot_active[2] !== 1'b1) begin
            $display("ERROR: held note did not remain active");
            errors = errors + 1;
        end

        // 加速串口测试期间，短音可能已经完成Release，也可能仍在Release。
        // 若仍活动，则必须标记为releasing；活动计数必须与槽位状态一致。
        if ((dut.u_midi_voice_allocator.slot_active[0]
             && !dut.u_midi_voice_allocator.slot_releasing[0])
            || (dut.u_midi_voice_allocator.slot_active[1]
                && !dut.u_midi_voice_allocator.slot_releasing[1])) begin
            $display("ERROR: Note Off slot is active without Release state");
            errors = errors + 1;
        end

        observed_active_count = 0;
        for (check_index = 0; check_index < 32; check_index = check_index + 1)
            if (dut.u_midi_voice_allocator.slot_active[check_index])
                observed_active_count = observed_active_count + 1;

        if (dut.active_voice_count !== observed_active_count[5:0]) begin
            $display("ERROR: active voice count got %0d, expected %0d",
                     dut.active_voice_count, observed_active_count);
            errors = errors + 1;
        end

        if (dut.active_voice_count < 6'd1
            || dut.active_voice_count > 6'd3) begin
            $display("ERROR: active voice count outside expected range: %0d",
                     dut.active_voice_count);
            errors = errors + 1;
        end

        if (dut.uart_framing_error !== 1'b0) begin
            $display("ERROR: unexpected UART framing error");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: UART MIDI parsing and voice allocation");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: top MIDI input test timed out");
        $finish;
    end

endmodule
