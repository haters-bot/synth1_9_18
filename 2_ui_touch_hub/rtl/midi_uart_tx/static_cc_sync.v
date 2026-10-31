`include "params.vh"
// Reconcile the authoritative live UI bank with the last FIFO-accepted values.
// This also replaces lossy single-cycle CC requests in the production top.
// Intermediate edits may coalesce under congestion; the newest value is retained.
module static_cc_sync(
    input wire clk,rst_n,
    input wire [279:0] values,
    input wire cc_accept,uart_busy,
    output wire cc_req,
    output wire [7:0] cc_param_id,
    output wire [6:0] cc_val,
    output reg startup_sync_done
);
    `include "static_cc_slots.vh"
    reg [5:0] scan;
    reg [39:0] initial_pending;
    reg [6:0] sent[0:39];
    reg [6:0] selected_value;
    integer slot;
    integer i;
    assign cc_param_id=static_cc_id(scan);
    // Constant slices follow the proven sender workaround for Gowin's
    // variable indexed-read miscompile. Keep the existing slot order.
    always @(*) begin
        selected_value=0;
        for(slot=0;slot<STATIC_CC_COUNT;slot=slot+1)
            if(scan==slot) selected_value=values[slot*7+:7];
    end
    assign cc_val=selected_value;
    assign cc_req=rst_n && (initial_pending[scan] || cc_val!=sent[scan]);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scan<=0;initial_pending<={40{1'b1}};startup_sync_done<=0;
            for(i=0;i<40;i=i+1) sent[i]<=0;
        end else begin
            // Acceptance denotes the exact FIFO write, never merely TX idle.
            if(cc_accept) begin
                sent[scan]<=cc_val;initial_pending[scan]<=0;
            end
            if(!cc_req || cc_accept) scan<=scan==STATIC_CC_COUNT-1 ? 0 : scan+1'b1;
            // Sticky completion means initial values have actually left UART.
            // LFO starts afterwards; further real edits retain Note > CC > SysEx.
            if(initial_pending==0 && !uart_busy && !cc_req) startup_sync_done<=1;
        end
    end
endmodule
