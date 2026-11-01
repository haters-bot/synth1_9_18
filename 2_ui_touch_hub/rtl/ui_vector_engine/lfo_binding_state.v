// Explicit BIND mode avoids long-press thresholds. One LFO per destination.
// Explicit UP or a quiet-contact timeout commits the last valid destination.
// Only an active drag receives 500 ms of aiming grace at 50 MHz. Ordinary
// contacts use the same 50-ms quiet release as the other touch editors.
module lfo_binding_state #(parameter WATCHDOG_CYCLES=25000000,
                          parameter CONTACT_TIMEOUT_CYCLES=WATCHDOG_CYCLES/10,
                          parameter ENABLE_CANCEL=0,parameter PRESET_ENABLE=0)(
    input wire clk,rst_n,touch_valid,touch_down,
    input wire cancel,
    input wire preset_load,preset_busy,
    input wire [13:0] touch_x,touch_y,
    input wire [1:0] active_tab,
    output reg armed,dragging,
    output wire capture_active,
    output reg [5:0] selected_target,
    output reg [5:0] hover_target,
    output wire [105:0] sources,
    output wire [423:0] depths,
    output reg event_valid,
    output reg [7:0] event_target,
    output reg [1:0] event_source,
    output reg signed [7:0] event_depth
);
    `include "mod_targets.vh"
    `include "audio_capabilities.vh"
    reg [1:0] source[0:52];
    reg signed [7:0] depth[0:52];
    reg finger,control_contact;
    reg [1:0] drag_source;
    reg [24:0] watchdog;
    // navigation_capture includes raw header geometry. Register cancellation
    // before it fans out to the binding bank; touch packets already have two
    // decode stages, so navigation still cancels ahead of its own packet.
    reg cancel_registered /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=32 */;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)cancel_registered<=0;
        else cancel_registered<=ENABLE_CANCEL && cancel;
    wire quiet_release = (dragging ? watchdog>=WATCHDOG_CYCLES :
                                    watchdog>=CONTACT_TIMEOUT_CYCLES) &&
                         (finger || dragging || control_contact);
    // Register parallel cell hits before encoding the destination. Packet
    // flags and the selected LFO travel through the same two decode stages.
    reg [52:0] target_hits;
    reg [5:0] encoded_target;
    reg valid0,down0,graph0,bind0,tool0,clear0,minus0;
    reg [1:0] tab0,packet_tab;
    integer k;
    always @(*) begin
        encoded_target=0;
        for(k=0;k<53;k=k+1)
            encoded_target=encoded_target | ({6{target_hits[k]}} & k[5:0]);
        if(!(|target_hits)) encoded_target=63;
    end
    genvar h;
    generate for(h=0;h<53;h=h+1) begin: hit_decode
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) target_hits[h]<=0;
            else target_hits[h]<=touch_x>=mod_cx(h)-22 && touch_x<=mod_cx(h)+22 &&
                                 touch_y>=mod_cy(h)-22 && touch_y<=mod_cy(h)+22;
        end
    end endgenerate
    reg [5:0] target;
    reg graph_hit,bind_hit,tool_hit;
    reg packet_valid,packet_down,clear_hit,minus_hit;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            target<=63;graph_hit<=0;bind_hit<=0;tool_hit<=0;
            packet_valid<=0;packet_down<=0;clear_hit<=0;minus_hit<=0;
            valid0<=0;down0<=0;graph0<=0;bind0<=0;tool0<=0;clear0<=0;minus0<=0;
            tab0<=0;packet_tab<=0;
        end else begin
            valid0<=touch_valid;down0<=touch_down;tab0<=active_tab;
            graph0<=touch_x>=824 && touch_x<=1224 && touch_y>=408 && touch_y<=552;
            bind0<=touch_x>=1080 && touch_x<=1240 && touch_y>=372 && touch_y<=398;
            tool0<=touch_x>=1000 && touch_x<=1240 && touch_y>=658 && touch_y<=693;
            clear0<=touch_x>=1160;minus0<=touch_x<1080;
            target<=encoded_target;graph_hit<=graph0;bind_hit<=bind0;tool_hit<=tool0;
            packet_valid<=valid0;packet_down<=down0;packet_tab<=tab0;
            clear_hit<=clear0;minus_hit<=minus0;
        end
    end
    // Reserve the gesture while a mode/tool press is still in the decoder.
    // This prevents a following back-to-back graph packet reaching an editor
    // before the binding FSM has observed the preceding BIND press.
    assign capture_active=armed || dragging || control_contact ||
        (valid0 && down0 && (bind0 || (tool0 && selected_target<53))) ||
        (packet_valid && packet_down && (bind_hit || (tool_hit && selected_target<53)));
    genvar n;
    generate for(n=0;n<53;n=n+1) begin: routing
        assign sources[n*2+:2]=source[n];assign depths[n*8+:8]=depth[n];
    end endgenerate
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            armed<=0;dragging<=0;finger<=0;control_contact<=0;drag_source<=0;
            selected_target<=63;hover_target<=63;watchdog<=0;
            event_valid<=0;event_target<=0;event_source<=0;event_depth<=0;
            for(i=0;i<53;i=i+1) begin source[i]<=0;depth[i]<=127;end
        end else if(PRESET_ENABLE && preset_load)begin
            for(i=0;i<53;i=i+1)begin source[i]<=0;depth[i]<=0;end
            armed<=0;dragging<=0;finger<=0;control_contact<=0;hover_target<=63;event_valid<=0;
        end else if(PRESET_ENABLE && preset_busy)begin
            armed<=0;dragging<=0;finger<=0;control_contact<=0;event_valid<=0;
        end else begin
            event_valid<=0;
            if(packet_valid) watchdog<=0;
            else if(watchdog<WATCHDOG_CYCLES) watchdog<=watchdog+1'b1;
            // A fresh packet always wins over expiry. Some HID paths have no
            // explicit UP, so timeout must finish, rather than erase, a drop.
            if(cancel_registered)begin
                armed<=0;dragging<=0;finger<=0;control_contact<=0;hover_target<=63;
            end else if(packet_valid || quiet_release) begin
                if(!packet_valid || !packet_down) begin
                    finger<=0;control_contact<=0;
                    if(dragging) begin
                        // Release coordinates can be zero on some HID reports:
                        // use the last pressed packet's hovered destination.
                        if(audio_lfo_connected(hover_target)) begin
                            source[hover_target]<=drag_source;depth[hover_target]<=127;
                            selected_target<=hover_target;event_valid<=1;
                            event_target<=mod_id(hover_target);event_source<=drag_source;event_depth<=127;
                        end
                        armed<=0;dragging<=0;hover_target<=63;
                    end
                end else begin
                    finger<=1;
                    // BIND is a mode button, not the start of the curve drag.
                    // Accept its graph handoff even if HID omitted the button's
                    // UP or the user moved directly into the graph. Once the
                    // drag is captured, ordinary packets cannot retrigger it.
                    if(armed && control_contact && !dragging && graph_hit) begin
                        dragging<=1;control_contact<=0;
                        drag_source<=packet_tab+1'b1;hover_target<=63;
                    end else if(!finger) begin
                        if(bind_hit) begin armed<=!armed;control_contact<=1;end
                        else if(armed && graph_hit) begin dragging<=1;drag_source<=packet_tab+1'b1;hover_target<=63;end
                        else if(armed && audio_lfo_connected(target)) begin
                            // Optional tap destination after BIND: commit on
                            // press and capture the contact to protect its base.
                            source[target]<=packet_tab+1'b1;depth[target]<=127;
                            selected_target<=target;event_valid<=1;
                            event_target<=mod_id(target);event_source<=packet_tab+1'b1;event_depth<=127;
                            armed<=0;control_contact<=1;
                        end
                        else if(armed) begin armed<=0;control_contact<=1;end
                        else if(tool_hit && selected_target<53) begin
                            control_contact<=1;event_valid<=1;
                            event_target<=mod_id(selected_target);event_source<=source[selected_target];
                            event_depth<=depth[selected_target];
                            if(clear_hit) begin source[selected_target]<=0;event_source<=0;end
                            else if(minus_hit && depth[selected_target]>-127) begin
                                depth[selected_target]<=depth[selected_target]>-119 ? depth[selected_target]-8 : -127;
                                event_depth<=depth[selected_target]>-119 ? depth[selected_target]-8 : -127;
                            end else if(!minus_hit && depth[selected_target]<127) begin
                                depth[selected_target]<=depth[selected_target]<119 ? depth[selected_target]+8 : 127;
                                event_depth<=depth[selected_target]<119 ? depth[selected_target]+8 : 127;
                            end
                        end else if(target<53 && source[target]!=0) selected_target<=target;
                    end else if(dragging) hover_target<=audio_lfo_connected(target) ? target : 6'd63;
                end
            end
        end
    end
endmodule
