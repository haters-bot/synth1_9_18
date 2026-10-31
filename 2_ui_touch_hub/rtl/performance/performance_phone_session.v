// Stop-and-wait command gate. ACK means the FPGA accepted the command, never
// merely that a gateway wrote bytes. Only the last control reply is cached;
// READ retries are idempotent offset reads and regenerate their audio packets.
module performance_phone_session #(
 parameter MAX_EVENTS=16384,BASE_NOTE=7'h29,KEY_COUNT=32,CALIBRATION_ENABLE=0
)(
 input wire clk,rst_n,tick_1ms,packet_valid,
 input wire [7:0] packet_type,packet_sequence,
 input wire [6:0] packet_length,input wire [511:0] packet_payload,
 input wire [15:0] packet_signature,input wire fast_baud,
 input wire local_calibrate,calibration_idle,
 input wire physical_note_valid,physical_note_on,
 input wire [6:0] physical_note,physical_velocity,
 output reg [6:0] calibrated_base_note,
 output reg [2:0] calibration_state,
 output reg [15:0] calibration_epoch,
 output reg invalidate_score,
 output reg command_valid,output reg [7:0] command_type,
 output reg [6:0] command_length,output reg [511:0] command_payload,
 input wire decoder_error,score_error,score_running,
 input wire record_active,record_busy,record_start_accepted,record_start_rejected,
 input wire backend_available,audio_link_up,input wire [3:0] record_status,
 input wire [31:0] stored_frames,
 output wire upload_active,output wire export_busy,
 output reg reply_valid,input wire reply_ready,
 output wire [7:0] reply_type,output reg [7:0] reply_sequence,
 output reg [6:0] reply_length,output reg [511:0] reply_payload,
 output wire read_valid,input wire read_ready,output wire [31:0] read_index,
 input wire read_data_valid,read_error,input wire [31:0] read_data,read_data_index,
 output wire read_data_ready
);
 localparam IDLE=0,CHECK=1,BATCH=2,FORWARD=3,SETTLE=4,RECORD_WAIT=5,
            COMPOSE=6,SEND=7,EXPORT_WAIT=8,BATCH_FETCH=9,BATCH_ADVANCE=10;
 reg [3:0] state;
 reg [7:0] kind,seq,status;
 reg [6:0] length;
 reg [15:0] signature;
 reg [511:0] payload;
 reg [5:0] settle;
 reg [11:0] wait_ms;
 reg cleared,uploading,loaded;
 reg [15:0] expected,received;
 reg [31:0] duration,last_time,check_time,generation;
 reg [3:0] batch_index,batch_count;
 reg cache_valid;
 reg [7:0] cache_kind,cache_seq;
 reg [6:0] cache_length;
 reg [15:0] cache_signature;
 reg [207:0] cache_reply;
 reg hello_seen;
 reg [31:0] hello_nonce;
 reg [5:0] calibration_settle;
 reg calibration_request_pending;
 wire calibrated=!CALIBRATION_ENABLE || calibration_state==2;
 wire [6:0] effective_base=CALIBRATION_ENABLE ? calibrated_base_note : BASE_NOTE;
 reg export_start;
 wire exporter_busy,export_done,export_packet_valid;
 wire [7:0] export_error;
 wire [6:0] export_packet_length;
 wire [511:0] export_packet_payload;
 reg [63:0] current_event;
 reg batch_event_invalid;
 assign upload_active=uploading;
 assign export_busy=exporter_busy || export_start || (state!=IDLE && kind==8'h43);
 assign reply_type=state==EXPORT_WAIT ? 8'h71 : 8'h70;
 // Data streaming bypasses the control reply buffer, with the same sequence.
 wire data_handshake=state==EXPORT_WAIT && export_packet_valid && reply_ready;
 performance_audio_export exporter(.clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.start(export_start),
  .offset(payload[31:0]),.count(payload[47:32]),.stereo(payload[55:48]==2),
  .stored_frames(stored_frames),.generation(generation),.backend_available(backend_available),
  .busy(exporter_busy),.done(export_done),.error(export_error),
  .read_valid(read_valid),.read_ready(read_ready),.read_index(read_index),
  .read_data_valid(read_data_valid),.read_data_ready(read_data_ready),
  .read_data(read_data),.read_data_index(read_data_index),.read_error(read_error),
  .packet_valid(export_packet_valid),.packet_ready(data_handshake),
  .packet_length(export_packet_length),.packet_payload(export_packet_payload));
 always @*begin
  reply_valid=state==SEND || (state==EXPORT_WAIT && export_packet_valid);
  reply_length=state==EXPORT_WAIT ? export_packet_length : CALIBRATION_ENABLE ? 7'd26 : 7'd22;
  reply_payload=state==EXPORT_WAIT ? export_packet_payload : {304'd0,cache_reply};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;command_valid<=0;command_type<=0;command_length<=0;
   kind<=0;seq<=0;length<=0;signature<=0;status<=0;settle<=0;wait_ms<=0;
   cleared<=0;uploading<=0;loaded<=0;expected<=0;received<=0;duration<=0;last_time<=0;check_time<=0;
   generation<=0;batch_index<=0;batch_count<=0;cache_valid<=0;
   current_event<=0;batch_event_invalid<=0;
   cache_kind<=0;cache_seq<=0;cache_length<=0;cache_signature<=0;cache_reply<=0;
   export_start<=0;reply_sequence<=0;
   calibrated_base_note<=BASE_NOTE;calibration_state<=0;calibration_epoch<=0;
   invalidate_score<=0;hello_seen<=0;hello_nonce<=0;calibration_settle<=0;calibration_request_pending<=0;
  end else begin
   command_valid<=0;export_start<=0;invalidate_score<=0;
   // Only an explicit panel action arms F15 capture. Drain old audition/touch
   // Notes before changing base, so their Note Offs retain the original pitch.
   if(CALIBRATION_ENABLE)begin
    // A panel pulse may coincide with a phone STATUS/ACK. Keep the explicit
    // action until the command gate is idle; do not defer busy recording/upload
    // actions until later, when they could unexpectedly erase a new score.
    if(local_calibrate && !uploading && !export_busy && !record_busy && !record_active)
     calibration_request_pending<=1;
    if(uploading || export_busy || record_busy || record_active)
     calibration_request_pending<=0;
    if(calibration_state==4)begin
     if(calibration_idle && state==IDLE)begin
      if(calibration_settle==63)begin calibration_state<=1;calibration_settle<=0;end
      else calibration_settle<=calibration_settle+1'b1;
     end else calibration_settle<=0;
    end
    if(calibration_state==1 && calibration_idle &&
       physical_note_valid && physical_note_on && physical_velocity!=0)begin
     // The four confirmed octave settings share pitch class F. 0x59 is
     // excluded: the user reports silent upper keys at that setting.
     if(physical_note==7'h29 || physical_note==7'h35 ||
        physical_note==7'h41 || physical_note==7'h4D)begin
      calibrated_base_note<=physical_note;calibration_state<=2;
      calibration_epoch<=calibration_epoch+1'b1;cache_valid<=0;
     end else begin calibration_state<=3;cache_valid<=0;end
    end
    if((local_calibrate || calibration_request_pending) && state==IDLE && !packet_valid && !uploading &&
       !export_busy && !record_busy && !record_active)begin
     calibration_request_pending<=0;
     calibration_state<=4;calibration_settle<=0;
     calibration_epoch<=calibration_epoch+1'b1;invalidate_score<=1;
     loaded<=0;cleared<=0;received<=0;cache_valid<=0;
    end
   end
   if(record_start_accepted)generation<=generation+1'b1;
   case(state)
    IDLE:if(packet_valid)begin
     kind<=packet_type;seq<=packet_sequence;length<=packet_length;
     signature<=packet_signature;payload<=packet_payload;status<=0;
     reply_sequence<=packet_sequence;state<=CHECK;
    end
    CHECK:begin
     if(kind!=8'h43 && kind!=1 && kind!=2 && cache_valid && kind==cache_kind && seq==cache_seq &&
        length==cache_length && signature==cache_signature)state<=SEND;
     else case(kind)
      8'h01:begin
       if(length!=0 && length!=4)status<=1;
       else if(CALIBRATION_ENABLE && (!hello_seen || length==0 || hello_nonce!=payload[31:0]))begin
        hello_seen<=1;hello_nonce<=payload[31:0];calibration_state<=0;
        calibration_epoch<=calibration_epoch+1'b1;calibration_settle<=0;calibration_request_pending<=0;
        invalidate_score<=1;loaded<=0;cleared<=0;uploading<=0;received<=0;
       end
       state<=COMPOSE;
      end
      8'h02:begin
       if(length!=0)status<=1;
       state<=COMPOSE;
      end
      8'h10:begin
       if(length!=0)begin status<=1;state<=COMPOSE;end
       else if(score_running)begin status<=2;state<=COMPOSE;end
       else begin cleared<=1;uploading<=0;loaded<=0;received<=0;last_time<=0;state<=FORWARD;end
      end
      8'h11:begin
       if(!calibrated || (CALIBRATION_ENABLE && payload[63:48]!=calibration_epoch))begin status<=7;state<=COMPOSE;end
       else if(length!=(CALIBRATION_ENABLE ? 8 : 6) || payload[47:32]==0 || payload[47:32]>MAX_EVENTS || payload[31:0]==0)begin status<=1;state<=COMPOSE;end
       else if(!cleared || score_running || uploading)begin status<=2;state<=COMPOSE;end
       else begin
        expected<=payload[47:32];duration<=payload[31:0];uploading<=1;loaded<=0;cleared<=0;
        received<=0;last_time<=0;state<=FORWARD;
       end
      end
      8'h12:begin
       if(!uploading || score_running)begin status<=2;state<=COMPOSE;end
       else if(length==0 || length>64 || length[2:0]!=0 || received+(length>>3)>expected)begin
        status<=1;uploading<=0;state<=COMPOSE;
       end else begin batch_index<=0;batch_count<=length>>3;check_time<=last_time;state<=BATCH_FETCH;end
      end
      8'h13:begin
       if(length!=0 || !uploading || received!=expected || score_error)begin
        status<=3;uploading<=0;loaded<=0;state<=COMPOSE;
       end else begin uploading<=0;loaded<=1;state<=FORWARD;end
      end
      8'h20:begin
       if(!calibrated)begin status<=7;state<=COMPOSE;end
       else if(length!=0 || !loaded || uploading || score_error)begin status<=3;state<=COMPOSE;end
       else state<=FORWARD;
      end
      8'h23:begin
       if(length!=1 || payload[1:0]>2)begin status<=1;state<=COMPOSE;end
       else state<=FORWARD;
      end
      8'h21,8'h22,8'h41:begin
       if(length!=0)begin status<=1;state<=COMPOSE;end else state<=FORWARD;
      end
      8'h30:begin
       if(!calibrated)begin status<=7;state<=COMPOSE;end
       else if(length!=3 || payload[7:0]<effective_base || payload[7:0]>=effective_base+KEY_COUNT ||
          payload[15:8]>127 || payload[23:16]>1)begin status<=1;state<=COMPOSE;end else state<=FORWARD;
      end
      8'h40:begin
       if(length!=0)begin status<=1;state<=COMPOSE;end
       else if(record_busy || !backend_available || !audio_link_up)begin status<=2;state<=COMPOSE;end
       else state<=FORWARD;
      end
      8'h43:begin
       if(length!=7 || (payload[55:48]!=1 && payload[55:48]!=2) || payload[47:32]==0 || payload[47:32]>1024)begin status<=1;state<=COMPOSE;end
       else if(record_busy || record_active || !backend_available)begin status<=2;state<=COMPOSE;end
       else begin export_start<=1;state<=EXPORT_WAIT;end
      end
      default:begin status<=1;state<=COMPOSE;end
     endcase
    end
    // Separate the 512-to-64 mux, validation and counter commit. Forward the
    // original frozen packet only after EVERY event has passed all checks.
    BATCH_FETCH:begin
     current_event<=payload[batch_index*64+:64];state<=BATCH;
    end
    BATCH:begin
     batch_event_invalid<=current_event[31:0]<check_time || current_event[31:0]>duration ||
        current_event[39:32]<effective_base || current_event[39:32]>=effective_base+KEY_COUNT ||
        current_event[47:40]>127 || current_event[63:49]!=0;
     state<=BATCH_ADVANCE;
    end
    BATCH_ADVANCE:begin
     if(batch_event_invalid)begin
      status<=1;uploading<=0;loaded<=0;state<=COMPOSE;
     end else if(batch_index+1>=batch_count)begin
      last_time<=current_event[31:0];received<=received+batch_count;state<=FORWARD;
     end else begin
      check_time<=current_event[31:0];batch_index<=batch_index+1'b1;state<=BATCH_FETCH;
     end
    end
    FORWARD:begin
     command_valid<=1;command_type<=kind;command_length<=kind==8'h11 && CALIBRATION_ENABLE ? 7'd6 : length;command_payload<=payload;
     settle<=0;wait_ms<=0;state<=kind==8'h40 ? RECORD_WAIT : SETTLE;
    end
    SETTLE:begin
     if(decoder_error || (score_error && kind!=8'h10))begin status<=3;loaded<=0;uploading<=0;end
     if(settle==24)state<=COMPOSE;else settle<=settle+1'b1;
    end
    RECORD_WAIT:begin
     if(record_start_accepted)state<=COMPOSE;
     else if(record_start_rejected || decoder_error)begin status<=2;state<=COMPOSE;end
     else if(tick_1ms)begin
      if(wait_ms==1000)begin status<=6;state<=COMPOSE;end else wait_ms<=wait_ms+1'b1;
     end
    end
    EXPORT_WAIT:if(export_done)begin status<=export_error;state<=COMPOSE;end
    COMPOSE:begin
     // Keep the page's link indicator alive for queries and offline export.
     if(kind==1 || kind==2 || kind==8'h43)begin command_valid<=1;command_type<=1;command_length<=0;end
     cache_reply[7:0]<=status;cache_reply[15:8]<=kind;
       cache_reply[23:16]<={CALIBRATION_ENABLE && calibrated,audio_link_up,export_busy,fast_baud,loaded,backend_available,record_busy,record_active};
     cache_reply[31:24]<={4'd0,record_status};cache_reply[63:32]<=stored_frames;
     cache_reply[79:64]<=received;cache_reply[87:80]<={1'b0,effective_base};cache_reply[95:88]<=KEY_COUNT;
     cache_reply[127:96]<=32'd96000;cache_reply[159:128]<=generation;cache_reply[175:160]<=MAX_EVENTS;
     cache_reply[183:176]<=CALIBRATION_ENABLE ? 8'd1 : 8'd0;
     cache_reply[191:184]<={5'd0,calibration_state};cache_reply[207:192]<=calibration_epoch;
     cache_valid<=1;cache_kind<=kind;cache_seq<=seq;cache_length<=length;cache_signature<=signature;state<=SEND;
    end
    SEND:if(reply_ready)state<=IDLE;
   endcase
  end
 end
endmodule
