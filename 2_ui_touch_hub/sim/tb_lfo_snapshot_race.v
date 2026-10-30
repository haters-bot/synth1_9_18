`timescale 1ns/1ps
module tb_lfo_snapshot_race;
parameter FIRST_HOLD=10;
parameter HOLD=56;
reg clk=0,rst_n=0,tv=0,td=0;reg [13:0] x=0,y=0;
wire [105:0] sources;wire [423:0] depths;wire req;wire [47:0] msgs;
integer cycle=0,sent=0;
always #10 clk=~clk;
lfo_binding_state b(.clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),.active_tab(2'd0),.cancel(1'b0),.sources(sources),.depths(depths));
lfo_sysex_tx #(.HOLD_CYCLES(HOLD),.FIRST_HOLD_CYCLES(FIRST_HOLD)) sx(.clk(clk),.rst_n(rst_n),
 .cfg_nodes(147'd0),.cfg_rates(9'd0),.cfg_steps(3'd0),.cfg_once(3'd0),.cfg_sources(sources),.cfg_depths(depths),.tx_accept(req),.sysex_req(req),.sysex_msgs(msgs));
always @(posedge clk)if(rst_n)begin
 cycle=cycle+1;
 if(sx.state==1)$display("TRACE: LATCH cycle=%d qsrc=%d dvec=%b",cycle,sx.q_sources[27:26],sx.drt_vec[13]);
 if(req && msgs==48'hF07D56027FF7)sent=sent+1;
end
task packet(input integer px,py,input bit down);begin
 @(negedge clk);x=px;y=py;td=down;tv=1;@(negedge clk);tv=0;repeat(10)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 repeat(300)@(negedge clk);
 packet(1140,385,1);packet(0,0,0);packet(980,485,1);packet(134,268,1);packet(0,0,0);
 packet(1140,385,1);packet(0,0,0);packet(980,485,1);packet(344,326,1);packet(0,0,0);
 repeat(1000)@(negedge clk);
 if(sources[27:26]!==1 || depths[111:104]!==127)$fatal(1,"binding FSM did not commit");
 if(!sent)$fatal(1,"snapshot swallowed a real binding: first_hold=%d live=%h q=%h shadow=%h",FIRST_HOLD,sources[27:26],sx.q_sources[27:26],sx.sh_sources[27:26]);
 $display("PASS: binding concurrent with batch latch reaches outgoing route");$finish;
end
endmodule
