`timescale 1ns/1ps
`include "params.vh"
module tb_modulated_env_touch;
reg clk=0,rst_n=0,tv=0,td=0;
reg [13:0] x=0,y=0;
reg [34:0] displayed={7'd35,7'd20,7'd80,7'd100,7'd120};
wire cap,fv,uv,uf;
wire [7:0] fid;
wire [1:0] tab;
wire [4:0] mask;
wire [34:0] values;
integer focuses=0,writes=0;
reg [7:0] last_focus;
always #10 clk=~clk;
curve_touch_editor #(.USE_DISPLAY_GEOMETRY(1)) dut(
 .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),
 .cutoff(7'd50),.resonance(7'd20),.filter_type(2'd0),.env_tab(2'd1),
 .attack(7'd10),.hold(7'd0),.decay(7'd40),.sustain(7'd90),.release_v(7'd35),
 .display_env_values(displayed),.capture_active(cap),.focus_valid(fv),.focus_id(fid),
 .update_valid(uv),.update_filter(uf),.update_tab(tab),.update_mask(mask),.update_values(values));
always @(posedge clk) begin
 if(fv)begin focuses=focuses+1;last_focus=fid;end
 if(uv)writes=writes+1;
end
task packet;
 input integer px,py;input down;
 begin @(negedge clk);x=px;y=py;td=down;tv=1;
 @(negedge clk);tv=0;repeat(12)@(negedge clk);end
endtask
initial begin
 repeat(8)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
 // Display A=120 lies 55 pixels away from base A=10, outside hit radius.
 packet(46+120*65/128,424,1);
 if(!cap || focuses!=1 || last_focus!=`PARAM_ID_ENV1_ATTACK || writes!=0)
  $fatal(1,"Displayed attack must capture without changing base");
 // Animation may move after capture; drag remains attached to attack.
 displayed={7'd35,7'd100,7'd10,7'd0,7'd0};
 packet(46+120*65/128+13,424,1);
 if(writes!=1 || uf || tab!=1 || mask!=1 || values[0+:7]!=35)
  $fatal(1,"Relative edit must use base A=10 (expected 35), not displayed A=120");
 packet(46+120*65/128,424,1);
 if(values[0+:7]!=10 || mask!=1)$fatal(1,"Anchor return must restore exact base");
 packet(0,0,0);if(cap)$fatal(1,"Release did not clear capture");
 // Sustain at displayed Y=546 is 79 pixels from base Y=467.
 displayed={7'd35,7'd20,7'd80,7'd100,7'd120};
 repeat(8)@(negedge clk);
 packet(96+(10+120*65/128)+(100*30/128)+(12+80*80/128),568-20*144/128,1);
 if(!cap || last_focus!=`PARAM_ID_ENV1_SUSTAIN)$fatal(1,"Displayed sustain did not capture");
 packet(96+(10+120*65/128)+(100*30/128)+(12+80*80/128),568-20*144/128-10,1);
 if(mask!=8 || values[21+:7]!=99)$fatal(1,"Sustain must edit base level relatively");
 packet(0,0,0);
 $display("PASS: animated ENV hit positions, no write on press, captured handle stability, base-relative edits, exact anchor return, sustain and release");
 $finish;
end
initial begin #100000;$fatal(1,"ENV touch timeout");end
endmodule
