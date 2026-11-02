`timescale 1ns/1ps

// 按板级50 MHz/1 MHz运行的引脚协议审查，不读取dut内部状态。
// 这是协议测试模型，并非TI模拟模型；遇到违规仍继续解码，以收集所有问题。
module tb_ads1256_protocol_audit;
    reg clk = 0;
    reg rst_n = 0;
    reg drdy_n = 1;
    reg dout = 0;
    wire cs_n, sclk, din, reset_n, sample_valid, initialized;
    wire [2:0] sample_channel;
    wire signed [23:0] sample_data;
    ads1256_scanner #(.CHANNEL_COUNT(4)) dut (
        .clk(clk), .rst_n(rst_n), .adc_drdy_n(drdy_n), .adc_dout(dout),
        .adc_cs_n(cs_n), .adc_sclk(sclk), .adc_din(din),
        .adc_reset_n(reset_n), .sample_valid(sample_valid), .sample_ready(1'b1),
        .sample_channel(sample_channel), .sample_data(sample_data),
        .initialized(initialized), .debug_state(), .debug_drdy()
    );
    always #10 clk = ~clk;

    localparam CMD = 0, WCOUNT = 1, WDATA = 2, RDATA = 3;
    integer mode = CMD;
    integer bits = 0;
    integer address = 0;
    integer remaining = 0;
    integer read_bit = 23;
    reg [7:0] input_byte = 0;
    reg [7:0] regs [0:3];
    reg [23:0] read_word;
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
        regs[0] = 8'h00; regs[1] = 8'h01;
        regs[2] = 8'h20; regs[3] = 8'hF0;
        ready_at = $time + 596000;
        calibration_until = ready_at;
    end
    always @(posedge clk) begin
        drdy_n <= !reset_n || ($time < ready_at);
        if (rst_n && sample_valid) begin
            if (sample_channel !== (samples % 4)
                || sample_data !== channel_word(sample_channel)) begin
                data_errors = data_errors + 1;
                $display("AUDIT data FAIL: channel=%0d data=%h", sample_channel, sample_data);
            end
            samples = samples + 1;
            if (samples == 8) begin
                $display("AUDIT SUMMARY: samples=%0d hold=%0d setup=%0d calibration=%0d data=%0d t6=%0d sync=%0d",
                         samples, hold_errors, setup_errors, calibration_errors,
                         data_errors, read_delay_errors, sync_errors);
                $finish;
            end
        end
    end

    always @(posedge cs_n) begin
        bits = 0;
        mode = CMD;
    end

    task accept_byte;
        input [7:0] value;
        begin
            case (mode)
                WCOUNT: begin remaining = value + 1; mode = WDATA; end
                WDATA: begin
                    if (address < 4) begin
                        if ((address == 3 && regs[3] != value)
                            || (address == 2 && regs[2][2:0] != value[2:0])
                            || (address == 0 && regs[0][1] != value[1]))
                            auto_cal_needed = 1;
                        regs[address] = value;
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
                        8'hF0: begin ready_at=$time+696000; calibration_until=ready_at; end
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
                        end
                    endcase
                end
            endcase
        end
    endtask

    always @(posedge sclk) begin
        if (!cs_n && mode == RDATA) begin
            if (read_bit == 23 && $time-read_command_end < 6511)
                read_delay_errors = read_delay_errors + 1;
            // 使用独立位指针和输出延迟，避免按dut.sequence_index伪造正确数据。
            dout <= #50 read_word[read_bit];
        end
    end
    always @(negedge sclk) begin
        if (rst_n && reset_n && !cs_n) begin
            last_sclk_fall = $time;
            if ($time-last_din_change < 50) setup_errors = setup_errors + 1;
            if (mode == RDATA) begin
                if (read_bit == 0) begin mode=CMD; ready_at=$time+66667; end
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
        #60000000;
        $display("AUDIT TIMEOUT: samples=%0d hold=%0d calibration=%0d", samples, hold_errors, calibration_errors);
        $finish;
    end
endmodule
