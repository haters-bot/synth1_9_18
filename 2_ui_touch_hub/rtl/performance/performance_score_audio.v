// Preserve score order under UART backpressure and release audition notes
// on Stop/Pause/restart/mode change, after any already-queued Note Ons.
// Physical keyboard input is monitoring only; it already reaches audio E19.
module performance_score_audio #(
    parameter integer BASE_NOTE=29,KEY_COUNT=32
)(
    input wire clk,rst_n,clear,
    input wire in_valid,in_on,
    input wire [6:0] in_note,in_velocity,
    output wire in_ready,
    output wire out_valid,out_on,
    output wire [6:0] out_note,out_velocity,
    input wire out_ready
);
    localparam integer BITS=$clog2(KEY_COUNT);
    reg [KEY_COUNT-1:0] active;
    reg cleaning;
    reg [BITS-1:0] scan;
    wire in_range=in_note>=BASE_NOTE && in_note<BASE_NOTE+KEY_COUNT;
    assign in_ready=out_ready && !cleaning && !clear;
    assign out_valid=!clear && (cleaning ? active[scan] : in_valid && in_range);
    assign out_on=!cleaning && in_on;
    assign out_note=cleaning ? BASE_NOTE+scan : in_note;
    assign out_velocity=cleaning ? 7'd0 : in_velocity;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin active<=0;cleaning<=0;scan<=0;end
        else if(clear)begin cleaning<=1;scan<=0;end
        else if(cleaning)begin
            if(!active[scan] || out_ready)begin
                active[scan]<=0;
                if(scan==KEY_COUNT-1)begin cleaning<=0;scan<=0;end
                else scan<=scan+1'b1;
            end
        end else if(in_valid && in_ready && in_range)active[in_note-BASE_NOTE]<=in_on;
    end
endmodule
