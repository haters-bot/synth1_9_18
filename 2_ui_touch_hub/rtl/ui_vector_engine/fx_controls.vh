// Shared geometry and IDs: touch, rendering and modulation use the same cells.
// Include inside a module; no guard because each module needs its own functions.
function [13:0] fx_cx;
    input integer idx;
    begin fx_cx=idx<6 ? 448+idx*56 : idx<13 ? 444+(idx-6)*48 : 448+(idx-13)*56; end
endfunction
function [13:0] fx_cy;
    input integer idx;
    begin fx_cy=idx<6 ? 416 : idx<13 ? 524 : 632; end
endfunction
function [7:0] fx_target;
    input [13:0] px,py;
    integer k;
    begin
        fx_target=0;
        for(k=0;k<19;k=k+1)
            if(px>=fx_cx(k)-22 && px<=fx_cx(k)+22 &&
               py>=fx_cy(k)-23 && py<=fx_cy(k)+23) fx_target=fx_target | (8'h60+k);
    end
endfunction
