`include "params.vh"
// Hardware focus is a visual state, separate from touch edit ownership.
module knob_ui_control(
 input wire clk,rst_n,motion_valid,motion_cw,button_valid,
 input wire [7:0] motion_id,button_id,
 input wire [1:0] button_action,
 input wire fx_touch_focus_valid,
 input wire [7:0] fx_touch_focus_id,
 input wire touch_focus_valid,touch_down,
 input wire [7:0] touch_focus_id,
 input wire [63:0] steps,
 output wire signed [7:0] delta,
 output reg [7:0] focus_id
);
 `include "knob_param_map.vh"
 function [7:0] screen_id;
  input [7:0] id;
  begin screen_id=id==`PARAM_ID_FX_REVERB ? 8'h66 : id==`PARAM_ID_FX_DELAY ? 8'h60 : id;end
 endfunction
 reg touch_latched;
 reg [1:0] step_code;
 integer i;
 always @*begin
  step_code=0;
  for(i=0;i<32;i=i+1)if(knob_param_id(i)==motion_id)step_code=steps[i*2+:2];
 end
 wire signed [7:0] amount=8'sd1<<step_code;
 assign delta=motion_cw ? amount : -amount;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin focus_id<=`PARAM_ID_NONE;touch_latched<=0;end
  else begin
   if(!touch_down)touch_latched<=0;
   if(fx_touch_focus_valid)focus_id<=fx_touch_focus_id;
   else if(motion_valid)focus_id<=screen_id(motion_id);
   else if(button_valid && button_action==1)focus_id<=screen_id(button_id);
   else if(touch_focus_valid && touch_down && !touch_latched && touch_focus_id!=`PARAM_ID_NONE)begin
    focus_id<=touch_focus_id;touch_latched<=1;
   end
  end
 end
endmodule
