`timescale 1ns/1ps
module tb_user_controls;
 reg clk=0,rst_n=0,touch_valid=0,touch_down=0;
 reg [13:0] touch_x=0,touch_y=0;
 reg [1:0] view=2;
 reg [7:0] section=1;
 wire [63:0] knob_steps;
 wire [1:0] knob_page,apply_step;
 wire [23:0] plot_scales;
 reg seed_valid=0;
 reg [6:0] seed_value=0;
 wire bank_cc;wire [7:0] bank_id;wire [6:0] bank_value;
 reg [6:0] last_bank_value=0;reg [7:0] last_bank_id=0;
 reg motion_valid=0,motion_cw=1,button_valid=0,touch_focus_valid=0;
 reg [7:0] motion_id=0,button_id=0,touch_focus_id=0;
 reg [1:0] button_action=0;
 reg fx_touch_focus_valid=0;
 reg [7:0] fx_touch_focus_id=0;
 wire signed [7:0] delta;
 wire [7:0] focus_id;
 reg [7:0] ids[0:31];
 reg [63:0] before_steps;
 reg [23:0] before_scales;
 integer i,c,t,k,checks=0;
 ui_user_settings #(.CONTACT_CYCLES(128)) settings(.*);
 knob_ui_control control(.clk(clk),.rst_n(rst_n),.steps(knob_steps),.*);
 param_merger bank(.clk(clk),.rst_n(rst_n),.spi_param_valid(seed_valid),.spi_param_id(motion_id),.spi_param_val(seed_value),
  .touch_delta_valid(motion_valid),.touch_selected_id(motion_id),.touch_delta_val(delta),
  .curve_update_valid(1'b0),.curve_update_filter(1'b0),.curve_update_tab(2'd0),.curve_update_mask(5'd0),.curve_update_values(35'd0),
  .midi_tx_busy(1'b0),.btn_tap_valid(1'b0),.btn_tap_id(8'd0),.btn_tap_action(2'd0),
  .midi_cc_req(bank_cc),.midi_cc_param_id(bank_id),.midi_cc_val(bank_value));
 always @(posedge clk)if(bank_cc)begin last_bank_value<=bank_value;last_bank_id<=bank_id;end
 always #10 clk=~clk;
 task packet(input integer x,y,input down);
  begin @(negedge clk);touch_valid=1;touch_down=down;touch_x=x;touch_y=y;
   @(negedge clk);touch_valid=0;repeat(3)@(negedge clk);end
 endtask
 task click(input integer x,y);
  begin packet(x,y,1);packet(0,0,0);end
 endtask
 task motion(input integer knob,input cw,input integer amount);
  begin motion_id=ids[knob];motion_cw=cw;motion_valid=1;@(negedge clk);
   if(delta!==(cw ? amount : -amount))$fatal(1,"Wrong physical step K%0d got %0d",knob+1,delta);
   if(focus_id!==(knob==30 ? 8'h66 : knob==31 ? 8'h60 : ids[knob]))$fatal(1,"Wrong physical focus K%0d",knob+1);
   motion_valid=0;repeat(4)@(negedge clk);checks=checks+1;end
 endtask
 initial begin
  // Independent PCB map, deliberately not using the RTL mapping function.
  ids[0]='h17;ids[1]='h18;ids[2]='h19;ids[3]='h1a;ids[4]='h13;ids[5]='h14;ids[6]='h15;ids[7]='h16;
  ids[8]='h40;ids[9]='h41;ids[10]='h42;ids[11]='h43;ids[12]='h44;ids[13]='h05;ids[14]='h01;ids[15]='h02;
  ids[16]='h27;ids[17]='h28;ids[18]='h29;ids[19]='h2a;ids[20]='h23;ids[21]='h24;ids[22]='h25;ids[23]='h26;
  ids[24]='h30;ids[25]='h31;ids[26]='h32;ids[27]='h33;ids[28]='h34;ids[29]='h35;ids[30]='h50;ids[31]='h51;
  repeat(5)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
  if(knob_steps!=={32{2'd2}})$fatal(1,"Default physical step is not four");
  for(i=0;i<32;i=i+1)begin
   if(knob_page!=i/8)click(520,590);
   for(c=0;c<4;c=c+1)begin
    before_steps=knob_steps;click(368+c*80,220+(i%8)*44);
    before_steps[i*2+:2]=c;
    if(knob_steps!==before_steps)$fatal(1,"Per-knob setting changed its neighbour K%0d",i+1);
    motion(i,1,1<<c);motion(i,0,1<<c);
   end
  end
  click(480,160);if(knob_steps!=={32{2'd3}})$fatal(1,"Apply all did not use last chosen step");
  // Actual shared static parameter bank, including its discrete unison clamp.
  for(i=0;i<30;i=i+1)begin
   motion_id=ids[i];seed_value=64;seed_valid=1;@(negedge clk);seed_valid=0;repeat(4)@(negedge clk);
   motion(i,1,8);
   if(last_bank_id!==ids[i] || last_bank_value!==(i==4 || i==20 ? 7'd8 : 7'd72))$fatal(1,"Configured step did not reach shared bank K%0d",i+1);
   motion(i,0,8);
   if(last_bank_value!==(i==4 || i==20 ? 7'd1 : 7'd64))$fatal(1,"Reverse step did not reach shared bank K%0d",i+1);
  end
  motion_id=ids[0];seed_value=126;seed_valid=1;@(negedge clk);seed_valid=0;repeat(4)@(negedge clk);motion(0,1,8);
  if(last_bank_value!=127)$fatal(1,"Configured step overflowed maximum");
  seed_value=1;seed_valid=1;@(negedge clk);seed_valid=0;repeat(4)@(negedge clk);motion(0,0,8);
  if(last_bank_value!=0)$fatal(1,"Configured step underflowed minimum");
  // A held contact cannot turn a page repeatedly, including repeated reports.
  packet(520,590,1);for(k=0;k<12;k=k+1)packet(520,590,1);
  if(knob_page!=0)$fatal(1,"Held NEXT contact repeated");packet(0,0,0);
  click(64,590);if(knob_page!=3)$fatal(1,"Previous page wrap failed");
  // Focus-valid is now an event, independent of retained touch ownership.
  touch_focus_valid=0;touch_focus_id='h31;touch_down=0;motion(0,1,8);
  repeat(4)@(negedge clk);if(focus_id!='h17)$fatal(1,"Stale touch selection stole physical focus");
  touch_down=1;touch_focus_valid=1;@(negedge clk);touch_focus_valid=0;
  if(focus_id!='h31)$fatal(1,"Live touch did not take focus");
  touch_down=0;button_valid=1;button_id='h50;button_action=1;@(negedge clk);
  if(focus_id!='h66)$fatal(1,"FX press did not highlight visible target");
  button_action=2;button_id='h27;@(negedge clk);button_valid=0;
  if(focus_id!='h66)$fatal(1,"Release changed focus");
  fx_touch_focus_valid=1;fx_touch_focus_id='h60;@(negedge clk);fx_touch_focus_valid=0;
  if(focus_id!='h60)$fatal(1,"FX touch did not take focus");
  // Both page and plot footer access the same saturated scale register.
  touch_focus_valid=0;section=2;
  for(t=0;t<6;t=t+1)begin
   for(c=0;c<4;c=c+1)click(704,216+t*56);
   if(plot_scales[t*4+:2]!=3)$fatal(1,"Display gain saturation failed");
   view=1;click(48+(t%3)*418,364+(t/3)*296);
   if(plot_scales[t*4+:2]!=2)$fatal(1,"Local gain and settings gain diverged");
   view=2;
   before_scales=plot_scales;
   for(c=0;c<4;c=c+1)click(1040,216+t*56);
   if(t==0 || t==5)begin
    if(plot_scales!==before_scales)$fatal(1,"Unsupported X control is active");
   end else begin
    if(plot_scales[t*4+2+:2]!=3)$fatal(1,"X saturation failed");
    view=1;click(232+(t%3)*418,364+(t/3)*296);view=2;
    if(plot_scales[t*4+2+:2]!=2)$fatal(1,"Local X and settings X diverged");
   end
  end
  view=0;before_scales=plot_scales;before_steps=knob_steps;
  click(704,216);click(480,160);
  if(plot_scales!==before_scales || knob_steps!==before_steps)$fatal(1,"Synth touch changed settings");
  $display("PASS: %0d physical direction/step checks, all 32 independent settings, apply-all, contact dedup, touch/physical/FX focus and synchronized display/local scales",checks);
  $finish;
 end
 initial begin #2000000;$fatal(1,"User controls watchdog");end
endmodule
