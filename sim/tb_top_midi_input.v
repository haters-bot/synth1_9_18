`timescale 1ns/1ps

module tb_top_midi_input;

    localparam integer TEST_UART_BAUD = 2500000;
    localparam integer CLKS_PER_BIT   = 50000000 / TEST_UART_BAUD;

    reg sys_clk;
    reg rst_n;
    reg uart_rx;

    wire MAX_SD;
    wire MAX_GAIN;
    wire MAX_DIN;
    wire MAX_BCLK;
    wire MAX_LRC;
    wire PA_EN;

    integer errors;
    integer osc_a_update_count;
    integer osc_b_update_count;
    integer release_wait_cycles;
    integer silence_check_count;
    integer consecutive_silent_samples;
    integer wt_a_before;
    integer wt_b_before;
    integer valid_mismatch_count;
    integer switch_wait_samples;

    reg [7:0]  osc_a_slot_log [0:15];
    reg [31:0] osc_a_step_log [0:15];
    reg        osc_a_enable_log [0:15];
    reg [7:0]  osc_b_slot_log [0:15];
    reg [31:0] osc_b_step_log [0:15];
    reg        osc_b_enable_log [0:15];

    top #(
        .UART_BAUD_RATE(TEST_UART_BAUD),
        .DEFAULT_UNISON_COUNT(1)
    ) dut (
        .sys_clk (sys_clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .MAX_SD  (MAX_SD),
        .MAX_GAIN(MAX_GAIN),
        .MAX_DIN (MAX_DIN),
        .MAX_BCLK(MAX_BCLK),
        .MAX_LRC (MAX_LRC),
        .PA_EN   (PA_EN)
    );

    always #10 sys_clk = ~sys_clk;

    always @(posedge sys_clk) begin
        #1;
        if (dut.osc_a_task_update_valid) begin
            osc_a_slot_log[osc_a_update_count]
                = dut.osc_a_task_update_slot;
            osc_a_step_log[osc_a_update_count]
                = dut.osc_a_task_update_phase_step;
            osc_a_enable_log[osc_a_update_count]
                = dut.osc_a_task_update_enable;
            osc_a_update_count = osc_a_update_count + 1;
        end

        if (dut.osc_b_task_update_valid) begin
            osc_b_slot_log[osc_b_update_count]
                = dut.osc_b_task_update_slot;
            osc_b_step_log[osc_b_update_count]
                = dut.osc_b_task_update_phase_step;
            osc_b_enable_log[osc_b_update_count]
                = dut.osc_b_task_update_enable;
            osc_b_update_count = osc_b_update_count + 1;
        end

        if (dut.osc_a_mix_valid != dut.osc_b_mix_valid)
            valid_mismatch_count = valid_mismatch_count + 1;
    end

    task send_uart_byte;
        input [7:0] value;
        integer bit_number;
        begin
            @(negedge sys_clk);
            uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);

            for (bit_number = 0; bit_number < 8;
                 bit_number = bit_number + 1) begin
                uart_rx = value[bit_number];
                repeat (CLKS_PER_BIT) @(negedge sys_clk);
            end

            uart_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);
        end
    endtask

    task send_cc;
        input [6:0] controller;
        input [6:0] value;
        begin
            send_uart_byte(8'hBF);
            send_uart_byte({1'b0, controller});
            send_uart_byte({1'b0, value});
        end
    endtask

    task expect_a_update;
        input integer index;
        input [7:0] expected_slot;
        input [31:0] expected_step;
        input expected_enable;
        begin
            if (osc_a_slot_log[index] !== expected_slot
                || osc_a_step_log[index] !== expected_step
                || osc_a_enable_log[index] !== expected_enable) begin
                $display("ERROR: OSC A update %0d got slot=%0d step=%08x enable=%0d",
                         index, osc_a_slot_log[index],
                         osc_a_step_log[index],
                         osc_a_enable_log[index]);
                errors = errors + 1;
            end
        end
    endtask

    task expect_b_update;
        input integer index;
        input [7:0] expected_slot;
        input [31:0] expected_step;
        input expected_enable;
        begin
            if (osc_b_slot_log[index] !== expected_slot
                || osc_b_step_log[index] !== expected_step
                || osc_b_enable_log[index] !== expected_enable) begin
                $display("ERROR: OSC B update %0d got slot=%0d step=%08x enable=%0d",
                         index, osc_b_slot_log[index],
                         osc_b_step_log[index],
                         osc_b_enable_log[index]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        rst_n = 1'b0;
        uart_rx = 1'b1;
        errors = 0;
        osc_a_update_count = 0;
        osc_b_update_count = 0;
        valid_mismatch_count = 0;

        repeat (6) @(posedge sys_clk);
        @(negedge sys_clk);
        rst_n = 1'b1;
        repeat (6) @(posedge sys_clk);

        // 演奏通道上的CC不能修改控制参数。
        send_uart_byte(8'hB0);
        send_uart_byte(8'h17);
        send_uart_byte(8'h07);
        repeat (3) @(posedge sys_clk);
        if (dut.osc_a_unison_count !== 4'd1
            || dut.osc_b_unison_count !== 4'd1) begin
            $display("ERROR: performance-channel CC changed oscillator controls");
            errors = errors + 1;
        end

        // OSC A：3成员Unison和默认Detune；OSC B：2成员且Detune为0。
        send_cc(7'd20, 7'd85);
        send_cc(7'd21, 7'd127);
        send_cc(7'd22, 7'd64);
        send_cc(7'd23, 7'd3);
        send_cc(7'd24, 7'd12);
        send_cc(7'd25, 7'd34);
        send_cc(7'd26, 7'd56);
        send_cc(7'd27, 7'd0);

        send_cc(7'd28, 7'd42);
        send_cc(7'd29, 7'd0);
        send_cc(7'd30, 7'd0);
        send_cc(7'd31, 7'd2);
        send_cc(7'd32, 7'd7);
        send_cc(7'd33, 7'd8);
        send_cc(7'd34, 7'd100);
        send_cc(7'd35, 7'd0);

        repeat (3) @(posedge sys_clk);
        if (dut.osc_a_wt_position_target !== 7'd85
            || dut.osc_a_waveform_select !== 3'd4
            || dut.osc_a_detune_amount !== 7'd64
            || dut.osc_a_unison_count !== 4'd3
            || dut.osc_a_attack_control !== 7'd12
            || dut.osc_a_decay_control !== 7'd34
            || dut.osc_a_sustain_control_target !== 7'd56
            || dut.osc_a_release_control !== 7'd0) begin
            $display("ERROR: OSC A controls were not routed independently");
            errors = errors + 1;
        end

        if (dut.osc_b_wt_position_target !== 7'd42
            || dut.osc_b_waveform_select !== 3'd0
            || dut.osc_b_detune_amount !== 7'd0
            || dut.osc_b_unison_count !== 4'd2
            || dut.osc_b_attack_control !== 7'd7
            || dut.osc_b_decay_control !== 7'd8
            || dut.osc_b_sustain_control_target !== 7'd100
            || dut.osc_b_release_control !== 7'd0) begin
            $display("ERROR: OSC B controls were not routed independently");
            errors = errors + 1;
        end

        // 两组WT Position平滑器应分别朝自己的目标前进一步。
        wt_a_before = dut.osc_a_wt_position_current;
        wt_b_before = dut.osc_b_wt_position_current;
        @(posedge dut.sample_tick);
        @(posedge sys_clk);
        #1;
        if (dut.osc_a_wt_position_current !== (wt_a_before + 1)
            || dut.osc_b_wt_position_current !== (wt_b_before + 1)) begin
            $display("ERROR: independent WT Position smoothing failed");
            errors = errors + 1;
        end

        // 关闭OSC A后，A平滑降到0，仍开启的B平滑升到单位增益。
        send_cc(7'd36, 7'd0);
        switch_wait_samples = 0;
        while (((dut.osc_a_mix_gain_q8 != 9'd0)
                || (dut.osc_b_mix_gain_q8 != 9'd256))
               && (switch_wait_samples < 300)) begin
            @(posedge dut.sample_tick);
            switch_wait_samples = switch_wait_samples + 1;
        end
        @(posedge sys_clk);
        #1;
        if (dut.osc_a_enabled !== 1'b0
            || dut.osc_b_enabled !== 1'b1
            || dut.osc_a_mix_gain_q8 !== 9'd0
            || dut.osc_b_mix_gain_q8 !== 9'd256) begin
            $display("ERROR: OSC A switch did not reach muted crossfade state");
            errors = errors + 1;
        end
        force dut.osc_a_mix = 16'sd16000;
        force dut.osc_b_mix = -16'sd12000;
        #1;
        if (dut.oscillator_mix !== -16'sd12000) begin
            $display("ERROR: muted OSC A still contributed to the mix");
            errors = errors + 1;
        end
        release dut.osc_a_mix;
        release dut.osc_b_mix;

        // 从“仅B”切换到“仅A”，验证两个开关互相独立。
        send_cc(7'd36, 7'd127);
        send_cc(7'd37, 7'd0);
        switch_wait_samples = 0;
        while (((dut.osc_a_mix_gain_q8 != 9'd256)
                || (dut.osc_b_mix_gain_q8 != 9'd0))
               && (switch_wait_samples < 300)) begin
            @(posedge dut.sample_tick);
            switch_wait_samples = switch_wait_samples + 1;
        end
        @(posedge sys_clk);
        #1;
        if (dut.osc_a_enabled !== 1'b1
            || dut.osc_b_enabled !== 1'b0
            || dut.osc_a_mix_gain_q8 !== 9'd256
            || dut.osc_b_mix_gain_q8 !== 9'd0) begin
            $display("ERROR: OSC B switch did not reach muted crossfade state");
            errors = errors + 1;
        end
        force dut.osc_a_mix = 16'sd16000;
        force dut.osc_b_mix = -16'sd12000;
        #1;
        if (dut.oscillator_mix !== 16'sd16000) begin
            $display("ERROR: muted OSC B still contributed to the mix");
            errors = errors + 1;
        end
        release dut.osc_a_mix;
        release dut.osc_b_mix;

        // 后续音符测试恢复两路开启，各自回到0.5增益。
        send_cc(7'd37, 7'd127);
        switch_wait_samples = 0;
        while (((dut.osc_a_mix_gain_q8 != 9'd128)
                || (dut.osc_b_mix_gain_q8 != 9'd128))
               && (switch_wait_samples < 300)) begin
            @(posedge dut.sample_tick);
            switch_wait_samples = switch_wait_samples + 1;
        end
        @(posedge sys_clk);
        #1;
        if (dut.osc_a_enabled !== 1'b1
            || dut.osc_b_enabled !== 1'b1
            || dut.osc_a_mix_gain_q8 !== 9'd128
            || dut.osc_b_mix_gain_q8 !== 9'd128) begin
            $display("ERROR: dual oscillator gain did not return to 0.5 each");
            errors = errors + 1;
        end
        force dut.osc_a_mix = 16'sd16000;
        force dut.osc_b_mix = -16'sd12000;
        #1;
        if (dut.oscillator_mix !== 16'sd2000) begin
            $display("ERROR: dual oscillator 0.5 + 0.5 mix is incorrect");
            errors = errors + 1;
        end
        release dut.osc_a_mix;
        release dut.osc_b_mix;

        // 控制通道上的Note必须被丢弃。
        send_uart_byte(8'h9F);
        send_uart_byte(8'h30);
        send_uart_byte(8'h7F);
        repeat (40) @(posedge sys_clk);
        if (osc_a_update_count !== 0 || osc_b_update_count !== 0) begin
            $display("ERROR: control-channel note reached a scheduler");
            errors = errors + 1;
        end

        // 同一个中央C事件扇出到两个独立调度器。
        send_uart_byte(8'h90);
        send_uart_byte(8'h3C);
        send_uart_byte(8'h64);
        repeat (80) @(posedge sys_clk);

        if (osc_a_update_count !== 3 || osc_b_update_count !== 2) begin
            $display("ERROR: dual allocation counts A=%0d B=%0d",
                     osc_a_update_count, osc_b_update_count);
            errors = errors + 1;
        end

        expect_a_update(0, 8'd0, 32'h0016460E, 1'b1);
        expect_a_update(1, 8'd1, 32'h0016534C, 1'b1);
        expect_a_update(2, 8'd2, 32'h0016608A, 1'b1);
        expect_b_update(0, 8'd0, 32'h0016534C, 1'b1);
        expect_b_update(1, 8'd1, 32'h0016534C, 1'b1);

        if (dut.osc_a_active_task_count !== 6'd3
            || dut.osc_b_active_task_count !== 6'd2) begin
            $display("ERROR: active task counts A=%0d B=%0d",
                     dut.osc_a_active_task_count,
                     dut.osc_b_active_task_count);
            errors = errors + 1;
        end

        if (dut.u_osc_a_tdm_bank.GEN_ENGINE[0]
                .u_oscillator_tdm_core.enable_state[2] !== 1'b1
            || dut.u_osc_b_tdm_bank.GEN_ENGINE[0]
                .u_oscillator_tdm_core.enable_state[1] !== 1'b1) begin
            $display("ERROR: independent TDM banks did not receive updates");
            errors = errors + 1;
        end

        // Note Off也必须分别释放A的3个任务和B的2个任务。
        send_uart_byte(8'h80);
        send_uart_byte(8'h3C);
        send_uart_byte(8'h00);
        repeat (80) @(posedge sys_clk);

        if (osc_a_update_count !== 6 || osc_b_update_count !== 4) begin
            $display("ERROR: dual release counts A=%0d B=%0d",
                     osc_a_update_count, osc_b_update_count);
            errors = errors + 1;
        end
        expect_a_update(3, 8'd0, 32'h0016460E, 1'b0);
        expect_a_update(4, 8'd1, 32'h0016534C, 1'b0);
        expect_a_update(5, 8'd2, 32'h0016608A, 1'b0);
        expect_b_update(2, 8'd0, 32'h0016534C, 1'b0);
        expect_b_update(3, 8'd1, 32'h0016534C, 1'b0);

        release_wait_cycles = 0;
        while (((dut.osc_a_active_task_count != 6'd0)
                || (dut.osc_b_active_task_count != 6'd0))
               && (release_wait_cycles < 200000)) begin
            @(posedge sys_clk);
            release_wait_cycles = release_wait_cycles + 1;
        end

        if (dut.osc_a_active_task_count !== 6'd0
            || dut.osc_b_active_task_count !== 6'd0) begin
            $display("ERROR: released tasks did not return both banks to idle");
            errors = errors + 1;
        end

        // Bank流水线允许少量在途数据，随后双Bank混音必须稳定静音。
        silence_check_count = 0;
        consecutive_silent_samples = 0;
        while ((silence_check_count < 16)
               && (consecutive_silent_samples < 4)) begin
            @(posedge dut.oscillator_mix_valid);
            #1;
            if (dut.oscillator_mix === 16'sd0)
                consecutive_silent_samples
                    = consecutive_silent_samples + 1;
            else
                consecutive_silent_samples = 0;
            silence_check_count = silence_check_count + 1;
        end

        if (consecutive_silent_samples < 4) begin
            $display("ERROR: dual oscillator mix did not settle to silence");
            errors = errors + 1;
        end

        if (valid_mismatch_count != 0) begin
            $display("ERROR: OSC A/B valid pulses were misaligned %0d times",
                     valid_mismatch_count);
            errors = errors + 1;
        end

        if (dut.oscillator_schedule_overrun !== 1'b0) begin
            $display("ERROR: a 1x32 oscillator bank overran its schedule");
            errors = errors + 1;
        end

        if (dut.uart_framing_error !== 1'b0
            || MAX_SD !== 1'b1 || MAX_GAIN !== 1'b1
            || PA_EN !== 1'b1) begin
            $display("ERROR: UART or MAX98357A control state is incorrect");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: independent OSC A/B routing, scheduling, and mixing");
        else
            $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL: dual-oscillator top test timed out");
        $finish;
    end

endmodule
