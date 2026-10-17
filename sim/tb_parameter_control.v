`timescale 1ns/1ps

module tb_parameter_control;

    reg clk;
    reg rst_n;
    reg sample_tick;
    reg [7:0] byte_data;
    reg byte_valid;

    wire parameter_valid;
    wire [6:0] parameter_id;
    wire [13:0] parameter_value;
    wire [14:0] current_value;
    wire busy;

    integer errors;
    integer index;
    reg [14:0] previous_value;

    highres_parameter_parser u_parser (
        .clk            (clk),
        .rst_n          (rst_n),
        .byte_data      (byte_data),
        .byte_valid     (byte_valid),
        .parameter_valid(parameter_valid),
        .parameter_id   (parameter_id),
        .parameter_value(parameter_value)
    );

    parameter_linear_interpolator #(
        .VALUE_WIDTH(15),
        .INTERPOLATION_SHIFT(9),
        .RESET_VALUE({7'd127, 8'd0})
    ) u_interpolator (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_tick  (sample_tick),
        .target_valid (parameter_valid && (parameter_id == 7'd1)),
        .target_value ({parameter_value, 1'b0}),
        .current_value(current_value),
        .busy         (busy)
    );

    always #5 clk = ~clk;

    task send_byte;
        input [7:0] value;
        begin
            @(negedge clk);
            byte_data = value;
            byte_valid = 1'b1;
            @(negedge clk);
            byte_valid = 1'b0;
        end
    endtask

    task send_parameter;
        input [6:0] id;
        input [13:0] value;
        begin
            send_byte(8'hF0);
            send_byte(8'h7D);
            send_byte({1'b0, id});
            send_byte({1'b0, value[13:7]});
            send_byte({1'b0, value[6:0]});
            send_byte(8'hF7);
        end
    endtask

    task send_parameter_with_realtime;
        input [6:0] id;
        input [13:0] value;
        begin
            send_byte(8'hF0);
            send_byte(8'h7D);
            send_byte({1'b0, id});
            send_byte(8'hF8);
            send_byte({1'b0, value[13:7]});
            send_byte({1'b0, value[6:0]});
            send_byte(8'hF7);
        end
    endtask

    task pulse_sample;
        begin
            @(negedge clk);
            sample_tick = 1'b1;
            @(negedge clk);
            sample_tick = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_tick = 1'b0;
        byte_data = 8'd0;
        byte_valid = 1'b0;
        errors = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Q7.7的80.5应被转换成Q7.8的80.5。
        send_parameter(7'd1, 14'd10304);
        @(posedge clk);
        #1;
        if (!busy || current_value !== {7'd127, 8'd0}) begin
            $display("ERROR: interpolation did not start from reset value");
            errors = errors + 1;
        end

        previous_value = current_value;
        for (index = 0; index < 512; index = index + 1) begin
            pulse_sample();
            if (current_value > previous_value) begin
                $display("ERROR: downward interpolation reversed at %0d", index);
                errors = errors + 1;
            end
            previous_value = current_value;
        end

        if (current_value !== 15'd20608 || busy) begin
            $display("ERROR: endpoint got %0d, expected 20608", current_value);
            errors = errors + 1;
        end

        send_parameter_with_realtime(7'd1, 14'd10304);
        @(posedge clk);
        #1;
        if (!busy) begin
            $display("ERROR: realtime byte interrupted high-resolution frame");
            errors = errors + 1;
        end

        // 不完整帧不能提交参数。
        send_byte(8'hF0);
        send_byte(8'h7D);
        send_byte(8'h01);
        send_byte(8'h20);
        send_byte(8'hF7);
        repeat (3) @(posedge clk);
        if (parameter_valid) begin
            $display("ERROR: incomplete frame was accepted");
            errors = errors + 1;
        end

        // 插值过程中允许新目标覆盖，并从当前值连续起步。
        send_parameter(7'd1, 14'd16256);
        repeat (100) pulse_sample();
        previous_value = current_value;
        send_parameter(7'd1, 14'd0);
        pulse_sample();
        if (current_value > previous_value) begin
            $display("ERROR: retarget did not reverse smoothly");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: high-resolution parameter parser and interpolation");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
