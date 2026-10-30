// Bounded, restartable offline reads of the ORIGINAL stereo I2S recording.
// Requests are 8k output-frame offsets. Replaying a block reconstructs FIR
// history, so a retransmission has exactly the same samples as a continuous run.
module performance_audio_export(
 input wire clk,rst_n,tick_1ms,start,
 input wire [31:0] offset,stored_frames,generation,
 input wire [15:0] count,input wire stereo,backend_available,
 output wire busy,output reg done,output reg [7:0] error,
 output wire read_valid,input wire read_ready,
 output reg [31:0] read_index,
 input wire read_data_valid,read_error,input wire [31:0] read_data,read_data_index,
 output wire read_data_ready,
 output reg packet_valid,input wire packet_ready,
 output reg [6:0] packet_length,output reg [511:0] packet_payload
);
 localparam IDLE=0,CALC=1,BOUNDS=2,PREPARE=3,REQUEST=4,RESPONSE=5,FILTER=6,SEND=7;
 reg [3:0] state;
 reg [33:0] raw_start,raw_end;
 reg [15:0] remaining;
 reg [31:0] output_index,take_generation;
 reg [4:0] packet_count;
 reg [3:0] phase;
 reg channels_stereo;
 reg filter_clear;
 reg [11:0] idle_ms;
 wire filter_ready,filtered_valid;
 wire signed [15:0] filtered_l,filtered_r;
 wire emit_sample=phase==11 && {2'd0,read_index}>=raw_start;
 wire accept_pcm=state==RESPONSE && read_data_valid && !read_error && read_data_index==read_index;
 wire signed [16:0] mixed=$signed({filtered_l[15],filtered_l})+$signed({filtered_r[15],filtered_r});
 assign busy=state!=IDLE;
 assign read_valid=state==REQUEST && filter_ready && backend_available;
 // Always drain a late/error response; abandoning it would wedge pcm_store.
 assign read_data_ready=1'b1;
 performance_export_filter filter(.clk(clk),.rst_n(rst_n),.clear(filter_clear),
  .in_valid(accept_pcm),.in_ready(filter_ready),.in_emit(emit_sample),
  .in_left(read_data[15:0]),.in_right(read_data[31:16]),
  .out_valid(filtered_valid),.out_ready(state==FILTER),.out_left(filtered_l),.out_right(filtered_r));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;done<=0;error<=0;read_index<=0;packet_valid<=0;packet_length<=0;
   raw_start<=0;raw_end<=0;remaining<=0;output_index<=0;take_generation<=0;
   packet_count<=0;phase<=0;channels_stereo<=0;filter_clear<=0;idle_ms<=0;
  end else begin
   done<=0;filter_clear<=0;
   if(state!=IDLE && tick_1ms && !packet_valid)begin
    if(idle_ms<2000)idle_ms<=idle_ms+1'b1;
    else begin error<=8'd6;done<=1;state<=IDLE;filter_clear<=1;end
   end
   if((read_data_valid && state==RESPONSE) || filtered_valid || (packet_valid && packet_ready))idle_ms<=0;
   case(state)
    IDLE:if(start)begin
     raw_start<=({2'd0,offset}<<3)+({2'd0,offset}<<2);
     output_index<=offset;remaining<=count;channels_stereo<=stereo;take_generation<=generation;
     error<=0;packet_count<=0;phase<=0;filter_clear<=1;idle_ms<=0;state<=CALC;
    end
    CALC:begin raw_end<=raw_start+({18'd0,remaining}<<3)+({18'd0,remaining}<<2);state<=BOUNDS;end
    BOUNDS:begin
     if(remaining==0 || remaining>1024 || raw_end>{2'd0,stored_frames} || !backend_available)begin
      error<=8'd4;done<=1;state<=IDLE;
     end else begin read_index<=raw_start>132 ? raw_start-132 : 0;state<=PREPARE;end
    end
    PREPARE:begin
     packet_payload[31:0]<=output_index;
     packet_payload[39:32]<=0;packet_payload[47:40]<=channels_stereo ? 2 : 1;
     packet_payload[79:48]<=take_generation;packet_count<=0;state<=REQUEST;
    end
    REQUEST:if(read_valid && read_ready)state<=RESPONSE;
    RESPONSE:if(read_data_valid)begin
     if(read_error || read_data_index!=read_index)begin error<=8'd5;done<=1;state<=IDLE;end
     else if(emit_sample)state<=FILTER;
     else begin phase<=phase==11 ? 0 : phase+1'b1;read_index<=read_index+1'b1;state<=REQUEST;end
    end
    FILTER:if(filtered_valid)begin
     if(channels_stereo)begin
      packet_payload[80+packet_count*32+:16]<=filtered_l;
      packet_payload[96+packet_count*32+:16]<=filtered_r;
     end else packet_payload[80+packet_count*16+:16]<=mixed[16:1];
     output_index<=output_index+1'b1;remaining<=remaining-1'b1;
     packet_count<=packet_count+1'b1;read_index<=read_index+1'b1;phase<=0;
     if(remaining==1 || packet_count==(channels_stereo ? 12 : 26))begin
      packet_payload[39:32]<={3'd0,packet_count}+1'b1;
      packet_length<=10+((packet_count+7'd1)<<(channels_stereo ? 2 : 1));
      packet_valid<=1;state<=SEND;
     end else state<=REQUEST;
    end
    SEND:if(packet_valid && packet_ready)begin
     packet_valid<=0;
     if(remaining==0)begin done<=1;state<=IDLE;end else state<=PREPARE;
    end
   endcase
  end
 end
endmodule
