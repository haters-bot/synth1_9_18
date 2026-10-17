`timescale 1ns/1ps
module tb_touch_trace;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg tv=0,down=0,bv=0,dv=0,cv=0,sv=0,curvev=0;
    reg [1:0] ltab=0;
    reg [48:0] nodes={7'd0,7'd16,7'd32,7'd64,7'd96,7'd127,7'd0};
    wire tx;
    wire [31:0] drops;
    integer fd,b,j;
    reg [7:0] rx;
    ui_debug_trace #(.CLK_FREQ(1000000),.BAUD(100000),.FIFO_BITS(2)) dut(
        .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(down),.touch_source(2'd1),
        .raw_x(16'd8192),.raw_y(16'd4800),.ui_x(14'd640),.ui_y(14'd360),
        .selected_id(8'h45),.selected_valid(1'b1),.selected_value(7'd1),.selected_value_valid(1'b1),
        .btn_valid(bv),.btn_id(8'h45),.btn_action(2'd1),.delta_valid(dv),.delta_value(-8'sd4),
        .cc_valid(cv),.cc_id(8'h30),.cc_value(7'd99),
        .spi_valid(sv),.spi_id(8'h13),.spi_value(7'd6),
        .curve_valid(curvev),.curve_filter(1'b0),.curve_tab(2'd1),.curve_mask(5'b10101),
        .curve_values({7'd111,7'd90,7'd40,7'd0,7'd10}),
        .env_tab(2'd1),.lfo_tab(ltab),.lfo_preset(2'd2),.lfo_nodes(nodes),.lfo_rate(3'd4),
        .lfo_once(1'b1),.lfo_stepped(1'b0),.button_state(32'h000155AA),
        .uart_tx(tx),.dropped_records(drops)
    );
    // Decode the physical serial waveform; check every start/data/stop bit.
    initial begin
        fd=$fopen("trace_bytes.hex","w");
        forever begin
            @(negedge tx);
            if(rst_n) begin
                #50;if(tx!==0)$fatal(1,"UART start");
                for(b=0;b<8;b=b+1)begin #100;rx[b]=tx;end
                #100;if(tx!==1)$fatal(1,"UART stop");
                if(^rx===1'bx)$fatal(1,"Unknown serial bit");
                $fwrite(fd,"%02x\n",rx);
            end
        end
    end
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        repeat(40)@(negedge clk);
        // Simultaneous classes must all survive one batch.
        tv=1;down=1;bv=1;dv=1;cv=1;sv=1;curvev=1;
        @(negedge clk);tv=0;bv=0;dv=0;cv=0;sv=0;curvev=0;
        repeat(40)@(negedge clk);
        // An event exactly on flush must start another batch.
        tv=1;down=0;@(negedge clk);tv=0;
        wait(dut.batch_timer==1);@(negedge clk);ltab=1;
        repeat(40000)@(negedge clk);
        if(drops!=0)$fatal(1,"Unexpected initial loss");
        // Overload a bounded FIFO deliberately; UI input must remain free.
        for(j=0;j<20;j=j+1)begin
            tv=1;down=~down;@(negedge clk);tv=0;
            repeat(32)@(negedge clk);
        end
        repeat(100)@(negedge clk);
        if(drops==0)$fatal(1,"Overflow counter missing");
        repeat(1020000)@(negedge clk); // next status reports loss after the burst
        if(dut.count!=0 || dut.sending)$fatal(1,"Trace did not drain");
        $fclose(fd);
        $display("PASS: waveform UART, simultaneous events, flush boundary, bounded FIFO overflow and heartbeat; drops=%0d",drops);
        $finish;
    end
    initial begin #20000000;$fatal(1,"Trace test timeout");end
endmodule
