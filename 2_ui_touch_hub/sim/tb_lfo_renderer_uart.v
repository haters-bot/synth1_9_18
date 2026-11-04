`timescale 1ns/1ps
module tb_lfo_renderer_uart;
reg clk=0,rst_n=0,tv=0,td=0,push=0,note_on=1,start=0,stop=0,pause=0,tick=0;
reg [31:0] time_ms=0;reg [13:0] x=0,y=0;
wire [105:0] sources;wire [423:0] depths;wire [146:0] nodes;wire [8:0] rates;wire [2:0] steps,once;
wire req,accept,uart,busy;wire [47:0] msgs;
wire performance_local_mode_valid;wire [1:0] performance_local_mode;
reg cc_req=0,note_req=0;
always #10 clk=~clk;
ui_top_renderer #(.PERFORMANCE_BASE_NOTE(7'd29),.PERFORMANCE_MAX_EVENTS(16),.BIND_WATCHDOG_CYCLES(1000)) dut(.clk(clk),.rst_n(rst_n),.in_hsync('0),.in_vsync('0),.in_den('0),.in_pixel_x('0),.in_pixel_y('0),.val_macro1('0),.val_macro2('0),.val_macro3('0),.val_macro4('0),.val_master_vol('0),.val_osca_unison('0),.val_osca_detune('0),.val_osca_blend('0),.val_osca_phase('0),.val_osca_rand('0),.val_osca_wt_pos('0),.val_osca_warp('0),.val_osca_pan('0),.val_osca_vol('0),.val_oscb_unison('0),.val_oscb_detune('0),.val_oscb_blend('0),.val_oscb_phase('0),.val_oscb_rand('0),.val_oscb_wt_pos('0),.val_oscb_warp('0),.val_oscb_pan('0),.val_oscb_vol('0),.val_flt_cutoff('0),.val_flt_res('0),.val_flt_pan('0),.val_flt_drive('0),.val_flt_fat('0),.val_flt_mix('0),.val_env_attack('0),.val_env_hold('0),.val_env_decay('0),.val_env_sustain('0),.val_env_release('0),.val_fx_reverb('0),.val_fx_delay('0),.val_fx_chorus('0),.val_portamento('0),.val_osca_power('0),.val_oscb_power('0),.val_flt_power('0),.val_osca_wave('0),.val_oscb_wave('0),.val_osca_oct('0),.val_osca_semi('0),.val_osca_fine('0),.val_oscb_oct('0),.val_oscb_semi('0),.val_oscb_fine('0),.val_flt_type('0),.val_flt_route_a('0),.val_flt_route_b('0),.val_flt_route_n('0),.val_flt_route_s('0),.val_flt_keytrack('0),.val_env_tab('0),.val_slot_bypass('0),.active_btn_id('0),.btn_flash_active('0),.selected_param_id('0),.usb_connected('0),.usb_conn_err('0),.usb_dev_type('0),.usb_raw_x('0),.usb_raw_y('0),.usb_raw_down('0),.usb_dbg_report('0),.usb_dbg_regs('0),.usb_dbg_pkt_cnt('0),.touch_diag_coords('0),.touch_diag_count('0),.touch_diag_mode('0),.ui_touch_valid(tv),.ui_touch_down(td),.ui_touch_x(x),.ui_touch_y(y),.audio_sample_valid('0),.audio_xy_a('0),.audio_xy_b('0),.audio_xy_valid('0),.audio_xy_available('0),.audio_sample('0),.audio_right_sample('0),.audio_stereo_valid('0),.audio_link_up('0),.external_param_valid('0),.external_param_id('0),.external_param_value('0),.performance_tick_1ms(tick),.performance_clear_events('0),.performance_event_push(push),.performance_event_time_ms(time_ms),.performance_event_note(7'd29),.performance_event_velocity(7'd100),.performance_event_on(note_on),.performance_start(start),.performance_stop(stop),.performance_pause(pause),.performance_mode(2'd2),.performance_local_mode_valid(performance_local_mode_valid),.performance_local_mode(performance_local_mode),.performance_duration_ms(32'd1500),.performance_gateway_up_in('0),.performance_recording_in('0),.performance_note_ready('0),.performance_record_status_in('0),.performance_remote_note_valid('0),.performance_remote_note_on('0),.performance_remote_note('0),.performance_remote_velocity('0),.performance_physical_note_valid(1'b0),.route_source_snapshot(sources),.route_depth_snapshot(depths),.lfo_node_snapshot(nodes),.lfo_rate_snapshot(rates),.lfo_step_snapshot(steps),.lfo_once_snapshot(once));
lfo_sysex_tx #(.HOLD_CYCLES(20),.FIRST_HOLD_CYCLES(20)) sx(.clk(clk),.rst_n(rst_n),.cfg_nodes(nodes),.cfg_rates(rates),.cfg_steps(steps),.cfg_once(once),.cfg_sources(sources),.cfg_depths(depths),.tx_accept(accept),.sysex_req(req),.sysex_msgs(msgs),.busy());
midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(5000000)) tx(.clk(clk),.rst_n(rst_n),.note_on_req(note_req),.note_off_req(1'b0),.note_number(7'd29),.note_velocity(7'd100),.cc_req(cc_req),.cc_param_id(8'h05),.cc_val(7'd99),.sysex_req(req),.sysex_msgs(msgs),.sysex_accept(accept),.uart_tx(uart),.tx_busy(busy),.note_ready());
reg [7:0] serial_byte;reg [47:0] frame=0;integer bi,bytes=0,frames=0,commits=0,needed=6,note_count=0,cc_count=0;reg [47:0] last_route[0:52];
initial forever begin
 @(negedge uart);#100;if(uart!==0)$fatal(1,"start");
 for(bi=0;bi<8;bi=bi+1)begin #200;serial_byte[bi]=uart;end
 #200;if(uart!==1)$fatal(1,"stop");
 if(bytes==0)needed=(serial_byte==8'hF0)?6:3;
 frame={frame[39:0],serial_byte};bytes=bytes+1;
 if(bytes==needed && needed==3)begin
  bytes=0;
  if(frame[23:0]==24'h901D64)note_count=note_count+1;
  else if(frame[23:0]==24'hBF3063)cc_count=cc_count+1;
  else $fatal(1,"unexpected ordinary MIDI %h",frame[23:0]);
 end else if(bytes==needed)begin
  bytes=0;frames=frames+1;
  if(frame[47:32]!==16'hF07D || frame[7:0]!==8'hF7)$fatal(1,"bad frame %h",frame);
  if(frame[31:24]>=73 && frame[31:24]<=125)last_route[frame[31:24]-73]=frame;
  if(frame==48'hF07D7E0000F7)commits=commits+1;
 end
end
task packet(input integer px,py,input bit down);begin
 @(negedge clk);x=px;y=py;td=down;tv=1;
 @(negedge clk);tv=0;repeat(10)@(negedge clk);
end endtask
task click(input integer px,py);begin packet(px,py,1);packet(px,py,0);end endtask
task settle;integer z;begin
 repeat(1200)@(negedge clk);
 z=0;while((busy || sx.busy || dut.mod_dragging) && z<60000)begin @(negedge clk);z=z+1;end
 repeat(10)@(negedge clk);
 if(busy || sx.busy)$fatal(1,"not drained");
end endtask
task check_route(input integer target,src,input [47:0] expected);begin
 settle;
 $display("CHECK: target=%0d source=%0d depth=%0d UART: %h",target,sources[target*2+:2],$signed(depths[target*8+:8]),last_route[target]);
 if(sources[target*2+:2]!==src[1:0] || depths[target*8+:8]!==8'h7F)$fatal(1,"wrong live binding");
 if(last_route[target]!==expected)$fatal(1,"wrong serial binding expected %h",expected);
 if(dut.u_binding.source[target]!==src[1:0] || dut.u_binding.depth[target]!==8'h7F)$fatal(1,"binding cell mismatch");
 if(sx.q_sources[target*2+:2]!==src[1:0] || sx.sh_sources[target*2+:2]!==src[1:0])$fatal(1,"source lost in q/sh snapshots");
end endtask
task bind_target(input integer target,input bit explicit_up);begin
 click(1140,385);packet(980,485,1);
 if(target==6)packet(134,268,1);else packet(344,326,1);
 if(explicit_up)packet(0,0,0);
end endtask
integer old_commits;
initial begin
 repeat(5)@(negedge clk);rst_n=1;wait(commits==1);settle;
 if(commits!=1)$fatal(1,"initial full sync");
 bind_target(6,1);
 check_route(6,1,48'hF07D4F027FF7);
 if(commits!=2)$fatal(1,"binding must commit exactly once");
 // Additional UP and ordinary contacts must preserve the route.
 packet(0,0,0);click(500,200);settle;
 if(sources[13:12]!==1 || commits!=2)$fatal(1,"release cleared binding");
 bind_target(13,1);
 check_route(13,1,48'hF07D56027FF7);
 click(1200,675);check_route(13,0,48'hF07D56007FF7);
 bind_target(13,1);check_route(13,1,48'hF07D56027FF7);
 old_commits=commits;click(930,385);settle;
 if(dut.lfo_tab!==1 || commits!=old_commits)$fatal(1,"tab switch changed routing");
 bind_target(6,1);check_route(6,2,48'hF07D4F047FF7);
 click(1020,385);bind_target(13,0);
 // Exercise Note and CC arbitration while the no-UP watchdog commits LFO3.
 @(negedge clk);note_req=1;@(negedge clk);note_req=0;
 repeat(5)@(negedge clk);cc_req=1;@(negedge clk);cc_req=0;
 check_route(13,3,48'hF07D56067FF7);
 if(dut.mod_dragging || dut.mod_armed || note_count!=1 || cc_count!=1)$fatal(1,"timeout release or UART arbitration");
 $display("PASS: real renderer binding targets 6/13, release preservation, clear/rebind, LFO2/3, no-UP timeout and serial Note/CC/Commit arbitration, commits=%0d",commits);$finish;
end
initial begin #16000000;$fatal(1,"timeout");end
endmodule
