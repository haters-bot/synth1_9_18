`include "params.vh"
// Reconcile the authoritative live UI bank with the last FIFO-accepted values.
// This also replaces lossy single-cycle CC requests in the production top.
// Intermediate edits may coalesce under congestion; the newest value is retained.
module static_cc_sync #(parameter COUNT=74,parameter PRESET_ENABLE=0)(
    input wire clk,rst_n,
    input wire preset_hold,preset_adopt,
    input wire [COUNT*7-1:0] values,
    input wire cc_accept,uart_busy,
    output reg cc_req,
    output reg [7:0] cc_param_id,
    output reg [6:0] cc_val,
    output reg startup_sync_done
);
    `include "static_cc_slots.vh"
    reg [6:0] scan;
    reg [COUNT-1:0] initial_pending;
    reg [6:0] sent[0:COUNT-1];
    wire [6:0] selected_value,selected_sent;
    wire [COUNT-1:0] selected_pending;
    wire [COUNT-1:0] value_bits[0:6],sent_bits[0:6];
    genvar slot,bit_index;
    integer i;
    // Constant slices follow the proven sender workaround for Gowin's
    // variable indexed-read miscompile. Reductions avoid a priority mux.
    generate for(slot=0;slot<COUNT;slot=slot+1)begin: select_slot
        wire selected=scan==slot;
        assign selected_pending[slot]=selected && initial_pending[slot];
        for(bit_index=0;bit_index<7;bit_index=bit_index+1)begin: select_bit
            assign value_bits[bit_index][slot]=selected && values[slot*7+bit_index];
            assign sent_bits[bit_index][slot]=selected && sent[slot][bit_index];
        end
    end
    for(bit_index=0;bit_index<7;bit_index=bit_index+1)begin: reduce_bit
        assign selected_value[bit_index]=|value_bits[bit_index];
        assign selected_sent[bit_index]=|sent_bits[bit_index];
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scan<=0;initial_pending<={COUNT{1'b1}};startup_sync_done<=0;
            cc_req<=0;cc_param_id<=0;cc_val<=0;
            for(i=0;i<COUNT;i=i+1) sent[i]<=0;
        end else if(PRESET_ENABLE && preset_adopt)begin
            for(i=0;i<COUNT;i=i+1)sent[i]<=values[i*7+:7];
            initial_pending<=0;startup_sync_done<=1;cc_req<=0;scan<=0;
        end else if(PRESET_ENABLE && preset_hold)begin
            cc_req<=0;
        end else begin
            // Acceptance denotes the exact FIFO write, never merely TX idle.
            if(cc_req && cc_accept) begin
                sent[scan]<=cc_val;initial_pending[scan]<=0;
                cc_req<=0;
                scan<=scan==COUNT-1 ? 0 : scan+1'b1;
            end else if(cc_req)begin
                // Under backpressure replace the staged value with the latest
                // bank value. Acceptance records the OLD staged payload, exactly
                // the word written to UART that edge; a simultaneous later edit
                // remains different from sent[] and is reconciled on the next lap.
                cc_val<=selected_value;
            end else begin
                // Cut scan/value selection from MIDI ID decode/FIFO/arbitration.
                cc_param_id<=static_cc_id(scan);cc_val<=selected_value;
                cc_req<=(|selected_pending) || selected_value!=selected_sent;
                if(!((|selected_pending) || selected_value!=selected_sent))
                    scan<=scan==COUNT-1 ? 0 : scan+1'b1;
            end
            // Sticky completion means initial values have actually left UART.
            // LFO starts afterwards; further real edits retain Note > CC > SysEx.
            if(initial_pending==0 && !uart_busy && !cc_req) startup_sync_done<=1;
        end
    end
endmodule
