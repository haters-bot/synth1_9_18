`timescale 1ns/1ps
`include "params.vh"
// Real touch state + live banks + FIFO arbitration + serial UART, decoded by
// the frozen audio team's unmodified MIDI parser and synth_control_router.
module tb_audio_protocol_alignment;
 reg clk=0,rst_n=0,tv=0,td=0,cancel=0,ext=0,sv=0,bv=0;
 reg [13:0] x=0,y=0;reg [7:0] eid=0,sid=0,bid=0;reg [6:0] ev=0,svalue=0;
 reg [1:0] action=0;
 wire [237:0] extras,base;wire [132:0] fx;
 wire [2:0] page,wave_a,wave_b;wire [1:0] menu;
 wire legacy_valid;wire [7:0] legacy_id;wire [6:0] legacy_value;
 wire [517:0] values={extras,fx[84+:7],fx[49+:7],fx[42+:7],fx[35+:7],fx[7+:7],fx[0+:7],base};
 wire cc_req,cc_accept,done,uart,busy,note_ready;wire [7:0] cc_id;wire [6:0] cc_val;
 reg note_req=0;
 always #10 clk=~clk;
 param_merger bank(.clk(clk),.rst_n(rst_n),.spi_param_valid(sv),.spi_param_id(sid),.spi_param_val(svalue),
  .touch_delta_valid(1'b0),.touch_selected_id(8'd0),.touch_delta_val(8'd0),
  .btn_tap_valid(bv),.btn_tap_id(bid),.btn_tap_action(action),.curve_update_valid(1'b0),
  .static_cc_values(base),.val_osca_wave(wave_a),.val_oscb_wave(wave_b));
 audio_controls_state #(.CONTACT_TIMEOUT(200)) controls(.clk(clk),.rst_n(rst_n),.cancel(cancel),
  .touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),.external_valid(ext),.external_id(eid),.external_value(ev),
  .legacy_values(fx),.extra_values(extras),.fx_page(page),.warp_menu(menu),
  .legacy_valid(legacy_valid),.legacy_id(legacy_id),.legacy_value(legacy_value));
 fx_editor_state legacy(.clk(clk),.rst_n(rst_n),.touch_valid(1'b0),.touch_down(1'b0),.touch_x(14'd0),.touch_y(14'd0),
  .external_valid(legacy_valid),.external_id(legacy_id),.external_value(legacy_value),.values(fx));
 static_cc_sync sync(.clk(clk),.rst_n(rst_n),.values(values),.cc_accept(cc_accept),.uart_busy(busy),
  .cc_req(cc_req),.cc_param_id(cc_id),.cc_val(cc_val),.startup_sync_done(done));
 midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(5000000)) tx(.clk(clk),.rst_n(rst_n),
  .note_on_req(note_req),.note_off_req(1'b0),.note_number(7'd29),.note_velocity(7'd100),
  .cc_req(cc_req),.cc_param_id(cc_id),.cc_val(cc_val),.cc_accept(cc_accept),
  .sysex_req(1'b0),.sysex_msgs(48'd0),.uart_tx(uart),.tx_busy(busy),.note_ready(note_ready));
 reg [7:0] rxbyte=0;reg rxvalid=0;
 wire ccv,nv,no;wire [3:0] ch,nch;wire [6:0] cc,value,note,velocity;
 midi_note_parser parser(.clk(clk),.rst_n(rst_n),.byte_data(rxbyte),.byte_valid(rxvalid),
  .control_change_valid(ccv),.control_change_channel(ch),.control_change_number(cc),.control_change_value(value),
  .note_event_valid(nv),.note_event_on(no),.note_event_channel(nch),.note_event_note(note),.note_event_velocity(velocity));
 synth_control_router audio(.clk(clk),.rst_n(rst_n),.raw_control_change_valid(ccv),.raw_control_change_channel(ch),
  .raw_control_change_number(cc),.raw_control_change_value(value),.raw_note_event_valid(nv),.raw_note_event_on(no),
  .raw_note_event_channel(nch),.raw_note_event_note(note),.raw_note_event_velocity(velocity));
 integer seen[0:127],counts[0:127],expected[0:73];integer messages=0,notes=0,bytes=0,bi,i,j,p,old,mode,offset,k;
 reg [7:0] serial_byte;reg [23:0] packet=0;
 always @(posedge clk)if(audio.note_event_valid)begin
  if(!audio.note_event_on || audio.note_event_note!=29 || audio.note_event_velocity!=100)$fatal(1,"audio Note mismatch");
  notes=notes+1;
 end
 initial forever begin
  @(negedge uart);#100;
  for(bi=0;bi<8;bi=bi+1)begin #200;serial_byte[bi]=uart;end
  #200;if(uart!==1)$fatal(1,"UART stop");
  rxbyte=serial_byte;rxvalid=1;@(negedge clk);rxvalid=0;
  packet={packet[15:0],serial_byte};bytes=bytes+1;
  if(bytes==3)begin
   bytes=0;
   if(packet[23:16]==8'hBF)begin
    if(messages<74 && packet[15:8]!==expected[messages][7:0])$fatal(1,"boot CC order %0d/%0d",messages,packet[15:8]);
    seen[packet[15:8]]=packet[7:0];counts[packet[15:8]]=counts[packet[15:8]]+1;messages=messages+1;
    $display("UART: BF %02h %02h",packet[15:8],packet[7:0]);
   end else if(packet!==24'h901D64)$fatal(1,"ordinary MIDI damaged %h",packet);
  end
 end
 task step;begin @(negedge clk);end endtask
 task touch(input integer px,py,input bit down);begin step;x=px;y=py;td=down;tv=1;step;tv=0;repeat(6)step;end endtask
 task click(input integer px,py);begin touch(px,py,1);touch(px,py,0);end endtask
 task drain;integer z;begin
  repeat(300)step;z=0;
  while((busy||cc_req) && z<100000)begin step;z=z+1;end
  if(busy||cc_req)$fatal(1,"drain timeout");repeat(300)step;
 end endtask
 task check(input integer number,v);begin drain;if(seen[number]!==v)$fatal(1,"CC%0d got%0d expected%0d",number,seen[number],v);end endtask
 task absolute(input [7:0] id,input [6:0] v);begin step;ext=1;eid=id;ev=v;step;ext=0;repeat(5)step;end endtask
 task base_set(input [7:0] id,input [6:0] v);begin step;sv=1;sid=id;svalue=v;step;sv=0;repeat(5)step;end endtask
 task wave_next(input [7:0] id,input [1:0] a);begin step;bv=1;bid=id;action=a;step;bv=0;repeat(5)step;end endtask
 integer expected_cell_id[0:5],expected_cell_cc[0:5],expected_defaults[0:5],newv;
 initial begin
  expected='{48,10,36,21,23,22,87,88,20,39,91,46,37,29,31,30,89,90,28,41,92,47,42,43,44,45,24,25,26,27,32,33,34,35,53,52,54,55,56,57,38,40,49,50,51,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86};
  for(i=0;i<128;i=i+1)begin seen[i]=-1;counts[i]=0;end
  repeat(5)step;rst_n=1;wait(done);drain;
  if(messages!=74)$fatal(1,"boot expected74 got%0d",messages);
  for(i=0;i<74;i=i+1)if(counts[expected[i]]!=1)$fatal(1,"missing/duplicate boot slot%0d",i);
  // Every source is selected from the real five-choice UI state (both directions).
  repeat(4)wave_next(`PARAM_ID_OSCA_WAVE,1);check(21,127);
  if(wave_a!==4 || audio.osc_a_waveform_select!==4)$fatal(1,"A SD mode truncated");
  wave_next(`PARAM_ID_OSCA_WAVE,1);check(21,0);wave_next(`PARAM_ID_OSCA_WAVE,2);check(21,127);
  repeat(3)wave_next(`PARAM_ID_OSCB_WAVE,1);check(29,127);
  if(wave_b!==4 || audio.osc_b_waveform_select!==4)$fatal(1,"B SD mode truncated");
  // Mode popup -> state -> static sync -> MIDI -> audio, 12 modes per bank.
  for(p=0;p<2;p=p+1)for(mode=0;mode<12;mode=mode+1)begin
   offset=p*416;click(80+offset,222);
   if(menu!==p+1)$fatal(1,"mode menu did not open");
   click(60+offset+(mode%3)*124,118+(mode/3)*26);check(p==0?38:40,mode);
   if((p==0 ? audio.osc_a_warp_mode : audio.osc_b_warp_mode)!==mode[3:0])$fatal(1,"audio WARP decode");
  end
  if(bank.val_osca_warp!==64 || bank.val_oscb_warp!==64)$fatal(1,"mode changed independent Amount");
  // The supplied WTB1 header has TEN tables. Do not expose six duplicate IDs.
  for(p=0;p<2;p=p+1)begin
   for(k=1;k<=10;k=k+1)begin click(380+p*416,222);check(p==0?49:50,k%10);end
   click(270+p*416,222);check(p==0?49:50,9);
   absolute(p==0?`PARAM_ID_OSCA_WT_INDEX:`PARAM_ID_OSCB_WT_INDEX,127);check(p==0?49:50,9);
  end
  if(audio.osc_a_wavetable_index!==9 || audio.osc_b_wavetable_index!==9)$fatal(1,"audio WT index");
  // Every FX tab, enable/type and six existing D/R parameters through touch.
  for(p=0;p<5;p=p+1)begin
   click(440+p*58,385);if(page!==p[2:0])$fatal(1,"FX tab");
   click(470,424);check(p==0?58:p==1?69:p==2?63:p==3?51:75,p==3?1:127);
   if(p==0)begin click(670,424);check(59,1);click(670,424);check(59,2);click(670,424);check(59,0);end
   if(p==3)begin click(670,424);check(51,3);click(470,424);check(51,2);click(670,424);check(51,0);end
  end
  if(!audio.distortion_enable || !audio.chorus_enable || !audio.phaser_enable || !audio.compressor_enable)$fatal(1,"FX enables local only");
  for(p=0;p<5;p=p+1)if(p!=3)begin
   click(440+p*58,385);
   case(p)
    0:begin expected_cell_cc='{60,61,62,0,0,0};expected_defaults='{32,127,64,0,0,0};end
    1:begin expected_cell_cc='{70,71,72,73,74,0};expected_defaults='{20,48,64,20,64,0};end
    2:begin expected_cell_cc='{64,65,66,67,68,0};expected_defaults='{20,32,48,20,64,0};end
    4:begin expected_cell_cc='{76,77,78,79,80,81};expected_defaults='{96,64,20,80,0,127};end
   endcase
   for(k=0;k<6;k=k+1)if(expected_cell_cc[k]!=0)begin
    touch(450+(k%2)*176,462+(k/2)*44,1);touch(470+(k%2)*176,452+(k/2)*44,1);touch(0,0,0);
    newv=expected_defaults[k]+15;if(newv>127)newv=127;check(expected_cell_cc[k],newv);
   end
  end
  click(627,385);expected_cell_id='{8'h61,8'h60,8'h65,8'h66,8'h67,8'h6C};
  expected_cell_cc='{52,53,54,55,56,57};expected_defaults='{64,64,32,64,64,32};
  for(k=0;k<6;k=k+1)begin
   touch(450+(k%2)*176,462+(k/2)*44,1);touch(470+(k%2)*176,452+(k/2)*44,1);touch(0,0,0);
   check(expected_cell_cc[k],expected_defaults[k]+15);
  end
  drain;old=messages;click(743,385);drain;
  if(page!=5 || messages!=old)$fatal(1,"PITCH tab changed audio without an edit");
  click(470,424);click(670,424);check(82,127);check(85,127);
  touch(450,462,1);touch(470,452,1);touch(0,0,0);check(83,67);
  touch(450,506,1);touch(470,496,1);touch(0,0,0);check(84,15);
  touch(626,462,1);touch(646,452,1);touch(0,0,0);check(86,95);
  absolute(`PARAM_ID_VIB_RATE,17);absolute(`PARAM_ID_VIB_DEPTH,21);absolute(`PARAM_ID_PORTA_TIME,37);check(83,17);check(84,21);check(86,37);
  if(!audio.vibrato_enable || audio.vibrato_rate!=17 || audio.vibrato_depth!=21 || !audio.portamento_enable || audio.portamento_time!=37)$fatal(1,"pitch extras not applied");
  click(470,424);click(670,424);check(82,0);check(85,0);
  if(audio.vibrato_enable || audio.portamento_enable || audio.vibrato_rate!=17 || audio.vibrato_depth!=21 || audio.portamento_time!=37)$fatal(1,"pitch bypass destroyed settings");
  // Pitch values queued before leaving the page retain their own CC identity.
  absolute(`PARAM_ID_VIB_RATE,19);absolute(`PARAM_ID_PORTA_TIME,39);click(440,385);check(83,19);check(86,39);
  // Centre/endpoints remain exactly 0/64/127. No new audio pan law.
  for(k=0;k<3;k=k+1)begin
   newv=k==0?0:k==1?64:127;
   base_set(`PARAM_ID_OSCA_PAN,newv);base_set(`PARAM_ID_OSCB_PAN,newv);base_set(`PARAM_ID_FLT_PAN,newv);
   check(91,newv);check(92,newv);check(10,newv);
   if(audio.osc_a_pan!=newv || audio.osc_b_pan!=newv || audio.pan_target!=newv)$fatal(1,"audio pan decode");
  end
  // Input updates while FIFO blocked and page switches must retain their ID.
  absolute(`PARAM_ID_DIST_DRIVE,99);click(440+2*58,385);absolute(`PARAM_ID_CHORUS_RATE,71);
  repeat(10)begin wait(note_ready);step;note_req=1;step;note_req=0;end
  check(60,99);check(64,71);
  if(audio.distortion_drive!=99 || audio.chorus_rate!=71 || notes!=10)$fatal(1,"queued identity/Note regression");
  // No explicit UP: quiet-release makes the next press a new menu/tab event.
  touch(440,385,1);repeat(220)step;click(510,385);if(page!==1)$fatal(1,"quiet contact release");
  click(80,222);if(menu!=1)$fatal(1,"popup");cancel=1;step;cancel=0;step;if(menu!=0)$fatal(1,"navigation leaves popup captured");
  $display("PASS: all74 boot CC exactly once; real touch 24 WARP selections/20 bank steps matching real10-table WTB, five FX plus sixth PITCH tab; vibrato/portamento switches and drags/absolute/queued values decoded by latest audio parser/router; bypass retains settings, 0/64/127 PAN, 10 Notes");$finish;
 end
 initial begin #100000000;$fatal(1,"protocol test watchdog");end
endmodule
