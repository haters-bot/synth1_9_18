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
    reg [143:0] label;
    reg valid;
    reg [4:0] col;
    reg [3:0] row;
    reg [5:0] ch;
    reg local_note;
    always @(*) begin
        valid=0;label=pack_font24("                        ");col=0;row=0;local_note=0;
        if(in_x>=880 && in_x<1072 && in_y>=108 && in_y<118) begin
            valid=1;col=(in_x-880)>>3;row=in_y[3:0]-4'd12;
            label=pack_font24("X:CUTOFF  Y:RES         ");
        end else if(in_x>=48 && in_x<240 && in_y>=592 && in_y<602) begin
            valid=1;col=(in_x-48)>>3;row=in_y[3:0];
            label=pack_font24("X:TIME  Y:LEVEL         ");
        end else if(in_x>=48 && in_x<240 && in_y>=608 && in_y<618) begin
            valid=1;col=(in_x-48)>>3;row=in_y[3:0];local_note=env_tab!=0;
            label=env_tab==0 ? pack_font24("H HANDLE ABOVE PEAK     ") : pack_font24("ENV 2:3 LOCAL EDIT ONLY ");
        end
        case(col)
            0:ch=label[143:138];
            1:ch=label[137:132];
            2:ch=label[131:126];
            3:ch=label[125:120];
            4:ch=label[119:114];
            5:ch=label[113:108];
            6:ch=label[107:102];
            7:ch=label[101:96];
            8:ch=label[95:90];
            9:ch=label[89:84];
            10:ch=label[83:78];
            11:ch=label[77:72];
            12:ch=label[71:66];
            13:ch=label[65:60];
            14:ch=label[59:54];
            15:ch=label[53:48];
            16:ch=label[47:42];
            17:ch=label[41:36];
            18:ch=label[35:30];
            19:ch=label[29:24];
            20:ch=label[23:18];
            21:ch=label[17:12];
            22:ch=label[11:6];
            23:ch=label[5:0];
            default:ch=0;
        endcase
    end
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
