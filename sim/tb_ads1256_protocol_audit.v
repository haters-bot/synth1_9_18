`timescale 1ns/1ps

// 按板级50 MHz/1 MHz运行的引脚协议审查，不读取dut内部状态。
// 独立协议模型（非TI模拟模型）：按器件时间检查，任何违规均判失败。
module tb_ads1256_protocol_audit #(parameter integer FAULT = 0);
    reg test_passed = 0;
    reg clk = 0;
    reg rst_n = 0;
    reg drdy_n = 1;
    reg dout = 0;
    wire cs_n, sclk, din, reset_n, sample_valid, initialized;
    wire [5:0] debug_state;
    reg sample_ready = 0;
    integer cycle = 0;
    reg held = 0;
    reg [26:0] held_sample;
    integer cs_errors = 0;
    integer fault_cycles = 0;
    integer config_reads = 0;
    integer calibrations = 0;
    wire [2:0] sample_channel;
    wire signed [23:0] sample_data;
    ads1256_scanner #(.CHANNEL_COUNT(4), .POWERUP_DELAY_CYCLES(50000),
        .DRDY_TIMEOUT_CYCLES(150000)) dut (
        .clk(clk), .rst_n(rst_n), .adc_drdy_n(drdy_n), .adc_dout(dout),
        .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_din(din),
        .adc_reset_n(reset_n), .sample_valid(sample_valid), .sample_ready(sample_ready),
        .sample_channel(sample_channel), .sample_data(sample_data),
        .initialized(initialized), .debug_state(debug_state), .debug_drdy()
    );
    always #10 clk = ~clk;

    localparam CMD = 0, WCOUNT = 1, WDATA = 2, RDATA = 3, RCOUNT = 4, RREG = 5;
    integer mode = CMD;
    integer bits = 0;
    integer address = 0;
    integer remaining = 0;
    integer read_bit = 23;
    reg [7:0] input_byte = 0;
    reg [7:0] regs [0:3];
    reg [23:0] read_word;
    reg [31:0] register_word;
    reg auto_cal_needed = 0;
    time last_din_change = 0;
    time last_sclk_fall = 0;
    time last_sync_end = 0;
    time read_command_end = 0;
    time ready_at = 0;
    time calibration_until = 0;
    integer hold_errors = 0;
    integer setup_errors = 0;
    integer calibration_errors = 0;
    integer data_errors = 0;
    integer read_delay_errors = 0;
    integer sync_errors = 0;
    integer samples = 0;

    function [23:0] channel_word;
        input [3:0] ch;
        case (ch)
            0: channel_word = 24'h13579B;
            1: channel_word = 24'h2468AC;
            2: channel_word = 24'h31A6E5;
            default: channel_word = 24'h42D80F;
        endcase
    endfunction

    // t5要求50 ns，不使用“一个系统时钟”替代器件时间规范。
    always @(din) begin
        if (rst_n && reset_n && !cs_n && last_sclk_fall != 0
            && ($time - last_sclk_fall < 50)) begin
            if (hold_errors < 3)
                $display("AUDIT t5 FAIL: DIN hold=%0d ns, required>=50 ns", $time-last_sclk_fall);
            hold_errors = hold_errors + 1;
        end
        last_din_change = $time;
    end

    always @(posedge reset_n) begin
        regs[0] = 8'h30; regs[1] = 8'h01;
        regs[2] = 8'h20; regs[3] = 8'hF0;
        ready_at = $time + 596000;
        calibration_until = ready_at;
    end
    always @(posedge clk) begin
        drdy_n <= (FAULT == 1) ? 1'b1 : (FAULT == 2) ? 1'b0 :
                  (FAULT == 6 && calibrations != 0) ? 1'b1 :
                  (FAULT == 7 && last_sync_end != 0) ? 1'b1 :
                  (!reset_n || ($time < ready_at));
        cycle = cycle + 1;
        // 周期性长背压跨越多个字节时间，检查valid和样本是否稳定。
        sample_ready <= ((cycle % 10000) >= 2500);
        if (held && (!sample_valid || {sample_channel,sample_data} !== held_sample))
            $fatal(1, "sample changed under backpressure");
        held = sample_valid && !sample_ready;
        held_sample = {sample_channel,sample_data};
        if (rst_n && debug_state >= 6'h3A) begin
            fault_cycles = fault_cycles + 1;
            if (fault_cycles > 2 && (initialized || sample_valid || !cs_n || sclk))
                $fatal(1, "fault did not stop scanner");
            if (fault_cycles == 100) begin
                if (((FAULT == 1 || FAULT == 2) && debug_state != 6'h3A)
                    || ((FAULT == 3 || FAULT == 5) && debug_state != 6'h3C)
                    || ((FAULT == 4 || FAULT == 8) && debug_state != 6'h3D)
                    || (FAULT == 6 && debug_state != 6'h3B)
                    || (FAULT == 7 && debug_state != 6'h3E)
                    || FAULT == 0) $fatal(1, "unexpected fault %h", debug_state);
                if (FAULT == 8 && samples < 4) $fatal(1, "runtime fault not exercised");
                if (FAULT != 8 && samples != 0) $fatal(1, "invalid samples escaped");
                check_protocol;
                $display("PASS ADS1256 fault=%0d state=%h samples=%0d", FAULT, debug_state, samples);
                test_passed = 1;
                wait (1'b0);
            end
        end
        if (rst_n && sample_valid && sample_ready) begin
            if (!initialized) $fatal(1, "sample before verified initialization");
            if (sample_channel !== (samples % 4)
                || sample_data !== channel_word(sample_channel)) begin
                data_errors = data_errors + 1;
                $display("AUDIT data FAIL: channel=%0d data=%h", sample_channel, sample_data);
            end
            samples = samples + 1;
            if (samples == 8 && FAULT == 0) begin
                $display("AUDIT SUMMARY: samples=%0d hold=%0d setup=%0d calibration=%0d data=%0d t6=%0d sync=%0d",
                         samples, hold_errors, setup_errors, calibration_errors,
                         data_errors, read_delay_errors, sync_errors);
                check_protocol;
                if (config_reads < 9 || calibrations != 1) $fatal(1, "missing readback/calibration");
                $display("PASS ADS1256 normal: 4 channels, 2 rounds, backpressure");
                test_passed = 1;
                wait (1'b0);
            end
        end
    end

    task check_protocol;
        begin
            if (hold_errors + setup_errors + calibration_errors + data_errors
                + read_delay_errors + sync_errors + cs_errors != 0)
                $fatal(1, "protocol violation");
        end
    endtask

    always @(posedge cs_n) begin
        if (rst_n && reset_n && last_sclk_fall != 0 && $time-last_sclk_fall < 1042)
            cs_errors = cs_errors + 1;
        if (mode == RDATA || mode == RREG) cs_errors = cs_errors + 1;
        bits = 0;
        mode = CMD;
    end

    task accept_byte;
        input [7:0] value;
        begin
            case (mode)
                RCOUNT: begin
                    if (value != 3 || address != 0) $fatal(1, "unexpected RREG");
                    register_word = {regs[0],regs[1],regs[2],regs[3]};
                    if (FAULT == 3) register_word[7:0] = 8'hF0;
                    if (FAULT == 4 || (FAULT == 8 && samples >= 4)) register_word[23:16] = 8'h78;
                    if (FAULT == 5) register_word = 32'hFFFFFFFF;
                    mode=RREG; read_bit=31; read_command_end=$time;
                    config_reads=config_reads+1;
                end
                WCOUNT: begin remaining = value + 1; mode = WDATA; end
                WDATA: begin
                    if (address < 4) begin
                        if ((address == 3 && regs[3] != value)
                            || (address == 2 && regs[2][2:0] != value[2:0])
                            || (address == 0 && regs[0][1] != value[1]))
                            auto_cal_needed = 1;
                        regs[address] = (address == 0) ? (8'h30 | (value & 8'h0E)) : value;
                    end
                    address = address + 1;
                    remaining = remaining - 1;
                    if (remaining == 0) begin
                        mode = CMD;
                        if (auto_cal_needed && regs[0][2]) begin
                            ready_at = $time + 696000;
                            calibration_until = ready_at;
                            $display("AUDIT: WREG starts automatic calibration at %0d ns", $time);
                        end
                    end
                end
                CMD: begin
                    if ($time < calibration_until) begin
                        calibration_errors = calibration_errors + 1;
                        $display("AUDIT calibration FAIL: command=%h arrives %0d ns before calibration ready",
                                 value, calibration_until-$time);
                    end
                    case (value)
                        8'hFE: begin ready_at=$time+596000; calibration_until=ready_at; end
                        8'hF0: begin calibrations=calibrations+1; ready_at=$time+696000; calibration_until=ready_at; end
                        8'hFC: begin last_sync_end=$time; ready_at=$time+100000000; end
                        8'h00, 8'hFF: begin
                            if (last_sync_end != 0 && $time-8000-last_sync_end < 3125)
                                sync_errors = sync_errors + 1;
                            ready_at=$time+250000;
                        end
                        8'h01: begin
                            read_word=channel_word(regs[1][7:4]);
                            mode=RDATA; read_bit=23; read_command_end=$time;
                        end
                        default: if (value[7:4] == 4'h5) begin
                            mode=WCOUNT; address=value[3:0]; auto_cal_needed=0;
                        end else if (value[7:4] == 4'h1) begin
                            mode=RCOUNT; address=value[3:0];
                        end else if (value != 8'h0F) $fatal(1, "unknown command %h", value);
                    endcase
                end
            endcase
        end
    endtask

    always @(posedge sclk) begin
        if (!cs_n && (mode == RDATA || mode == RREG)) begin
            if (((mode == RDATA && read_bit == 23) || (mode == RREG && read_bit == 31)) && $time-read_command_end < 6511)
                read_delay_errors = read_delay_errors + 1;
            // 使用独立位指针和输出延迟，避免按dut.sequence_index伪造正确数据。
            dout <= #50 ((mode == RDATA) ? read_word[read_bit] : register_word[read_bit]);
        end
    end
    always @(negedge sclk) begin
        if (rst_n && reset_n && !cs_n) begin
            last_sclk_fall = $time;
            if ($time-last_din_change < 50) setup_errors = setup_errors + 1;
            if (mode == RDATA || mode == RREG) begin
                if (read_bit == 0) begin
                    if (mode == RDATA) ready_at=$time+66667;
                    mode=CMD;
                end
                else read_bit=read_bit-1;
            end else begin
                input_byte={input_byte[6:0],din};
                bits=bits+1;
                if (bits == 8) begin bits=0; accept_byte(input_byte); end
            end
        end
    end

    initial begin
        #100 rst_n = 1;
        #20000000;
        if (!test_passed) begin
            $display("AUDIT TIMEOUT: samples=%0d hold=%0d calibration=%0d", samples, hold_errors, calibration_errors);
            $fatal(1, "test timeout");
        end
    end
endmodule
