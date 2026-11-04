`include "params.vh"
`include "font_3x5.vh"
`include "font_7x10.vh"
`include "pixel_coverage.vh"
module modulation_overlay(
    input wire clk,rst_n,
    input wire [13:0] in_x,in_y,
    input wire [105:0] sources,
    input wire [423:0] depths,
    input wire [370:0] preview_values,
    input wire armed,dragging,
    input wire [5:0] hover_target,selected_target,
    input wire [1:0] active_tab,
    input wire [13:0] touch_x,touch_y,
    input wire [48:0] curve_nodes,
    output reg out_hit,
    output reg [23:0] out_rgb
);
    `include "mod_targets.vh"
    `include "audio_capabilities.vh"
    function [5:0] digit;
        input [6:0] num;
        begin digit=`CH_0+num;end
    endfunction
    // Register UI state before the control-rate helpers use it. This also
    // isolates slow parameter buses from the raster combinational path.
    reg [13:0] px,py;
    reg [13:0] px0 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [13:0] py0 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [105:0] sources_r;
    reg [423:0] depths_r;
    reg [370:0] preview_values_r;
    reg armed_r,dragging_r;
    reg [5:0] hover_target_r,selected_target_r;
    reg [1:0] active_tab_r;
    reg [48:0] curve_nodes_r;
    always @(posedge clk) begin
        px0<=in_x;py0<=in_y;px<=px0;py<=py0;
        sources_r<=sources;depths_r<=depths;preview_values_r<=preview_values;
        armed_r<=armed;dragging_r<=dragging;hover_target_r<=hover_target;selected_target_r<=selected_target;
        active_tab_r<=active_tab;curve_nodes_r<=curve_nodes;
    end
    wire signed [7:0] selected_depth=selected_target_r<53 ? depths_r[selected_target_r*8+:8] : 8'sd0;
    function [5:0] char_at;
        input [143:0] text;
        input [4:0] column;
        begin case(column)
            5'd0:char_at=text[143:138];
            5'd1:char_at=text[137:132];
            5'd2:char_at=text[131:126];
            5'd3:char_at=text[125:120];
            5'd4:char_at=text[119:114];
            5'd5:char_at=text[113:108];
            5'd6:char_at=text[107:102];
            5'd7:char_at=text[101:96];
            5'd8:char_at=text[95:90];
            5'd9:char_at=text[89:84];
            5'd10:char_at=text[83:78];
            5'd11:char_at=text[77:72];
            5'd12:char_at=text[71:66];
            5'd13:char_at=text[65:60];
            5'd14:char_at=text[59:54];
            5'd15:char_at=text[53:48];
            5'd16:char_at=text[47:42];
            5'd17:char_at=text[41:36];
            5'd18:char_at=text[35:30];
            5'd19:char_at=text[29:24];
            5'd20:char_at=text[23:18];
            5'd21:char_at=text[17:12];
            5'd22:char_at=text[11:6];
            5'd23:char_at=text[5:0];
            default:char_at=0;
        endcase end
    endfunction
    // Control-rate work stays off the raster critical path. The miniature is
    // rebuilt in 97 clocks; it is only a drag aid, not the main smooth curve.
    reg [10:0] ghost_x;
    reg [9:0] ghost_y;
    reg [10:0] ghost_right;
    reg [9:0] ghost_bottom;
    reg [5:0] miniature[0:96];
    reg [6:0] build_index,index_a,index_b;
    wire [2:0] build_segment=build_index==96 ? 3'd5 : build_index[6:4];
    reg [6:0] a0,b0;
    reg [4:0] fraction0;
    reg [12:0] weighted1;
    reg [7:0] amount_abs,amount_remainder;
    reg amount_negative,amount_negative1;
    reg [5:0] amount_hundreds,amount_tens,amount_units;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ghost_x<=4;ghost_y<=4;ghost_right<=100;ghost_bottom<=40;build_index<=0;index_a<=0;index_b<=0;
            a0<=0;b0<=0;fraction0<=0;weighted1<=0;
            amount_abs<=0;amount_remainder<=0;amount_negative<=0;amount_negative1<=0;
            amount_hundreds<=`CH_0;amount_tens<=`CH_0;amount_units<=`CH_0;
        end else begin
            ghost_x<=touch_x>1175 ? 11'd1175 : touch_x<52 ? 11'd4 : touch_x-14'd48;
            ghost_y<=touch_y>665 ? 10'd665 : touch_y<50 ? 10'd4 : touch_y-14'd46;
            ghost_right<=touch_x>1175 ? 11'd1271 : touch_x<52 ? 11'd100 : touch_x+14'd48;
            ghost_bottom<=touch_y>665 ? 10'd701 : touch_y<50 ? 10'd40 : touch_y-14'd10;
            build_index<=build_index==96 ? 0 : build_index+1'b1;
            index_a<=build_index;index_b<=index_a;
            a0<=curve_nodes_r[build_segment*7+:7];b0<=curve_nodes_r[(build_segment+1)*7+:7];
            fraction0<=build_index==96 ? 5'd16 : {1'b0,build_index[3:0]};
            weighted1<=a0*(5'd16-fraction0)+b0*fraction0;
            miniature[index_b]<=6'd34-weighted1[12:6];
            amount_negative<=selected_depth<0;amount_abs<=selected_depth<0 ? -selected_depth : selected_depth;
            amount_negative1<=amount_negative;
            amount_remainder<=amount_abs>=100 ? amount_abs-100 : amount_abs;
            amount_hundreds<=amount_abs>=100 ? `CH_1 : `CH_0;
            amount_tens<=digit(amount_remainder/8'd10);amount_units<=digit(amount_remainder%8'd10);
        end
    end
    // The target cells are disjoint. Parallel masked fields and an OR tree
    // avoid a 53-element priority chain in the pixel path.
    reg [52:0] mark_hit,mark_text,mark_white;
    reg [23:0] mark_rgb[0:52];
    reg [5:0] mark_char[0:52];
    reg [2:0] mark_rx[0:52];
    reg [3:0] mark_ry[0:52];
    genvar n;
    generate for(n=0;n<53;n=n+1) begin: cells
        localparam [13:0] CX=mod_cx(n), CY=mod_cy(n);
        // Stage one: constant origin subtraction and clipping. Stage two
        // computes distance/color only from these bounded registered fields.
        reg box_hit;
        reg [5:0] lx,ly;
        always @(posedge clk) begin
            box_hit<=in_x>=CX-14'd22 && in_x<=CX+14'd22 && in_y>=CY-14'd22 && in_y<=CY+14'd22;
            lx<=in_x-(CX-14'd22);ly<=in_y-(CY-14'd22);
        end
        wire [5:0] ax=lx>=22 ? lx-6'd22 : 6'd22-lx;
        wire [5:0] ay=ly>=22 ? ly-6'd22 : 6'd22-ly;
        wire [6:0] distance_l1={1'b0,ax}+{1'b0,ay};
        wire [1:0] src=sources_r[n*2+:2];
        wire [12:0] scaled_value=preview_values_r[n*7+:7]*6'd34;
        wire [5:0] marker_top=6'd39-scaled_value[12:7];
        localparam CONNECTED=audio_lfo_connected(n);
        wire ring=src!=0 && distance_l1>=25 && distance_l1<=27;
        wire indicator=CONNECTED && src!=0 && lx>=40 && lx<=43 && ly>=marker_top && ly<=marker_top+6'd3;
        wire candidate=CONNECTED && dragging_r && hover_target_r==n && (distance_l1==29 || distance_l1==30);
        wire cell_hit=box_hit && (ring || indicator || candidate);
        wire cell_text=box_hit && (src!=0 || !CONNECTED) && lx>=14 && lx<30 && ly<10;
        // Coverage is already registered separately. Mask color in the next
        // reduction stage, so the full ring/indicator predicate need not also
        // drive every RGB register bit in this stage.
        wire [23:0] cell_color=CONNECTED ? source_color(src) : 24'h50545C;
        wire [5:0] cell_char=cell_text ? (CONNECTED ? (lx>=22 ? digit({5'd0,src}) : `CH_L) : (lx>=22 ? `CH_C : `CH_N)) : 6'd0;
        wire [2:0] cell_rx=cell_text ? lx-6'd14 : 3'd0;
        wire [3:0] cell_ry=cell_text ? ly : 4'd0;
        always @(posedge clk) begin
            mark_hit[n]<=cell_hit;mark_text[n]<=cell_text;mark_white[n]<=indicator || candidate;
            mark_rgb[n]<=cell_color;
            mark_char[n]<=cell_char;mark_rx[n]<=cell_rx;mark_ry[n]<=cell_ry;
        end
    end endgenerate
    function [23:0] source_color;
        input [1:0] src;
        begin source_color=src==1 ? 24'h38E8FF : src==2 ? 24'hEEB34D : 24'hDD88FF;end
    endfunction
    reg hit;
    reg [23:0] color;
    reg [5:0] ch;
    reg [2:0] text_rx;
    reg [3:0] text_ry;
    reg text_valid;
    reg [143:0] amount_label;
    always @(*) begin
        amount_label=pack_font24("AMOUNT +000             ");
        amount_label[101:96]=amount_negative1 ? `CH_MINUS : `CH_PLUS;
        amount_label[95:90]=amount_hundreds;
        amount_label[89:84]=amount_tens;amount_label[83:78]=amount_units;
    end
    integer i;
    reg [4:0] col;
    reg [6:0] ghost_dx,ghost_dx0;
    reg [5:0] ghost_dy,ghost_dy0;
    reg [5:0] ghost_level;
    reg ghost_box,ghost_box0;
    always @(posedge clk) begin
        ghost_dx0<=in_x-ghost_x;ghost_dy0<=in_y-ghost_y;
        ghost_dx<=ghost_dx0;ghost_dy<=ghost_dy0;ghost_box<=ghost_box0;
        ghost_level<=miniature[ghost_dx0<=96 ? ghost_dx0 : 0];
        ghost_box0<=in_x>=ghost_x && in_x<=ghost_right && in_y>=ghost_y && in_y<=ghost_bottom;
    end
    always @(*) begin
        hit=|mark_hit;color=0;ch=0;text_valid=|mark_text;
        text_rx=0;text_ry=0;col=0;
        for(i=0;i<53;i=i+1) begin
            color=color|((mark_hit[i] || mark_text[i]) ? (mark_white[i] ? 24'hFFFFFF : mark_rgb[i]) : 24'd0);ch=ch|mark_char[i];
            text_rx=text_rx|mark_rx[i];text_ry=text_ry|mark_ry[i];
        end
        // Dedicated mode button; the selected LFO supplies the binding source.
        if(px>=1080 && px<=1240 && py>=372 && py<=398) begin
            hit=1;color=armed_r ? source_color(active_tab_r+1'b1) : 24'h28425A;
            if(px>=1096 && px<1224 && py>=380 && py<390) begin
                text_valid=1;text_rx=px[2:0];text_ry=py[3:0]-4'd12;
                col=px[7:3]-5'd9;
                ch=dragging_r ? char_at(pack_font24("DROP ON KNOB            "),col) :
                    armed_r ? char_at(pack_font24("DRAG CURVE              "),col) :
                    char_at(pack_font24("BIND LFO                "),col);
            end
        end
        if(px>=808 && px<=1240 && py>=658 && py<=693) begin
            hit=1;color=24'h181C24;
            if(selected_target_r<53) begin
                if(px>=1000) color=24'h28384A;
                if(py>=670 && py<680) begin
                    text_valid=1;text_rx=px[2:0];text_ry=py[3:0]-4'd14;ch=0;
                    if(px<1000) begin
                        col=px[7:3]-5'd6;
                        if(px>=816) ch=char_at(amount_label,col);
                    end else if(px<1080) begin
                        col=px[7:3]-5'd31;
                        if(px>=1016) ch=char_at(pack_font24("-                       "),col);
                    end else if(px<1160) begin
                        col=px[7:3]-5'd9;
                        if(px>=1096) ch=char_at(pack_font24("+                       "),col);
                    end else begin
                        col=px[7:3]-5'd19;
                        if(px>=1176) ch=char_at(pack_font24("CLEAR                   "),col);
                    end
                end
            end else if(py>=670 && py<680 && px<1000) begin
                text_valid=1;text_rx=px[2:0];text_ry=py[3:0]-4'd14;ch=0;
                col=px[7:3]-5'd6;
                if(px>=816) ch=char_at(pack_font24("UI PREVIEW / NO AUDIO   "),col);
            end
        end
        // A miniature copy of the whole seven-node curve follows the finger.
        // This drag thumbnail is linear; the main curve and parameter preview
        // continue to use the shared smooth interpolation table.
        if(dragging_r && ghost_box) begin
            hit=1;text_valid=0;
            color=ghost_dy==0 || ghost_dy==36 || ghost_dx==0 || ghost_dx==96 ? 24'hFFFFFF :
                  ghost_dy+1>=ghost_level && ghost_dy<=ghost_level+1 ? source_color(active_tab_r+1'b1) : 24'h15283A;
        end
    end
    reg hit0,hit1,tv0;
    reg [23:0] rgb0,rgb1;
    reg [5:0] ch0;
    reg [2:0] rx0;
    reg [3:0] ry0;
    reg [1:0] cov1;
    always @(posedge clk) begin
        hit0<=hit;hit1<=hit0;rgb0<=color;rgb1<=rgb0;tv0<=text_valid;
        ch0<=ch;rx0<=text_rx;ry0<=text_ry;
        cov1<=tv0 ? get_font_7x10(ch0,rx0,ry0) : 0;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin out_hit<=0;out_rgb<=0;end
        else begin
            out_hit<=hit1 || cov1!=0;
            out_rgb<=cov1!=0 ? blend_rgb_q4(rgb1==24'h50545C ? 24'hA0A4AC : 24'hFFFFFF,rgb1,font_alpha_q4(cov1)) : rgb1;
        end
    end
endmodule
