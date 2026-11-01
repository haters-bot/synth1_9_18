`timescale 1ns/1ps

module tb_ribbon_pitch_path;
    reg clk;
    reg rst_n;
    reg sample_valid;
    reg [2:0] sample_channel;
    reg signed [23:0] sample_data;
    wire sample_ready;
    wire pitch_event_valid;
    wire pitch_event_ready;
    wire pitch_event_on;
    wire [2:0] pitch_event_source;
    wire [14:0] pitch_event_q8;
    wire [6:0] pitch_event_velocity;
    wire step_event_valid;
    wire step_event_on;
    wire [2:0] step_event_source;
    wire [31:0] step_event_base_step;
    wire [6:0] step_event_velocity;

    integer errors;
    integer gate_on_events;
    integer gate_off_events;
    integer pitch_update_events;
    reg [31:0] first_step;
    reg [31:0] latest_step;

    ribbon_pitch_processor dut_processor (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_channel(sample_channel),
        .sample_data(sample_data),
        .sample_ready(sample_ready),
        .event_valid(pitch_event_valid),
        .event_ready(pitch_event_ready),
        .event_on(pitch_event_on),
        .event_source(pitch_event_source),
        .event_pitch_q8(pitch_event_q8),
        .event_velocity(pitch_event_velocity)
    );

    ribbon_pitch_to_step dut_converter (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(pitch_event_valid),
        .in_ready(pitch_event_ready),
        .in_on(pitch_event_on),
        .in_source(pitch_event_source),
        .in_pitch_q8(pitch_event_q8),
        .in_velocity(pitch_event_velocity),
        .out_valid(step_event_valid),
        .out_ready(1'b1),
        .out_on(step_event_on),
        .out_source(step_event_source),
        .out_base_step(step_event_base_step),
        .out_velocity(step_event_velocity)
    );

    always #10 clk = ~clk;

    always @(posedge clk) begin
        if (step_event_valid) begin
            latest_step = step_event_base_step;
            if (step_event_on) begin
                if (gate_on_events == 0) begin
                    gate_on_events = 1;
                    first_step = step_event_base_step;
                end else begin
                    pitch_update_events = pitch_update_events + 1;
                end
            end else begin
                gate_off_events = gate_off_events + 1;
            end
        end
    end

    task send_sample;
        input [2:0] channel;
        input signed [23:0] value;
        begin
            while (!sample_ready)
                @(posedge clk);
            @(negedge clk);
            sample_channel = channel;
            sample_data = value;
            sample_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    integer i;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid = 1'b0;
        sample_channel = 3'd0;
        sample_data = 24'sd0;
        errors = 0;
        gate_on_events = 0;
        gate_off_events = 0;
        pitch_update_events = 0;
        first_step = 32'd0;
        latest_step = 32'd0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // 三次稳定触摸后产生Gate On，通道0左端应映射到C1。
        repeat (3) send_sample(3'd0, 24'sd1409286);
        repeat (20) @(posedge clk);
        if (gate_on_events != 1) begin
            $display("ERROR: expected one ribbon Gate On, got %0d",
                     gate_on_events);
            errors = errors + 1;
        end
        if (first_step != 32'h0002CA6A) begin
            $display("ERROR: C1 phase step is %h", first_step);
            errors = errors + 1;
        end

        // 向右滑动。滤波器应产生连续更新，且频率高于初始值。
        for (i = 0; i < 48; i = i + 1)
            send_sample(3'd0, 24'sd3858759);
        repeat (20) @(posedge clk);
        if (pitch_update_events == 0 || latest_step <= first_step) begin
            $display("ERROR: continuous pitch update was not generated");
            errors = errors + 1;
        end

        // 松手电压下降后，需连续低于阈值才触发一次Gate Off。
        for (i = 0; i < 48; i = i + 1)
            send_sample(3'd0, 24'sd0);
        repeat (20) @(posedge clk);
        if (gate_off_events != 1) begin
            $display("ERROR: expected one ribbon Gate Off, got %0d",
                     gate_off_events);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: ribbon debounce, filtering, mapping and phase-step conversion");
        else
            $display("FAIL: %0d ribbon path error(s)", errors);
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: ribbon pitch path test timed out");
        $finish;
    end
endmodule
