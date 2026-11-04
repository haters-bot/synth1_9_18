// Connect the confirmed audio-board I2S PCM pair to the song-sized DDR
// transport. The caller supplies the real DDR user clock and backend interface;
// this module does not claim a memory is present until init_done is asserted.
module performance_recording_subsystem #(
    parameter integer FIFO_ADDR_BITS=3,
    parameter integer RESPONSE_TIMEOUT=100000
)(
    input wire rst_n,src_clk,mem_clk,init_done,
    input wire start,stop,
    input wire [28:0] base_addr,region_end_addr,
    input wire [31:0] capacity_frames,
    input wire link_up,stereo_valid,
    input wire signed [15:0] sample_left,sample_right,
    output wire recording,active,done,full,
    output wire start_accepted,start_rejected,
    output wire capture_error,storage_error,protocol_error,command_error,
    output wire [31:0] captured_frames,accepted_frames,stored_frames,
    input wire read_valid,
    output wire read_ready,
    input wire [31:0] read_index,
    output wire read_data_valid,
    input wire read_data_ready,
    output wire [31:0] read_data,read_data_index,
    output wire read_error,backend_available,
    output wire req_valid,input wire req_ready,
    output wire req_write,output wire [28:0] req_addr,
    output wire [255:0] req_wdata,output wire [31:0] req_wmask,
    input wire rsp_valid,rsp_write,rsp_error,
    input wire [255:0] rsp_rdata
);
    wire store_start_accepted,store_busy,store_done;
    wire capture_busy,capture_done,capture_overflow,capture_source_error,capture_command_error;
    wire frame_valid,frame_ready;
    wire [31:0] frame_index,frame_data,capture_written;
    wire [31:0] store_accepted;
    // Capture faults are sticky until its next accepted start. Do not let
    // the preceding take's fault poison the store during that reset edge.
    reg capture_epoch;
    always @(posedge src_clk or negedge rst_n)
        if(!rst_n)capture_epoch<=0;
        else if(start && !store_busy && !capture_busy)capture_epoch<=0;
        else if(store_start_accepted)capture_epoch<=1;
    performance_pcm_capture capture(
        .clk(src_clk),.rst_n(rst_n),.start(store_start_accepted),.stop(stop),.clear(1'b0),
        .link_up(link_up),.stereo_valid(stereo_valid),
        .sample_left(sample_left),.sample_right(sample_right),.capacity_frames(capacity_frames),
        .write_valid(frame_valid),.write_ready(frame_ready),.write_index(frame_index),.write_data(frame_data),
        .recording(recording),.busy(capture_busy),.done(capture_done),.full(full),
        .overflow(capture_overflow),.source_error(capture_source_error),.command_error(capture_command_error),
        .captured_frames(captured_frames),.written_frames(capture_written));
    performance_pcm_store #(.FIFO_ADDR_BITS(FIFO_ADDR_BITS),.RESPONSE_TIMEOUT(RESPONSE_TIMEOUT)) store(
        .rst_n(rst_n),.src_clk(src_clk),.start(start),.finish(capture_done),
        .source_error_in(capture_epoch && !store_start_accepted &&
                         (capture_overflow || capture_source_error || capture_command_error)),
        .base_addr(base_addr),.region_end_addr(region_end_addr),.capacity_frames(capacity_frames),
        .start_accepted(store_start_accepted),.start_rejected(start_rejected),.frame_valid(frame_valid),.frame_ready(frame_ready),
        .frame_index(frame_index),.frame_data(frame_data),.busy(store_busy),.done(store_done),
        .storage_error(storage_error),.protocol_error(protocol_error),.command_error(command_error),
        .accepted_frames(store_accepted),.stored_frames(stored_frames),
        .read_valid(read_valid),.read_ready(read_ready),.read_index(read_index),
        .read_data_valid(read_data_valid),.read_data_ready(read_data_ready),.read_data(read_data),
        .read_data_index(read_data_index),.read_error(read_error),.backend_available(backend_available),
        .mem_clk(mem_clk),.init_done(init_done),.req_valid(req_valid),.req_ready(req_ready),.req_write(req_write),
        .req_addr(req_addr),.req_wdata(req_wdata),.req_wmask(req_wmask),
        .rsp_valid(rsp_valid),.rsp_write(rsp_write),.rsp_error(rsp_error),.rsp_rdata(rsp_rdata));
    assign active=capture_busy || store_busy;
    assign start_accepted=store_start_accepted;
    assign done=store_done;
    assign capture_error=capture_overflow || capture_source_error || capture_command_error;
    assign accepted_frames=store_accepted;
endmodule
