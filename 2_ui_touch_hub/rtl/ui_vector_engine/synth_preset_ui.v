// Session UI only. User presets have no write port or fake persistence yet.
module synth_preset_ui #(parameter CONTACT_CYCLES=2500000)(
 input wire clk,rst_n,touch_valid,touch_down,
 input wire [13:0] touch_x,touch_y,
 input wire [2:0] view,
 input wire [7:0] section,
 input wire applied_valid,
 input wire [3:0] active_index,
 output reg [2:0] category,
 output reg apply_req,
 output reg [3:0] apply_index,
 output reg back_req,
 output reg custom_notice
);
 reg finger;
 reg [21:0] quiet;
 integer i;
 function [3:0] category_first;
  input [2:0] c;begin case(c)
   0:category_first=0;1:category_first=2;2:category_first=4;
   3:category_first=6;4:category_first=8;default:category_first=11;
  endcase end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   finger<=0;quiet<=0;category<=0;apply_req<=0;apply_index<=0;back_req<=0;custom_notice<=0;
  end else begin
   apply_req<=0;back_req<=0;
   if(quiet<CONTACT_CYCLES)quiet<=quiet+1'b1;else finger<=0;
   if(touch_valid)begin
    quiet<=0;
    if(!touch_down)finger<=0;
    else begin
     finger<=1;
     if(!finger && view==3 && section==4)begin
      for(i=0;i<6;i=i+1)
       if(touch_x>=40 && touch_x<248 && touch_y>=172+i*68 && touch_y<228+i*68)begin
        category<=i;custom_notice<=0;
       end
      for(i=0;i<3;i=i+1)
       if(touch_x>=280 && touch_x<1248 && touch_y>=192+i*128 && touch_y<304+i*128 &&
          (i<2 || category==4) && (category!=5 || i==0))begin
        apply_index<=category_first(category)+i;apply_req<=1;custom_notice<=0;
       end
      if(touch_y>=612 && touch_y<660)begin
       if(touch_x>=280 && touch_x<488 && applied_valid)begin apply_index<=active_index;apply_req<=1;end
       if(touch_x>=504 && touch_x<696)back_req<=1;
       if(touch_x>=800 && touch_x<1248)custom_notice<=1;
      end
     end
    end
   end
  end
 end
endmodule
