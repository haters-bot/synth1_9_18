`timescale 1ns/1ps
`include "params.vh"
// Actual state owners, static reconciliation, LFO dispatcher, UART FIFO and
// serial decoder. Expected bytes are produced by the pinned Python METHOD.
module tb_synth_presets;
 reg clk=0,rst_n=0,apply=0;
 always #5 clk=~clk;
 reg [3:0] index=0;
 wire busy,load,adopt,applied,pending,invalid;
 wire [3:0] active,pending_index;
 wire [517:0] bank,values;
 wire [237:0] base,extra;
 wire [132:0] fx;
 wire [10:0] switches;
 wire [105:0] sources;
 wire [423:0] depths;
 reg [146:0] nodes=0;
 reg [8:0] rates={3'd7,3'd4,3'd3};
 reg [2:0] steps=5,once_bits=6;
 reg tv=0,td=0;reg [13:0] x=0,y=0;
 reg knob_valid=0;reg [7:0] knob_id=0;reg [6:0] knob_value=0;
 wire legacy;wire [7:0] legacy_id;wire [6:0] legacy_value;
 wire bcc,bsx,scc,ssx,ca,sa,tx,tx_busy,startup,lf_busy,note_ready;
 wire [7:0] bid,sid;wire [6:0] bv,sv;wire [47:0] bm,sm;
 reg note_on=0,note_off=0;
 synth_preset_controller controller(.clk(clk),.rst_n(rst_n),.apply_req(apply),.apply_index(index),
  .uart_busy(tx_busy),.cc_accept(ca&&busy),.sysex_accept(sa&&busy),
  .lfo_nodes(nodes),.lfo_rates(rates),.lfo_steps(steps),.lfo_once(once_bits),
  .busy(busy),.load_bank(load),.adopt_bank(adopt),.bank_values(bank),.active_index(active),
  .applied_valid(applied),.pending(pending),.pending_index(pending_index),.invalid_request(invalid),
  .cc_req(bcc),.cc_id(bid),.cc_value(bv),.sysex_req(bsx),.sysex_msgs(bm));
 param_merger #(.PRESET_ENABLE(1)) merger(.clk(clk),.rst_n(rst_n),.preset_load(load),.preset_busy(busy),.preset_values(bank),
  .spi_param_valid(knob_valid),.spi_param_id(knob_id),.spi_param_val(knob_value),.touch_delta_valid(1'b0),
  .touch_selected_id(8'd0),.touch_delta_val(8'd0),.curve_update_valid(1'b0),.curve_update_filter(1'b0),
  .curve_update_tab(2'd0),.curve_update_mask(5'd0),.curve_update_values(35'd0),.midi_tx_busy(tx_busy),
  .btn_tap_valid(1'b0),.btn_tap_id(8'd0),.btn_tap_action(2'd0),.static_cc_values(base));
 fx_editor_state #(.AUX_ENABLE(1),.PRESET_ENABLE(1)) fxstate(.clk(clk),.rst_n(rst_n),
  .preset_load(load),.preset_busy(busy),.preset_values(bank),.touch_valid(1'b0),.touch_down(1'b0),
  .touch_x(14'd0),.touch_y(14'd0),.external_valid(1'b0),.external_id(8'd0),.external_value(7'd0),
  .aux_valid(legacy),.aux_id(legacy_id),.aux_value(legacy_value),.aux_owner_valid(1'b0),.aux_owner_id(8'd0),
  .values(fx),.switches(switches));
 audio_controls_state #(.PRESET_ENABLE(1)) extras(.clk(clk),.rst_n(rst_n),
  .preset_load(load),.preset_busy(busy),.preset_values(bank),.cancel(1'b0),.touch_valid(1'b0),.touch_down(1'b0),
  .touch_x(14'd0),.touch_y(14'd0),.external_valid(1'b0),.external_id(8'd0),.external_value(7'd0),
  .legacy_values(fx),.extra_values(extra),.legacy_valid(legacy),.legacy_id(legacy_id),.legacy_value(legacy_value));
 lfo_binding_state #(.PRESET_ENABLE(1),.ENABLE_CANCEL(1)) binding(.clk(clk),.rst_n(rst_n),
  .preset_load(load),.preset_busy(busy),.cancel(1'b0),.touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),
  .active_tab(2'd0),.sources(sources),.depths(depths));
 assign values={extra,fx[84+:7],fx[49+:7],fx[42+:7],fx[35+:7],fx[7+:7],fx[0+:7],base};
 static_cc_sync #(.PRESET_ENABLE(1)) sync(.clk(clk),.rst_n(rst_n),.preset_hold(busy),.preset_adopt(adopt),
  .values(values),.cc_accept(ca&&!busy),.uart_busy(tx_busy),.cc_req(scc),.cc_param_id(sid),.cc_val(sv),.startup_sync_done(startup));
 lfo_sysex_tx #(.PRESET_ENABLE(1),.HOLD_CYCLES(16),.FIRST_HOLD_CYCLES(8)) lfo(
  .clk(clk),.rst_n(rst_n),.preset_hold(busy||!startup),.preset_adopt(adopt),
  .cfg_nodes(nodes),.cfg_rates(rates),.cfg_steps(steps),.cfg_once(once_bits),.cfg_sources(sources),.cfg_depths(depths),
  .tx_accept(sa&&!busy),.sysex_req(ssx),.sysex_msgs(sm),.busy(lf_busy));
 midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(5000000)) uart(.clk(clk),.rst_n(rst_n),
  .note_on_req(note_on),.note_off_req(note_off),.note_number(7'd60),.note_velocity(7'd100),
  .cc_req(busy?bcc:scc),.cc_param_id(busy?bid:sid),.cc_val(busy?bv:sv),
  .sysex_req(busy?bsx:ssx),.sysex_msgs(busy?bm:sm),.sysex_accept(sa),.cc_accept(ca),
  .uart_tx(tx),.tx_busy(tx_busy),.note_ready(note_ready));
 reg [7:0] golden[0:12050]; // 17 batches, then ordinary CC and LFO rebind
 reg [7:0] received,msg[0:5];
 integer bitno,mi=0,expected_len=0,position=0,notes=0,loads=0,trace;
 reg collect=0;
 // UART bit period = ten clocks. This checks the serial wire, not injection.
 initial forever begin
  @(negedge tx);#150;
  for(bitno=0;bitno<8;bitno=bitno+1)begin received[bitno]=tx;#100;end
  if(tx!==1)$fatal(1,"FAIL: invalid UART stop bit");
  if(collect)begin
   msg[mi]=received;
   if(mi==0)begin
    if(received==8'hF0)expected_len=6;
    else if(received==8'hBF || received==8'h90 || received==8'h80)expected_len=3;
    else $fatal(1,"FAIL: unexpected status %h at byte %d",received,position);
   end
   mi=mi+1;
   if(mi==expected_len)begin
    if(msg[0]==8'h90 || msg[0]==8'h80)begin
     if(msg[1]!=60 || (msg[0]==8'h90 && msg[2]!=100) || (msg[0]==8'h80 && msg[2]!=0))$fatal(1,"FAIL: Note payload");
     notes=notes+1;
    end else begin
     for(mi=0;mi<expected_len;mi=mi+1)begin
      if(position>=12051 || msg[mi]!==golden[position])$fatal(1,"FAIL: UART[%0d] got %02h expected %02h",position,msg[mi],golden[position]);
      $fwrite(trace,"%02x\n",msg[mi]);position=position+1;
     end
    end
    mi=0;
   end
  end
 end
 always @(posedge clk)if(load)begin
  loads=loads+1;
  #1;
  if(values!==bank)$fatal(1,"FAIL: preset %d UI state diverges from transmitted bank",active);
  if(sources!==0 || depths!==0)$fatal(1,"FAIL: old LFO route/depth retained");
  if(merger.env_h[0]!==0 || merger.env_h[1]!==0)$fatal(1,"FAIL: Hold not local/reset");
  if(switches!==0)$fatal(1,"FAIL: legacy FX link still active");
 end
 task request;
  input [3:0] n;
  begin @(negedge clk);index=n;apply=1;@(negedge clk);apply=0;end
 endtask
 task finished;
  begin wait(busy);wait(!busy);repeat(200)@(negedge clk);
   if(tx_busy || scc || ssx || lf_busy)$fatal(1,"FAIL: duplicate reconciliation after preset");
  end
 endtask
 task packet;
  input down;input [13:0] xx,yy;
  begin @(negedge clk);tv=1;td=down;x=xx;y=yy;@(negedge clk);tv=0;repeat(5)@(negedge clk);end
 endtask
 integer k;
 initial begin
  $readmemh("preset_expected.hex",golden);trace=$fopen("preset_actual.hex","w");
  for(k=0;k<21;k=k+1)nodes[k*7+:7]=(k*7+11)%128;
  repeat(5)@(negedge clk);rst_n=1;
  wait(startup && !lfo.first_boot && !lf_busy && !tx_busy);repeat(100)@(negedge clk);
  // Seed a REAL binding before recall; clearing only the transport would fail.
  packet(1,1160,384);packet(0,1160,384);packet(1,1000,460);packet(1,134,268);packet(0,0,0);
  if(sources[13:12]!==1)$fatal(1,"FAIL: test failed to create prior binding");
  wait(!lf_busy && !tx_busy);repeat(1000)@(negedge clk);wait(!lf_busy && !tx_busy);
  collect=1;
  for(k=0;k<13;k=k+1)begin request(k);finished();$display("CHECK: preset %0d complete, all 74 live values and 708 serial bytes match",k);end
  request(12);finished(); // Reapply the new piano even if every value is unchanged.
  request(0);wait(load);repeat(7)@(negedge clk);request(5);request(6);request(12);
  if(!pending || pending_index!=12)$fatal(1,"FAIL: latest new-piano request not retained");
  // A conflicting Note wins FIFO acceptance over bulk controls.
  wait(bcc && !tx_busy);@(negedge clk);note_on=1;
  #1;if(ca)$fatal(1,"FAIL: CC stole priority from Note");
  @(negedge clk);note_on=0;
  wait(bsx && !tx_busy);@(negedge clk);note_off=1;
  #1;if(sa)$fatal(1,"FAIL: SysEx stole priority from Note");
  @(negedge clk);note_off=0;
  finished();
  if(loads!=16 || notes!=2 || position!=11328 || mi!=0)$fatal(1,"FAIL: totals loads=%0d Notes=%0d bytes=%0d",loads,notes,position);
  // Recall before the normal startup sync has even sent its first CC. The
  // adopted shadows must not append a second boot/LFO transaction afterward.
  @(negedge clk);rst_n=0;repeat(5)@(negedge clk);
  index=2;apply=1;rst_n=1;@(negedge clk);apply=0;finished();
  if(loads!=17 || position!=12036)$fatal(1,"FAIL: boot-time recall totals");
  request(15);repeat(4)@(negedge clk);if(busy || loads!=17)$fatal(1,"FAIL: invalid request altered state");
  // With hooks ENABLED, normal physical CC edits and real LFO binding still
  // work after adoption; a stale shadow or stuck hold fails serial equality.
  @(negedge clk);knob_valid=1;knob_id=`PARAM_ID_MASTER_VOL;knob_value=25;
  @(negedge clk);knob_valid=0;wait(position==12039);wait(!tx_busy);
  packet(1,1160,384);packet(0,0,0);packet(1,1000,460);packet(1,134,268);packet(0,0,0);
  wait(position==12051);wait(!tx_busy);repeat(200)@(negedge clk);
  if(position!=12051 || sources[13:12]!=1 || depths[55:48]!=127)$fatal(1,"FAIL: post-preset CC/LFO editing");
  $fclose(trace);
  $display("PASS: 13 presets + full reapply + latest pending + boot recall; 12051 exact serial bytes, all state banks, LFO clear/adopt, Note priority and subsequent CC/rebind");$finish;
 end
 initial begin #50000000;$fatal(1,"FAIL: preset bench timeout");end
endmodule
