// Loss-detecting stereo PCM capture frontend, in the I2S receiver clock domain.
// Input is i2s_visual_rx's completed final-output PCM pair (stereo_valid),
// never its OSC A/B extension words. This small FIFO only absorbs backpressure;
// a song-sized store must consume the write stream and provide capacity_frames.
module performance_pcm_capture #(
    parameter integer FIFO_DEPTH = 16
)(
    input wire clk, rst_n,
    input wire start, stop, clear,
    input wire link_up, stereo_valid,
    input wire signed [15:0] sample_left, sample_right,
    input wire [31:0] capacity_frames,
    output wire write_valid,
    input wire write_ready,
    output wire [31:0] write_index,
    // One 32-bit frame: left in bits 15:0, right in 31:16 (WAV LE order).
    output wire [31:0] write_data,
    output reg recording,
    output wire busy,
    output reg done,
    output reg full, overflow, source_error, command_error,
    output reg [31:0] captured_frames, written_frames
);
    localparam integer PTR_BITS = (FIFO_DEPTH < 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam integer COUNT_BITS = $clog2(FIFO_DEPTH + 1);
    // Deliberately small elastic FIFO, not the recording storage backend.
    reg [31:0] fifo [0:FIFO_DEPTH-1];
    reg [PTR_BITS-1:0] rd_ptr, wr_ptr;
    reg [COUNT_BITS-1:0] count;
    reg [31:0] limit_frames;
    assign write_valid = count != 0;
    assign write_data = fifo[rd_ptr];
    assign write_index = written_frames;
    assign busy = recording || write_valid;
    wire pop = write_valid && write_ready;
    wire space = (count < FIFO_DEPTH) || pop;
    wire push = recording && !stop && link_up && stereo_valid && space;

    // FIFO data has no reset; count makes unwritten words inaccessible.
    always @(posedge clk)
        if (rst_n && push)
            fifo[wr_ptr] <= {sample_right, sample_left};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr<=0;wr_ptr<=0;count<=0;limit_frames<=0;
            recording<=0;done<=0;full<=0;overflow<=0;
            source_error<=0;command_error<=0;
            captured_frames<=0;written_frames<=0;
        end else begin
            done<=0;
            if (pop) begin
                rd_ptr <= (rd_ptr == FIFO_DEPTH-1) ? 0 : rd_ptr + 1'b1;
                written_frames <= written_frames + 1'b1;
                if (!recording && count == 1 && !push)
                    done<=1;
            end
            if (push) begin
                wr_ptr <= (wr_ptr == FIFO_DEPTH-1) ? 0 : wr_ptr + 1'b1;
                captured_frames <= captured_frames + 1'b1;
                if (captured_frames == limit_frames-1'b1) begin
                    full<=1;
                    recording<=0;
                end
            end
            case ({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: begin end
            endcase

            // Samples cannot be paused at the source. Fail explicitly on the
            // first lost frame; retain and drain all preceding queued frames.
            if (recording && !stop) begin
                if (!link_up) begin
                    recording<=0;source_error<=1;
                    if (count==0 || (count==1 && pop))done<=1;
                end else if (stereo_valid && !space) begin
                    recording<=0;overflow<=1;
                end
            end
            if (stop) begin
                recording<=0;
                if (recording && (count==0 || (count==1 && pop)))done<=1;
            end

            // Clear/restart cannot discard pending writes. Finish draining
            // before accepting either command. stop has priority over start.
            if (clear || start) begin
                if (busy || (clear && start) || stop) begin
                    command_error<=1;
                end else if (clear) begin
                    rd_ptr<=0;wr_ptr<=0;count<=0;
                    captured_frames<=0;written_frames<=0;
                    full<=0;overflow<=0;source_error<=0;command_error<=0;
                end else begin
                    rd_ptr<=0;wr_ptr<=0;count<=0;
                    captured_frames<=0;written_frames<=0;
                    full<=0;overflow<=0;command_error<=0;
                    limit_frames<=capacity_frames;
                    if (capacity_frames==0 || !link_up) begin
                        recording<=0;source_error<=1;
                    end else begin
                        recording<=1;source_error<=0;
                    end
                end
            end
        end
    end
endmodule
