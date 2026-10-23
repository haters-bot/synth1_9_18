// Logical parameter adapter. External protocol/framing is intentionally separate.
// Values are normalized 0..127; touch owns its captured parameter until release.
module fx_editor_state #(parameter WATCHDOG_CYCLES=2500000)(
    input wire clk,rst_n,touch_valid,touch_down,
    input wire [13:0] touch_x,touch_y,
    input wire external_valid,
    input wire [7:0] external_id,
    input wire [6:0] external_value,
    output wire [132:0] values,
    output reg [10:0] switches,
    output reg event_valid,
    output reg [7:0] event_id,
    output reg [6:0] event_value
);
    `include "fx_controls.vh"
    reg [6:0] params[0:18];
    reg finger,drag;
    reg [4:0] captured;
    reg [13:0] anchor_x,anchor_y;
    reg [6:0] anchor_value;
    reg [21:0] watchdog;
    // Decode the packet before committing state. External events travel with
    // the same packet stage, preserving same-cycle touch/external arbitration.
    reg packet_valid,packet_down,external_pending;
    reg [13:0] packet_x,packet_y;
    reg [7:0] packet_external_id;
    reg [6:0] packet_external_value;
    reg [18:0] target_hits;
    reg [3:0] toggle_id;
    reg [7:0] target;
    integer k;
    always @(*) begin
        target=0;
        for(k=0;k<19;k=k+1)
            target=target | ({8{target_hits[k]}} & (8'h60+k));
    end
    wire signed [16:0] delta=($signed({3'd0,packet_x})-$signed({3'd0,anchor_x})+
                               $signed({3'd0,anchor_y})-$signed({3'd0,packet_y})) >>> 1;
    wire signed [17:0] next_value=$signed({11'd0,anchor_value})+delta;
    wire [6:0] clamped=next_value<0 ? 7'd0 : next_value>127 ? 7'd127 : next_value[6:0];
    genvar n;
    generate for(n=0;n<19;n=n+1) begin: outputs
        assign values[n*7+:7]=params[n];
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) target_hits[n]<=0;
            else target_hits[n]<=touch_x>=fx_cx(n)-22 && touch_x<=fx_cx(n)+22 &&
                                  touch_y>=fx_cy(n)-23 && touch_y<=fx_cy(n)+23;
        end
    end endgenerate
    integer i;
    reg [3:0] toggle_next;
    always @(*) begin
        toggle_next=15;
        if(touch_y>=372 && touch_y<=395) begin
            if(touch_x>=744 && touch_x<=779) toggle_next=0;
            else if(touch_x>=504 && touch_x<=566) toggle_next=3;
            else if(touch_x>=574 && touch_x<=636) toggle_next=4;
            else if(touch_x>=644 && touch_x<=736) toggle_next=5;
        end else if(touch_y>=480 && touch_y<=503) begin
            if(touch_x>=744 && touch_x<=779) toggle_next=1;
            else if(touch_x>=552 && touch_x<=724) toggle_next=6;
        end else if(touch_y>=588 && touch_y<=611) begin
            if(touch_x>=744 && touch_x<=779) toggle_next=2;
            else if(touch_x>=504 && touch_x<=606) toggle_next=7;
            else if(touch_x>=624 && touch_x<=736) toggle_next=8;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            packet_valid<=0;packet_down<=0;packet_x<=0;packet_y<=0;toggle_id<=15;
            external_pending<=0;packet_external_id<=0;packet_external_value<=0;
        end else begin
            packet_valid<=touch_valid;packet_down<=touch_down;
            packet_x<=touch_x;packet_y<=touch_y;toggle_id<=toggle_next;
            external_pending<=external_valid;packet_external_id<=external_id;
            packet_external_value<=external_value;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            finger<=0;drag<=0;captured<=0;anchor_x<=0;anchor_y<=0;anchor_value<=0;
            watchdog<=0;switches<=11'b00001001111;event_valid<=0;event_id<=0;event_value<=0;
            for(i=0;i<19;i=i+1) params[i]<=64;
            params[5]<=32;params[12]<=32;params[15]<=64;params[18]<=64;
        end else begin
            event_valid<=0;
            if(watchdog<WATCHDOG_CYCLES) watchdog<=watchdog+1'b1;
            else begin finger<=0;drag<=0;end
            if(external_pending && packet_external_id>=8'h60 && packet_external_id<=8'h72 &&
               !(drag && (packet_external_id==8'h60+captured ||
                 (switches[4] && (captured==1 || captured==2) &&
                  (packet_external_id==8'h61 || packet_external_id==8'h62))))) begin
                params[packet_external_id-8'h60]<=packet_external_value;
                if(switches[4] && packet_external_id==8'h61) params[2]<=packet_external_value;
                if(switches[4] && packet_external_id==8'h62) params[1]<=packet_external_value;
                event_valid<=1;event_id<=packet_external_id;event_value<=packet_external_value;
            end else if(external_pending && packet_external_id>=8'h80 && packet_external_id<=8'h88) begin
                if(packet_external_id==8'h87) begin switches[7]<=packet_external_value==1;switches[9]<=packet_external_value>=2;end
                else if(packet_external_id==8'h88) begin switches[8]<=packet_external_value==1;switches[10]<=packet_external_value>=2;end
                else switches[packet_external_id-8'h80]<=packet_external_value!=0;
                event_valid<=1;event_id<=packet_external_id;
                event_value<=(packet_external_id==8'h87 || packet_external_id==8'h88) ?
                    (packet_external_value>=2 ? 7'd2 : packet_external_value) : packet_external_value!=0;
            end
            if(packet_valid) begin
                watchdog<=0;
                if(!packet_down) begin finger<=0;drag<=0;end
                else begin
                    finger<=1;
                    if(!finger) begin
                        drag<=target!=0;
                        if(target!=0) begin
                            captured<=target-8'h60;anchor_x<=packet_x;anchor_y<=packet_y;
                            anchor_value<=params[target-8'h60];
                        end else if(toggle_id<9) begin
                            event_valid<=1;event_id<=8'h80+toggle_id;
                            if(toggle_id==7) begin
                                switches[7]<=!switches[7] && !switches[9];switches[9]<=switches[7];
                                event_value<=switches[9] ? 0 : switches[7] ? 2 : 1;
                            end else if(toggle_id==8) begin
                                switches[8]<=!switches[8] && !switches[10];switches[10]<=switches[8];
                                event_value<=switches[10] ? 0 : switches[8] ? 2 : 1;
                            end else begin
                                switches[toggle_id]<=!switches[toggle_id];event_value<=!switches[toggle_id];
                                if(toggle_id==4 && !switches[4]) params[2]<=params[1];
                            end
                        end
                    end else if(drag && params[captured]!=clamped) begin
                        params[captured]<=clamped;event_valid<=1;
                        if(switches[4] && captured==1) params[2]<=clamped;
                        if(switches[4] && captured==2) params[1]<=clamped;
                        event_id<=8'h60+captured;event_value<=clamped;
                    end
                end
            end
        end
    end
endmodule
