// Observation-only UART trace. Instantiate only in the diagnostic build.
// 64-byte binary frames, little endian; byte 63 is XOR(bytes 0..62).
// Events within 16 clocks share a record; no ready/backpressure enters the UI.
module ui_debug_trace #(
    parameter CLK_FREQ=62500000, parameter BAUD=115200,
    parameter FIFO_BITS=5, parameter BATCH_CYCLES=16
)(
    input wire clk,rst_n,
    input wire touch_valid,touch_down,
    input wire [1:0] touch_source,
    input wire [15:0] raw_x,raw_y,
    input wire [13:0] ui_x,ui_y,
    input wire [7:0] selected_id,
    input wire selected_valid,
    input wire [6:0] selected_value,
    input wire selected_value_valid,
    input wire btn_valid,
    input wire [7:0] btn_id,
    input wire [1:0] btn_action,
    input wire delta_valid,
    input wire signed [7:0] delta_value,
    input wire cc_valid,
    input wire [7:0] cc_id,
    input wire [6:0] cc_value,
    input wire spi_valid,
    input wire [7:0] spi_id,
    input wire [6:0] spi_value,
    input wire curve_valid,curve_filter,
    input wire [1:0] curve_tab,
    input wire [4:0] curve_mask,
    input wire [34:0] curve_values,
    input wire [1:0] env_tab,lfo_tab,lfo_preset,
    input wire [48:0] lfo_nodes,
    input wire [2:0] lfo_rate,
    input wire lfo_once,lfo_stepped,
    input wire [31:0] button_state,
    output wire uart_tx,
    output reg [31:0] dropped_records
);
    localparam DEPTH=1<<FIFO_BITS;
    localparam MS_DIV=CLK_FREQ/1000;
    reg [31:0] sub_ms,tick_ms;
    reg [9:0] heartbeat;
    wire ms_tick=sub_ms==MS_DIV-1;
    wire status_tick=ms_tick && heartbeat==999;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin sub_ms<=0;tick_ms<=0;heartbeat<=0;end
        else if(ms_tick) begin
            sub_ms<=0;tick_ms<=tick_ms+1'b1;
            heartbeat<=heartbeat==999 ? 0 : heartbeat+1'b1;
        end else sub_ms<=sub_ms+1'b1;
    end

    wire [59:0] lfo_state={lfo_tab,lfo_preset,lfo_rate,lfo_once,lfo_stepped,2'b0,lfo_nodes};
    reg [59:0] last_lfo;
    reg [33:0] last_buttons;
    wire [7:0] events={status_tick || {env_tab,button_state}!=last_buttons,
        lfo_state!=last_lfo,spi_valid,curve_valid,cc_valid,delta_valid,btn_valid,touch_valid};
    reg [7:0] pending;
    reg [7:0] batch_timer;
    reg [31:0] sequence_id;
    reg [31:0] event_time;
    reg [1:0] held_source;
    reg held_down;
    reg [15:0] held_raw_x,held_raw_y;
    reg [13:0] held_x,held_y;
    reg [7:0] held_btn,held_delta,held_cc_id,held_spi_id;
    reg [1:0] held_action,held_curve_tab;
    reg [6:0] held_cc_value,held_spi_value;
    reg held_curve_filter;
    reg [4:0] held_curve_mask;
    reg [34:0] held_curve_values;
    wire flush=(batch_timer==1);

    // Field pulses are latched independently, including simultaneous events.
    // If a new event lands on flush, it starts the next batch, never disappears.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pending<=8'h80;batch_timer<=BATCH_CYCLES;sequence_id<=0;
            event_time<=0;last_lfo<=0;last_buttons<=0;
            held_source<=0;held_down<=0;held_raw_x<=0;held_raw_y<=0;held_x<=0;held_y<=0;
            held_btn<=0;held_action<=0;held_delta<=0;held_cc_id<=0;held_cc_value<=0;
            held_spi_id<=0;held_spi_value<=0;held_curve_filter<=0;
            held_curve_tab<=0;held_curve_mask<=0;held_curve_values<=0;
        end else begin
            last_lfo<=lfo_state;last_buttons<={env_tab,button_state};
            if(touch_valid) begin
                held_source<=touch_source;held_down<=touch_down;
                held_raw_x<=raw_x;held_raw_y<=raw_y;held_x<=ui_x;held_y<=ui_y;
            end
            if(btn_valid) begin held_btn<=btn_id;held_action<=btn_action;end
            if(delta_valid) held_delta<=delta_value;
            if(cc_valid) begin held_cc_id<=cc_id;held_cc_value<=cc_value;end
            if(spi_valid) begin held_spi_id<=spi_id;held_spi_value<=spi_value;end
            if(curve_valid) begin
                held_curve_filter<=curve_filter;held_curve_tab<=curve_tab;
                held_curve_mask<=curve_mask;held_curve_values<=curve_values;
            end
            if(flush) begin
                sequence_id<=sequence_id+1'b1;
                pending<=events;batch_timer<=events!=0 ? BATCH_CYCLES : 0;
                if(events!=0) event_time<=tick_ms;
            end else if(batch_timer!=0) begin
                batch_timer<=batch_timer-1'b1;pending<=pending|events;
            end else if(events!=0) begin
                pending<=events;batch_timer<=BATCH_CYCLES;event_time<=tick_ms;
            end
        end
    end

    reg [511:0] record_data;
    reg [7:0] check_xor;
    integer k;
    always @(*) begin
        record_data=0;
        record_data[7:0]=8'h55;record_data[15:8]=8'hAA;
        record_data[23:16]=1;record_data[31:24]=pending;
        record_data[63:32]=sequence_id;record_data[95:64]=event_time;
        record_data[127:96]=dropped_records;
        record_data[135:128]={7'b0,held_down};
        record_data[143:136]={6'b0,held_source};
        record_data[159:144]=held_raw_x;record_data[175:160]=held_raw_y;
        record_data[191:176]={2'b0,held_x};record_data[207:192]={2'b0,held_y};
        record_data[215:208]=selected_id;record_data[223:216]=held_btn;
        record_data[231:224]={6'b0,held_action};record_data[239:232]=held_delta;
        record_data[247:240]=held_cc_id;record_data[255:248]={1'b0,held_cc_value};
        record_data[263:256]=held_spi_id;record_data[271:264]={1'b0,held_spi_value};
        record_data[279:272]={5'b0,held_curve_filter,held_curve_tab};
        record_data[287:280]={3'b0,held_curve_mask};
        for(k=0;k<5;k=k+1) record_data[(36+k)*8+:8]={1'b0,held_curve_values[k*7+:7]};
        record_data[335:328]={6'b0,env_tab};record_data[343:336]={6'b0,lfo_tab};
        record_data[351:344]={5'b0,lfo_rate};
        record_data[359:352]={4'b0,lfo_preset,lfo_stepped,lfo_once};
        for(k=0;k<7;k=k+1) record_data[(45+k)*8+:8]={1'b0,lfo_nodes[k*7+:7]};
        record_data[423:416]={7'b0,selected_valid};
        record_data[431:424]={1'b0,selected_value};
        record_data[463:432]=button_state;
        record_data[471:464]={7'b0,selected_value_valid};
        // 59..62 reserved, currently zero. Checksum is an error detector, not CRC.
        check_xor=0;
        for(k=0;k<63;k=k+1) check_xor=check_xor^record_data[k*8+:8];
        record_data[511:504]=check_xor;
    end

    reg [511:0] fifo[0:DEPTH-1];
    reg [FIFO_BITS-1:0] wr_ptr,rd_ptr;
    reg [FIFO_BITS:0] count;
    reg [511:0] active_record;
    reg sending;
    reg [5:0] byte_index;
    wire byte_busy;
    wire pop=!sending && !byte_busy && count!=0;
    wire push=flush && (count<DEPTH || pop);
    wire send_byte=sending && !byte_busy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr<=0;rd_ptr<=0;count<=0;dropped_records<=0;
            sending<=0;byte_index<=0;active_record<=0;
        end else begin
            if(flush && !push) dropped_records<=dropped_records+1'b1;
            if(push) begin fifo[wr_ptr]<=record_data;wr_ptr<=wr_ptr+1'b1;end
            if(pop) begin
                active_record<=fifo[rd_ptr];rd_ptr<=rd_ptr+1'b1;
                sending<=1;byte_index<=0;
            end else if(send_byte) begin
                active_record<=active_record>>8;byte_index<=byte_index+1'b1;
                if(byte_index==63) sending<=0;
            end
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
        end
    end
    ui_trace_uart_byte #(.CLK_FREQ(CLK_FREQ),.BAUD(BAUD)) u_byte(
        .clk(clk),.rst_n(rst_n),.send(send_byte),.data(active_record[7:0]),
        .busy(byte_busy),.tx(uart_tx));
endmodule

module ui_trace_uart_byte #(parameter CLK_FREQ=62500000,parameter BAUD=115200)(
    input wire clk,rst_n,send,input wire [7:0] data,output reg busy,output reg tx
);
    localparam DIV=(CLK_FREQ+BAUD/2)/BAUD;
    reg [31:0] timer;
    reg [3:0] bits_left;
    reg [8:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin timer<=0;bits_left<=0;shift<=9'h1FF;busy<=0;tx<=1;end
        else if(!busy) begin
            tx<=1;
            if(send) begin tx<=0;shift<={1'b1,data};timer<=DIV-1;bits_left<=10;busy<=1;end
        end else if(timer!=0) timer<=timer-1'b1;
        else if(bits_left==1) begin busy<=0;tx<=1;end
        else begin tx<=shift[0];shift<={1'b1,shift[8:1]};bits_left<=bits_left-1'b1;timer<=DIV-1;end
    end
endmodule
