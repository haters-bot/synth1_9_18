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
    input wire [12:0] curve_q6,
    output reg out_hit,
    output reg [23:0] out_rgb
);
    // Control state settles independently of the pixel pipeline. Isolate the
    // editor's bank selection before the per-pixel nearest-node mux/geometry.
    reg [48:0] nodes_r;
    always @(posedge clk) nodes_r<=nodes;
    function [6:0] node_value;
        input [2:0] idx;
        begin
            case(idx)
                0:node_value=nodes_r[6:0]; 1:node_value=nodes_r[13:7];
                2:node_value=nodes_r[20:14]; 3:node_value=nodes_r[27:21];
                4:node_value=nodes_r[34:28]; 5:node_value=nodes_r[41:35];
                default:node_value=nodes_r[48:42];
            endcase
        end
    endfunction
    wire [8:0] gx = in_x-14'd832;
    wire [2:0] segment = gx[8:6] < 6 ? gx[8:6] : 3'd5;
    wire [6:0] a = node_value(segment), b = node_value(segment+1'b1);
    wire [6:0] prev = node_value(segment==0 ? 3'd0 : segment-1'b1);
    // Node boxes are disjoint (7 x 7 pixels), so nearest-node selection is
    // unnecessary for hit testing. Parallel fixed-X boxes remove the
    // segment/nearest/node-value mux chain from the first pixel stage.
    wire node_hit0 = in_x >= 14'd829 && in_x <= 14'd835 &&
        in_y+14'd3 >= (14'd543-{7'd0,nodes_r[6:0]}) &&
        in_y <= (14'd543-{7'd0,nodes_r[6:0]})+14'd3;
    wire node_hit1 = in_x >= 14'd893 && in_x <= 14'd899 &&
        in_y+14'd3 >= (14'd543-{7'd0,nodes_r[13:7]}) &&
        in_y <= (14'd543-{7'd0,nodes_r[13:7]})+14'd3;
    wire node_hit2 = in_x >= 14'd957 && in_x <= 14'd963 &&
        in_y+14'd3 >= (14'd543-{7'd0,nodes_r[20:14]}) &&
        in_y <= (14'd543-{7'd0,nodes_r[20:14]})+14'd3;
    wire node_hit3 = in_x >= 14'd1021 && in_x <= 14'd1027 &&
        in_y+14'd3 >= (14'd543-{7'd0,nodes_r[27:21]}) &&
        in_y <= (14'd543-{7'd0,nodes_r[27:21]})+14'd3;
    wire node_hit4 = in_x >= 14'd1085 && in_x <= 14'd1091 &&
        in_y+14'd3 >= (14'd543-{7'd0,nodes_r[34:28]}) &&
        in_y <= (14'd543-{7'd0,nodes_r[34:28]})+14'd3;
    wire node_hit5 = in_x >= 14'd1149 && in_x <= 14'd1155 &&
        in_y+14'd3 >= (14'd543-{7'd0,nodes_r[41:35]}) &&
        in_y <= (14'd543-{7'd0,nodes_r[41:35]})+14'd3;
    wire node_hit6 = in_x >= 14'd1213 && in_x <= 14'd1219 &&
        in_y+14'd3 >= (14'd543-{7'd0,nodes_r[48:42]}) &&
        in_y <= (14'd543-{7'd0,nodes_r[48:42]})+14'd3;
    wire node_hit = node_hit0 || node_hit1 || node_hit2 || node_hit3 ||
                    node_hit4 || node_hit5 || node_hit6;
    wire jump_hit = stepped && gx[5:0]==0 &&
        ((in_y>=543-a && in_y<=543-prev) || (in_y>=543-prev && in_y<=543-a));

    // Native 7x10 coverage glyphs in the existing 8-pixel character cells.
    // Decode character/coordinates first, look up the font in the next stage.
    reg [4:0] label_id;
    reg [13:0] tx, ty;
    reg label_area;
    always @(*) begin
        label_id=0; tx=0; ty=0; label_area=0;
        if(in_y>=380 && in_y<390) begin
            label_area=1; ty=380;
            if(in_x>=824 && in_x<880) begin tx=824; label_id=1; end
            else if(in_x>=912 && in_x<968) begin tx=912; label_id=2; end
            else if(in_x>=1000 && in_x<1056) begin tx=1000; label_id=3; end
            else if(in_x>=1112 && in_x<1240) begin tx=1112; label_id=4; end
            else label_area=0;
        end else if(in_y>=570 && in_y<580) begin
            label_area=1; ty=570;
            if(in_x>=840 && in_x<920) begin tx=840; label_id=5; end
            else if(in_x>=992 && in_x<1040) begin tx=992; label_id=6; end
            else if(in_x>=1136 && in_x<1200) begin tx=1136; label_id=7; end
            else label_area=0;
        end else if(in_y>=616 && in_y<626) begin
            label_area=1; ty=616;
            if(in_x>=856 && in_x<904) begin tx=856; label_id=8; end
            else if(in_x>=992 && in_x<1040) begin tx=992; label_id=9; end
            else if(in_x>=1120 && in_x<1224) begin tx=1120; label_id=10; end
            else label_area=0;
        end else if(in_y>=636 && in_y<646) begin
            label_area=1; ty=636;
            if(in_x>=840 && in_x<920) begin
                tx=840;
                label_id=11;
            end else if(in_x>=984 && in_x<1048) begin tx=984; label_id=12; end
            else if(in_x>=1136 && in_x<1208) begin tx=1136; label_id=13; end
            else label_area=0;
        end else if(in_y>=664 && in_y<674 && in_x>=832 && in_x<992) begin
            label_area=1; tx=832; ty=664; label_id=14;
        end else if(in_y>=682 && in_y<692 && in_x>=832 && in_x<992) begin
            label_area=1; tx=832; ty=682; label_id=15;
        end
    end
    // Capture the character number before the font lookup. Keeping the packed
    // label and origin out of the second stage removes a coordinate subtract
    // plus 24-way character mux from the font register path.
    reg [13:0] x0 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [13:0] y0 /* synthesis syn_preserve=1 syn_maxfan=32 */;
    reg [5:0] char0;
    reg [3:0] text_ry0;
    reg text_valid0;
    reg [2:0] text_rx0;
    function [5:0] label_char_at;
        input [4:0] id;
        input [4:0] column;
        input [2:0] rate_sel;
        input once_sel, running_sel;
        begin
            label_char_at=0;
            case(id)
                1,2,3: begin
                    case(column)
                        0:label_char_at=`CH_L; 1:label_char_at=`CH_F; 2:label_char_at=`CH_O;
                        4:label_char_at=`CH_1+(id-1);
                    endcase
                end
                4: begin case(column)
                    0:label_char_at=`CH_L; 1:label_char_at=`CH_O; 2:label_char_at=`CH_C;
                    3:label_char_at=`CH_A; 4:label_char_at=`CH_L; 6:label_char_at=`CH_P;
                    7:label_char_at=`CH_R; 8:label_char_at=`CH_E; 9:label_char_at=`CH_V;
                    10:label_char_at=`CH_I; 11:label_char_at=`CH_E; 12:label_char_at=`CH_W;
                endcase end
                5: begin case(column)
                    0:label_char_at=`CH_T; 1:label_char_at=`CH_R; 2:label_char_at=`CH_I;
                    3:label_char_at=`CH_A; 4:label_char_at=`CH_N; 5:label_char_at=`CH_G;
                    6:label_char_at=`CH_L; 7:label_char_at=`CH_E;
                endcase end
                6: begin case(column)
                    0:label_char_at=`CH_R; 1:label_char_at=`CH_A; 2:label_char_at=`CH_M; 3:label_char_at=`CH_P;
                endcase end
                7: begin case(column)
                    0:label_char_at=`CH_S; 1:label_char_at=`CH_Q; 2:label_char_at=`CH_U;
                    3:label_char_at=`CH_A; 4:label_char_at=`CH_R; 5:label_char_at=`CH_E;
                endcase end
                8: begin case(column) 0:label_char_at=`CH_R; 1:label_char_at=`CH_A; 2:label_char_at=`CH_T; 3:label_char_at=`CH_E; endcase end
                9: begin case(column) 0:label_char_at=`CH_M; 1:label_char_at=`CH_O; 2:label_char_at=`CH_D; 3:label_char_at=`CH_E; endcase end
                10: begin case(column) 0:label_char_at=`CH_R; 1:label_char_at=`CH_E; 2:label_char_at=`CH_S; 3:label_char_at=`CH_T; 4:label_char_at=`CH_A; 5:label_char_at=`CH_R; 6:label_char_at=`CH_T; endcase end
                11: begin case(rate_sel)
                    0: case(column) 0:label_char_at=`CH_0; 1:label_char_at=`CH_DOT; 2:label_char_at=`CH_2; 3:label_char_at=`CH_5; 5:label_char_at=`CH_H; 6:label_char_at=`CH_Z; endcase
                    1: case(column) 0:label_char_at=`CH_0; 1:label_char_at=`CH_DOT; 2:label_char_at=`CH_5; 4:label_char_at=`CH_H; 5:label_char_at=`CH_Z; endcase
                    2: case(column) 0:label_char_at=`CH_1; 2:label_char_at=`CH_H; 3:label_char_at=`CH_Z; endcase
                    3: case(column) 0:label_char_at=`CH_2; 2:label_char_at=`CH_H; 3:label_char_at=`CH_Z; endcase
                    4: case(column) 0:label_char_at=`CH_4; 2:label_char_at=`CH_H; 3:label_char_at=`CH_Z; endcase
                    5: case(column) 0:label_char_at=`CH_8; 2:label_char_at=`CH_H; 3:label_char_at=`CH_Z; endcase
                    6: case(column) 0:label_char_at=`CH_1; 1:label_char_at=`CH_6; 3:label_char_at=`CH_H; 4:label_char_at=`CH_Z; endcase
                    7: case(column) 0:label_char_at=`CH_3; 1:label_char_at=`CH_2; 3:label_char_at=`CH_H; 4:label_char_at=`CH_Z; endcase
                endcase end
                12: begin case(column) 0:label_char_at=once_sel?`CH_O:`CH_F; 1:label_char_at=once_sel?`CH_N:`CH_R; 2:label_char_at=once_sel?`CH_C:`CH_E; 3:label_char_at=once_sel?`CH_E:`CH_E; endcase end
                13: begin case(column) 0:label_char_at=running_sel?`CH_P:`CH_S; 1:label_char_at=running_sel?`CH_L:`CH_T; 2:label_char_at=running_sel?`CH_A:`CH_O; 3:label_char_at=running_sel?`CH_Y:`CH_P; 4:label_char_at=running_sel?`CH_I:`CH_P; 5:label_char_at=running_sel?`CH_N:`CH_E; 6:label_char_at=running_sel?`CH_G:`CH_D; 7:label_char_at=running_sel?`CH_SPACE:`CH_E; endcase end
                14: begin case(column) 0:label_char_at=`CH_D; 1:label_char_at=`CH_R; 2:label_char_at=`CH_A; 3:label_char_at=`CH_G; 5:label_char_at=`CH_T; 6:label_char_at=`CH_H; 8:label_char_at=`CH_7; 10:label_char_at=`CH_N; 11:label_char_at=`CH_O; 12:label_char_at=`CH_D; 13:label_char_at=`CH_E; 14:label_char_at=`CH_S; endcase end
                15: begin case(column) 0:label_char_at=`CH_A; 1:label_char_at=`CH_U; 2:label_char_at=`CH_D; 3:label_char_at=`CH_I; 4:label_char_at=`CH_O; 6:label_char_at=`CH_L; 7:label_char_at=`CH_I; 8:label_char_at=`CH_N; 9:label_char_at=`CH_K; 11:label_char_at=`CH_P; 12:label_char_at=`CH_E; 13:label_char_at=`CH_N; 14:label_char_at=`CH_D; 15:label_char_at=`CH_I; 16:label_char_at=`CH_N; 17:label_char_at=`CH_G; endcase end
            endcase
        end
    endfunction
    // Disjoint label rectangles: decode constant labels in parallel rather
    // than selecting an ID/origin before a second variable character mux.
    wire [5:0] char_parallel =
        ((in_x>=14'd824 && in_x<14'd880 && in_y>=14'd380 && in_y<14'd390) ?
            label_char_at(5'd1,in_x[7:3]-5'd7,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd912 && in_x<14'd968 && in_y>=14'd380 && in_y<14'd390) ?
            label_char_at(5'd2,in_x[7:3]-5'd18,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd1000 && in_x<14'd1056 && in_y>=14'd380 && in_y<14'd390) ?
            label_char_at(5'd3,in_x[7:3]-5'd29,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd1112 && in_x<14'd1240 && in_y>=14'd380 && in_y<14'd390) ?
            label_char_at(5'd4,in_x[7:3]-5'd11,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd840 && in_x<14'd920 && in_y>=14'd570 && in_y<14'd580) ?
            label_char_at(5'd5,in_x[7:3]-5'd9,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd992 && in_x<14'd1040 && in_y>=14'd570 && in_y<14'd580) ?
            label_char_at(5'd6,in_x[7:3]-5'd28,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd1136 && in_x<14'd1200 && in_y>=14'd570 && in_y<14'd580) ?
            label_char_at(5'd7,in_x[7:3]-5'd14,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd856 && in_x<14'd904 && in_y>=14'd616 && in_y<14'd626) ?
            label_char_at(5'd8,in_x[7:3]-5'd11,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd992 && in_x<14'd1040 && in_y>=14'd616 && in_y<14'd626) ?
            label_char_at(5'd9,in_x[7:3]-5'd28,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd1120 && in_x<14'd1224 && in_y>=14'd616 && in_y<14'd626) ?
            label_char_at(5'd10,in_x[7:3]-5'd12,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd840 && in_x<14'd920 && in_y>=14'd636 && in_y<14'd646) ?
            label_char_at(5'd11,in_x[7:3]-5'd9,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd984 && in_x<14'd1048 && in_y>=14'd636 && in_y<14'd646) ?
            label_char_at(5'd12,in_x[7:3]-5'd27,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd1136 && in_x<14'd1208 && in_y>=14'd636 && in_y<14'd646) ?
            label_char_at(5'd13,in_x[7:3]-5'd14,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd832 && in_x<14'd992 && in_y>=14'd664 && in_y<14'd674) ?
            label_char_at(5'd14,in_x[7:3]-5'd8,rate,once_mode,running) : 6'd0) |
        ((in_x>=14'd832 && in_x<14'd992 && in_y>=14'd682 && in_y<14'd692) ?
            label_char_at(5'd15,in_x[7:3]-5'd8,rate,once_mode,running) : 6'd0);
    reg [13:0] x1,y1;
    reg hit0,hit1,graph0,graph1,node0,node1,grid0,grid1;
    reg jump0,jump1;
    reg [6:0] a0;
    reg signed [7:0] delta0;
    reg [6:0] frac0;
    reg signed [15:0] product1;
    reg [6:0] a1;
    reg [1:0] text1;
    reg [23:0] base0,base1;
    reg [13:0] head0,head1;
    reg step0;
    wire signed [16:0] interpolated = $signed({10'd0,a1})+(product1 >>> 6);
    reg [12:0] amplitude0,amplitude1;
    wire [13:0] curve_y = 14'd543-amplitude1[12:6];
    wire signed [16:0] interpolated_q6=$signed({4'd0,a1,6'b0})+$signed(product1);
    wire signed [16:0] curve_y_q6=17'sd34752-$signed({4'd0,amplitude1});
    wire [15:0] curve_y_q2={3'b0,curve_y_q6[16:4]};
    wire [2:0] stroke_alpha=curve_alpha_q4(y1,curve_y_q2,5'd3);
    wire [23:0] graph_bg=x1==head1 ? 24'h6888A8 : grid1 ? 24'h243244 :
        y1>curve_y ? 24'h102C3C : 24'h0A0E16;
    always @(posedge clk) begin
        amplitude0<=curve_q6;amplitude1<=amplitude0;
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
        char0<=char_parallel;
        text_ry0<=in_y[3:0]-ty[3:0];
        text_valid0<=label_area && ((in_x[7:3]-tx[7:3])<20);
        text_rx0<=in_x[2:0];
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
        text1<=text_valid0 && text_rx0<7 ?
            get_font_7x10(char0,text_rx0,text_ry0) : 2'd0;
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
