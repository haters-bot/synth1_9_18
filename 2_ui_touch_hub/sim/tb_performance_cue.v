`timescale 1ns/1ps
module tb_performance_cue;
reg clk=0,rst_n=0,push=0,note_on=1,start=0,stop=0,pause=0,tick=0;
reg [31:0] time_ms=0;integer i,want;
always #10 clk=~clk;
always @(posedge clk)if(rst_n && dut.performance_note_valid)
 $fatal(1,"Guidance-only score unexpectedly emitted an audio Note");
ui_top_renderer dut(.clk(clk),.rst_n(rst_n),.in_hsync('0),.in_vsync('0),.in_den('0),.in_pixel_x('0),.in_pixel_y('0),.val_macro1('0),.val_macro2('0),.val_macro3('0),.val_macro4('0),.val_master_vol('0),.val_osca_unison('0),.val_osca_detune('0),.val_osca_blend('0),.val_osca_phase('0),.val_osca_rand('0),.val_osca_wt_pos('0),.val_osca_warp('0),.val_osca_pan('0),.val_osca_vol('0),.val_oscb_unison('0),.val_oscb_detune('0),.val_oscb_blend('0),.val_oscb_phase('0),.val_oscb_rand('0),.val_oscb_wt_pos('0),.val_oscb_warp('0),.val_oscb_pan('0),.val_oscb_vol('0),.val_flt_cutoff('0),.val_flt_res('0),.val_flt_pan('0),.val_flt_drive('0),.val_flt_fat('0),.val_flt_mix('0),.val_env_attack('0),.val_env_hold('0),.val_env_decay('0),.val_env_sustain('0),.val_env_release('0),.val_fx_reverb('0),.val_fx_delay('0),.val_fx_chorus('0),.val_portamento('0),.val_osca_power('0),.val_oscb_power('0),.val_flt_power('0),.val_osca_wave('0),.val_oscb_wave('0),.val_osca_oct('0),.val_osca_semi('0),.val_osca_fine('0),.val_oscb_oct('0),.val_oscb_semi('0),.val_oscb_fine('0),.val_flt_type('0),.val_flt_route_a('0),.val_flt_route_b('0),.val_flt_route_n('0),.val_flt_route_s('0),.val_flt_keytrack('0),.val_env_tab('0),.val_slot_bypass('0),.active_btn_id('0),.btn_flash_active('0),.selected_param_id('0),.usb_connected('0),.usb_conn_err('0),.usb_dev_type('0),.usb_raw_x('0),.usb_raw_y('0),.usb_raw_down('0),.usb_dbg_report('0),.usb_dbg_regs('0),.usb_dbg_pkt_cnt('0),.touch_diag_coords('0),.touch_diag_count('0),.touch_diag_mode('0),.ui_touch_valid('0),.ui_touch_down('0),.ui_touch_x('0),.ui_touch_y('0),.audio_sample_valid('0),.audio_xy_a('0),.audio_xy_b('0),.audio_xy_valid('0),.audio_xy_available('0),.audio_sample('0),.audio_right_sample('0),.audio_stereo_valid('0),.audio_link_up('0),.external_param_valid('0),.external_param_id('0),.external_param_value('0),.performance_tick_1ms(tick),.performance_clear_events('0),.performance_event_push(push),.performance_event_time_ms(time_ms),.performance_event_note(7'd60),.performance_event_velocity(7'd100),.performance_event_on(note_on),.performance_start(start),.performance_stop(stop),.performance_pause(pause),.performance_duration_ms(32'd1500),.performance_gateway_up_in('0),.performance_recording_in('0),.performance_note_ready('0),.performance_record_status_in('0),.performance_remote_note_valid('0),.performance_remote_note_on('0),.performance_remote_note('0),.performance_remote_velocity('0));
task step;begin @(negedge clk);end endtask
task advance;begin tick=1;step;tick=0;repeat(12)step;end endtask
initial begin repeat(5)step;rst_n=1;step;
 time_ms=1000;push=1;step;push=0;step;
 time_ms=1500;note_on=0;push=1;step;push=0;step;
 start=1;step;start=0;repeat(15)step;
 for(i=0;i<1000;i=i+1)begin
  want=390-((1000-i)*51)/256;
  if(!dut.performance_next_key_valid || dut.performance_next_key!=0 || dut.performance_next_key_y!=want)
   $fatal(1,"Cue i=%0d y=%0d want=%0d valid=%b",i,dut.performance_next_key_y,want,dut.performance_next_key_valid);
  if(i==500)begin
   pause=1;repeat(20)advance;
   if(dut.performance_song_time_ms!=500 || dut.performance_next_key_y!=want)$fatal(1,"Pause moved cue");
   pause=0;
  end
  advance;
 end
 repeat(15)step;
 if(dut.performance_guide_keys!==32'h1 || dut.performance_next_key_valid)$fatal(1,"Note Off incorrectly shown as upcoming press");
 stop=1;step;stop=0;repeat(15)step;
 if(dut.performance_guide_keys!=0 || dut.performance_next_key_valid)$fatal(1,"Stop retained guide/cue");
 $display("PASS: 1000 positions of score-clock falling cue, exact MIDI key, pause freeze, no Note-Off cue, stop clears guidance");$finish;
end
initial begin #1000000;$fatal(1,"Cue watchdog");end
endmodule
