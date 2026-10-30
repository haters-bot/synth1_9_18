// Converts validated V1 transport packets into scheduler/control pulses.
// All outputs are synchronous to the UI pixel clock.
module performance_command_decoder #(
    parameter integer MAX_PAYLOAD = 64,
    parameter integer GATEWAY_TIMEOUT_MS = 2000,
    parameter integer MAX_EVENTS = 16384
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    tick_1ms,
    input  wire                    packet_valid,
    input  wire [7:0]              packet_type,
    input  wire [6:0]              packet_length,
    input  wire [MAX_PAYLOAD*8-1:0] packet_payload,
    input  wire                    local_play,
    input  wire                    local_pause_toggle,
    input  wire                    local_stop,
    input  wire                    local_record_toggle,
    input  wire                    local_mode_valid,
    input  wire [1:0]              local_mode,
    input  wire                    record_start_accepted,
    input  wire                    record_start_rejected,
    input  wire                    record_active,
    input  wire                    record_busy,
    input  wire                    record_done,
    output reg                     clear_events,
    output reg                     event_push,
    output reg [31:0]              event_time_ms,
    output reg [6:0]               event_note,
    output reg [6:0]               event_velocity,
    output reg                     event_on,
    output reg                     start_pulse,
    output reg                     stop_pulse,
    output reg                     record_start_pulse,
    output reg                     record_stop_pulse,
    output reg                     pause_state,
    output reg                     manual_valid,
    output reg                     manual_on,
    output reg [6:0]               manual_note,
    output reg [6:0]               manual_velocity,
    output reg [31:0]              song_duration_ms,
    output reg                     song_loaded,
    output reg                     gateway_up,
    output reg                     recording,
    output reg [1:0]               performance_mode,
    output reg                     protocol_error
);
    localparam [7:0] TYPE_HELLO        = 8'h01;
    localparam [7:0] TYPE_SONG_CLEAR   = 8'h10;
    localparam [7:0] TYPE_SONG_BEGIN   = 8'h11;
    localparam [7:0] TYPE_EVENT_BATCH  = 8'h12;
    localparam [7:0] TYPE_SONG_END     = 8'h13;
    localparam [7:0] TYPE_PLAY         = 8'h20;
    localparam [7:0] TYPE_PAUSE        = 8'h21;
    localparam [7:0] TYPE_STOP         = 8'h22;
    localparam [7:0] TYPE_MANUAL_NOTE  = 8'h30;
    localparam [7:0] TYPE_RECORD_START = 8'h40;
    localparam [7:0] TYPE_RECORD_STOP  = 8'h41;
    localparam [7:0] TYPE_MODE         = 8'h23;

    reg [MAX_PAYLOAD*8-1:0] batch_payload;
    reg [3:0] batch_index;
    reg [3:0] batch_count;
    reg batch_active;
    reg [31:0] gateway_idle_ms;
    reg record_was_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_events      <= 1'b0;
            event_push        <= 1'b0;
            event_time_ms     <= 32'd0;
            event_note        <= 7'd0;
            event_velocity    <= 7'd0;
            event_on          <= 1'b0;
            start_pulse       <= 1'b0;
            stop_pulse        <= 1'b0;
            record_start_pulse<= 1'b0;
            record_stop_pulse <= 1'b0;
            pause_state       <= 1'b0;
            manual_valid      <= 1'b0;
            manual_on         <= 1'b0;
            manual_note       <= 7'd0;
            manual_velocity   <= 7'd0;
            song_duration_ms  <= 32'd0;
            song_loaded       <= 1'b0;
            gateway_up        <= 1'b0;
            recording         <= 1'b0;
            performance_mode  <= 2'd2;
            protocol_error    <= 1'b0;
            batch_payload     <= {(MAX_PAYLOAD*8){1'b0}};
            batch_index       <= 4'd0;
            batch_count       <= 4'd0;
            batch_active      <= 1'b0;
            gateway_idle_ms   <= 32'd0;
            record_was_active <= 1'b0;
        end else begin
            clear_events   <= 1'b0;
            event_push     <= 1'b0;
            start_pulse    <= 1'b0;
            stop_pulse     <= 1'b0;
            record_start_pulse <= 1'b0;
            record_stop_pulse <= 1'b0;
            manual_valid   <= 1'b0;
            protocol_error <= 1'b0;
            record_was_active <= record_active;

            // This is a request latch, not proof that PCM is being recorded.
            // Backend acknowledgement and automatic termination release it so
            // the next tap can start again after a rejected/full/lost-input run.
            if (record_start_accepted) recording <= 1'b1;
            if (record_start_rejected || record_done ||
                (record_was_active && !record_active)) recording <= 1'b0;

            if (tick_1ms && gateway_up) begin
                if (gateway_idle_ms < GATEWAY_TIMEOUT_MS)
                    gateway_idle_ms <= gateway_idle_ms + 1'b1;
                else
                    gateway_up <= 1'b0;
            end

            // Emit one scheduler record per UI clock. The UART frame rate is
            // far slower than this, so a packet is drained before another
            // normal-sized batch can arrive.
            if (batch_active) begin
                event_time_ms  <= batch_payload[batch_index*64 +: 32];
                event_note     <= batch_payload[batch_index*64 + 32 +: 7];
                event_velocity <= batch_payload[batch_index*64 + 40 +: 7];
                event_on       <= batch_payload[batch_index*64 + 48] &&
                                  (batch_payload[batch_index*64 + 40 +: 7] != 0);
                event_push     <= (batch_payload[batch_index*64 + 32 +: 8] >= 8'd21) &&
                                  (batch_payload[batch_index*64 + 32 +: 8] <= 8'd108);
                if (batch_index + 1'b1 >= batch_count) begin
                    batch_active <= 1'b0;
                end else begin
                    batch_index <= batch_index + 1'b1;
                end
            end

            if (packet_valid) begin
                gateway_up      <= 1'b1;
                gateway_idle_ms <= 32'd0;
                case (packet_type)
                    TYPE_HELLO: begin end
                    TYPE_SONG_CLEAR: begin
                        if (packet_length == 0) begin
                            clear_events <= 1'b1;
                            song_loaded  <= 1'b0;
                        end else protocol_error <= 1'b1;
                    end
                    TYPE_SONG_BEGIN: begin
                        if (packet_length == 6 && packet_payload[47:32] <= MAX_EVENTS && packet_payload[47:32] != 0) begin
                            song_duration_ms <= packet_payload[31:0];
                            song_loaded      <= 1'b0;
                        end else protocol_error <= 1'b1;
                    end
                    TYPE_EVENT_BATCH: begin
                        if ((packet_length != 0) && (packet_length[2:0] == 0) &&
                            (packet_length <= MAX_PAYLOAD)) begin
                            batch_payload <= packet_payload;
                            batch_index   <= 4'd0;
                            batch_count   <= packet_length >> 3;
                            batch_active  <= 1'b1;
                        end else protocol_error <= 1'b1;
                    end
                    TYPE_SONG_END: begin
                        if (packet_length == 0)
                            song_loaded <= 1'b1;
                        else protocol_error <= 1'b1;
                    end
                    TYPE_PLAY: begin
                        if (packet_length == 0) begin
                            pause_state <= 1'b0;
                            start_pulse <= 1'b1;
                        end else protocol_error <= 1'b1;
                    end
                    TYPE_PAUSE: begin
                        if (packet_length == 0) pause_state <= 1'b1;
                        else protocol_error <= 1'b1;
                    end
                    TYPE_STOP: begin
                        if (packet_length == 0) begin
                            pause_state <= 1'b0;
                            stop_pulse  <= 1'b1;
                        end else protocol_error <= 1'b1;
                    end
                    TYPE_MODE: begin
                        if (packet_length == 1 && packet_payload[1:0] <= 2'd2) begin
                            performance_mode <= packet_payload[1:0];
                            pause_state <= 1'b0;
                            stop_pulse <= 1'b1;
                        end else protocol_error <= 1'b1;
                    end
                    TYPE_MANUAL_NOTE: begin
                        if (packet_length >= 3) begin
                            manual_note     <= packet_payload[6:0];
                            manual_velocity <= packet_payload[14:8];
                            manual_on       <= packet_payload[16];
                            manual_valid    <= 1'b1;
                        end else protocol_error <= 1'b1;
                    end
                    TYPE_RECORD_START: begin
                        if (packet_length == 0) begin recording <= 1'b1; record_start_pulse <= 1'b1; end
                        else protocol_error <= 1'b1;
                    end
                    TYPE_RECORD_STOP: begin
                        if (packet_length == 0) begin recording <= 1'b0; record_stop_pulse <= 1'b1; end
                        else protocol_error <= 1'b1;
                    end
                    default: protocol_error <= 1'b1;
                endcase
            end

            // Local touchscreen transport shares the same scheduler state as
            // the reserved phone protocol. Local actions win a same-cycle
            // collision so a deliberate on-screen command is deterministic.
            if (local_play) begin
                pause_state <= 1'b0;
                start_pulse <= 1'b1;
            end else if (local_pause_toggle) begin
                pause_state <= !pause_state;
            end else if (local_stop) begin
                pause_state <= 1'b0;
                stop_pulse <= 1'b1;
            end else if (local_record_toggle) begin
                if (recording || record_active) begin
                    recording <= 1'b0;
                    record_stop_pulse <= 1'b1;
                end else if (!record_busy) begin
                    recording <= 1'b1;
                    record_start_pulse <= 1'b1;
                end else protocol_error <= 1'b1;
            end
            if(local_mode_valid && local_mode<=2'd2) begin
                performance_mode<=local_mode;
                pause_state<=1'b0;stop_pulse<=1'b1;
            end
        end
    end
endmodule
