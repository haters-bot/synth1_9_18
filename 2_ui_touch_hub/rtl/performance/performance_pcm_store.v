// Song-sized PCM storage transport. No PCM array is allocated here: the
// external DDR backend owns the actual capacity. Source frames become masked
// 256-bit writes, cross clocks in a Gray-pointer FIFO, and complete only after
// the backend's write responses. Readback uses the same ordered request port.
// Gowin adapter addresses are 32-bit words: +8 per 32-byte transaction.
module performance_pcm_store #(
    parameter integer FIFO_ADDR_BITS=3,
    parameter integer RESPONSE_TIMEOUT=100000
)(
    input wire rst_n,
    input wire src_clk,
    input wire start, finish, source_error_in,
    input wire [28:0] base_addr, region_end_addr,
    input wire [31:0] capacity_frames,
    output reg start_accepted,
    output reg start_rejected,
    input wire frame_valid,
    output wire frame_ready,
    input wire [31:0] frame_index, frame_data,
    output wire busy,
    output reg done, storage_error, protocol_error, command_error,
    output reg [31:0] accepted_frames, stored_frames,
    input wire read_valid,
    output wire read_ready,
    input wire [31:0] read_index,
    output wire read_data_valid,
    input wire read_data_ready,
    output wire [31:0] read_data, read_data_index,
    output wire read_error,
    output wire backend_available,
    input wire mem_clk, init_done,
    output wire req_valid,
    input wire req_ready,
    output reg req_write,
    output reg [28:0] req_addr,
    output reg [255:0] req_wdata,
    output reg [31:0] req_wmask,
    input wire rsp_valid, rsp_write, rsp_error,
    input wire [255:0] rsp_rdata
);
    reg [1:0] src_reset_pipe,mem_reset_pipe;
    always @(posedge src_clk or negedge rst_n)
        if(!rst_n)src_reset_pipe<=0;else src_reset_pipe<={src_reset_pipe[0],1'b1};
    always @(posedge mem_clk or negedge rst_n)
        if(!rst_n)mem_reset_pipe<=0;else mem_reset_pipe<={mem_reset_pipe[0],1'b1};
    wire src_rst_n=src_reset_pipe[1],mem_rst_n=mem_reset_pipe[1];
    localparam [1:0] T_BEGIN=0,T_DATA=1,T_END=2,T_READ=3;
    localparam [1:0] R_END=0,R_FAULT=1,R_READ=2;
    localparam [2:0] S_IDLE=0,S_BEGIN=1,S_FILL=2,S_SEND=3,S_END=4,S_WAIT=5;
    reg [2:0] src_state;
    reg [255:0] packed_data;
    reg [31:0] packed_mask,limit_frames;
    reg [28:0] source_base;
    reg [3:0] packed_frames;
    reg finish_pending,read_pending,source_incomplete;
    reg [1:0] online_sync;
    reg poisoned;
    wire online=init_done && !poisoned;
    always @(posedge src_clk or negedge src_rst_n)
        if(!src_rst_n)online_sync<=0;else online_sync<={online_sync[0],online};
    assign backend_available=online_sync[1];
    assign busy=src_state!=S_IDLE;
    wire [32:0] rounded_capacity=({1'b0,capacity_frames}+33'd7)&33'h1fffffff8;
    wire region_valid=base_addr[2:0]==0 && region_end_addr[2:0]==0 &&
        region_end_addr>base_addr && capacity_frames!=0 &&
        ({4'd0,base_addr}+rounded_capacity)<={4'd0,region_end_addr};
    assign frame_ready=src_rst_n && src_state==S_FILL && !finish_pending && !finish &&
        !storage_error && !protocol_error && accepted_frames<limit_frames;

    wire token_ready,token_valid,mem_token_ready;
    wire fifo_token_valid;
    wire [322:0] fifo_token;
    reg mem_token_valid /* synthesis syn_preserve=1 syn_keep=1 */;
    reg [322:0] mem_token /* synthesis syn_preserve=1 syn_keep=1 */;
    wire fifo_token_ready=!mem_token_valid || mem_token_ready;
    // Register the wide RAM output before validating command fields and
    // driving 256-bit request muxes. No combinational protocol checks sit
    // directly on the BSRAM-to-register timing path. Preserve this boundary:
    // otherwise synthesis can absorb it into the RAM output and reconnect
    // the command validators directly to the BSRAM timing arc.
    always @(posedge mem_clk)begin
        if(fifo_token_ready && fifo_token_valid)mem_token<=fifo_token;
    end
    always @(posedge mem_clk or negedge mem_rst_n)begin
        if(!mem_rst_n)mem_token_valid<=0;
        else if(fifo_token_ready)mem_token_valid<=fifo_token_valid;
    end
    wire [1:0] source_kind=src_state==S_BEGIN ? T_BEGIN : src_state==S_SEND ? T_DATA : src_state==S_END ? T_END : T_READ;
    wire [255:0] source_data=src_state==S_BEGIN ? {224'd0,limit_frames} :
        src_state==S_END ? {224'd0,accepted_frames} : src_state==S_IDLE ? {224'd0,read_index} : packed_data;
    wire [31:0] source_mask=src_state==S_END ? {31'd0,(protocol_error || storage_error)} : packed_mask;
    wire [28:0] source_address=src_state==S_BEGIN ? source_base :
        src_state==S_IDLE ? read_index[28:0] : source_base+accepted_frames-packed_frames;
    assign token_valid=src_rst_n && (src_state==S_BEGIN || src_state==S_SEND || src_state==S_END ||
        (src_state==S_IDLE && read_valid && !read_pending && !start && backend_available));
    assign read_ready=src_rst_n && src_state==S_IDLE && !read_pending && !start && backend_available && token_ready;
    performance_async_fifo #(.WIDTH(323),.ADDR_BITS(FIFO_ADDR_BITS)) commands(
        .wr_clk(src_clk),.wr_rst_n(src_rst_n),.wr_valid(token_valid),.wr_ready(token_ready),
        .wr_data({source_kind,packed_frames,source_address,source_mask,source_data}),
        .rd_clk(mem_clk),.rd_rst_n(mem_rst_n),.rd_valid(fifo_token_valid),.rd_ready(fifo_token_ready),.rd_data(fifo_token));

    wire response_valid,response_ready,return_ready;
    wire [66:0] response;
    reg return_valid;
    reg [66:0] return_data;
    wire [1:0] response_kind=response[66:65];
    assign read_data_valid=response_valid && response_kind==R_READ;
    assign read_data=response[31:0];
    assign read_data_index=response[63:32];
    assign read_error=response[64];
    assign response_ready=response_kind!=R_READ || read_data_ready;
    performance_async_fifo #(.WIDTH(67),.ADDR_BITS(2)) responses(
        .wr_clk(mem_clk),.wr_rst_n(mem_rst_n),.wr_valid(return_valid),.wr_ready(return_ready),.wr_data(return_data),
        .rd_clk(src_clk),.rd_rst_n(src_rst_n),.rd_valid(response_valid),.rd_ready(response_ready),.rd_data(response));

    always @(posedge src_clk or negedge src_rst_n)begin
        if(!src_rst_n)begin
            src_state<=S_IDLE;packed_data<=0;packed_mask<=32'hffffffff;packed_frames<=0;
            source_base<=0;limit_frames<=0;finish_pending<=0;read_pending<=0;source_incomplete<=0;
            start_accepted<=0;start_rejected<=0;done<=0;storage_error<=0;protocol_error<=0;command_error<=0;
            accepted_frames<=0;stored_frames<=0;
        end else begin
            start_accepted<=0;start_rejected<=0;done<=0;
            if(start && (busy || read_pending))begin command_error<=1;start_rejected<=1;end
            if(finish && busy)finish_pending<=1;
            if(source_error_in && busy)begin source_incomplete<=1;protocol_error<=1;finish_pending<=1;end
            if(busy && !backend_available)begin storage_error<=1;finish_pending<=1;end
            case(src_state)
                S_IDLE:begin
                    if(start && !read_pending)begin
                        if(!backend_available || !region_valid)begin command_error<=1;start_rejected<=1;end
                        else begin
                            source_base<=base_addr;limit_frames<=capacity_frames;
                            packed_data<=0;packed_mask<=32'hffffffff;packed_frames<=0;
                            accepted_frames<=0;stored_frames<=0;finish_pending<=0;source_incomplete<=0;
                            storage_error<=0;protocol_error<=0;command_error<=0;
                            start_accepted<=1;src_state<=S_BEGIN;
                        end
                    end else if(read_valid && read_ready)read_pending<=1;
                end
                S_BEGIN:if(token_ready)src_state<=S_FILL;
                S_FILL:begin
                    if(finish || finish_pending)src_state<=packed_frames!=0 ? S_SEND : S_END;
                    else if(frame_valid && frame_ready)begin
                        if(source_error_in || frame_index!=accepted_frames)begin
                            protocol_error<=1;source_incomplete<=1;finish_pending<=1;
                        end
                        else begin
                            packed_data[packed_frames*32+:32]<=frame_data;
                            packed_mask[packed_frames*4+:4]<=0;
                            packed_frames<=packed_frames+1'b1;
                            accepted_frames<=accepted_frames+1'b1;
                            if(packed_frames==7)src_state<=S_SEND;
                            if(accepted_frames==limit_frames-1'b1)finish_pending<=1;
                        end
                    end
                end
                S_SEND:if(token_ready)begin
                    packed_data<=0;packed_mask<=32'hffffffff;packed_frames<=0;
                    src_state<=(finish || finish_pending) ? S_END : S_FILL;
                end
                S_END:if(token_ready)src_state<=S_WAIT;
                default:begin end
            endcase
            if(response_valid && response_ready)begin
                if(response_kind==R_READ)read_pending<=0;
                else if(response_kind==R_FAULT)begin storage_error<=1;finish_pending<=1;end
                else if(response_kind==R_END)begin
                    stored_frames<=response[63:32];storage_error<=storage_error || response[64];
                    src_state<=S_IDLE;done<=1;finish_pending<=0;
                end
            end
        end
    end

    localparam [3:0] M_IDLE=0,M_VALIDATE=1,M_REQUEST=2,M_RESPONSE=3,M_CALCULATE=4,M_FAULT=5,M_COMPLETE=6;
    reg [3:0] mem_state;
    reg session,session_error,last_good;
    reg [28:0] memory_base,last_base;
    reg [31:0] memory_limit,committed,last_frames;
    localparam integer WATCHDOG_BITS=(RESPONSE_TIMEOUT<=1) ? 1 : $clog2(RESPONSE_TIMEOUT);
    reg [WATCHDOG_BITS-1:0] watchdog;
    reg [31:0] pending_read_index;
    reg pending_read_out_of_range /* synthesis syn_preserve=1 syn_keep=1 */;
    reg completion_error;
    reg [31:0] completion_read_data;
    reg [1:0] pending_kind;
    reg [3:0] pending_command_frames;
    reg [28:0] pending_command_addr;
    reg [31:0] pending_command_mask;
    reg [255:0] pending_command_data;
    reg [28:0] expected_command_addr /* synthesis syn_preserve=1 syn_keep=1 */;
    reg [32:0] pending_end_frame /* synthesis syn_preserve=1 syn_keep=1 */;
    assign mem_token_ready=mem_state==M_IDLE && !return_valid;
    assign req_valid=mem_state==M_REQUEST && init_done && !poisoned;
    wire request_fire=req_valid && req_ready;
    // A response may legally coincide with request acceptance.
    wire response_fire=(mem_state==M_RESPONSE || request_fire) && rsp_valid;
    wire transaction_active=mem_state==M_REQUEST || mem_state==M_RESPONSE;
    wire timed_out=transaction_active && (watchdog>=RESPONSE_TIMEOUT-1);
    wire transaction_failed=transaction_active && (!init_done || timed_out);

    always @(posedge mem_clk or negedge mem_rst_n)begin
        if(!mem_rst_n)begin
            mem_state<=M_IDLE;session<=0;session_error<=0;poisoned<=0;last_good<=0;
            memory_base<=0;last_base<=0;memory_limit<=0;committed<=0;last_frames<=0;watchdog<=0;
            pending_read_index<=0;pending_read_out_of_range<=0;completion_error<=0;completion_read_data<=0;
            pending_kind<=0;pending_command_frames<=0;
            pending_command_addr<=0;pending_command_mask<=0;pending_command_data<=0;
            expected_command_addr<=0;pending_end_frame<=0;
            req_write<=0;req_addr<=0;req_wdata<=0;req_wmask<=0;return_valid<=0;return_data<=0;
        end else begin
            // These payloads settle before req_valid and cannot change while a
            // transaction is outstanding. Avoid a shared state-decode enable
            // spanning the wide request bus and the completion/status logic.
            req_wdata<=pending_command_data;
            req_wmask<=pending_command_mask;
            // Capture the response payload independently of request acceptance.
            // M_COMPLETE consumes the sample from the response-fire edge. This
            // also supports a backend returning a response on the request edge
            // without sending its high-fanout ready/valid path into counters,
            // read selection and the response FIFO in that same cycle.
            completion_error<=rsp_error || (rsp_write!=req_write);
            completion_read_data<=rsp_rdata[pending_read_index[2:0]*32+:32];
            // A lost calibration invalidates the previous recording even if
            // the port was idle and later becomes ready again.
            if(!init_done)begin last_good<=0;if(session)session_error<=1;end
            if(return_valid && return_ready)return_valid<=0;
            if(mem_state!=M_IDLE)watchdog<=watchdog+1'b1;
            else watchdog<=0;
            // First stage only captures the wide asynchronous-FIFO output.
            // The following validation stage cannot gate the 256-bit request
            // data/mask register inputs with the committed-frame comparator.
            if(mem_token_valid && mem_token_ready)begin
                pending_kind<=mem_token[322:321];
                pending_command_frames<=mem_token[320:317];
                pending_command_addr<=mem_token[316:288];
                pending_command_mask<=mem_token[287:256];
                pending_command_data<=mem_token[255:0];
                mem_state<=M_CALCULATE;
            end
            // Break the wide add -> compare -> status mux path into separate
            // cycles. No other transaction can change committed while held.
            if(mem_state==M_CALCULATE)begin
                expected_command_addr<=memory_base+committed;
                pending_end_frame<={1'b0,committed}+pending_command_frames;
                // Bound comparison has its own register boundary before the
                // error-response mux. Metadata is stable for this command;
                // live session/calibration checks stay in M_VALIDATE.
                pending_read_out_of_range<=pending_command_data[31:29]!=0 ||
                    pending_command_data[31:0]>=last_frames;
                mem_state<=M_VALIDATE;
            end
            if(mem_state==M_VALIDATE)begin
                case(pending_kind)
                    T_BEGIN:begin
                        mem_state<=M_IDLE;
                        session<=1;session_error<=session || !online;last_good<=0;
                        memory_base<=pending_command_addr;memory_limit<=pending_command_data[31:0];committed<=0;
                        if(session || !online)begin return_valid<=1;return_data<={R_FAULT,1'b1,32'd0,32'd0};end
                    end
                    T_DATA:begin
                        if(!session || session_error || !online)begin
                            mem_state<=M_IDLE;
                            session_error<=1;
                            if(!session_error)begin return_valid<=1;return_data<={R_FAULT,1'b1,committed,32'd0};end
                        end else if(pending_command_frames==0 || pending_command_frames>8 ||
                            pending_command_addr!=expected_command_addr ||
                            pending_end_frame>{1'b0,memory_limit} ||
                            pending_command_mask!=(32'hffffffff<<(pending_command_frames*4)))begin
                            // Defer the response one state so the wide limit
                            // compare is not on the DDR status return path.
                            mem_state<=M_FAULT;
                        end else begin
                            mem_state<=M_REQUEST;
                        end
                    end
                    T_END:begin
                        mem_state<=M_IDLE;
                        return_valid<=1;
                        return_data<={R_END,(!session || session_error || !online || pending_command_mask[0] || pending_command_data[31:0]!=committed),committed,32'd0};
                        last_frames<=committed;last_base<=memory_base;
                        last_good<=session && !session_error && online && !pending_command_mask[0] && pending_command_data[31:0]==committed;
                        session<=0;
                    end
                    T_READ:begin
                        pending_read_index<=pending_command_data[31:0];
                        if(session || !last_good || !online || pending_read_out_of_range)begin
                            mem_state<=M_IDLE;
                            return_valid<=1;return_data<={R_READ,1'b1,pending_command_data[31:0],32'd0};
                        end else begin
                            mem_state<=M_REQUEST;
                        end
                    end
                endcase
            end
            if(mem_state==M_FAULT)begin
                mem_state<=M_IDLE;
                session_error<=1;return_valid<=1;
                return_data<={R_FAULT,1'b1,committed,32'd0};
            end
            if(mem_state==M_COMPLETE)begin
                mem_state<=M_IDLE;
                if(req_write)begin
                    if(completion_error)begin
                        session_error<=1;return_valid<=1;return_data<={R_FAULT,1'b1,committed,32'd0};
                    end else committed<=pending_end_frame[31:0];
                end else begin
                    return_valid<=1;
                    return_data<={R_READ,completion_error,pending_read_index,completion_read_data};
                end
            end
            // Payload staging is deliberately independent of command-valid
            // logic; req_valid remains low unless M_VALIDATE accepts it.
            if(mem_state==M_VALIDATE)begin
                req_write<=pending_kind==T_DATA;
                req_addr<=pending_kind==T_READ ? last_base+{pending_command_data[28:3],3'd0} : pending_command_addr;
            end
            if(request_fire)mem_state<=M_RESPONSE;
            if(response_fire)begin
                // Accept before checking timeout, including on the final legal
                // watchdog edge. Completion is no longer transaction-active.
                mem_state<=M_COMPLETE;
            end else if(transaction_failed)begin
                // A late response cannot be safely associated with a retry.
                // Quarantine this memory port until a coordinated reset.
                poisoned<=1;mem_state<=M_IDLE;session_error<=1;return_valid<=1;
                return_data<=req_write ? {R_FAULT,1'b1,committed,32'd0} : {R_READ,1'b1,pending_read_index,32'd0};
            end
        end
    end
endmodule
