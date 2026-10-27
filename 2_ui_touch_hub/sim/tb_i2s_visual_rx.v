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
    wire signed [15:0] sample_right;
    wire stereo_valid;
    integer pairs;
    integer errors;
    integer sample_count;
    reg signed [15:0] expected_sample;

    i2s_visual_rx #(.LINK_TIMEOUT_CYCLES(200)) dut(
        .clk(clk), .rst_n(rst_n), .i2s_bclk(bclk), .i2s_lrc(lrc),
        .i2s_din(din), .sample(sample), .sample_valid(sample_valid),
        .link_up(link_up),.sample_right(sample_right),.stereo_valid(stereo_valid)
    );

    always #10 clk=~clk;

    task pulse_bclk;
        begin
            #50 bclk=1'b0;
            #50 bclk=1'b1;
            #50 bclk=1'b0;
        end
    endtask

    task short_channel;
        input channel;
        integer n;
        begin
            lrc=channel;din=0;pulse_bclk();
            for(n=0;n<4;n=n+1)begin din=n[0];pulse_bclk();end
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
        if(stereo_valid)begin
            if((pairs==0 && {sample,sample_right}!==32'hA55A1234) ||
               (pairs==1 && {sample,sample_right}!==32'h5AA5F00D) || pairs>1)
                $fatal(1,"Stereo channel pairing mismatch: %h %h",sample,sample_right);
            pairs=pairs+1;
        end
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
        errors=0; sample_count=0; pairs=0; expected_sample=16'shA55A;
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
        // Allow the final right bit to cross the synchronizer and then the
        // registered output pulse to reach the scoreboard.
        repeat(6)@(negedge clk);

        if(pairs!=2)$fatal(1,"Expected two distinct stereo pairs, got %0d",pairs);
        if(sample_count!=2) begin
            $display("ERROR: expected two decoded left samples, got %0d",sample_count);
            errors=errors+1;
        end
        if(!link_up) begin
            $display("ERROR: link_up did not assert during I2S traffic");
            errors=errors+1;
        end
        // A complete left word followed by a broken right and broken left
        // must not later be paired with a right word from another frame.
        expected_sample=16'h2468;
        send_channel(1'b0,16'h2468,1'b1);
        short_channel(1'b1);short_channel(1'b0);
        send_channel(1'b1,16'hABCD,1'b0);
        repeat(6)@(negedge clk);
        if(pairs!=2 || sample_count!=3)$fatal(1,"Short slots reused an unmatched left word");
        repeat(230) @(posedge clk);
        if(link_up) begin
            $display("ERROR: link_up did not time out");
            errors=errors+1;
        end
        if(errors==0) $display("PASS: I2S visualization receiver, distinct L/R pairing, short-slot rejection and link timeout");
        else $fatal(1,"FAIL: %0d error(s)",errors);
        $finish;
    end
endmodule
