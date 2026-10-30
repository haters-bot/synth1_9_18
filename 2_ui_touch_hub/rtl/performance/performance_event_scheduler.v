// Deterministic millisecond event scheduler for the phone-performance path.
// Transport, MIDI parsing and audio synthesis remain separate modules.
module performance_event_scheduler #(
    parameter integer MAX_EVENTS = 4096
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick_1ms,
    input  wire        clear_events,
    input  wire        event_push,
    input  wire [31:0] event_time_ms,
    input  wire [6:0]  event_note,
    input  wire [6:0]  event_velocity,
    input  wire        event_on,
    input  wire        start,
    input  wire        stop,
    input  wire        pause,
    // In follow mode a correct physical key advances one score event while
    // the millisecond clock remains frozen.
    input  wire        follow_step,
    output reg         running,
    output reg         event_valid,
    output reg         event_on_out,
    output reg  [6:0]  event_note_out,
    output reg  [6:0]  event_velocity_out,
    output reg  [31:0] song_time_ms,
    output reg         done,
    output reg         load_error,
    output wire [6:0]  next_note,
    output wire [31:0] next_time_ms,
    output wire        next_on_valid,
    output wire [$clog2(MAX_EVENTS+1)-1:0] loaded_events
);
    localparam integer ADDR_BITS = (MAX_EVENTS <= 2) ? 1 : $clog2(MAX_EVENTS);
    localparam integer COUNT_BITS = $clog2(MAX_EVENTS + 1);

    // A single write port and a single synchronous read port match Gowin's
    // BSRAM template. Neither port nor the memory contents has a reset.
    // Resettable control is kept in the separate process below.
    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg [46:0] event_mem [0:MAX_EVENTS-1];
    reg [ADDR_BITS-1:0] write_ptr;
    reg [ADDR_BITS-1:0] read_ptr;
    reg [COUNT_BITS-1:0] event_count;
    reg [46:0] ram_record;
    reg [46:0] current_record;
    reg        current_record_valid;
    reg        fetch_wait;

    wire accept_event = rst_n && event_push && !running && !clear_events &&
                        !stop && !start && (event_count < MAX_EVENTS);
    wire [COUNT_BITS-1:0] consumed_events =
        {{(COUNT_BITS-ADDR_BITS){1'b0}},read_ptr} + 1'b1;

    always @(posedge clk) begin
        if (accept_event)
            event_mem[write_ptr] <= {event_time_ms,event_note,event_velocity,event_on};
        ram_record <= event_mem[read_ptr];
    end

    reg [6:0] next_note_reg;
    assign loaded_events = event_count;
    assign next_note = next_note_reg;
    assign next_time_ms = current_record[46:15];
    assign next_on_valid = running && current_record_valid && current_record[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running           <= 1'b0;
            event_valid       <= 1'b0;
            event_on_out      <= 1'b0;
            event_note_out    <= 7'd0;
            event_velocity_out<= 7'd0;
            song_time_ms      <= 32'd0;
            done              <= 1'b0;
            load_error        <= 1'b0;
            write_ptr         <= {ADDR_BITS{1'b0}};
            read_ptr          <= {ADDR_BITS{1'b0}};
            event_count       <= {COUNT_BITS{1'b0}};
            next_note_reg     <= 7'd0;
            current_record    <= 47'd0;
            current_record_valid <= 1'b0;
            fetch_wait        <= 1'b0;
        end else begin
            event_valid <= 1'b0;
            done        <= 1'b0;
            if(event_push && !accept_event && !clear_events)load_error<=1'b1;

            if (accept_event) begin
                write_ptr               <= write_ptr + 1'b1;
                event_count             <= event_count + 1'b1;
                if (event_count == 0)
                    next_note_reg <= event_note;
            end

            if (stop) begin
                running      <= 1'b0;
                read_ptr     <= {ADDR_BITS{1'b0}};
                song_time_ms <= 32'd0;
                next_note_reg<= 7'd0;
                current_record_valid <= 1'b0;
                fetch_wait <= 1'b0;
            end else if (clear_events && !running) begin
                write_ptr   <= {ADDR_BITS{1'b0}};
                read_ptr    <= {ADDR_BITS{1'b0}};
                event_count <= {COUNT_BITS{1'b0}};
                load_error <= 1'b0;
                song_time_ms<= 32'd0;
                next_note_reg <= 7'd0;
                current_record_valid <= 1'b0;
                fetch_wait <= 1'b0;
            end else if (start && (event_count != 0) && !load_error && !event_push) begin
                running      <= 1'b1;
                read_ptr     <= {ADDR_BITS{1'b0}};
                song_time_ms <= 32'd0;
                current_record_valid <= 1'b0;
                fetch_wait <= 1'b1;
            end else if (running) begin
                if (tick_1ms && !pause)
                    song_time_ms <= song_time_ms + 32'd1;

                // Wait for the registered RAM address, then capture its data.
                // Equal-time events stay ordered; each fetch takes four clocks
                // (80 ns at 50 MHz), well below a millisecond score tick.
                if (fetch_wait) begin
                    fetch_wait <= 1'b0;
                end else if (!current_record_valid) begin
                    current_record <= ram_record;
                    current_record_valid <= 1'b1;
                    next_note_reg <= ram_record[14:8];
                end else if ((!pause || follow_step) &&
                    (follow_step || current_record[46:15] <= song_time_ms)) begin
                    event_valid        <= 1'b1;
                    event_on_out       <= current_record[0];
                    event_note_out     <= current_record[14:8];
                    event_velocity_out <= current_record[7:1];
                    read_ptr            <= read_ptr + 1'b1;
                    if (consumed_events >= event_count) begin
                        done    <= 1'b1;
                        running <= 1'b0;
                        next_note_reg <= 7'd0;
                        current_record_valid <= 1'b0;
                    end else begin
                        current_record_valid <= 1'b0;
                        fetch_wait <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
