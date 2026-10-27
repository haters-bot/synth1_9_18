`timescale 1ns/1ps

module tb_i2s_visual_rx;
    reg clk;
    reg rst_n;
    reg bclk;
    reg lrc;
    reg din;
    wire signed [15:0] sample;
    wire sample_valid;
    wire link_up;
    integer errors;
    integer sample_count;
    reg signed [15:0] expected_sample;

    i2s_visual_rx #(.LINK_TIMEOUT_CYCLES(200)) dut(
        .clk(clk), .rst_n(rst_n), .i2s_bclk(bclk), .i2s_lrc(lrc),
        .i2s_din(din), .sample(sample), .sample_valid(sample_valid),
        .link_up(link_up)
    );

    always #10 clk=~clk;

    task pulse_bclk;
        begin
            #50 bclk=1'b0;
            #50 bclk=1'b1;
            #50 bclk=1'b0;
        end
    endtask

    task send_channel;
        input channel;
        input [15:0] word;
        input [0:0] previous_lsb;
        integer i;
        begin
            // WS transition and the old channel LSB occupy the first slot.
            lrc=channel;
            din=previous_lsb;
            pulse_bclk();
            for(i=15;i>=0;i=i-1) begin
                din=word[i];
                pulse_bclk();
            end
        end
    endtask

    always @(posedge clk) begin
        if(sample_valid) begin
            sample_count=sample_count+1;
            if(sample!==expected_sample) begin
                $display("ERROR: expected sample %h got %h",expected_sample,sample);
                errors=errors+1;
            end
        end
    end

    initial begin
        clk=0; rst_n=0; bclk=0; lrc=1; din=0;
        errors=0; sample_count=0; expected_sample=16'shA55A;
        repeat(5) @(negedge clk);
        rst_n=1;
        // Establish the initial right slot before the first WS transition.
        pulse_bclk();

        // Left sample is exported; right is sent as the mirrored word.
        send_channel(1'b0,16'hA55A,1'b0);
        send_channel(1'b1,16'h1234,16'h0);
        expected_sample=16'sh5AA5;
        send_channel(1'b0,16'h5AA5,16'h0);
        send_channel(1'b1,16'hF00D,16'h1);

        if(sample_count!=2) begin
            $display("ERROR: expected two decoded left samples, got %0d",sample_count);
            errors=errors+1;
        end
        if(!link_up) begin
            $display("ERROR: link_up did not assert during I2S traffic");
            errors=errors+1;
        end
        repeat(230) @(posedge clk);
        if(link_up) begin
            $display("ERROR: link_up did not time out");
            errors=errors+1;
        end
        if(errors==0) $display("PASS: I2S visualization receiver decodes 16-bit left samples and link timeout");
        else $fatal(1,"FAIL: %0d error(s)",errors);
        $finish;
    end
endmodule
