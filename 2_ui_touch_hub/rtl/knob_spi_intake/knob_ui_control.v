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
 // Physical IDs are unique. Parallel masked reductions preserve the default
 // step and exact event cycle without the old 32-entry priority chain.
 wire [31:0] step_low,step_high;
 wire [1:0] step_code={|step_high,|step_low};
 genvar i;
 generate for(i=0;i<32;i=i+1)begin: select_step
  wire selected=knob_param_id(i)==motion_id;
  assign step_low[i]=selected && steps[i*2];
  assign step_high[i]=selected && steps[i*2+1];
 end endgenerate
 wire signed [7:0] amount=8'sd1<<step_code;
 assign delta=motion_cw ? amount : -amount;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin focus_id<=`PARAM_ID_NONE;end
  else begin
   if(motion_valid)focus_id<=screen_id(motion_id);
   else if(button_valid && button_action==1)focus_id<=screen_id(button_id);
   else if(fx_touch_focus_valid)focus_id<=fx_touch_focus_id;
   else if(touch_focus_valid && touch_focus_id!=`PARAM_ID_NONE)begin
    focus_id<=touch_focus_id;
   end
  end
 end
endmodule
