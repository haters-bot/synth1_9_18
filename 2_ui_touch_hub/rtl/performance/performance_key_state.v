// Maps scheduled MIDI events and local piano touches to key/guide masks.
module performance_key_state #(
    parameter integer KEY_COUNT = 32,
    parameter integer BASE_NOTE = 60
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    event_valid,
    input  wire                    event_on,
    input  wire [6:0]              event_note,
    input  wire                    clear_scheduled,
    input  wire                    manual_valid,
    input  wire                    manual_down,
    input  wire [$clog2(KEY_COUNT)-1:0] manual_key,
    input  wire                    remote_valid,
    input  wire                    remote_down,
    input  wire [$clog2(KEY_COUNT)-1:0] remote_key,
    output wire [KEY_COUNT-1:0]    active_keys,
    output wire [KEY_COUNT-1:0]    guide_keys
);
    localparam integer KEY_BITS = (KEY_COUNT <= 2) ? 1 : $clog2(KEY_COUNT);
    reg [KEY_COUNT-1:0] scheduled_active;
    reg [KEY_COUNT-1:0] manual_active;
    reg [KEY_COUNT-1:0] remote_active;

    function integer note_index;
        input [6:0] note;
        integer index;
        begin
            index = note - BASE_NOTE;
            if ((note >= BASE_NOTE) && (index < KEY_COUNT))
                note_index = index;
            else
                note_index = -1;
        end
    endfunction

    integer event_index;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scheduled_active <= {KEY_COUNT{1'b0}};
            manual_active    <= {KEY_COUNT{1'b0}};
            remote_active    <= {KEY_COUNT{1'b0}};
        end else begin
            if (clear_scheduled) begin
                scheduled_active <= {KEY_COUNT{1'b0}};
            end else if (event_valid) begin
                event_index = note_index(event_note);
                if (event_index >= 0) begin
                    if (event_on)
                        scheduled_active[event_index] <= 1'b1;
                    else
                        scheduled_active[event_index] <= 1'b0;
                end
            end
            if (manual_valid && (manual_key < KEY_COUNT)) begin
                if (manual_down)
                    manual_active[manual_key] <= 1'b1;
                else
                    manual_active[manual_key] <= 1'b0;
            end
            if(remote_valid && remote_key<KEY_COUNT)remote_active[remote_key]<=remote_down;
        end
    end

    assign active_keys = scheduled_active | manual_active | remote_active;
    assign guide_keys  = scheduled_active;
endmodule
