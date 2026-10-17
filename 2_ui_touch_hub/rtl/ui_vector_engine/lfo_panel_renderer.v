`include "params.vh"
`include "font_3x5.vh"
`include "font_7x10.vh"
`include "pixel_coverage.vh"

// Three pixel pipeline stages, matching the other vector renderers.
// Seven-point piecewise linear/stepped waveform and local preview playhead.
module lfo_panel_renderer(
    input wire clk, rst_n,
    input wire [13:0] in_x, in_y,
    input wire [1:0] active_tab, preset,
    input wire [48:0] nodes,
    input wire [2:0] rate,
    input wire once_mode, stepped,
    input wire [8:0] phase,
    input wire running,
    output reg out_hit,
    output reg [23:0] out_rgb
);
    function [6:0] node_value;
        input [2:0] idx;
        begin
            case(idx)
                0:node_value=nodes[6:0]; 1:node_value=nodes[13:7];
                2:node_value=nodes[20:14]; 3:node_value=nodes[27:21];
                4:node_value=nodes[34:28]; 5:node_value=nodes[41:35];
                default:node_value=nodes[48:42];
            endcase
        end
    endfunction
    wire [8:0] gx = in_x-14'd832;
    wire [2:0] segment = gx[8:6] < 6 ? gx[8:6] : 3'd5;
    wire [9:0] rounded_x = {1'b0,gx}+10'd32;
    wire [2:0] nearest = rounded_x[9:6] > 6 ? 3'd6 : rounded_x[8:6];
    wire [6:0] a = node_value(segment), b = node_value(segment+1'b1);
    wire [6:0] nn = node_value(nearest);
    wire [6:0] prev = node_value(segment==0 ? 3'd0 : segment-1'b1);
    wire [13:0] nx = 14'd832+{nearest,6'b0};
    wire [13:0] ny = 14'd543-nn;
    wire node_hit = in_x+3 >= nx && in_x <= nx+3 && in_y+3 >= ny && in_y <= ny+3;
    wire jump_hit = stepped && gx[5:0]==0 &&
        ((in_y>=543-a && in_y<=543-prev) || (in_y>=543-prev && in_y<=543-a));

    // Native 7x10 coverage glyphs in the existing 8-pixel character cells.
    // Decode character/coordinates first, look up the font in the next stage.
    reg [143:0] label;
    reg [13:0] tx, ty;
    reg label_area;
    always @(*) begin
        label=pack_font24("                        "); tx=0; ty=0; label_area=0;
        if(in_y>=380 && in_y<390) begin
            label_area=1; ty=380;
            if(in_x>=824 && in_x<880) begin tx=824; label=pack_font24("LFO 1                   "); end
            else if(in_x>=912 && in_x<968) begin tx=912; label=pack_font24("LFO 2                   "); end
            else if(in_x>=1000 && in_x<1056) begin tx=1000; label=pack_font24("LFO 3                   "); end
            else if(in_x>=1112 && in_x<1240) begin tx=1112; label=pack_font24("LOCAL PREVIEW           "); end
            else label_area=0;
        end else if(in_y>=570 && in_y<580) begin
            label_area=1; ty=570;
            if(in_x>=840 && in_x<920) begin tx=840; label=pack_font24("TRIANGLE                "); end
            else if(in_x>=992 && in_x<1040) begin tx=992; label=pack_font24("RAMP                    "); end
            else if(in_x>=1136 && in_x<1200) begin tx=1136; label=pack_font24("SQUARE                  "); end
            else label_area=0;
        end else if(in_y>=616 && in_y<626) begin
            label_area=1; ty=616;
            if(in_x>=856 && in_x<904) begin tx=856; label=pack_font24("RATE                    "); end
            else if(in_x>=992 && in_x<1040) begin tx=992; label=pack_font24("MODE                    "); end
            else if(in_x>=1120 && in_x<1224) begin tx=1120; label=pack_font24("RESTART                 "); end
            else label_area=0;
        end else if(in_y>=636 && in_y<646) begin
            label_area=1; ty=636;
            if(in_x>=840 && in_x<920) begin
                tx=840;
                case(rate)
                    0:label=pack_font24("0.25 HZ                 "); 1:label=pack_font24("0.5 HZ                  ");
                    2:label=pack_font24("1 HZ                    "); 3:label=pack_font24("2 HZ                    ");
                    4:label=pack_font24("4 HZ                    "); default:label=pack_font24("8 HZ                    ");
                endcase
            end else if(in_x>=984 && in_x<1048) begin tx=984; label=once_mode ? pack_font24("ONCE                    ") : pack_font24("FREE                    "); end
            else if(in_x>=1136 && in_x<1208) begin tx=1136; label=running ? pack_font24("PLAYING                 ") : pack_font24("STOPPED                 "); end
            else label_area=0;
        end else if(in_y>=664 && in_y<674 && in_x>=832 && in_x<992) begin
            label_area=1; tx=832; ty=664; label=pack_font24("DRAG THE 7 NODES        ");
        end else if(in_y>=682 && in_y<692 && in_x>=832 && in_x<992) begin
            label_area=1; tx=832; ty=682; label=pack_font24("AUDIO LINK PENDING      ");
        end
    end
    // All label origins are aligned to 8 pixels. Only character-cell bits
    // need subtraction, while the 2x glyph column comes straight from X.
    wire [4:0] text_col=in_x[7:3]-tx[7:3];
    wire [3:0] text_dy=in_y[3:0]-ty[3:0];
    reg [5:0] ch;
    always @(*) begin
        case(text_col)
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
    reg [13:0] x0,y0,x1,y1;
    reg hit0,hit1,graph0,graph1,node0,node1,grid0,grid1;
    reg jump0,jump1;
    reg [6:0] a0;
    reg signed [7:0] delta0;
    reg [6:0] frac0;
    reg signed [15:0] product1;
    reg [6:0] a1;
    reg [5:0] ch0;
    reg [2:0] rx0;
    reg [3:0] ry0;
    reg text_valid0;
    reg [1:0] text1;
    reg [23:0] base0,base1;
    reg [13:0] head0,head1;
    reg step0;
    wire signed [16:0] interpolated = $signed({10'd0,a1})+(product1 >>> 6);
    wire [13:0] curve_y = 14'd543-interpolated[6:0];
    wire signed [16:0] interpolated_q6=$signed({4'd0,a1,6'b0})+$signed(product1);
    wire signed [16:0] curve_y_q6=17'sd34752-interpolated_q6;
    wire [15:0] curve_y_q2={3'b0,curve_y_q6[16:4]};
    wire [2:0] stroke_alpha=curve_alpha_q4(y1,curve_y_q2,5'd3);
    wire [23:0] graph_bg=x1==head1 ? 24'h6888A8 : grid1 ? 24'h243244 :
        y1>curve_y ? 24'h102C3C : 24'h0A0E16;
    always @(posedge clk) begin
        x0<=in_x; y0<=in_y;
        hit0<=in_x>=796 && in_x<=1256 && in_y>=368 && in_y<=693;
        graph0<=in_x>=832 && in_x<=1216 && in_y>=416 && in_y<=543;
        node0<=node_hit;
        jump0<=jump_hit;
        grid0<=gx[5:0]==0 || in_y==416 || in_y==448 || in_y==480 || in_y==512 || in_y==543;
        a0<=a; delta0<=$signed({1'b0,b})-$signed({1'b0,a});
        frac0<=in_x==1216 ? 7'd64 : {1'b0,gx[5:0]};
        head0<=14'd832+phase;
        step0<=stepped;
        ch0<=ch; rx0<=in_x[2:0]; ry0<=text_dy;
        text_valid0<=label_area && text_col<20 && in_x[2:0]<7;
        base0<=24'h181C24;
        if(in_x==796 || in_x==1256 || in_y==368 || in_y==693) base0<=24'h2A3140;
        else if(in_y<=398) begin
            base0<=24'h222834;
            if((in_x>=808 && in_x<=888 && active_tab==0) ||
               (in_x>=896 && in_x<=976 && active_tab==1) ||
               (in_x>=984 && in_x<=1064 && active_tab==2))
                base0<=in_y<=375 ? 24'h38E8FF : 24'h28425C;
        end else if(in_x>=824 && in_x<=1224 && in_y>=408 && in_y<=552)
            base0<=(in_x==824 || in_x==1224 || in_y==408 || in_y==552) ? 24'h2A3140 : 24'h0A0E16;
        else if(in_x>=808 && in_x<=1240 && in_y>=560 && in_y<=590) begin
            base0<=24'h222E40;
            if((in_x<=936 && preset==0) || (in_x>=944 && in_x<=1072 && preset==1) ||
               (in_x>=1080 && preset==2)) base0<=24'h284B60;
            if(in_x==940 || in_x==1076) base0<=24'h181C24;
        end else if(in_x>=808 && in_x<=1240 && in_y>=608 && in_y<=652)
            base0<=(in_x==940 || in_x==1076) ? 24'h181C24 : 24'h222E40;

        x1<=x0; y1<=y0; hit1<=hit0; graph1<=graph0;
        node1<=node0; grid1<=grid0; base1<=base0; head1<=head0; jump1<=jump0;
        a1<=a0;
        product1<=step0 && frac0!=64 ? 16'sd0 : delta0*$signed({1'b0,frac0});
        text1<=text_valid0 ? get_font_7x10(ch0,rx0,ry0) : 2'd0;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin out_hit<=0; out_rgb<=0; end
        else begin
            out_hit<=hit1; out_rgb<=base1;
            if(graph1) begin
                if(node1) out_rgb<=24'hFFFFFF;
                else if(jump1) out_rgb<=24'h38E8FF;
                else if(stroke_alpha!=0) out_rgb<=blend_rgb_q4(24'h38E8FF,graph_bg,stroke_alpha);
                else if(x1==head1) out_rgb<=24'h6888A8;
                else if(grid1) out_rgb<=24'h243244;
                else if(y1>curve_y) out_rgb<=24'h102C3C;
                else out_rgb<=24'h0A0E16;
            end
            if(text1!=0) out_rgb<=blend_rgb_q4(y1>=682 ? 24'hC8A870 : 24'hE0E8F0,base1,font_alpha_q4(text1));
        end
    end
endmodule
