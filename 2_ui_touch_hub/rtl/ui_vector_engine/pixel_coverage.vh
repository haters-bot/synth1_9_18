`ifndef PIXEL_COVERAGE_VH
`define PIXEL_COVERAGE_VH
// Quarter-coverage blend. Ten-bit intermediates prevent bright-color overflow.
function [7:0] blend_channel_q4;
    input [7:0] fg,bg;
    input [2:0] alpha;
    reg [9:0] f,b,sum;
    begin
        f={2'b0,fg}; b={2'b0,bg};
        case(alpha)
            1:sum=f+b+(b<<1);
            2:sum=(f<<1)+(b<<1);
            3:sum=f+(f<<1)+b;
            4:sum=f<<2;
            default:sum=b<<2;
        endcase
        blend_channel_q4=sum[9:2];
    end
endfunction
function [23:0] blend_rgb_q4;
    input [23:0] fg,bg;
    input [2:0] alpha;
    begin
        blend_rgb_q4={blend_channel_q4(fg[23:16],bg[23:16],alpha),
                      blend_channel_q4(fg[15:8],bg[15:8],alpha),
                      blend_channel_q4(fg[7:0],bg[7:0],alpha)};
    end
endfunction
function [2:0] font_alpha_q4;
    input [1:0] coverage;
    begin
        case(coverage)
            1:font_alpha_q4=1;
            2:font_alpha_q4=3;
            3:font_alpha_q4=4;
            default:font_alpha_q4=0;
        endcase
    end
endfunction
// Pixel-area coverage about a Q2 line center. The half-width can grow for
// steep ENV segments so a rising edge_limit stays connected between columns.
function [2:0] curve_alpha_q4;
    input [13:0] y;
    input [15:0] target_q2;
    input [4:0] half_width_q2;
    reg [15:0] py,distance_q2;
    reg [5:0] edge_limit;
    begin
        py={y,2'b0};
        distance_q2=py>=target_q2 ? py-target_q2 : target_q2-py;
        edge_limit={1'b0,half_width_q2}+6'd2;
        if(distance_q2>=edge_limit) curve_alpha_q4=0;
        else if(edge_limit-distance_q2>=4) curve_alpha_q4=4;
        else curve_alpha_q4=edge_limit-distance_q2;
    end
endfunction
`endif
