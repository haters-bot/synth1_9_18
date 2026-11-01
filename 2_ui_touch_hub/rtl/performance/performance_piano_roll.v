// Read-only score visualization. Two 208 x 64 bitmaps replace per-pixel
// event searches: low 32 bits are note bodies, high 32 bits are attack edges.
// Eight score milliseconds per row gives 1648 ms of advance notice. Full
// score scans pair Note On/Off, including notes held across the window.
module performance_piano_roll #(
    parameter integer MAX_EVENTS=4096,
    parameter integer KEY_COUNT=32
)(
    input wire clk,rst_n,
    input wire frame_start,
    input wire running,
    input wire invalidate,
    input wire [31:0] song_time_ms,
    input wire [6:0] base_note,
    input wire [$clog2(MAX_EVENTS+1)-1:0] loaded_events,
    output wire [((MAX_EVENTS<=2)?1:$clog2(MAX_EVENTS))-1:0] preview_address,
    input wire [46:0] preview_record,
    // This is the raw raster Y, BEFORE the renderer's entry register. RAM's
    // synchronous result therefore belongs to that same registered pixel.
    input wire [13:0] raster_y,
    output wire [31:0] body_keys,
    output wire [31:0] onset_keys,
    output reg visible,
    output reg [31:0] displayed_time_ms
);
    localparam AB=(MAX_EVENTS<=2)?1:$clog2(MAX_EVENTS);
    localparam CB=$clog2(MAX_EVENTS+1);
    localparam IDLE=0,CLEAR=1,FETCH=2,CAPTURE=3,EVENT=4,ADVANCE=5,
               FINALIZE=6,CLIP=7,ROWS=8,READ_ROW=9,WRITE_ROW=10,READY=11;
    localparam integer LAST_ROW=206;
    localparam integer HORIZON_MS=LAST_ROW*8;
    reg [3:0] state;
    reg front_buffer;
    reg [7:0] row;
    reg [AB-1:0] scan_address;
    reg [CB-1:0] scan_count;
    reg [31:0] window_time,window_end;
    reg [6:0] window_base;
    reg [46:0] record;
    reg [31:0] starts[0:KEY_COUNT-1];
    reg [CB-1:0] holds[0:KEY_COUNT-1];
    reg [5:0] final_key;
    reg finalizing;
    reg [31:0] segment_start,segment_end;
    reg [31:0] delta_start,delta_end;
    reg [31:0] key_mask;
    reg attack_visible;
    reg [7:0] bottom_row;
    reg [31:0] completed_time;

    wire [6:0] note=record[14:8];
    wire [6:0] key_index=note-window_base;
    wire in_range=note>=window_base && key_index<KEY_COUNT;
    wire note_on=record[0] && record[7:1]!=0;
    wire [7:0] raw_bottom=LAST_ROW-(delta_start>>3);
    wire [7:0] raw_top=LAST_ROW-(delta_end>>3);
    wire [7:0] render_row=raster_y-14'd192;
    wire [8:0] back_address={!front_buffer,row};
    wire [8:0] front_address={front_buffer,render_row};
    wire write_enable=state==CLEAR || state==WRITE_ROW;
    wire [63:0] draw_bits={(attack_visible && row==bottom_row)?key_mask:32'd0,key_mask};
    reg [63:0] back_data,front_data;
    wire [63:0] write_data=state==CLEAR ? 64'd0 : back_data|draw_bits;
    (* syn_ramstyle="block_ram", ram_style="block" *) reg [63:0] bitmap[0:511];
    // One read/write builder port, one display read port; no reset on RAM.
    always @(posedge clk) begin
        if(write_enable)bitmap[back_address]<=write_data;
        back_data<=bitmap[back_address];
        front_data<=bitmap[front_address];
    end
    reg raster_in_roll;
    always @(posedge clk)raster_in_roll<=raster_y>=192 && raster_y<400;
    assign body_keys=(visible && raster_in_roll && running && !invalidate)?front_data[31:0]:32'd0;
    assign onset_keys=(visible && raster_in_roll && running && !invalidate)?front_data[63:32]:32'd0;
    assign preview_address=scan_address;
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;front_buffer<=0;row<=0;scan_address<=0;scan_count<=0;
            window_time<=0;window_end<=0;window_base<=0;record<=0;
            final_key<=0;finalizing<=0;segment_start<=0;segment_end<=0;
            delta_start<=0;delta_end<=0;key_mask<=0;attack_visible<=0;
            bottom_row<=0;visible<=0;displayed_time_ms<=0;completed_time<=0;
            for(k=0;k<KEY_COUNT;k=k+1)begin starts[k]<=0;holds[k]<=0;end
        end else if(!running || invalidate)begin
            state<=IDLE;visible<=0;
        end else case(state)
            IDLE:begin
                window_time<=song_time_ms;window_end<=song_time_ms+HORIZON_MS;
                window_base<=base_note;scan_count<=loaded_events;scan_address<=0;
                row<=0;final_key<=0;finalizing<=0;
                for(k=0;k<KEY_COUNT;k=k+1)holds[k]<=0;
                state<=CLEAR;
            end
            CLEAR:if(row==207)begin
                row<=0;state<=scan_count==0 ? READY : FETCH;
                completed_time<=window_time;
            end else row<=row+1'b1;
            FETCH:state<=CAPTURE;
            CAPTURE:begin record<=preview_record;state<=EVENT;end
            EVENT:begin
                if(record[46:15]>window_end)begin final_key<=0;state<=FINALIZE;end
                else if(!in_range)state<=ADVANCE;
                else if(note_on)begin
                    if(holds[key_index]==0)starts[key_index]<=record[46:15];
                    holds[key_index]<=holds[key_index]+1'b1;
                    state<=ADVANCE;
                end else if(holds[key_index]>1)begin
                    holds[key_index]<=holds[key_index]-1'b1;state<=ADVANCE;
                end else if(holds[key_index]==1)begin
                    holds[key_index]<=0;
                    segment_start<=starts[key_index];segment_end<=record[46:15];
                    key_mask<=32'd1<<key_index;finalizing<=0;state<=CLIP;
                end else state<=ADVANCE;
            end
            ADVANCE:if(({1'b0,scan_address}+1'b1)>=scan_count)begin
                final_key<=0;state<=FINALIZE;
            end else begin scan_address<=scan_address+1'b1;state<=FETCH;end
            FINALIZE:if(final_key>=KEY_COUNT)state<=READY;
                else if(holds[final_key]!=0)begin
                    segment_start<=starts[final_key];segment_end<=window_end;
                    key_mask<=32'd1<<final_key;finalizing<=1;state<=CLIP;
                end else final_key<=final_key+1'b1;
            CLIP:if(segment_end<=window_time || segment_start>window_end || segment_end<segment_start)begin
                if(finalizing)begin final_key<=final_key+1'b1;state<=FINALIZE;end
                else state<=ADVANCE;
            end else begin
                delta_start<=segment_start>window_time ? segment_start-window_time : 32'd0;
                delta_end<=segment_end<window_end ? segment_end-window_time : HORIZON_MS;
                attack_visible<=segment_start>=window_time;
                state<=ROWS;
            end
            ROWS:begin
                bottom_row<=raw_bottom;
                // Sub-row notes still get a visible two-pixel body.
                row<=raw_top==raw_bottom && raw_bottom!=0 ? raw_top-1'b1 : raw_top;
                state<=READ_ROW;
            end
            READ_ROW:state<=WRITE_ROW;
            WRITE_ROW:if(row==bottom_row)begin
                if(finalizing)begin final_key<=final_key+1'b1;state<=FINALIZE;end
                else state<=ADVANCE;
            end else begin row<=row+1'b1;state<=READ_ROW;end
            READY:if(frame_start)begin
                front_buffer<=!front_buffer;visible<=1;displayed_time_ms<=completed_time;
                state<=IDLE;
            end
            default:state<=IDLE;
        endcase
    end
endmodule
