// Simulation-only alternative to lfo_route_probe, selected by --rates.
// Auto-assigned pins/accelerated timers/UART: NEVER DEPLOY its bitstream.
module lfo_route_probe(
 input wire clk,rst_n,touch_valid,touch_down,
 input wire [15:0] raw_x,raw_y,
 output wire uart_tx,sysex_req,config_busy,uart_busy,
 output wire [47:0] sysex_msgs,
 output wire [1:0] active_tab,
 output wire [2:0] rate_index,
 output wire [8:0] all_rates,
 output wire [2:0] all_steps,all_once
);
 wire tv,td,accept;wire [13:0] x,y;wire [146:0] nodes;
 touch_event_router router(.clk(clk),.rst_n(rst_n),.touch_valid(touch_valid),
  .raw_touch_x(raw_x),.raw_touch_y(raw_y),.touch_state(touch_down),
  .curve_capture_active(1'b0),.curve_focus_valid(1'b0),.curve_focus_id(8'd0),
  .ui_touch_valid(tv),.ui_touch_down(td),.ui_touch_x(x),.ui_touch_y(y));
 lfo_editor_state #(.WATCHDOG_CYCLES(1000)) editor(.clk(clk),.rst_n(rst_n),
  .touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),
  .active_tab(active_tab),.rate(rate_index),.all_nodes(nodes),
  .all_rates(all_rates),.all_stepped(all_steps),.all_once(all_once));
 lfo_sysex_tx #(.HOLD_CYCLES(100),.FIRST_HOLD_CYCLES(100)) sx(
  .clk(clk),.rst_n(rst_n),.cfg_nodes(nodes),.cfg_rates(all_rates),
  .cfg_steps(all_steps),.cfg_once(all_once),.cfg_sources(106'd0),
  .cfg_depths({53{8'h7F}}),.tx_accept(accept),
  .sysex_req(sysex_req),.sysex_msgs(sysex_msgs),.busy(config_busy));
 midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(5000000)) tx(
  .clk(clk),.rst_n(rst_n),.note_on_req(1'b0),.note_off_req(1'b0),
  .note_number(7'd0),.note_velocity(7'd0),.cc_req(1'b0),.cc_param_id(8'd0),.cc_val(7'd0),
  .sysex_req(sysex_req),.sysex_msgs(sysex_msgs),.sysex_accept(accept),.uart_tx(uart_tx),.tx_busy(uart_busy));
endmodule
