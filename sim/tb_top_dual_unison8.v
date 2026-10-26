`timescale 1ns/1ps

// 完整顶层容量验证：两个实体振荡器各使用32个TDM槽位，
// 两组同时打开8复音，每个音符使用Unison=8。
module tb_top_dual_unison8;

    localparam integer TEST_UART_BAUD = 2500000;
    localparam integer CLKS_PER_BIT   = 50000000 / TEST_UART_BAUD;

    reg sys_clk;
    reg rst_n;
    reg uart_rx;
    reg control_uart_rx;

    wire MAX_SD;
    wire MAX_GAIN;
    wire MAX_DIN;
    wire MAX_BCLK;
    wire MAX_LRC;
    wire VIS_BCLK;
    wire VIS_LRC;
    wire VIS_DIN;
    wire PA_EN;
    wire sd_clk;
    tri  sd_cmd;
    reg  sd_dat0;
    wire [14:0] ddr_addr;
    wire [2:0] ddr_bank;
    wire ddr_cs, ddr_ras, ddr_cas, ddr_we, ddr_ck, ddr_ck_n;
    wire ddr_cke, ddr_odt, ddr_reset_n;
    wire [3:0] ddr_dm;
    tri [31:0] ddr_dq;
    tri [3:0] ddr_dqs, ddr_dqs_n;

    integer errors;
    integer note_index;
    integer sample_count;
    integer valid_count;

    top #(
        .UART_BAUD_RATE(TEST_UART_BAUD),
        .CONTROL_UART_BAUD_RATE(TEST_UART_BAUD),
        .DEFAULT_UNISON_COUNT(1),
        .OSC_ENGINE_COUNT(2),
        .SLOTS_PER_ENGINE(32),
        .EXTERNAL_WAVETABLE_ENABLE(0)
    ) dut (
        .sys_clk (sys_clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .control_uart_rx(control_uart_rx),
        .MAX_SD  (MAX_SD),
        .MAX_GAIN(MAX_GAIN),
        .MAX_DIN (MAX_DIN),
        .MAX_BCLK(MAX_BCLK),
        .MAX_LRC (MAX_LRC),
        .VIS_BCLK(VIS_BCLK),
        .VIS_LRC (VIS_LRC),
        .VIS_DIN (VIS_DIN),
        .PA_EN   (PA_EN),
        .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0),
        .ddr_addr(ddr_addr), .ddr_bank(ddr_bank), .ddr_cs(ddr_cs),
        .ddr_ras(ddr_ras), .ddr_cas(ddr_cas), .ddr_we(ddr_we),
        .ddr_ck(ddr_ck), .ddr_ck_n(ddr_ck_n), .ddr_cke(ddr_cke),
        .ddr_odt(ddr_odt), .ddr_reset_n(ddr_reset_n), .ddr_dm(ddr_dm),
        .ddr_dq(ddr_dq), .ddr_dqs(ddr_dqs), .ddr_dqs_n(ddr_dqs_n)
    );

    always #10 sys_clk = ~sys_clk;

    always @(posedge sys_clk) begin
        #1;
        if (dut.osc_a_mix_valid != dut.osc_b_mix_valid)
            errors = errors + 1;
        if (dut.osc_a_mix_valid && dut.osc_b_mix_valid)
            valid_count = valid_count + 1;
        if ((VIS_BCLK !== MAX_BCLK) ||
            (VIS_LRC  !== MAX_LRC)  ||
            (VIS_DIN  !== MAX_DIN))
            errors = errors + 1;
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

    task send_control_byte;
        input [7:0] value;
        integer bit_number;
        begin
            @(negedge sys_clk);
            control_uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);
            for (bit_number = 0; bit_number < 8;
                 bit_number = bit_number + 1) begin
                control_uart_rx = value[bit_number];
                repeat (CLKS_PER_BIT) @(negedge sys_clk);
            end
            control_uart_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge sys_clk);
        end
    endtask

    task send_cc;
        input [6:0] controller;
        input [6:0] value;
        begin
            send_uart_byte(8'hBF); // MIDI通道16（内部编号15）
            send_uart_byte({1'b0, controller});
            send_uart_byte({1'b0, value});
        end
    endtask

    task send_note_on;
        input [6:0] note;
        begin
            send_uart_byte(8'h90); // MIDI通道1（内部编号0）
            send_uart_byte({1'b0, note});
            send_uart_byte(8'h7F);
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        rst_n = 1'b0;
        uart_rx = 1'b1;
        control_uart_rx = 1'b1;
        sd_dat0 = 1'b1;
        errors = 0;
        valid_count = 0;

        repeat (8) @(posedge sys_clk);
        @(negedge sys_clk);
        rst_n = 1'b1;
        repeat (8) @(posedge sys_clk);

        // 两个振荡器分别设置为Unison=8并保持启用。
        send_cc(7'd23, 7'd8);
        send_cc(7'd31, 7'd8);
        // 127 对应当前三维 Acid 波表。
        send_cc(7'd21, 7'd127);
        send_cc(7'd29, 7'd127);
        send_cc(7'd20, 7'd64);
        send_cc(7'd28, 7'd64);
        send_cc(7'd36, 7'd127);
        send_cc(7'd37, 7'd127);
        repeat (20) @(posedge sys_clk);

        if (dut.osc_a_unison_count !== 4'd8
            || dut.osc_b_unison_count !== 4'd8
            || dut.osc_a_waveform_select !== 3'd4
            || dut.osc_b_waveform_select !== 3'd4
            || dut.osc_a_enabled !== 1'b1
            || dut.osc_b_enabled !== 1'b1) begin
            $display("ERROR: two oscillator controls did not reach Unison=8/enabled");
            errors = errors + 1;
        end

        // 新增演奏音高CC必须通过原共享UART到达控制寄存器。
        send_cc(7'd82, 7'd127);
        send_cc(7'd83, 7'd73);
        send_cc(7'd84, 7'd41);
        send_cc(7'd85, 7'd127);
        send_cc(7'd86, 7'd92);
        repeat (20) @(posedge sys_clk);
        if (!dut.vibrato_enable || dut.vibrato_rate !== 7'd73
            || dut.vibrato_depth !== 7'd41 || !dut.portamento_enable
            || dut.portamento_time !== 7'd92) begin
            $display("ERROR: vibrato/portamento controls did not reach top");
            errors = errors + 1;
        end
        // 后续容量测试保持原复音模式，避免改变既有64任务验收条件。
        send_cc(7'd82, 7'd0);
        send_cc(7'd85, 7'd0);

        // 两路UART同拍完成CC，验证两条指令均保留。
        fork
            send_cc(7'd46, 7'd73);
            begin
                send_control_byte(8'hBF);
                send_control_byte(8'd47);
                send_control_byte(8'd91);
            end
        join
        repeat (20) @(posedge sys_clk);
        if (dut.osc_a_level !== 7'd73 || dut.osc_b_level !== 7'd91
            || dut.control_event_overflow) begin
            $display("ERROR: dual UART CC collision"); errors = errors + 1;
        end
        // 独立控制口接收高精度SysEx。
        send_control_byte(8'hF0); send_control_byte(8'h7D);
        send_control_byte(8'd26); send_control_byte(8'd0);
        send_control_byte(8'd5); send_control_byte(8'hF7);
        repeat (20) @(posedge sys_clk);
        if (dut.u_lfo_modulation_router.shadow_route_index !== 3'd5) begin
            $display("ERROR: external SysEx parser"); errors = errors + 1;
        end

        // 每发一个音符等待两组调度器空闲，避免测试UART吞掉事件。
        for (note_index = 0; note_index < 8; note_index = note_index + 1) begin
            send_note_on(7'd48 + note_index);
            repeat (12000) @(posedge sys_clk);
            if (dut.osc_a_scheduler_busy || dut.osc_b_scheduler_busy) begin
                $display("ERROR: scheduler remained busy after note %0d", note_index);
                errors = errors + 1;
            end
        end

        repeat (200) @(posedge sys_clk);
        if (dut.osc_a_active_task_count !== 7'd64
            || dut.osc_b_active_task_count !== 7'd64) begin
            $display("ERROR: active tasks A=%0d B=%0d, expected 64/64",
                     dut.osc_a_active_task_count,
                     dut.osc_b_active_task_count);
            errors = errors + 1;
        end

        // 按住音符改变Detune，验证已分配槽位的步进随之变化。
        send_cc(7'd22, 7'd0);
        repeat (2000) @(posedge sys_clk);
        wait (dut.u_osc_a_tdm_bank.GEN_ENGINE[0].u_oscillator_tdm_core.pipe_valid && dut.u_osc_a_tdm_bank.GEN_ENGINE[0].u_oscillator_tdm_core.pipe_slot == 0);
        #1;
        if (dut.u_osc_a_tdm_bank.GEN_ENGINE[0].u_oscillator_tdm_core.pipe_phase_step !== dut.u_osc_a_tdm_bank.GEN_ENGINE[0].u_oscillator_tdm_core.base_step_state[0]) begin
            $display("ERROR: live detune zero did not restore base"); errors = errors + 1;
        end
        send_cc(7'd22, 7'd127);
        repeat (2000) @(posedge sys_clk);
        wait (dut.u_osc_a_tdm_bank.GEN_ENGINE[0].u_oscillator_tdm_core.pipe_valid && dut.u_osc_a_tdm_bank.GEN_ENGINE[0].u_oscillator_tdm_core.pipe_slot == 0);
        #1;
        if (dut.u_osc_a_tdm_bank.GEN_ENGINE[0].u_oscillator_tdm_core.pipe_phase_step >= dut.u_osc_a_tdm_bank.GEN_ENGINE[0].u_oscillator_tdm_core.base_step_state[0]
            || dut.osc_a_active_task_count !== 7'd64) begin
            $display("ERROR: held voice live detune did not change step"); errors = errors + 1;
        end

        // 保持一段时间，确认两个完整Bank都能持续产生同步采样。
        sample_count = 0;
        while (sample_count < 2000) begin
            @(posedge sys_clk);
            if (dut.osc_a_mix_valid && dut.osc_b_mix_valid)
                sample_count = sample_count + 1;
        end

        if (valid_count == 0) begin
            $display("ERROR: no dual oscillator mix samples were produced");
            errors = errors + 1;
        end
        if (dut.oscillator_schedule_overrun !== 1'b0
            || dut.osc_a_schedule_overrun !== 1'b0
            || dut.osc_b_schedule_overrun !== 1'b0) begin
            $display("ERROR: oscillator schedule overrun detected");
            errors = errors + 1;
        end
        if (dut.uart_framing_error !== 1'b0) begin
            $display("ERROR: UART framing error detected");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: top dual oscillator, 8 voices x Unison=8, 64 tasks per bank");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #300000000;
        $display("FAIL: top dual Unison=8 test timed out");
        $finish;
    end

endmodule
