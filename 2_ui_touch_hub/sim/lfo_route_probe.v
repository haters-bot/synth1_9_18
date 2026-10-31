// SIMULATION-ONLY probe. Auto-assigned pins, short UI timers, 5-Mbaud UART.
// NEVER program the bitstream generated for this top onto a board.
module lfo_route_probe(
 input wire clk,rst_n,touch_valid,touch_down,
 input wire [15:0] raw_x,raw_y,
 input wire [1:0] active_tab,
 input wire [6:0] point3,
 output wire uart_tx,sysex_req,
 output wire [47:0] sysex_msgs,
 output wire [1:0] source6,source13,
 output wire [7:0] depth6,depth13,
 output wire binding_armed,binding_dragging
);
 wire tv,td,capture,accept;
 wire [13:0] x,y;
 wire [105:0] sources;
 wire [423:0] depths;
 wire [146:0] nodes={119'd0,point3,21'd0};
 touch_event_router router(.clk(clk),.rst_n(rst_n),.touch_valid(touch_valid),
  .raw_touch_x(raw_x),.raw_touch_y(raw_y),.touch_state(touch_down),
  .curve_capture_active(capture),.curve_focus_valid(1'b0),.curve_focus_id(8'd0),
  .ui_touch_valid(tv),.ui_touch_down(td),.ui_touch_x(x),.ui_touch_y(y));
 lfo_binding_state #(.WATCHDOG_CYCLES(1000),.ENABLE_CANCEL(1)) binding(
  .clk(clk),.rst_n(rst_n),.touch_valid(tv),.touch_down(td),.touch_x(x),.touch_y(y),
  .cancel(1'b0),.active_tab(active_tab),.armed(binding_armed),.dragging(binding_dragging),
  .capture_active(capture),.sources(sources),.depths(depths));
 lfo_sysex_tx #(.HOLD_CYCLES(20),.FIRST_HOLD_CYCLES(20)) sx(
  .clk(clk),.rst_n(rst_n),.cfg_nodes(nodes),.cfg_rates(9'd0),.cfg_steps(3'd0),
  .cfg_once(3'd0),.cfg_sources(sources),.cfg_depths(depths),.tx_accept(accept),
  .sysex_req(sysex_req),.sysex_msgs(sysex_msgs));
 midi_uart_tx #(.CLK_FREQ(50000000),.BAUD(5000000)) tx(
  .clk(clk),.rst_n(rst_n),.note_on_req(1'b0),.note_off_req(1'b0),.note_number(7'd0),
  .note_velocity(7'd0),.cc_req(1'b0),.cc_param_id(8'd0),.cc_val(7'd0),
  .sysex_req(sysex_req),.sysex_msgs(sysex_msgs),.sysex_accept(accept),.uart_tx(uart_tx));
 assign source6=sources[13:12];assign depth6=depths[55:48];
 assign source13=sources[27:26];assign depth13=depths[111:104];
endmodule
