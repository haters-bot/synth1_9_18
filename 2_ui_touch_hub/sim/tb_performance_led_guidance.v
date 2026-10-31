`timescale 1ns/1ps
module tb_performance_led_guidance;
reg clk=0,rst_n=0,tv=0,td=0,push=0,start=0,stop=0,pause=0,tick=0,remote=0;
reg [31:0] time_ms=0;reg [13:0] x=0,y=0;reg [1:0] mode=1;reg [6:0] score_note;reg score_on;
wire [105:0] sources;wire [423:0] depths;wire [146:0] nodes;wire [8:0] rates;wire [2:0] steps,once;
wire performance_local_mode_valid;wire [1:0] performance_local_mode;
wire out_valid,out_on,tx_ready;wire [6:0] out_note,out_vel;
reg rx=1;wire [7:0] data;wire bv,nv,physical_on;wire [6:0] note,vel;
reg vs=0,clear_events=0,invalidate=0,remote_on=1;
reg [6:0] base=7'h29;wire led_data;
wire local_play,local_pause,local_stop,local_record;
performance_touch_controls #(.CONTACT_TIMEOUT_CYCLES(64)) controls(.clk(clk),.rst_n(rst_n),
 .page_active(dut.navigation_view==2),.touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),
 .play(local_play),.pause_toggle(local_pause),.stop(local_stop),.record_toggle(local_record));
integer mode_changes=0,plays=0,pauses=0,stops=0,records=0;
always @(posedge clk)begin
 if(performance_local_mode_valid)mode_changes=mode_changes+1;
 if(local_play)plays=plays+1;if(local_pause)pauses=pauses+1;
 if(local_stop)stops=stops+1;if(local_record)records=records+1;
end
always #10 clk=~clk;
performance_uart_rx #(.CLK_FREQ(50000000),.BAUD(5000000)) uart(.clk(clk),.rst_n(rst_n),.uart_rx(rx),.byte_data(data),.byte_valid(bv),.framing_error());
keyboard_midi_parser parser(.clk(clk),.rst_n(rst_n),.byte_data(data),.byte_valid(bv),.note_event_valid(nv),.note_event_on(physical_on),.note_event_note(note),.note_event_velocity(vel));
wire tx;
midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(5000000)) midi(.clk(clk),.rst_n(rst_n),.note_on_req(out_valid&&out_on),.note_off_req(out_valid&&!out_on),.note_number(out_note),.note_velocity(out_vel),.cc_req(1'b0),.cc_param_id(8'd0),.cc_val(7'd0),.sysex_req(1'b0),.sysex_msgs(48'd0),.uart_tx(tx),.note_ready(tx_ready),.tx_busy());
integer observed=0;reg [23:0] messages[0:63];reg [7:0] rb;reg [23:0] message=0;integer bi,bytes=0;
initial forever begin
 @(negedge tx);#100;
 for(bi=0;bi<8;bi=bi+1)begin #200;rb[bi]=tx;end
 #200;if(tx!==1)$fatal(1,"MIDI stop");message={message[15:0],rb};bytes=bytes+1;
 if(bytes==3)begin messages[observed]=message;observed=observed+1;bytes=0;end
end
ui_top_renderer #(.PERFORMANCE_MAX_EVENTS(64),.PERFORMANCE_RUNTIME_BASE(1),.PERFORMANCE_USE_NOTE_READY(1),.TOUCH_CONTACT_TIMEOUT_CYCLES(64)) dut(.clk(clk),.rst_n(rst_n),.in_hsync('0),.in_vsync(vs),.in_den('0),.in_pixel_x('0),.in_pixel_y('0),.val_macro1('0),.val_macro2('0),.val_macro3('0),.val_macro4('0),.val_master_vol('0),.val_osca_unison('0),.val_osca_detune('0),.val_osca_blend('0),.val_osca_phase('0),.val_osca_rand('0),.val_osca_wt_pos('0),.val_osca_warp('0),.val_osca_pan('0),.val_osca_vol('0),.val_oscb_unison('0),.val_oscb_detune('0),.val_oscb_blend('0),.val_oscb_phase('0),.val_oscb_rand('0),.val_oscb_wt_pos('0),.val_oscb_warp('0),.val_oscb_pan('0),.val_oscb_vol('0),.val_flt_cutoff('0),.val_flt_res('0),.val_flt_pan('0),.val_flt_drive('0),.val_flt_fat('0),.val_flt_mix('0),.val_env_attack('0),.val_env_hold('0),.val_env_decay('0),.val_env_sustain('0),.val_env_release('0),.val_fx_reverb('0),.val_fx_delay('0),.val_fx_chorus('0),.val_portamento('0),.val_osca_power('0),.val_oscb_power('0),.val_flt_power('0),.val_osca_wave('0),.val_oscb_wave('0),.val_osca_oct('0),.val_osca_semi('0),.val_osca_fine('0),.val_oscb_oct('0),.val_oscb_semi('0),.val_oscb_fine('0),.val_flt_type('0),.val_flt_route_a('0),.val_flt_route_b('0),.val_flt_route_n('0),.val_flt_route_s('0),.val_flt_keytrack('0),.val_env_tab('0),.val_slot_bypass('0),.active_btn_id('0),.btn_flash_active('0),.selected_param_id('0),.usb_connected('0),.usb_conn_err('0),.usb_dev_type('0),.usb_raw_x('0),.usb_raw_y('0),.usb_raw_down('0),.usb_dbg_report('0),.usb_dbg_regs('0),.usb_dbg_pkt_cnt('0),.touch_diag_coords('0),.touch_diag_count('0),.touch_diag_mode('0),.ui_touch_valid(tv),.ui_touch_down(td),.ui_touch_x(x),.ui_touch_y(y),.audio_sample_valid('0),.audio_xy_a('0),.audio_xy_b('0),.audio_xy_valid('0),.audio_xy_available('0),.audio_sample('0),.audio_right_sample('0),.audio_stereo_valid('0),.audio_link_up('0),.external_param_valid('0),.external_param_id('0),.external_param_value('0),.performance_tick_1ms(tick),.performance_clear_events(clear_events),.performance_event_push(push),.performance_event_time_ms(time_ms),.performance_event_note(score_note),.performance_event_velocity(7'd100),.performance_event_on(score_on),.performance_start(start),.performance_stop(stop),.performance_pause(pause),.performance_mode(mode),.performance_local_mode_valid(performance_local_mode_valid),.performance_local_mode(performance_local_mode),.performance_duration_ms(32'd1500),.performance_gateway_up_in('0),.performance_recording_in('0),.performance_note_ready(tx_ready),.performance_record_status_in('0),.performance_remote_note_valid(remote),.performance_remote_note_on(remote_on),.performance_remote_note(7'h29),.performance_remote_velocity('0),.performance_physical_note_valid(nv),.performance_physical_note_on(physical_on),.performance_physical_note(note),.performance_physical_velocity(vel),.performance_base_note(base),.performance_calibration_state(3'd2),.performance_invalidate(invalidate),.performance_led_data(led_data),.performance_note_valid(out_valid),.performance_note_on(out_on),.performance_note_number(out_note),.performance_note_velocity(out_vel),.route_source_snapshot(sources),.route_depth_snapshot(depths),.lfo_node_snapshot(nodes),.lfo_rate_snapshot(rates),.lfo_step_snapshot(steps),.lfo_once_snapshot(once));
task step;begin @(negedge clk);end endtask
task load(input integer t,n,input bit on);begin time_ms=t;score_note=n;score_on=on;push=1;step;push=0;step;end endtask
task advance(input integer n);integer k;begin for(k=0;k<n;k=k+1)begin tick=1;step;tick=0;repeat(10)step;end end endtask
task byte_send(input [7:0] b);integer i;begin step;rx=0;#200;for(i=0;i<8;i=i+1)begin rx=b[i];#200;end rx=1;#200;end endtask
task physical(input integer n,v);begin byte_send(8'h90);byte_send(n);byte_send(v);repeat(20)step;end endtask
task play;begin start=1;step;start=0;repeat(50)step;end endtask
task halt;begin stop=1;step;stop=0;repeat(1000)step;end endtask
task packet(input integer px,py,input bit down);begin
 step;x=px;y=py;td=down;tv=1;step;tv=0;repeat(10)step;
end endtask
task click(input integer px,py);begin packet(px,py,1);packet(0,0,0);end endtask

// Scale only strip timing; tb_ws2812_serial separately checks production 50MHz.
defparam dut.u_performance_leds.CLK_HZ=5000000;
defparam dut.u_performance_leds.RESET_CYCLES=30;
reg [23:0] palette[0:23],planned_masks[0:127],last_rgb[0:23];
reg [23:0] pixel_grb,last_mask=0,expected_rgb;
integer planned=0,frames=0,pixel,bitnum,high_cycles,led,checks=0,octave;
always @(posedge clk)if(rst_n && dut.led_latch)begin
 if(planned>=128)$fatal(1,"too many frames");
 planned_masks[planned]=dut.led_last_active|dut.led_last_guide;planned=planned+1;
end
initial forever begin
 for(pixel=0;pixel<24;pixel=pixel+1)begin
  pixel_grb=0;
  for(bitnum=23;bitnum>=0;bitnum=bitnum-1)begin
   wait(led_data===1'b1);high_cycles=0;
   while(led_data===1'b1)begin high_cycles=high_cycles+1;@(posedge clk);#1;end
   if(high_cycles!=2 && high_cycles!=4)$fatal(1,"bad scaled pulse %0d",high_cycles);
   pixel_grb[bitnum]=(high_cycles==4);
  end
  last_rgb[pixel]={pixel_grb[15:8],pixel_grb[23:16],pixel_grb[7:0]};
  expected_rgb=planned_masks[frames][pixel] ? palette[pixel] : 24'd0;
  if(last_rgb[pixel]!==expected_rgb)$fatal(1,"GRB/atomic frame %0d pixel %0d RGB=%h expected=%h",frames,pixel,last_rgb[pixel],expected_rgb);
  if(pixel>=19 && last_rgb[pixel]!==0)$fatal(1,"unused pixel lit");
 end
 last_mask=planned_masks[frames];frames=frames+1;
end

task check_sources(input [23:0] active,input [23:0] guide);
 begin repeat(12)step;
  if(dut.led_active_source!==active || dut.led_guide_source!==guide)
   $fatal(1,"score=%0d mode=%0d running=%b active=%h/%h guide=%h/%h",dut.performance_song_time_ms,mode,dut.performance_running,dut.led_active_source,active,dut.led_guide_source,guide);
  checks=checks+1;
 end
endtask
task frame(input [23:0] mask);
 integer timeout;
 begin timeout=0;
  while((frames==0 || last_mask!==mask) && timeout<24000)begin step;timeout=timeout+1;end
  if(frames==0 || last_mask!==mask)$fatal(1,"missing DIN mask %h last=%h",mask,last_mask);
  checks=checks+1;
 end
endtask
task clear_score;
 begin halt;clear_events=1;step;clear_events=0;repeat(12)step;end
endtask
task short_score;
 begin load(10,base,1);load(20,base,0);load(30,base+2,1);load(40,base+2,0);end
endtask
initial begin
 palette[0]=24'h200000;palette[1]=24'h200600;palette[2]=24'h200C00;
 palette[3]=24'h201200;palette[4]=24'h201A00;palette[5]=24'h202000;
 palette[6]=24'h142000;palette[7]=24'h082000;palette[8]=24'h002000;
 palette[9]=24'h00200C;palette[10]=24'h002018;palette[11]=24'h002020;
 palette[12]=24'h001420;palette[13]=24'h000820;palette[14]=24'h000020;
 palette[15]=24'h080020;palette[16]=24'h100020;palette[17]=24'h180020;palette[18]=24'h200020;
 for(led=19;led<24;led=led+1)palette[led]=0;
 repeat(5)step;rst_n=1;step;mode=2;
 click(650,20);vs=1;repeat(10)step;vs=0;repeat(20)step;
 if(dut.navigation_view!=2)$fatal(1,"navigation");check_sources(0,0);
 physical(41,100);check_sources(1,0);frame(1);
 physical(41,0);physical(42,100);check_sources(0,0);
 physical(42,0);physical(72,100);check_sources(24'h40000,0);frame(24'h40000);
 // Follow must cue the waiting onset BEFORE a correct physical hit exists.
 clear_score;short_score;mode=1;play;advance(9);check_sources(0,0);
 advance(1);check_sources(0,1);
 if(dut.performance_guide_keys!==0)$fatal(1,"follow emitted before acknowledgement");
 frame(1);physical(43,100);check_sources(0,1);physical(43,0);
 remote=1;step;remote=0;repeat(40)step;check_sources(0,1);
 remote_on=0;remote=1;step;remote=0;repeat(20)step;
 pause=1;advance(30);check_sources(0,1);
 if(dut.performance_song_time_ms!=10)$fatal(1,"pause advanced time");
 pause=0;physical(41,100);advance(20);check_sources(0,2);frame(2);
 physical(41,0);physical(43,100);advance(15);
 if(dut.performance_running)$fatal(1,"follow did not finish");
 check_sources(24'h40002,0);physical(43,0);
 // Perform is entirely score-driven while a wrong held key stays suppressed.
 clear_score;short_score;mode=2;play;advance(9);check_sources(0,0);
 advance(1);check_sources(0,1);frame(1);
 physical(45,100);check_sources(0,1);physical(45,0);
 pause=1;advance(30);check_sources(0,1);pause=0;
 advance(10);check_sources(0,0);frame(0);
 advance(10);check_sources(0,2);frame(2);
 advance(15);check_sources(24'h40000,0);frame(24'h40000);
 clear_score;short_score;mode=0;play;advance(10);check_sources(0,1);
 halt;check_sources(24'h40000,0);frame(24'h40000);physical(72,0);
 // A full 19-white-key chord checks the palette on actual DIN, not just RGB.
 invalidate=1;repeat(4)step;invalidate=0;clear_score;mode=2;
 for(led=0;led<32;led=led+1)
  if(((41+led)%12==0)||((41+led)%12==2)||((41+led)%12==4)||((41+led)%12==5)||((41+led)%12==7)||((41+led)%12==9)||((41+led)%12==11))load(10,41+led,1);
 for(led=0;led<32;led=led+1)
  if(((41+led)%12==0)||((41+led)%12==2)||((41+led)%12==4)||((41+led)%12==5)||((41+led)%12==7)||((41+led)%12==9)||((41+led)%12==11))load(30,41+led,0);
 play;advance(10);repeat(160)step;check_sources(0,24'h7FFFF);frame(24'h7FFFF);
 pause=1;advance(50);check_sources(0,24'h7FFFF);pause=0;
 advance(20);repeat(160)step;check_sources(0,0);frame(0);
 for(octave=0;octave<4;octave=octave+1)begin
  clear_score;invalidate=1;repeat(4)step;base=41+12*octave;
  repeat(4)step;invalidate=0;short_score;play;advance(10);check_sources(0,1);
  invalidate=1;check_sources(0,0);invalidate=0;halt;
 end
 clear_score;short_score;mode=1;play;advance(10);check_sources(0,1);frame(1);
 click(150,20);vs=1;repeat(10)step;vs=0;repeat(20)step;
 if(dut.navigation_view==2)$fatal(1,"did not leave page");check_sources(0,0);frame(0);
 if(frames<8)$fatal(1,"insufficient wire coverage");
 $display("PASS: score LEDs before hits; follow/perform/audition, wrong-key isolation, pause/stop/end/page/invalidate, 4 calibration octaves; %0d checks, %0d complete GRB frames, 19 pitch colors and 5 dark LEDs",checks,frames);$finish;
end
initial begin #20000000;$fatal(1,"LED guidance timeout");end
endmodule
