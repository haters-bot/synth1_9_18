`timescale 1ns/1ps
module tb_performance_command_decoder;
    reg clk = 0;
    reg rst_n = 0;
    reg tick_1ms = 0;
    reg packet_valid = 0;
    reg [7:0] packet_type = 0;
    reg [6:0] packet_length = 0;
    reg [511:0] packet_payload = 0;
    reg page_active = 1;
    reg touch_valid = 0;
    reg touch_down = 0;
    reg [13:0] touch_x = 0, touch_y = 0;
    wire local_play, local_pause_toggle, local_stop;
    wire local_record_toggle;
    wire start_pulse, stop_pulse, pause_state;
    wire record_start_pulse, record_stop_pulse, recording;
    reg record_start_accepted=0,record_start_rejected=0,record_active=0,record_busy=0,record_done=0;

    always #10 clk = ~clk;

    performance_touch_controls controls(
        .clk(clk), .rst_n(rst_n), .page_active(page_active),
        .touch_valid(touch_valid), .touch_down(touch_down),
        .touch_x(touch_x), .touch_y(touch_y),
        .play(local_play), .pause_toggle(local_pause_toggle), .stop(local_stop),
        .record_toggle(local_record_toggle));

    performance_command_decoder dut(
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .packet_valid(packet_valid), .packet_type(packet_type),
        .packet_length(packet_length), .packet_payload(packet_payload),
        .local_play(local_play), .local_pause_toggle(local_pause_toggle),
        .local_stop(local_stop), .local_record_toggle(local_record_toggle),
        .record_start_accepted(record_start_accepted),.record_start_rejected(record_start_rejected),
        .record_active(record_active),.record_busy(record_busy),.record_done(record_done),
        .clear_events(), .event_push(),
        .event_time_ms(), .event_note(), .event_velocity(), .event_on(),
        .start_pulse(start_pulse), .stop_pulse(stop_pulse), .pause_state(pause_state),
        .record_start_pulse(record_start_pulse), .record_stop_pulse(record_stop_pulse),
        .manual_valid(), .manual_on(), .manual_note(), .manual_velocity(),
        .song_duration_ms(), .song_loaded(), .gateway_up(), .recording(recording),
        .protocol_error());

    task press;
        input [13:0] x;
        input [13:0] y;
        begin
            @(negedge clk); touch_x = x; touch_y = y; touch_down = 1; touch_valid = 1;
            @(posedge clk); #1;
        end
    endtask

    task release_touch;
        begin
            @(negedge clk); touch_valid = 0;
            @(negedge clk); touch_down = 0; touch_valid = 1;
            @(negedge clk); touch_valid = 0;
        end
    endtask

    task tap;
        input [13:0] x;
        input [13:0] y;
        begin
            press(x, y);
            release_touch();
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        press(14'd64, 14'd152);
        if (!start_pulse || pause_state) $fatal(1, "Local play did not start/unpause");
        release_touch(); @(posedge clk); #1;
        if (start_pulse) $fatal(1, "Start pulse did not clear");

        tap(14'd140, 14'd152); @(posedge clk); #1;
        if (!pause_state) $fatal(1, "Local pause did not pause");
        @(posedge clk); #1;

        tap(14'd140, 14'd152); @(posedge clk); #1;
        if (pause_state) $fatal(1, "Local pause toggle did not resume");
        tap(14'd300, 14'd152); @(posedge clk); #1;
        if (start_pulse || stop_pulse) $fatal(1, "Touch outside controls triggered an action");
        page_active = 0; tap(14'd64, 14'd152); @(posedge clk); #1;
        if (start_pulse) $fatal(1, "Controls triggered off the performance page");
        page_active = 1;

        @(negedge clk); packet_valid = 1; packet_type = 8'h21;
        @(posedge clk); #1;
        if (!pause_state) $fatal(1, "Remote pause state was not retained");
        @(negedge clk); packet_valid = 0;
        press(14'd64, 14'd152);
        if (!start_pulse || pause_state) $fatal(1, "Local play did not clear remote pause");
        release_touch();

        press(14'd220, 14'd152);
        if (!stop_pulse || pause_state) $fatal(1, "Local stop did not stop/unpause");
        release_touch();
        press(14'd1040, 14'd152);
        if (!record_start_pulse) $fatal(1, "Local record did not request start");
        release_touch();
        press(14'd1040, 14'd152);
        if (!record_stop_pulse) $fatal(1, "Local record did not request stop");
        release_touch();
        press(14'd1040,14'd152);release_touch();
        @(negedge clk);record_start_rejected=1;@(negedge clk);record_start_rejected=0;
        if(recording)$fatal(1,"Rejected backend kept request latched");
        press(14'd1040,14'd152);
        if(!record_start_pulse)$fatal(1,"Retry tap sent stop after rejection");
        release_touch();
        @(negedge clk);record_start_accepted=1;record_active=1;record_busy=1;
        @(negedge clk);record_start_accepted=0;repeat(2)@(negedge clk);
        record_active=0;repeat(3)@(negedge clk);
        if(recording)$fatal(1,"Automatic stop kept request latched");
        press(14'd1040,14'd152);
        if(record_start_pulse || record_stop_pulse)$fatal(1,"Flush-busy accepted a new request");
        release_touch();record_busy=0;record_done=1;@(negedge clk);record_done=0;
        press(14'd1040,14'd152);
        if(!record_start_pulse)$fatal(1,"Completed backend did not allow restart");
        $display("PASS: touchscreen hit regions/page gate, play/pause/stop/record and shared remote pause state");
        $finish;
    end
endmodule
