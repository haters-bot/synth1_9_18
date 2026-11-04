`include "params.vh"

// Captures a curve gesture at first contact; edits absolute parameter values.
// All arithmetic is at touch/control rate, outside the raster path.
module curve_touch_editor # (parameter WATCHDOG_CYCLES=2500000,
                            parameter USE_DISPLAY_GEOMETRY=0)(
    input wire clk,rst_n,
    input wire touch_valid,touch_down,
    input wire [13:0] touch_x,touch_y,
    input wire [6:0] cutoff,resonance,
    input wire [1:0] filter_type,env_tab,
    input wire [6:0] attack,hold,decay,sustain,release_v,
    input wire [34:0] display_env_values,
    output reg capture_active,
    output reg focus_valid,
    output reg [7:0] focus_id,
    output reg update_valid,update_filter,
    output reg [1:0] update_tab,
    output reg [4:0] update_mask,
    output reg [34:0] update_values
);
    reg finger_down,filter_gesture,notch_gesture;
    reg [2:0] handle;
    reg [1:0] captured_tab;
    reg [13:0] anchor_x,anchor_y;
    reg [6:0] base_cut,base_res,base_a,base_h,base_d,base_s,base_r;
    reg [21:0] watchdog;
    // Keep the touch packet and parameter snapshot aligned through four
    // geometry stages: lengths, endpoints, distances, balanced minimum tree.
    // Normalized coordinates are bounded to 1279/719 by the shared router.
    reg [3:0] valid_pipe;
    reg down_pipe[0:3];
    reg [13:0] x_pipe[0:3],y_pipe[0:3];
    reg [6:0] cut_pipe[0:3],res_pipe[0:3];
    reg [6:0] a_pipe[0:3],h_pipe[0:3],d_pipe[0:3],s_pipe[0:3],r_pipe[0:3];
    reg [1:0] tab_pipe[0:3],type_pipe[0:3];
    reg [7:0] la0,lh0,ld0,lr0,sh0;
    reg [9:0] ax1,hx1,dx1,sx1,rx1,sy1;
    reg [11:0] distances2[0:4];
    reg [11:0] best_dist;
    reg [2:0] nearest;
    integer pipe_i;
    // Locate moving handles at their displayed modulation position, but latch
    // the separate base inputs for no-jump relative parameter edits.
    wire [34:0] hit_env=USE_DISPLAY_GEOMETRY ? display_env_values : {release_v,sustain,decay,hold,attack};
    function [11:0] distance;
        input [10:0] x;
        input [9:0] y,nx,ny;
        reg [10:0] adx;
        reg [9:0] ady;
        begin
            adx=x>nx ? x-nx : nx-x;ady=y>ny ? y-ny : ny-y;
            distance={1'b0,adx}+{2'b0,ady};
        end
    endfunction
    wire choose_h=distances2[1]<distances2[0];
    wire choose_s=distances2[3]<distances2[2];
    wire [11:0] pair_ah=choose_h ? distances2[1] : distances2[0];
    wire [11:0] pair_ds=choose_s ? distances2[3] : distances2[2];
    wire choose_ds=pair_ds<pair_ah;
    wire [11:0] best_four=choose_ds ? pair_ds : pair_ah;
    wire [2:0] best_four_id=choose_ds ? (choose_s ? 3'd3 : 3'd2) : (choose_h ? 3'd1 : 3'd0);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_pipe<=0;nearest<=0;best_dist<=0;
        end else begin
            valid_pipe<={valid_pipe[2:0],touch_valid};
            down_pipe[0]<=touch_down;x_pipe[0]<=touch_x;y_pipe[0]<=touch_y;
            cut_pipe[0]<=cutoff;res_pipe[0]<=resonance;
            a_pipe[0]<=attack;h_pipe[0]<=hold;d_pipe[0]<=decay;s_pipe[0]<=sustain;r_pipe[0]<=release_v;
            tab_pipe[0]<=env_tab;type_pipe[0]<=filter_type;
            for(pipe_i=1;pipe_i<4;pipe_i=pipe_i+1) begin
                down_pipe[pipe_i]<=down_pipe[pipe_i-1];x_pipe[pipe_i]<=x_pipe[pipe_i-1];y_pipe[pipe_i]<=y_pipe[pipe_i-1];
                cut_pipe[pipe_i]<=cut_pipe[pipe_i-1];res_pipe[pipe_i]<=res_pipe[pipe_i-1];
                a_pipe[pipe_i]<=a_pipe[pipe_i-1];h_pipe[pipe_i]<=h_pipe[pipe_i-1];d_pipe[pipe_i]<=d_pipe[pipe_i-1];
                s_pipe[pipe_i]<=s_pipe[pipe_i-1];r_pipe[pipe_i]<=r_pipe[pipe_i-1];
                tab_pipe[pipe_i]<=tab_pipe[pipe_i-1];type_pipe[pipe_i]<=type_pipe[pipe_i-1];
            end
            la0<=`ENV_LEN_A(hit_env[0+:7]);lh0<=`ENV_LEN_H(hit_env[7+:7]);
            ld0<=`ENV_LEN_D(hit_env[14+:7]);lr0<=`ENV_LEN_R(hit_env[28+:7]);sh0<=`ENV_SUS_HEIGHT(hit_env[21+:7]);
            ax1<=10'd36+la0;hx1<=10'd36+la0+lh0;
            dx1<=10'd36+la0+lh0+ld0;sx1<=10'd96+la0+lh0+ld0;
            rx1<=10'd96+la0+lh0+ld0+lr0;sy1<=10'd568-sh0;
            distances2[0]<=distance(x_pipe[1][10:0],y_pipe[1][9:0],ax1,10'd424);
            distances2[1]<=distance(x_pipe[1][10:0],y_pipe[1][9:0],hx1,10'd412);
            distances2[2]<=distance(x_pipe[1][10:0],y_pipe[1][9:0],dx1,sy1);
            distances2[3]<=distance(x_pipe[1][10:0],y_pipe[1][9:0],sx1,sy1);
            distances2[4]<=distance(x_pipe[1][10:0],y_pipe[1][9:0],rx1,10'd568);
            best_dist<=distances2[4]<best_four ? distances2[4] : best_four;
            nearest<=distances2[4]<best_four ? 3'd4 : best_four_id;
        end
    end
    function [6:0] pixel_value;
        input signed [17:0] pixels;
        input integer span;
        reg [18:0] reciprocal;
        reg [26:0] scaled;
        begin
            // Bounded reciprocal multiply replaces a long signed divider.
            // Exhaustively checked against rounded integer division for every
            // pixel in every supported span (including 127 saturation).
            case(span)
                280:reciprocal=18'd29959;44:reciprocal=18'd190650;
                65:reciprocal=19'd129056;30:reciprocal=19'd279620;
                80:reciprocal=19'd104858;144:reciprocal=18'd58254;
                default:reciprocal=0;
            endcase
            scaled=pixels[8:0]*reciprocal+27'd32768;
            if(pixels<=0) pixel_value=0;
            else if(pixels>=span) pixel_value=127;
            else pixel_value=scaled[26:16]>=127 ? 7'd127 : scaled[22:16];
        end
    endfunction
    wire [13:0] event_x=x_pipe[3],event_y=y_pipe[3];
    wire signed [17:0] move_x=$signed({4'd0,event_x})-$signed({4'd0,anchor_x});
    wire signed [17:0] move_up=$signed({4'd0,anchor_y})-$signed({4'd0,event_y});
    reg signed [17:0] p0,p1,p2,p3,p4;
    reg pending,pending_filter;
    reg [1:0] pending_tab;
    reg [4:0] pending_mask;
    reg zero_x,zero_y;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            finger_down<=0; capture_active<=0; focus_valid<=0; focus_id<=0;
            update_valid<=0; update_filter<=0; update_tab<=0; update_mask<=0; update_values<=0;
            watchdog<=0; filter_gesture<=0; notch_gesture<=0; handle<=0;
            anchor_x<=0;anchor_y<=0;captured_tab<=0;
            base_cut<=0;base_res<=0;base_a<=0;base_h<=0;base_d<=0;base_s<=0;base_r<=0;
            pending<=0;pending_filter<=0;pending_tab<=0;pending_mask<=0;
            zero_x<=1;zero_y<=1;
            p0<=0;p1<=0;p2<=0;p3<=0;p4<=0;
        end else begin
            pending<=0; focus_valid<=0;
            update_valid<=pending;
            update_filter<=pending_filter;update_tab<=pending_tab;update_mask<=pending_mask;
            if(pending_filter) begin
                update_values[6:0]<=zero_x ? base_cut : pixel_value(p0,280);
                update_values[13:7]<=zero_y ? base_res : pixel_value(p1,44);
                update_values[34:14]<=0;
            end else begin
                update_values[6:0]<=zero_x ? base_a : pixel_value(p0,65);
                update_values[13:7]<=zero_x ? base_h : pixel_value(p1,30);
                update_values[20:14]<=zero_x ? base_d : pixel_value(p2,80);
                update_values[27:21]<=zero_y ? base_s : pixel_value(p3,144);
                update_values[34:28]<=zero_x ? base_r : pixel_value(p4,80);
            end
            if(watchdog<WATCHDOG_CYCLES) watchdog<=watchdog+1'b1;
            else begin finger_down<=0;capture_active<=0; end
            if(valid_pipe[3]) begin
                watchdog<=0;
                if(!down_pipe[3]) begin finger_down<=0;capture_active<=0; end
                else begin
                    finger_down<=1;
                    if(!finger_down) begin
                        capture_active<=0;
                        anchor_x<=event_x;anchor_y<=event_y;
                        base_cut<=cut_pipe[3];base_res<=res_pipe[3];
                        base_a<=a_pipe[3];base_h<=h_pipe[3];base_d<=d_pipe[3];base_s<=s_pipe[3];base_r<=r_pipe[3];
                        captured_tab<=tab_pipe[3];
                        if(event_x>=`FLT_WIN_X0 && event_x<=`FLT_WIN_X1 &&
                           event_y>=`FLT_WIN_Y0 && event_y<=`FLT_WIN_Y1) begin
                            capture_active<=1;filter_gesture<=1;notch_gesture<=type_pipe[3]==3;
                            focus_valid<=1;focus_id<=`PARAM_ID_FLT_CUTOFF;
                        end else if(event_x>=`ENV_WIN_X0 && event_x<=`ENV_WIN_X1 &&
                                    event_y>=`ENV_WIN_Y0 && event_y<=`ENV_WIN_Y1 && best_dist<=40) begin
                            capture_active<=1;filter_gesture<=0;handle<=nearest;
                            focus_valid<=1;
                            case(nearest)
                                0:focus_id<=`PARAM_ID_ENV1_ATTACK;
                                1:focus_id<=`PARAM_ID_ENV1_HOLD;
                                2:focus_id<=`PARAM_ID_ENV1_DECAY;
                                3:focus_id<=`PARAM_ID_ENV1_SUSTAIN;
                                default:focus_id<=`PARAM_ID_ENV1_RELEASE;
                            endcase
                        end
                    end else if(capture_active) begin
                        pending<=1;pending_filter<=filter_gesture;pending_tab<=captured_tab;
                        zero_x<=move_x==0;zero_y<=move_up==0;
                        pending_mask<=0;
                        if(filter_gesture) begin
                            p0<=((base_cut*18'd280)>>7)+move_x;
                            p1<=((base_res*18'd44)>>7)+(notch_gesture ? -move_up : move_up);
                            pending_mask<=5'b00011;
                        end else begin
                            p0<=((base_a*18'd65)>>7)+move_x;
                            p1<=((base_h*18'd30)>>7)+move_x;
                            p2<=((base_d*18'd80)>>7)+move_x;
                            p3<=((base_s*18'd144)>>7)+move_up;
                            p4<=((base_r*18'd80)>>7)+move_x;
                            case(handle)
                                0:pending_mask<=5'b00001;
                                1:pending_mask<=5'b00010;
                                2:pending_mask<=5'b01100;
                                3:pending_mask<=5'b01000;
                                4:pending_mask<=5'b10000;
                            endcase
                        end
                    end
                end
            end
        end
    end
endmodule
