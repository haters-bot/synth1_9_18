`timescale 1ns/1ps

module tb_acid_wavetable_reader;

    reg clk;
    reg rst_n;
    reg req_valid;
    reg [7:0] phase_address;
    reg [6:0] wt_position;
    wire sample_valid;
    wire signed [15:0] sample_data;
    integer errors;

    acid_wavetable_reader dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .phase_address(phase_address),
        .wt_position(wt_position),
        .sample_valid(sample_valid),
        .sample_data(sample_data)
    );

    always #10 clk = ~clk;

    task request_and_expect;
        input [7:0] phase;
        input [6:0] position;
        input signed [15:0] expected;
        begin
            @(negedge clk);
            phase_address = phase;
            wt_position = position;
            req_valid = 1'b1;
            @(negedge clk);
            req_valid = 1'b0;
            #1;
            if (!sample_valid || sample_data !== expected) begin
                $display("ERROR: phase=%0d wt=%0d got valid=%0d data=%0d expected=%0d",
                         phase, position, sample_valid, sample_data, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        req_valid = 1'b0;
        phase_address = 8'd0;
        wt_position = 7'd0;
        errors = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        request_and_expect(8'd0, 7'd0, -16'sd995);
        request_and_expect(8'd0, 7'd4, -16'sd2528);
        request_and_expect(8'd0, 7'd8, -16'sd4061);
        request_and_expect(8'd255, 7'd0, -16'sd1018);
        request_and_expect(8'd255, 7'd120, -16'sd5101);

        if (errors == 0)
            $display("PASS: Acid ROM synchronous read and WT interpolation");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
