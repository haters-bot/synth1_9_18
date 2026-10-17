`timescale 1ns/1ps
`include "params.vh"
module tb_touch_coordinate_observer;
    reg clk=0, rst_n=0, valid=0, down=0;
    reg [15:0] x=0, y=0;
    wire [63:0] coords;
    wire [15:0] count;
    wire mode64;
    wire [7:0] selected_id, tap_id;
    wire [1:0] tap_action;
    wire tap_valid;
    reg [7:0] last_tap_id;
    reg [1:0] last_tap_action;
    touch_event_router dut(.clk(clk), .rst_n(rst_n),
        .touch_valid(valid), .raw_touch_x(x), .raw_touch_y(y),
        .touch_state(down), .diag_contact_coords(coords),
        .diag_contact_count(count), .diag_mode_64k(mode64),
        .selected_param_id(selected_id), .btn_tap_valid(tap_valid),
        .btn_tap_id(tap_id), .btn_tap_action(tap_action));
    always #8 clk=~clk;
    always @(posedge clk) if(tap_valid) begin
        last_tap_id <= tap_id;
        last_tap_action <= tap_action;
    end
    task packet;
        input [15:0] px,py;
        input pressed;
        begin
            @(negedge clk); x=px; y=py; down=pressed; valid=1;
            @(posedge clk); #1;
            if (pressed && (coords[31:16] !== {2'b00,dut.s0_tx} ||
                            coords[15:0] !== {2'b00,dut.s0_ty}))
                $fatal(1,"Observer differs from coordinates actually routed");
            @(negedge clk); valid=0;
            repeat(4) @(negedge clk);
        end
    endtask
    reg [63:0] retained;
    initial begin
        #1; rst_n=0; repeat(3) @(negedge clk); rst_n=1;
        packet(8192,4800,1);
        if(coords !== {16'd8192,16'd4800,16'd640,16'd359} || count!==1)
            $fatal(1,"Panel center measurement invalid");
        retained=coords;
        packet(0,0,0);
        repeat(5) @(negedge clk);
        if(coords !== retained || count!==1)
            $fatal(1,"Release erased persistent measurement");
        packet(2150,5120,1);
        if(last_tap_id !== `PARAM_ID_ENV_TAB || last_tap_action !== 2'd1)
            $fatal(1,"ENV 2 raw panel coordinates did not select ENV 2");
        packet(0,0,0);
        packet(12160,3584,1);
        if(selected_id !== `PARAM_ID_FLT_CUTOFF)
            $fatal(1,"Cutoff raw panel coordinates selected wrong knob");
        packet(0,0,0);
        packet(16384,9516,1);
        if(coords[31:0] !== {16'd1279,16'd713} || mode64)
            $fatal(1,"Measured corner packet mapped incorrectly");
        packet(16385,9601,1);
        if(coords[31:0] !== {16'd1279,16'd719} || mode64)
            $fatal(1,"Panel edge overshoot changed range or failed to clamp");
        packet(65535,65535,1);
        if(!mode64 || coords[31:0] !== {16'd1279,16'd719})
            $fatal(1,"Mode transition / clamped observation mismatch");
        packet(32768,32768,1);
        if(coords[31:0] !== {16'd640,16'd360})
            $fatal(1,"64K center measurement invalid");
        $display("PASS: panel center, ENV 2, cutoff selection, measured corner, edge overshoot, release retention, 64K fallback");
        $finish;
    end
endmodule
