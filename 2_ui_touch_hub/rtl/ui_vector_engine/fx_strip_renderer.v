`include "params.vh"
`include "font_3x5.vh"
`include "font_7x10.vh"
`include "pixel_coverage.vh"
// Three stacked effect strips in X420..780. Five-stage raster pipeline.
module fx_strip_renderer(
    input wire clk,rst_n,
    input wire [13:0] in_x,in_y,
    input wire [132:0] values,
    input wire [10:0] switches,
    input wire [7:0] selected_id,
    output reg out_hit,
    output reg [23:0] out_rgb
);
    `include "fx_controls.vh"
    function [5:0] digit;
        input [3:0] num;
        begin digit=`CH_0+num;end
    endfunction
    function [7:0] small_square;
        input [5:0] d;
        begin case(d)
            13:small_square=169;12:small_square=144;11:small_square=121;
            10:small_square=100;9:small_square=81;8:small_square=64;
            7:small_square=49;6:small_square=36;5:small_square=25;
            4:small_square=16;3:small_square=9;2:small_square=4;
            1:small_square=1;default:small_square=0;
        endcase end
    endfunction
    // A bounded one-hot character mux avoids subtract/multiply/barrel-shift
    // of a 32-bit signed raster column in the old implementation.
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
    function [143:0] knob_label;
        input integer idx;
        begin case(idx)
            0:knob_label=pack_font24("FDBK                    ");
            1:knob_label=pack_font24("LEFT                    ");
            2:knob_label=pack_font24("RIGHT                   ");
            3:knob_label=pack_font24("FREQ                    ");
            4:knob_label=pack_font24("Q                       ");
            5,12:knob_label=pack_font24("MIX                     ");
            6:knob_label=pack_font24("SIZE                    ");
            7:knob_label=pack_font24("DECAY                   ");
            8:knob_label=pack_font24("L CUT                   ");
            9:knob_label=pack_font24("H CUT                   ");
            10:knob_label=pack_font24("SPIN                    ");
            11:knob_label=pack_font24("DEPTH                   ");
            13,16:knob_label=pack_font24("FREQ                    ");
            14,17:knob_label=pack_font24("Q                       ");
            default:knob_label=pack_font24("GAIN                    ");
        endcase end
    endfunction
    reg [13:0] px,py;
    reg [13:0] px0 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [13:0] py0 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [132:0] values_r;
    reg [10:0] switches_r;
    always @(posedge clk) begin
        px0<=in_x;py0<=in_y;px<=px0;py<=py0;values_r<=values;switches_r<=switches;
    end
    reg [18:0] body_knob,body_bar,body_text;
    reg [23:0] body_rgb[0:18];
    reg [5:0] body_char[0:18];
    reg [2:0] body_rx[0:18];
    reg [3:0] body_ry[0:18];
    genvar n;
    generate for(n=0;n<19;n=n+1) begin: cells
        localparam [13:0] CX=fx_cx(n),CY=fx_cy(n);
        localparam [23:0] ACCENT=n<6 ? 24'hBC7DFF : n<13 ? 24'h9FE438 : 24'hB6CADC;
        localparam [143:0] CAPTION=knob_label(n);
        wire [6:0] value=values_r[n*7+:7];
        // Decimal conversion belongs to the control plane, before pixel muxes.
        reg [6:0] rem0,rem1;
        reg [3:0] hundreds0,hundreds1,hundreds2,tens1,tens2,units2;
        reg [5:0] bar_width;
        wire [12:0] bar_product=value*6'd40;
        always @(posedge clk) begin
            rem0<=value>=100 ? value-7'd100 : value;
            hundreds0<=value>=100 ? 1 : 0;
            rem1<=rem0;tens1<=rem0/7'd10;hundreds1<=hundreds0;
            tens2<=tens1;units2<=rem1-tens1*4'd10;hundreds2<=hundreds1;
            bar_width<=bar_product[12:7];
        end
        reg box_hit;
        reg [5:0] lx;
        reg [6:0] ly;
        always @(posedge clk) begin
            box_hit<=in_x>=CX-14'd24 && in_x<CX+14'd24 && in_y>=CY-14'd19 && in_y<CY+14'd55;
            lx<=in_x-(CX-14'd24);ly<=in_y-(CY-14'd19);
        end
        wire [5:0] ax=lx>=24 ? lx-6'd24 : 6'd24-lx;
        wire [6:0] ay=ly>=19 ? ly-7'd19 : 7'd19-ly;
        wire [8:0] radius2={1'b0,small_square(ax)}+{1'b0,small_square(ay[5:0])};
        wire knob_hit=box_hit && ax<=13 && ay<=13 && radius2<=169;
        wire bar_hit=box_hit && ly==66 && lx>=4 && lx<=6'd4+bar_width;
        wire [23:0] cell_color=(knob_hit || bar_hit) ?
            ((bar_hit || radius2>=121) ? (selected_id==8'h60+n ? 24'hFFFFFF : ACCENT) : 24'h101620) : 24'd0;
        wire caption_hit=box_hit && ly>=40 && ly<50 && lx>=4;
        wire number_hit=box_hit && ly>=14 && ly<24 && lx>=12 && lx<36;
        wire [5:0] caption_x=lx-6'd4;
        wire text_hit=caption_hit || number_hit;
        wire [5:0] cell_char=caption_hit ? char_at(CAPTION,{2'd0,caption_x[5:3]}) :
            number_hit ? digit(lx<20 ? hundreds2 : lx<28 ? tens2 : units2) : 6'd0;
        wire [2:0] cell_rx=caption_hit ? lx-6'd4 : number_hit ? lx-6'd12 : 3'd0;
        wire [3:0] cell_ry=caption_hit ? ly-7'd40 : number_hit ? ly-7'd14 : 4'd0;
        always @(posedge clk) begin
            body_knob[n]<=knob_hit;body_bar[n]<=bar_hit;body_rgb[n]<=cell_color;
            body_text[n]<=text_hit;body_char[n]<=cell_char;body_rx[n]<=cell_rx;body_ry[n]<=cell_ry;
        end
    end endgenerate

    // Fixed caption cells decode independently one raster stage earlier.
    // This removes row -> label/origin mux -> character mux from ch0's path.
    function [13:0] header_left;
        input integer n;
        begin case(n)
            0,5,8:header_left=432;1,9:header_left=512;2:header_left=576;
            3:header_left=648;6:header_left=568;10:header_left=632;
            default:header_left=752;
        endcase end
    endfunction
    function [13:0] header_right;
        input integer n;
        begin case(n)
            0,5,8:header_right=496;1:header_right=570;2:header_right=640;
            3,10:header_right=752;6:header_right=712;9:header_right=614;
            default:header_right=781;
        endcase end
    endfunction
    function [143:0] header_caption;
        input integer n;
        input [10:0] sw;
        begin case(n)
            0:header_caption=pack_font24("DELAY                   ");
            1:header_caption=sw[3] ? pack_font24("BPM                     ") : pack_font24("FREE                    ");
            2:header_caption=sw[4] ? pack_font24("LINK                    ") : pack_font24("DUAL                    ");
            3:header_caption=sw[5] ? pack_font24("PINGPONG                ") : pack_font24("NORMAL                  ");
            5:header_caption=pack_font24("REVERB                  ");
            6:header_caption=sw[6] ? pack_font24("HALL                    ") : pack_font24("PLATE                   ");
            8:header_caption=pack_font24("EQ                      ");
            9:header_caption=sw[9] ? pack_font24("L CUT                   ") : sw[7] ? pack_font24("L SHELF                 ") : pack_font24("L BELL                  ");
            10:header_caption=sw[10] ? pack_font24("H CUT                   ") : sw[8] ? pack_font24("H SHELF                 ") : pack_font24("H BELL                  ");
            default:header_caption=pack_font24("ON                      ");
        endcase end
    endfunction
    wire [11:0] header_cells;
    wire [5:0] header_chars[0:11];
    wire [3:0] header_rows[0:11];
    genvar hn;
    generate for(hn=0;hn<12;hn=hn+1) begin: header_cells_decode
        localparam [13:0] LEFT=header_left(hn),RIGHT=header_right(hn);
        localparam [13:0] TOP=hn<5 ? 380 : hn<8 ? 488 : 596;
        assign header_cells[hn]=px0>=LEFT && px0<RIGHT && py0>=TOP && py0<TOP+10;
        assign header_chars[hn]=header_cells[hn] ?
            char_at(header_caption(hn,switches_r),px0[7:3]-LEFT[7:3]) : 6'd0;
        assign header_rows[hn]=header_cells[hn] ? py0[3:0]-TOP[3:0] : 4'd0;
    end endgenerate
    reg header_text;
    reg [5:0] header_char,header_char_comb;
    reg [2:0] header_rx;
    reg [3:0] header_ry,header_ry_comb;
    integer hc;
    always @(*) begin
        header_char_comb=0;header_ry_comb=0;
        for(hc=0;hc<12;hc=hc+1) begin
            header_char_comb=header_char_comb|header_chars[hc];
            header_ry_comb=header_ry_comb|header_rows[hc];
        end
    end
    always @(posedge clk) begin
        header_text<=|header_cells;header_char<=header_char_comb;
        header_rx<=px0[2:0];header_ry<=header_ry_comb;
    end
    reg [23:0] bg;
    reg [5:0] ch;
    reg [2:0] rx;
    reg [3:0] ry;
    reg valid;
    wire header0=py>=368 && py<=395;
    wire header1=py>=476 && py<=503;
    wire header2=py>=584 && py<=611;
    wire border=px==420 || px==780 || py==368 || py==476 || py==584 || py==693;
    integer i;
    always @(*) begin
        bg=24'h181C24;ch=0;rx=0;ry=0;valid=|body_text;
        for(i=0;i<19;i=i+1) begin
            ch=ch|body_char[i];rx=rx|body_rx[i];ry=ry|body_ry[i];
        end
        if(|(body_knob|body_bar)) begin
            bg=0;
            for(i=0;i<19;i=i+1) bg=bg|body_rgb[i];
        end
        if(border) begin bg=24'h384256;valid=0;end
        else if(header0 || header1 || header2) begin
            bg=24'h222834;valid=0;
            if(px>=748 && px<=776) begin
                if(header0) bg=switches_r[0] ? 24'hBC7DFF : 24'h343844;
                else if(header1) bg=switches_r[1] ? 24'h9FE438 : 24'h343844;
                else bg=switches_r[2] ? 24'hB6CADC : 24'h343844;
            end
            if(header_text) begin
                valid=1;ch=header_char;rx=header_rx;ry=header_ry;
            end
        end
    end
    reg hit0,hit1,valid0;
    reg [23:0] bg0,bg1;
    reg [5:0] ch0;
    reg [2:0] rx0;
    reg [3:0] ry0;
    reg [1:0] coverage1;
    always @(posedge clk) begin
        hit0<=px>=420 && px<=780 && py>=368 && py<=693;
        hit1<=hit0;bg0<=bg;bg1<=bg0;ch0<=ch;
        rx0<=rx;ry0<=ry;valid0<=valid;
        coverage1<=valid0 ? get_font_7x10(ch0,rx0,ry0) : 0;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin out_hit<=0;out_rgb<=0;end
        else begin out_hit<=hit1;out_rgb<=blend_rgb_q4(24'hE0E8F0,bg1,font_alpha_q4(coverage1));end
    end
endmodule
