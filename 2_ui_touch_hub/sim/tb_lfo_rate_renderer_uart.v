`timescale 1ns/1ps
// Named to use the isolated RTL/.vo runner. All edits are real touch packets.
module tb_lfo_rate_renderer_uart;
 reg clk=0,rst_n=0,touch_valid=0,touch_down=0;
 reg [15:0] raw_x=0,raw_y=0;
 wire uart_tx,sysex_req,config_busy,uart_busy;wire [47:0] sysex_msgs;
 wire [1:0] active_tab;wire [2:0] rate_index,all_steps,all_once;wire [8:0] all_rates;
 reg tv=0,td=0,push=0,note_on=1,start=0,stop=0,pause=0,tick=0;
 reg [31:0] time_ms=0;reg [13:0] x=0,y=0;
 wire [105:0] sources;wire [423:0] depths;wire [146:0] nodes;wire [8:0] rates;wire [2:0] steps,once;
 wire req,accept,uart,busy;wire [47:0] msgs;
 wire performance_local_mode_valid;wire [1:0] performance_local_mode;reg cc_req=0,note_req=0;
ui_top_renderer #(.PERFORMANCE_BASE_NOTE(7'd29),.PERFORMANCE_MAX_EVENTS(16),.BIND_WATCHDOG_CYCLES(1000)) dut(.clk(clk),.rst_n(rst_n),.in_hsync('0),.in_vsync('0),.in_den('0),.in_pixel_x('0),.in_pixel_y('0),.val_macro1('0),.val_macro2('0),.val_macro3('0),.val_macro4('0),.val_master_vol('0),.val_osca_unison('0),.val_osca_detune('0),.val_osca_blend('0),.val_osca_phase('0),.val_osca_rand('0),.val_osca_wt_pos('0),.val_osca_warp('0),.val_osca_pan('0),.val_osca_vol('0),.val_oscb_unison('0),.val_oscb_detune('0),.val_oscb_blend('0),.val_oscb_phase('0),.val_oscb_rand('0),.val_oscb_wt_pos('0),.val_oscb_warp('0),.val_oscb_pan('0),.val_oscb_vol('0),.val_flt_cutoff('0),.val_flt_res('0),.val_flt_pan('0),.val_flt_drive('0),.val_flt_fat('0),.val_flt_mix('0),.val_env_attack('0),.val_env_hold('0),.val_env_decay('0),.val_env_sustain('0),.val_env_release('0),.val_fx_reverb('0),.val_fx_delay('0),.val_fx_chorus('0),.val_portamento('0),.val_osca_power('0),.val_oscb_power('0),.val_flt_power('0),.val_osca_wave('0),.val_oscb_wave('0),.val_osca_oct('0),.val_osca_semi('0),.val_osca_fine('0),.val_oscb_oct('0),.val_oscb_semi('0),.val_oscb_fine('0),.val_flt_type('0),.val_flt_route_a('0),.val_flt_route_b('0),.val_flt_route_n('0),.val_flt_route_s('0),.val_flt_keytrack('0),.val_env_tab('0),.val_slot_bypass('0),.active_btn_id('0),.btn_flash_active('0),.selected_param_id('0),.usb_connected('0),.usb_conn_err('0),.usb_dev_type('0),.usb_raw_x('0),.usb_raw_y('0),.usb_raw_down('0),.usb_dbg_report('0),.usb_dbg_regs('0),.usb_dbg_pkt_cnt('0),.touch_diag_coords('0),.touch_diag_count('0),.touch_diag_mode('0),.ui_touch_valid(tv),.ui_touch_down(td),.ui_touch_x(x),.ui_touch_y(y),.audio_sample_valid('0),.audio_xy_a('0),.audio_xy_b('0),.audio_xy_valid('0),.audio_xy_available('0),.audio_sample('0),.audio_right_sample('0),.audio_stereo_valid('0),.audio_link_up('0),.external_param_valid('0),.external_param_id('0),.external_param_value('0),.performance_tick_1ms(tick),.performance_clear_events('0),.performance_event_push(push),.performance_event_time_ms(time_ms),.performance_event_note(7'd29),.performance_event_velocity(7'd100),.performance_event_on(note_on),.performance_start(start),.performance_stop(stop),.performance_pause(pause),.performance_mode(2'd2),.performance_local_mode_valid(performance_local_mode_valid),.performance_local_mode(performance_local_mode),.performance_duration_ms(32'd1500),.performance_gateway_up_in('0),.performance_recording_in('0),.performance_note_ready('0),.performance_record_status_in('0),.performance_remote_note_valid('0),.performance_remote_note_on('0),.performance_remote_note('0),.performance_remote_velocity('0),.performance_physical_note_valid(1'b0),.route_source_snapshot(sources),.route_depth_snapshot(depths),.lfo_node_snapshot(nodes),.lfo_rate_snapshot(rates),.lfo_step_snapshot(steps),.lfo_once_snapshot(once));
lfo_sysex_tx #(.HOLD_CYCLES(20),.FIRST_HOLD_CYCLES(20)) sx(.clk(clk),.rst_n(rst_n),.cfg_nodes(nodes),.cfg_rates(rates),.cfg_steps(steps),.cfg_once(once),.cfg_sources(sources),.cfg_depths(depths),.tx_accept(accept),.sysex_req(req),.sysex_msgs(msgs),.busy());
midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(25000000)) tx(.clk(clk),.rst_n(rst_n),.note_on_req(note_req),.note_off_req(1'b0),.note_number(7'd29),.note_velocity(7'd100),.cc_req(cc_req),.cc_param_id(8'h05),.cc_val(7'd99),.sysex_req(req),.sysex_msgs(msgs),.sysex_accept(accept),.uart_tx(uart),.tx_busy(busy),.note_ready());
 assign uart_tx=uart;assign sysex_req=req;assign config_busy=sx.busy;assign uart_busy=busy;
 assign active_tab=dut.lfo_tab;assign all_rates=rates;assign all_steps=steps;assign all_once=once;
 assign rate_index=rates[active_tab*3+:3];
 always #10 clk=~clk;
 reg [7:0] sb;reg [47:0] frame=0;
 reg [47:0] last_mode[0:2],last_sync=0;
 integer i,bytes=0,commits=0,frames=0,b,c,k,target,before_commit,z,checks=0;
 reg [7:0] expected_value;reg [47:0] expected_frame;
 reg [47:0] previous_frame=0,previous_previous_frame=0;
 reg [47:0] committed_mode=0,committed_sync=0;
 integer byte_log;
 initial byte_log=$fopen("lfo_uart_frames.hex","w");
 function [63:0] hz(input integer index);
  case(index)
   0:hz="0.25";1:hz="0.5";2:hz="1";3:hz="2";
   4:hz="4";5:hz="8";6:hz="16";7:hz="32";
  endcase
 endfunction
 initial forever begin
  @(negedge uart_tx);#20;
  for(i=0;i<8;i=i+1)begin #40;sb[i]=uart_tx;end
  #40;if(uart_tx!==1)$fatal(1,"UART stop");
  frame={frame[39:0],sb};bytes=bytes+1;
  if(bytes==6)begin
   bytes=0;frames=frames+1;
   $fdisplay(byte_log,"%012h",frame);
   if(frame[47:32]!==16'hF07D || frame[7:0]!==8'hF7)$fatal(1,"frame %h",frame);
   if(frame[31:24]>=69 && frame[31:24]<=71)begin
    last_mode[frame[31:24]-69]=frame;
    $display("UART: mode bytes=%h live_rates=%h",frame,all_rates);
`ifdef GATE_PROBE
    $display("CHECK: q_rates=%h sh_rates=%h",dut.\sx/q_rates ,dut.\sx/sh_rates );
`endif
   end
   if(frame[31:24]==72)last_sync=frame;
   if(frame==48'hF07D7E0000F7)begin
    commits=commits+1;committed_mode=previous_previous_frame;committed_sync=previous_frame;
   end
   previous_previous_frame=previous_frame;previous_frame=frame;
  end
 end
 task packet(input integer px,py,input bit down);
  begin
   @(negedge clk);x=px;y=py;
   td=down;tv=1;
   @(negedge clk);tv=0;repeat(10)@(negedge clk);
  end
 endtask
 task click(input integer px,py);begin packet(px,py,1);packet(0,0,0);end endtask
 task drain;
  integer wait_cycles;
  begin
   repeat(200)@(negedge clk);wait_cycles=0;
   while((config_busy || uart_busy || sysex_req) && wait_cycles<60000)begin
    @(negedge clk);wait_cycles=wait_cycles+1;
   end
   if(config_busy || uart_busy || sysex_req)$fatal(1,"transport did not drain");
   repeat(20)@(negedge clk);
  end
 endtask
 initial begin
  #1000;repeat(8)@(negedge clk);rst_n=1;
  wait(commits==1);drain;
  if(all_rates!==9'b010010010)$fatal(1,"boot editor rates");
  if(last_mode[0]!==48'hF07D450002F7)$fatal(1,"boot mode: live index2 sent %h",last_mode[0]);
  for(b=0;b<3;b=b+1)begin
   click(b==0 ? 850 : b==1 ? 930 : 1015,385);drain;
   // Four Stepped/Once combinations, each with a complete 8-step UI cycle.
   for(c=0;c<4;c=c+1)begin
    if(all_steps[b]!==c[0])begin click(c[0]?1140:860,575);drain;end
    if(all_once[b]!==c[1])begin click(1000,620);drain;end
    for(k=0;k<8;k=k+1)begin
     target=(k+3)%8; // First check is exactly the user's 2-Hz case.
     z=0;
     while(rate_index!=target && z<8)begin click(860,620);drain;z=z+1;end
     if(rate_index!==target[2:0])$fatal(1,"UI cannot reach bank%0d rate_index%0d",b,target);
     // Unchanged state still must match its last committed frame.
     expected_value=target | (c[0]?8:0) | (c[1]?16:0);
     expected_frame={16'hF07D,8'h45+b[7:0],8'h00,expected_value,8'hF7};
     $display("CHECK: LFO%0d UI=%0sHz rate_index=%0d stepped=%0d once=%0d mode_value=%0d bytes=%h",b+1,hz(target),rate_index,c[0],c[1],expected_value,last_mode[b]);
     if(all_rates[b*3+:3]!==target[2:0] || last_mode[b]!==expected_frame)
      $fatal(1,"mode encoding mismatch expected %h",expected_frame);
     if(last_sync!=={24'hF07D48,8'h00,8'd4+b[7:0],8'hF7})$fatal(1,"restart bank mismatch %h",last_sync);
     if(committed_mode!==expected_frame || committed_sync!==last_sync)
      $fatal(1,"batch must end with mode -> correct restart -> Commit");
     checks=checks+1;
    end
   end
  end
  if(checks!=96)$fatal(1,"incomplete mode coverage");
  $display("PASS: 96 full-renderer touch/editor/snapshot/serial rate/mode combinations, three banks, restart and Commit; frames=%0d",frames);$finish;
 end
 initial begin #30000000;$fatal(1,"rate test timeout");end
endmodule
