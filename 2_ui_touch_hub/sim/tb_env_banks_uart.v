`timescale 1ns/1ps
`include "params.vh"
module tb_env_banks_uart;
reg clk=0,rst_n=0,sv=0,dv=0,bv=0,cv=0,force_busy=0;
reg [7:0] sid=0,did=0;reg [6:0] value=0;reg signed [7:0] delta=0;
reg [1:0] ba=0,ct=0;reg [4:0] cm=0;reg [34:0] values=0;
wire req,uart,busy;wire [7:0] id;wire [6:0] mv;wire [1:0] tab;
integer seen[0:127],counts[0:127],messages=0,j,save_count;
always #10 clk=~clk;
param_merger bank(.clk(clk),.rst_n(rst_n),.spi_param_valid(sv),.spi_param_id(sid),.spi_param_val(value),
 .touch_delta_valid(dv),.touch_selected_id(did),.touch_delta_val(delta),
 .btn_tap_valid(bv),.btn_tap_id(`PARAM_ID_ENV_TAB),.btn_tap_action(ba),
 .curve_update_valid(cv),.curve_update_filter(1'b0),.curve_update_tab(ct),.curve_update_mask(cm),.curve_update_values(values),
 .midi_tx_busy(busy|force_busy),.val_env_tab(tab),.midi_cc_req(req),.midi_cc_param_id(id),.midi_cc_val(mv));
midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(5000000)) tx(.clk(clk),.rst_n(rst_n),
 .note_on_req(1'b0),.note_off_req(1'b0),.note_number(7'd0),.note_velocity(7'd0),
 .cc_req(req),.cc_param_id(id),.cc_val(mv),.sysex_req(1'b0),.sysex_msgs(48'd0),.uart_tx(uart),.tx_busy(busy));
reg [7:0] byte_data;integer bit_index,byte_at=0,cc;
initial forever begin
 @(negedge uart);#100;
 for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin #200;byte_data[bit_index]=uart;end
 #200;if(uart!==1)$fatal(1,"UART stop bit");
 case(byte_at)
  0:begin if(byte_data!==8'hBF)$fatal(1,"status %h",byte_data);byte_at=1;end
  1:begin cc=byte_data;byte_at=2;end
  2:begin seen[cc]=byte_data;counts[cc]=counts[cc]+1;messages=messages+1;byte_at=0;$display("UART: BF %02h %02h",cc,byte_data);end
 endcase
end
task step;begin @(negedge clk);end endtask
task bank_select(input [1:0] b);begin ba=b;bv=1;step;bv=0;repeat(5)step;if(tab!=b)$fatal(1,"bank selection");end endtask
task absolute(input [7:0] p,input [6:0] v);begin sid=p;value=v;sv=1;step;sv=0;repeat(5)step;end endtask
task increment(input [7:0] p,input signed [7:0] v);begin did=p;delta=v;dv=1;step;dv=0;repeat(5)step;end endtask
task curve(input [1:0] b,input [34:0] v);begin ct=b;cm=31;values=v;cv=1;step;cv=0;repeat(6)step;end endtask
task drain;begin repeat(4000)step;if(busy||bank.curve_midi_pending)$fatal(1,"pending");end endtask
initial begin
 for(j=0;j<128;j=j+1)begin seen[j]=-1;counts[j]=0;end
 repeat(5)step;rst_n=1;step;
 absolute(`PARAM_ID_ENV1_ATTACK,31);absolute(`PARAM_ID_ENV1_DECAY,32);absolute(`PARAM_ID_ENV1_SUSTAIN,33);absolute(`PARAM_ID_ENV1_RELEASE,34);drain;
 if(seen[24]!=31||seen[25]!=32||seen[26]!=33||seen[27]!=34)$fatal(1,"ENV1 absolute mapping");
 bank_select(1);
 absolute(`PARAM_ID_ENV1_ATTACK,41);absolute(`PARAM_ID_ENV1_DECAY,42);absolute(`PARAM_ID_ENV1_SUSTAIN,43);absolute(`PARAM_ID_ENV1_RELEASE,44);drain;
 if(seen[32]!=41||seen[33]!=42||seen[34]!=43||seen[35]!=44)$fatal(1,"ENV2 absolute mapping");
 increment(`PARAM_ID_ENV1_ATTACK,1);increment(`PARAM_ID_ENV1_DECAY,-2);increment(`PARAM_ID_ENV1_SUSTAIN,3);increment(`PARAM_ID_ENV1_RELEASE,-4);drain;
 if(seen[32]!=42||seen[33]!=40||seen[34]!=46||seen[35]!=40)$fatal(1,"ENV2 delta mapping");
 // Pending values retain their bank even after switching the visible page.
 force_busy=1;bank_select(0);increment(`PARAM_ID_ENV1_ATTACK,5);bank_select(1);force_busy=0;drain;
 if(seen[24]!=36||seen[32]!=42)$fatal(1,"ENV1 queued event moved to ENV2");
 force_busy=1;increment(`PARAM_ID_ENV1_ATTACK,6);bank_select(0);force_busy=0;drain;
 if(seen[32]!=48||seen[24]!=36)$fatal(1,"ENV2 queued event moved to ENV1");
 force_busy=1;curve(1,{7'd74,7'd73,7'd72,7'd99,7'd71});bank_select(2);force_busy=0;drain;
 if(seen[32]!=71||seen[33]!=72||seen[34]!=73||seen[35]!=74)$fatal(1,"ENV2 curve queued bank");
 force_busy=1;curve(0,{7'd54,7'd53,7'd52,7'd98,7'd51});bank_select(1);force_busy=0;drain;
 if(seen[24]!=51||seen[25]!=52||seen[26]!=53||seen[27]!=54)$fatal(1,"ENV1 curve queued bank");
 save_count=messages;
 absolute(`PARAM_ID_ENV1_HOLD,91);increment(`PARAM_ID_ENV1_HOLD,1);bank_select(0);absolute(`PARAM_ID_ENV1_HOLD,92);increment(`PARAM_ID_ENV1_HOLD,1);
 bank_select(2);absolute(`PARAM_ID_ENV1_ATTACK,61);absolute(`PARAM_ID_ENV1_HOLD,62);absolute(`PARAM_ID_ENV1_DECAY,63);absolute(`PARAM_ID_ENV1_SUSTAIN,64);absolute(`PARAM_ID_ENV1_RELEASE,65);
 increment(`PARAM_ID_ENV1_ATTACK,1);increment(`PARAM_ID_ENV1_HOLD,1);increment(`PARAM_ID_ENV1_DECAY,1);increment(`PARAM_ID_ENV1_SUSTAIN,1);increment(`PARAM_ID_ENV1_RELEASE,1);
 curve(2,{7'd84,7'd83,7'd82,7'd81,7'd80});bank_select(0);bank_select(1);drain;
 if(messages!=save_count)$fatal(1,"Hold/ENV3/page switch leaked MIDI");
 $display("PASS: ENV1/ENV2 absolute/delta/curve UART, queued bank both directions, ENV3/Hold/page switch silence");$finish;
end
initial begin #3000000;$fatal(1,"timeout");end
endmodule
