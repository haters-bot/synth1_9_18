`timescale 1ns/1ps
// 在扫描器与控制器边界注入样本/故障，验证四条滑带能在背压下释放。
// ADC引脚协议由tb_ads1256_protocol_audit单独验证。
module tb_ribbon_adc_fault;
    reg clk=0, rst_n=0, scheduler_ready=0;
    always #10 clk=~clk;
    wire event_valid,event_on;
    wire [2:0] event_source;
    wire [31:0] event_step;
    wire [6:0] velocity;
    reg feed_valid=0;
    reg [2:0] feed_channel=0;
    reg [5:0] feed_state=6'h12;
    reg [3:0] active=0, released=0;
    reg fault_started=0;
    reg held=0;
    reg [42:0] previous_event;
    integer cycle=0, i, ch;
    ribbon_controller_6ch dut (
        .clk(clk),.rst_n(rst_n),.adc_drdy_n(1'b1),.adc_dout(1'b0),
        .adc_cs_n(),.adc_sclk(),.adc_din(),.adc_reset_n(),
        .scheduler_ready(scheduler_ready),.continuous_event_valid(event_valid),
        .continuous_event_on(event_on),.continuous_event_source(event_source),
        .continuous_event_base_step(event_step),.continuous_event_velocity(velocity),
        .adc_initialized(),.adc_debug_state(),.adc_debug_drdy(),
        .adc_sample_accepted(),.adc_sample_channel(),.adc_sample_data()
    );
    always @(posedge clk) begin
        cycle=cycle+1;
        scheduler_ready <= cycle % 41 > 20;
        if (held && (!event_valid || {event_on,event_source,event_step,velocity} !== previous_event))
            $fatal(1,"event changed under backpressure");
        held=event_valid && !scheduler_ready;
        previous_event={event_on,event_source,event_step,velocity};
        if (event_valid && scheduler_ready) begin
            if (event_source >= 4) $fatal(1,"bad ribbon source");
            if (event_on) active[event_source]=1;
            else if (fault_started) released[event_source]=1;
        end
    end
    task send_sample;
        input [2:0] channel;
        begin
            @(negedge clk);
            feed_channel=channel; feed_valid=1;
            @(posedge clk);
            while (!dut.sample_ready) @(posedge clk);
            @(negedge clk); feed_valid=0;
        end
    endtask
    initial begin
        force dut.sample_valid=feed_valid;
        force dut.sample_channel=feed_channel;
        force dut.sample_data=24'sd3000000;
        force dut.adc_debug_state=feed_state;
        #100 rst_n=1;
        for (i=0;i<20;i=i+1)
            for (ch=0;ch<4;ch=ch+1) send_sample(ch);
        wait(active==4'hF);
        @(negedge clk); fault_started=1; feed_state=6'h3D;
        wait(released==4'hF);
        $display("PASS ribbon ADC fault releases all 4 sources with backpressure");
        $finish;
    end
    initial begin #2000000; $fatal(1,"fault release timeout active=%h released=%h",active,released); end
endmodule
