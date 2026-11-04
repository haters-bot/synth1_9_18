`timescale 1ns/1ps
module tb_performance_modes;
reg clk=0,rst_n=0,tv=0,td=0,push=0,start=0,stop=0,pause=0,tick=0,remote=0;
reg [31:0] time_ms=0;reg [13:0] x=0,y=0;reg [1:0] mode=1;reg [6:0] score_note;reg score_on;
wire [105:0] sources;wire [423:0] depths;wire [146:0] nodes;wire [8:0] rates;wire [2:0] steps,once;
wire performance_local_mode_valid;wire [1:0] performance_local_mode;
wire out_valid,out_on,tx_ready;wire [6:0] out_note,out_vel;
reg rx=1;wire [7:0] data;wire bv,nv,physical_on;wire [6:0] note,vel;
reg vs=0;
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
ui_top_renderer #(.PERFORMANCE_MAX_EVENTS(16),.PERFORMANCE_USE_NOTE_READY(1),.TOUCH_CONTACT_TIMEOUT_CYCLES(64)) dut(.clk(clk),.rst_n(rst_n),.in_hsync('0),.in_vsync(vs),.in_den('0),.in_pixel_x('0),.in_pixel_y('0),.val_macro1('0),.val_macro2('0),.val_macro3('0),.val_macro4('0),.val_master_vol('0),.val_osca_unison('0),.val_osca_detune('0),.val_osca_blend('0),.val_osca_phase('0),.val_osca_rand('0),.val_osca_wt_pos('0),.val_osca_warp('0),.val_osca_pan('0),.val_osca_vol('0),.val_oscb_unison('0),.val_oscb_detune('0),.val_oscb_blend('0),.val_oscb_phase('0),.val_oscb_rand('0),.val_oscb_wt_pos('0),.val_oscb_warp('0),.val_oscb_pan('0),.val_oscb_vol('0),.val_flt_cutoff('0),.val_flt_res('0),.val_flt_pan('0),.val_flt_drive('0),.val_flt_fat('0),.val_flt_mix('0),.val_env_attack('0),.val_env_hold('0),.val_env_decay('0),.val_env_sustain('0),.val_env_release('0),.val_fx_reverb('0),.val_fx_delay('0),.val_fx_chorus('0),.val_portamento('0),.val_osca_power('0),.val_oscb_power('0),.val_flt_power('0),.val_osca_wave('0),.val_oscb_wave('0),.val_osca_oct('0),.val_osca_semi('0),.val_osca_fine('0),.val_oscb_oct('0),.val_oscb_semi('0),.val_oscb_fine('0),.val_flt_type('0),.val_flt_route_a('0),.val_flt_route_b('0),.val_flt_route_n('0),.val_flt_route_s('0),.val_flt_keytrack('0),.val_env_tab('0),.val_slot_bypass('0),.active_btn_id('0),.btn_flash_active('0),.selected_param_id('0),.usb_connected('0),.usb_conn_err('0),.usb_dev_type('0),.usb_raw_x('0),.usb_raw_y('0),.usb_raw_down('0),.usb_dbg_report('0),.usb_dbg_regs('0),.usb_dbg_pkt_cnt('0),.touch_diag_coords('0),.touch_diag_count('0),.touch_diag_mode('0),.ui_touch_valid(tv),.ui_touch_down(td),.ui_touch_x(x),.ui_touch_y(y),.audio_sample_valid('0),.audio_xy_a('0),.audio_xy_b('0),.audio_xy_valid('0),.audio_xy_available('0),.audio_sample('0),.audio_right_sample('0),.audio_stereo_valid('0),.audio_link_up('0),.external_param_valid('0),.external_param_id('0),.external_param_value('0),.performance_tick_1ms(tick),.performance_clear_events('0),.performance_event_push(push),.performance_event_time_ms(time_ms),.performance_event_note(score_note),.performance_event_velocity(7'd100),.performance_event_on(score_on),.performance_start(start),.performance_stop(stop),.performance_pause(pause),.performance_mode(mode),.performance_local_mode_valid(performance_local_mode_valid),.performance_local_mode(performance_local_mode),.performance_duration_ms(32'd1500),.performance_gateway_up_in('0),.performance_recording_in('0),.performance_note_ready(tx_ready),.performance_record_status_in('0),.performance_remote_note_valid(remote),.performance_remote_note_on(1'b1),.performance_remote_note(7'h29),.performance_remote_velocity('0),.performance_physical_note_valid(nv),.performance_physical_note_on(physical_on),.performance_physical_note(note),.performance_physical_velocity(vel),.performance_note_valid(out_valid),.performance_note_on(out_on),.performance_note_number(out_note),.performance_note_velocity(out_vel),.route_source_snapshot(sources),.route_depth_snapshot(depths),.lfo_node_snapshot(nodes),.lfo_rate_snapshot(rates),.lfo_step_snapshot(steps),.lfo_once_snapshot(once));
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
integer i;
initial begin
 repeat(5)step;rst_n=1;step;
 if(dut.PERFORMANCE_BASE_NOTE!=41)$fatal(1,"default must be MIDI41/hex29");
 load(10,41,1);load(20,41,0);load(30,43,1);load(30,45,1);load(40,43,0);load(40,45,0);load(50,46,1);load(60,46,0);
 play;advance(40);
 if(dut.performance_song_time_ms!=10||dut.u_performance_scheduler.read_ptr!=0)$fatal(1,"follow did not wait at first onset");
 physical(42,100);physical(46,100);advance(10);
 if(dut.performance_song_time_ms!=10)$fatal(1,"wrong key advanced");
 remote=1;step;remote=0;advance(10);
 if(dut.performance_song_time_ms!=10)$fatal(1,"phone note counted as physical key");
 physical(41,100);advance(40);
 if(dut.performance_song_time_ms!=30||dut.u_performance_scheduler.read_ptr!=2)$fatal(1,"correct key/off/timeline did not advance");
 physical(45,100);physical(43,100);advance(40);
 if(dut.performance_song_time_ms!=50||dut.u_performance_scheduler.read_ptr!=6)$fatal(1,"chord order or stale wrong-key token");
 pause=1;physical(46,100);advance(10);if(dut.u_performance_scheduler.read_ptr!=6)$fatal(1,"paused follow advanced");pause=0;
 physical(46,0);physical(46,100);advance(20);
 if(dut.performance_running)$fatal(1,"follow did not complete");
 if(dut.performance_physical_keys[0]!==1 || dut.performance_physical_keys[5]!==1)$fatal(1,"physical display keys");
 halt;mode=0;repeat(50)step;observed=0;play;advance(15);repeat(800)step;
 if(observed!=1||messages[0]!==24'h902964)$fatal(1,"audition first MIDI %d %h",observed,messages[0]);
 halt;repeat(1000)step;
 if(observed!=2||messages[1]!==24'h802900)$fatal(1,"stop did not release audition");
 observed=0;play;advance(80);repeat(4000)step;
 if(observed!=8)$fatal(1,"audition score event count %d",observed);
 for(i=0;i<8;i=i+1)if(messages[i][23:16]!==((i==0||i==2||i==3||i==6)?8'h90:8'h80))$fatal(1,"audition event status");
 halt;mode=2;repeat(50)step;observed=0;play;advance(80);repeat(1000)step;
 if(observed!=0 || dut.performance_running)$fatal(1,"guidance mode emitted audio or did not complete");
 click(650,20);vs=1;repeat(10)step;vs=0;repeat(20)step;
 if(dut.navigation_view!=2)$fatal(1,"performance navigation");
 click(340,150);if(performance_local_mode!=0)$fatal(1,"audition mode button");
 click(500,150);if(performance_local_mode!=1)$fatal(1,"follow mode button");
 click(700,150);if(performance_local_mode!=2)$fatal(1,"perform mode button");
 packet(340,150,1);packet(340,150,1);repeat(80)step;
 packet(500,150,1);repeat(80)step;
 if(mode_changes!=5 || performance_local_mode!=1)$fatal(1,"mode missing-UP recovery or duplicate hold");
 packet(60,150,1);packet(60,150,1);repeat(80)step;
 packet(140,150,1);repeat(80)step;packet(220,150,1);repeat(80)step;
 click(1050,150);
 if(plays!=1 || pauses!=1 || stops!=1 || records!=1)$fatal(1,"transport controls missing-UP recovery");
 observed=0;packet(20,500,1);packet(60,500,1);packet(0,0,0);repeat(1800)step;
 if(observed!=4 || messages[0]!=24'h902964 || messages[1]!=24'h802900 ||
    messages[2]!=24'h902A64 || messages[3]!=24'h802A00)$fatal(1,"touch glide/release bytes");
 observed=0;packet(20,500,1);repeat(1800)step;
 if(observed!=2 || messages[1]!=24'h802900)$fatal(1,"touch no-UP left stuck note");
 $display("PASS: physical follow/chords/pause, audition serial MIDI/stop, silent guidance, all mode/transport controls, missing-UP recovery and keyboard glide/release");$finish;
end
initial begin #5000000;$fatal(1,"timeout");end
endmodule
