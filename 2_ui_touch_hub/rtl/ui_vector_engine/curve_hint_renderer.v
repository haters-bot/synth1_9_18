`include "params.vh"
`include "font_3x5.vh"
`include "font_7x10.vh"
`include "pixel_coverage.vh"
module curve_hint_renderer(
    input wire clk,rst_n,
    input wire [13:0] in_x,in_y,
    input wire [1:0] env_tab,
    output reg out_hit,
    output reg [23:0] out_rgb
);
    function [5:0] label_char;
        input [143:0] text;
        input [4:0] col;
        begin
        case(col)
            0:label_char=text[143:138];
            1:label_char=text[137:132];
            2:label_char=text[131:126];
            3:label_char=text[125:120];
            4:label_char=text[119:114];
            5:label_char=text[113:108];
            6:label_char=text[107:102];
            7:label_char=text[101:96];
            8:label_char=text[95:90];
            9:label_char=text[89:84];
            10:label_char=text[83:78];
            11:label_char=text[77:72];
            12:label_char=text[71:66];
            13:label_char=text[65:60];
            14:label_char=text[59:54];
            15:label_char=text[53:48];
            16:label_char=text[47:42];
            17:label_char=text[41:36];
            18:label_char=text[35:30];
            19:label_char=text[29:24];
            20:label_char=text[23:18];
            21:label_char=text[17:12];
            22:label_char=text[11:6];
            23:label_char=text[5:0];
            default:label_char=0;
        endcase
        end
    endfunction
    wire filter_area=in_x>=880 && in_x<1072 && in_y>=108 && in_y<118;
    wire time_area=in_x>=48 && in_x<240 && in_y>=592 && in_y<602;
    wire note_area=in_x>=48 && in_x<240 && in_y>=608 && in_y<618;
    wire valid=filter_area || time_area || note_area;
    wire local_note=note_area && env_tab!=0;
    wire [3:0] row=filter_area ? in_y[3:0]-4'd12 : in_y[3:0];
    // Constant text per disjoint row: no label mux followed by a character mux.
    wire [4:0] filter_col=in_x[7:3]-5'd14;
    wire [4:0] env_col=in_x[7:3]-5'd6;
    wire [5:0] ch=(filter_area ? label_char(pack_font24("X:CUTOFF  Y:RES         "),filter_col) : 6'd0) |
                 (time_area ? label_char(pack_font24("X:TIME  Y:LEVEL         "),env_col) : 6'd0) |
                 (note_area && env_tab==0 ? label_char(pack_font24("H HANDLE ABOVE PEAK     "),env_col) : 6'd0) |
                 (note_area && env_tab!=0 ? label_char(pack_font24("ENV 2:3 LOCAL EDIT ONLY "),env_col) : 6'd0);
    reg v0,n0,n1;
    reg [1:0] coverage1;
    reg [23:0] bg0,bg1;
    reg [5:0] ch0;
    reg [2:0] rx0;
    reg [3:0] ry0;
    always @(posedge clk) begin
        v0<=valid && in_x[2:0]<7;ch0<=ch;rx0<=in_x[2:0];ry0<=row;n0<=local_note;
        bg0<=in_y<200 ? 24'h0C0E14 : 24'h181C24; bg1<=bg0;
        coverage1<=v0 ? get_font_7x10(ch0,rx0,ry0) : 2'd0;n1<=n0;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin out_hit<=0;out_rgb<=0;end
        else begin out_hit<=coverage1!=0;out_rgb<=blend_rgb_q4(n1 ? 24'hC8A870 : 24'hA0B8CC,bg1,font_alpha_q4(coverage1));end
    end
endmodule
