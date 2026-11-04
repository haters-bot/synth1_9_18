`timescale 1ns/1ps
module tb_focus_handoff;
 reg clk=0,rst_n=0,touch_valid=0,touch_state=0;
 reg [15:0] raw_touch_x=0,raw_touch_y=0;
 wire [7:0] selected_param_id;
 wire selected_valid,focus_event_valid,ui_touch_down;
 reg motion_valid=0,button_valid=0;
 reg [7:0] motion_id=0,button_id=0;
 reg [1:0] button_action=0;
 wire [7:0] focus_id;
 integer checks=0,i;
 always #10 clk=~clk;
 touch_event_router router(.clk(clk),.rst_n(rst_n),.touch_valid(touch_valid),
  .touch_state(touch_state),.raw_touch_x(raw_touch_x),.raw_touch_y(raw_touch_y),
  .curve_capture_active(1'b0),.curve_focus_valid(1'b0),.curve_focus_id(8'd0),
  .selected_param_id(selected_param_id),.selected_valid(selected_valid),
  .focus_event_valid(focus_event_valid),.ui_touch_down(ui_touch_down));
 knob_ui_control control(.clk(clk),.rst_n(rst_n),.motion_valid(motion_valid),
  .motion_cw(1'b1),.motion_id(motion_id),.button_valid(button_valid),
  .button_id(button_id),.button_action(button_action),.steps(64'd0),
  .fx_touch_focus_valid(1'b0),.fx_touch_focus_id(8'd0),
  .touch_focus_valid(focus_event_valid),.touch_focus_id(selected_param_id),
  .touch_down(ui_touch_down),.focus_id(focus_id));
 task expect_focus(input [7:0] id);
  begin if(focus_id!==id)$fatal(1,"Focus got %h expected %h",focus_id,id);checks=checks+1;end
 endtask
 task touch(input integer x,y,input down);
  begin @(negedge clk);raw_touch_x=(x*64+4)/5;raw_touch_y=(y*65536+4914)/4915;
   touch_state=down;touch_valid=1;@(negedge clk);touch_valid=0;
   repeat(8)@(negedge clk);end
 endtask
 task rotate(input [7:0] id);
  begin @(negedge clk);motion_id=id;motion_valid=1;
   @(negedge clk);motion_valid=0;expect_focus(id);
   repeat(100)begin @(negedge clk);expect_focus(id);end
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
  rotate('h17);
  // Real coordinate decode updates ID two clocks after raw DOWN.
  touch(1182,22,1);expect_focus('h05);
  // No UP packet: persistent DOWN and selected_valid cannot reclaim focus.
  rotate('h27);expect_focus('h27);
  touch(1182,22,1);expect_focus('h27);
  rotate('h40);
  touch(0,0,0);touch(200,22,1);expect_focus('h01);
  touch(0,0,0);rotate('h18);
  // Repeat after release, touching the SAME prior parameter.
  touch(200,22,1);expect_focus('h01);rotate('h28);
  touch(0,0,0);
  for(i=0;i<8;i=i+1)begin
   touch(1182,22,1);expect_focus('h05);touch(0,0,0);
   rotate('h17+i);
  end
  // Physical press selects; RELEASE must not select another control.
  button_valid=1;button_id='h50;button_action=1;@(negedge clk);expect_focus('h66);
  button_id='h27;button_action=2;@(negedge clk);expect_focus('h66);
  button_valid=0;repeat(32)@(negedge clk);expect_focus('h66);
  $display("PASS: %0d real-router touch/physical focus checks, delayed IDs, repeated same touch, missing UP, press/release and idle persistence",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"Focus handoff watchdog");end
endmodule
