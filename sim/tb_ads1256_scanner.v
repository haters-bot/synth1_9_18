`timescale 1ns/1ps

module tb_ads1256_scanner;
    reg clk;
    reg rst_n;
    reg adc_drdy_n;
    reg adc_dout;
    wire adc_cs_n;
    wire adc_sclk;
    wire adc_din;
    wire adc_reset_n;
    wire sample_valid;
    wire [2:0] sample_channel;
    wire signed [23:0] sample_data;
    wire initialized;
    integer errors;
    integer sample_count;
    time last_sclk_fall;
    reg have_sclk_fall;
    localparam [23:0] TEST_WORD = 24'hA5C33C;

    // 模拟ADC在SCLK上升沿改变DOUT，主机在下降沿采样。
    always @(posedge adc_sclk) begin
        if (dut.sequence_kind == 4'd8)
            adc_dout <= TEST_WORD[16 - 8*dut.sequence_index + dut.spi_bit_index];
    end
    always @(negedge adc_sclk) begin
        if (rst_n && !adc_cs_n) begin
            last_sclk_fall = $time;
            have_sclk_fall = 1'b1;
        end
    end
    always @(posedge adc_cs_n) begin
        if (rst_n && have_sclk_fall && ($time - last_sclk_fall < 2000)) begin
            $display("ERROR: CS released before 2 us hold time");
            errors = errors + 1;
        end
        have_sclk_fall = 1'b0;
    end

    ads1256_scanner #(
        .SYS_CLK_HZ(20000000),
        .SCLK_HZ(2000000),
        .POWERUP_DELAY_CYCLES(4),
        .RESET_DELAY_CYCLES(4),
        .COMMAND_DELAY_CYCLES(2),
        .RDATA_DELAY_CYCLES(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .adc_drdy_n(adc_drdy_n),
        .adc_dout(adc_dout),
        .adc_cs_n(adc_cs_n),
        .adc_sclk(adc_sclk),
        .adc_din(adc_din),
        .adc_reset_n(adc_reset_n),
        .sample_valid(sample_valid),
        .sample_ready(1'b1),
        .sample_channel(sample_channel),
        .sample_data(sample_data),
        .initialized(initialized)
    );

    always #25 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n && (dut.state == 6'd21 || dut.state == 6'd22
                      || (dut.state == 6'd23 && !dut.sequence_done)) && adc_cs_n) begin
            $display("ERROR: CS released during RDATA transaction");
            errors = errors + 1;
        end
        if (sample_valid) begin
            if (sample_channel !== sample_count[2:0]) begin
                $display("ERROR: sample %0d came from channel %0d",
                         sample_count, sample_channel);
                errors = errors + 1;
            end
            if (sample_data !== TEST_WORD) begin
                $display("ERROR: DOUT word mismatch %h", sample_data);
                errors = errors + 1;
            end
            sample_count = sample_count + 1;
        end
    end

    task pulse_drdy;
        begin
            adc_drdy_n = 1'b1;
            repeat (4) @(posedge clk);
            adc_drdy_n = 1'b0;
            repeat (4) @(posedge clk);
        end
    endtask

    integer channel_index;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        adc_drdy_n = 1'b1;
        adc_dout = 1'b0;
        errors = 0;
        sample_count = 0;
        have_sclk_fall = 0;
        last_sclk_fall = 0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        wait (dut.state == 6'd11);
        pulse_drdy();

        for (channel_index = 0; channel_index < 6;
             channel_index = channel_index + 1) begin
            wait (dut.state == 6'd18);
            pulse_drdy();
            wait (sample_count == channel_index + 1);
        end

        if (!initialized) begin
            $display("ERROR: scanner did not report initialization");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: ADS1256 CS hold, RDATA transaction, nonzero data and scan order");
        else
            $display("FAIL: %0d ADS1256 scanner error(s)", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: ADS1256 scanner test timed out at state %0d", dut.state);
        $finish;
    end
endmodule
