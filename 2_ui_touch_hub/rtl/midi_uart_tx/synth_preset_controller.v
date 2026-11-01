`include "params.vh"
// Finite, backpressured batch producer. Uses the existing Note-priority UART.
// A second selection is coalesced into ONE pending complete transaction. It
// never interrupts/interleaves the current transaction or queues stale banks.
module synth_preset_controller(
 input wire clk,rst_n,apply_req,
 input wire [3:0] apply_index,
 input wire uart_busy,cc_accept,sysex_accept,
 input wire [146:0] lfo_nodes,
 input wire [8:0] lfo_rates,
 input wire [2:0] lfo_steps,lfo_once,
 output wire busy,load_bank,adopt_bank,
 output wire [517:0] bank_values,
 output reg [3:0] active_index,
 output reg applied_valid,
 output reg pending,
 output reg [3:0] pending_index,
 output wire cc_req,
 output reg [7:0] cc_id,
 output reg [6:0] cc_value,
 output wire sysex_req,
 output reg [47:0] sysex_msgs,
 output reg invalid_request
);
 `include "synth_presets.vh"
 `include "static_cc_slots.vh"
 localparam IDLE=0,DRAIN=1,LOAD=2,SETTLE=3,CC_SELECT=4,CC_STAGE=5,
            CC_SEND=6,CC_DRAIN=7,SX_SELECT=8,SX_STAGE=9,SX_SEND=10,
            SX_DRAIN=11,FINISH=12,CC_ADVANCE=13,SX_ADVANCE=14;
 reg [3:0] state;
 reg [6:0] message_index,slot,sx_index;
 reg [146:0] saved_nodes;
 reg [8:0] saved_rates;
 reg [2:0] saved_steps,saved_once;
 assign busy=state!=IDLE;
 assign load_bank=state==LOAD;
 assign adopt_bank=state==FINISH;
 assign bank_values=synth_preset_bank(active_index);
 // One bulk message at a time leaves the FIFO free for performance Notes.
 // Wait for idle BEFORE presenting a request. The held request itself must
 // not include the UART busy/FIFO decode in the same-cycle acceptance loop.
 assign cc_req=state==CC_SEND;
 assign sysex_req=state==SX_SEND;
 wire [73:0] value_bits[0:6];
 wire [6:0] selected_value;
 genvar s,b;
 generate for(s=0;s<74;s=s+1)begin:select_slot
  for(b=0;b<7;b=b+1)begin:select_bit
   assign value_bits[b][s]=(slot==s) && bank_values[s*7+b];
  end
 end
 for(b=0;b<7;b=b+1)begin:reduce_value
  assign selected_value[b]=|value_bits[b];
 end endgenerate
 reg [7:0] sx_id;
 reg [13:0] sx_value;
 integer n;
 always @* begin
  sx_id=0;sx_value=0;
  // Python configuration_fields order: each bank's 7 points then mode,
  // all routes, restarts,
  // then Commit. All source/depth pairs are explicitly unbound (zero).
  for(n=0;n<21;n=n+1)begin
   sx_id=sx_id|({8{sx_index==n+n/7}}&(8'd48+n));
   sx_value=sx_value|({14{sx_index==n+n/7}}&{7'd0,saved_nodes[n*7+:7]});
  end
  for(n=0;n<3;n=n+1)begin
   sx_id=sx_id|({8{sx_index==7+n*8}}&(8'd69+n));
   sx_value=sx_value|({14{sx_index==7+n*8}}&{9'd0,saved_once[n],saved_steps[n],saved_rates[n*3+:3]});
   sx_id=sx_id|({8{sx_index==77+n}}&8'd72);
   sx_value=sx_value|({14{sx_index==77+n}}&(14'd4+n));
  end
  for(n=0;n<53;n=n+1)sx_id=sx_id|({8{sx_index==24+n}}&(8'd73+n));
  if(sx_index==80)sx_id=126;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;active_index<=0;applied_valid<=0;pending<=0;pending_index<=0;
   message_index<=0;slot<=0;sx_index<=0;cc_id<=0;cc_value<=0;sysex_msgs<=0;
   saved_nodes<=0;saved_rates<=0;saved_steps<=0;saved_once<=0;invalid_request<=0;
  end else begin
   invalid_request<=apply_req && apply_index>=12;
   if(apply_req && apply_index<12 && busy)begin pending<=1;pending_index<=apply_index;end
   case(state)
    IDLE:if(apply_req && apply_index<12)begin
     active_index<=apply_index;pending<=0;state<=DRAIN;
    end
    DRAIN:if(!uart_busy)state<=LOAD;
    LOAD:begin
     saved_nodes<=lfo_nodes;saved_rates<=lfo_rates;saved_steps<=lfo_steps;saved_once<=lfo_once;
     message_index<=0;sx_index<=0;state<=SETTLE;
    end
    SETTLE:state<=CC_SELECT;
    CC_SELECT:if(!uart_busy)begin slot<=synth_preset_send_slot(message_index);state<=CC_STAGE;end
    CC_STAGE:begin cc_id<=static_cc_id(slot);cc_value<=selected_value;state<=CC_SEND;end
    CC_SEND:if(cc_accept)state<=CC_ADVANCE;
    CC_ADVANCE:begin
     if(message_index==41 || message_index==73)state<=CC_DRAIN;
     else begin message_index<=message_index+1'b1;state<=CC_SELECT;end
    end
    CC_DRAIN:if(!uart_busy)begin
     if(message_index==41)begin message_index<=42;state<=SX_SELECT;end
     else state<=FINISH;
    end
    SX_SELECT:if(!uart_busy)state<=SX_STAGE;
    SX_STAGE:begin sysex_msgs<={8'hF0,8'h7D,sx_id,1'b0,sx_value[13:7],1'b0,sx_value[6:0],8'hF7};state<=SX_SEND;end
    SX_SEND:if(sysex_accept)state<=SX_ADVANCE;
    SX_ADVANCE:begin
     if(sx_index==80)state<=SX_DRAIN;
     else begin sx_index<=sx_index+1'b1;state<=SX_SELECT;end
    end
    SX_DRAIN:if(!uart_busy)state<=CC_SELECT;
    FINISH:begin
     applied_valid<=1;
     // Latest same-cycle request wins over the previous pending selection.
     if(apply_req && apply_index<12)begin active_index<=apply_index;pending<=0;state<=DRAIN;end
     else if(pending)begin active_index<=pending_index;pending<=0;state<=DRAIN;end
     else state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
