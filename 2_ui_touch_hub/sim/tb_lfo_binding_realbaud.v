`timescale 1ns/1ps
// Real 50 MHz / 31250 baud, including production raw-coordinate normalization.
// No route configuration is injected: only touch DOWN/MOVE/UP packets.
// Default: fast boot transport and short UI timers isolate the real UART baud.
// FULL_BOOT_UART=1, HID_REPORT_CYCLES=250000, QUIET_CYCLES=1000000,
// BIND_GRACE_CYCLES=25000000 reproduce unscaled startup and 5-ms HID reports.
module tb_lfo_binding_realbaud #(
    parameter FULL_BOOT_UART=0,
    parameter HID_REPORT_CYCLES=8,
    parameter QUIET_CYCLES=20,
    parameter BIND_GRACE_CYCLES=1000
);
    reg clk=0,rst_n=0,touch_valid=0,touch_down=0;
    reg [15:0] raw_x=0,raw_y=0;
    wire tv,td,capture,req,accept,uart,uart_busy,sysex_busy;
    wire [13:0] x,y;
    wire [105:0] sources;
    wire [423:0] depths;
    wire [47:0] msgs;
    reg boot_transport=1;
    integer boot_frames=0;
    reg [47:0] boot6=0,boot13=0;
    wire bypass_boot=boot_transport && !FULL_BOOT_UART;
    always @(posedge clk) if(rst_n && boot_transport && req && (bypass_boot || accept))begin
        boot_frames=boot_frames+1;
        if(msgs[31:24]==8'h4F)boot6=msgs;
        if(msgs[31:24]==8'h56)boot13=msgs;
        if(msgs==48'hF07D7E0000F7)boot_transport<=0;
    end
    always #10 clk=~clk;
    touch_event_router router(.clk(clk),.rst_n(rst_n),.touch_valid(touch_valid),
        .raw_touch_x(raw_x),.raw_touch_y(raw_y),.touch_state(touch_down),
        .curve_capture_active(capture),.curve_focus_valid(1'b0),.curve_focus_id(8'd0),
        .ui_touch_valid(tv),.ui_touch_down(td),.ui_touch_x(x),.ui_touch_y(y));
    lfo_binding_state #(.WATCHDOG_CYCLES(BIND_GRACE_CYCLES)) binding(.clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td),
        .touch_x(x),.touch_y(y),.active_tab(2'd0),.cancel(1'b0),
        .capture_active(capture),.sources(sources),.depths(depths));
    lfo_sysex_tx #(.HOLD_CYCLES(QUIET_CYCLES),.FIRST_HOLD_CYCLES(20)) sx(.clk(clk),.rst_n(rst_n),.cfg_nodes(147'd0),.cfg_rates(9'd0),
        .cfg_steps(3'd0),.cfg_once(3'd0),.cfg_sources(sources),.cfg_depths(depths),
        .tx_accept(bypass_boot ? req : accept),.sysex_req(req),.sysex_msgs(msgs),.busy(sysex_busy));
    midi_uart_tx tx(.clk(clk),.rst_n(rst_n),.note_on_req(1'b0),.note_off_req(1'b0),
        .note_number(7'd0),.note_velocity(7'd0),.cc_req(1'b0),.cc_param_id(8'd0),
        .cc_val(7'd0),.sysex_req(req && !bypass_boot),.sysex_msgs(msgs),.sysex_accept(accept),
        .uart_tx(uart),.tx_busy(uart_busy));
    reg [7:0] serial_byte;
    reg [47:0] frame=0,last6=0,last13=0;
    integer bit_index,byte_index=0,commits=0,frames=0;
    initial forever begin
        @(negedge uart);
        #16000;
        if(uart!==0)$fatal(1,"invalid start bit");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
            #32000;serial_byte[bit_index]=uart;
        end
        #32000;
        if(uart!==1)$fatal(1,"invalid stop bit");
        frame={frame[39:0],serial_byte};byte_index=byte_index+1;
        if(byte_index==6)begin
            byte_index=0;frames=frames+1;
            if(frame[47:32]!==16'hF07D || frame[7:0]!==8'hF7)
                $fatal(1,"invalid SysEx frame %h",frame);
            if(frame[31:24]==8'h4F)begin last6=frame;$display("UART: target6 %h",frame);end
            if(frame[31:24]==8'h56)begin last13=frame;$display("UART: target13 %h",frame);end
            if(frame==48'hF07D7E0000F7)begin commits=commits+1;$display("UART: commit %h",frame);end
        end
    end
    task packet(input integer px,py,input bit down);
        begin
            @(negedge clk);
            raw_x=(px*65536+5119)/5120;
            raw_y=(py*65536+4914)/4915;
            touch_down=down;touch_valid=1;
            @(negedge clk);touch_valid=0;
            repeat(HID_REPORT_CYCLES)@(negedge clk);
        end
    endtask
    task bind_to(input integer px,py);
        begin
            packet(1140,385,1);packet(1140,385,1);packet(0,0,0);
            packet(980,485,1);packet(800,360,1);
            packet(px,py,1);packet(px,py,1);packet(0,0,0);
        end
    endtask
    initial begin
        repeat(8)@(negedge clk);rst_n=1;
        wait(!boot_transport);wait(!uart_busy && !sysex_busy);
        if(boot_frames!=81 || boot6!==48'hF07D4F007FF7 || boot13!==48'hF07D56007FF7)
            $fatal(1,"boot defaults must be source0/depth127");
        bind_to(134,268);
        wait(commits==(FULL_BOOT_UART ? 2 : 1));wait(!uart_busy && !sysex_busy);
        if(sources[13:12]!==2'd1 || depths[55:48]!==8'h7F || last6!==48'hF07D4F027FF7)
            $fatal(1,"real-baud target6 failed: live=%h/%h UART=%h",sources[13:12],depths[55:48],last6);
        bind_to(344,326);
        wait(commits==(FULL_BOOT_UART ? 3 : 2));wait(!uart_busy && !sysex_busy);
        if(sources[27:26]!==2'd1 || depths[111:104]!==8'h7F || last13!==48'hF07D56027FF7)
            $fatal(1,"real-baud target13 failed: live=%h/%h UART=%h",sources[27:26],depths[111:104],last13);
        $display("PASS: raw touch normalization -> binding FSM -> snapshots -> FIFO -> 31250 baud UART, target6/13, frames=%0d commits=%0d",frames,commits);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"real-baud timeout");end
endmodule
