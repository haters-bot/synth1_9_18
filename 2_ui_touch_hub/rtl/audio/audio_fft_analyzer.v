// Native 96 kHz PCM: contiguous 1024-sample Hann-windowed frames, scaled
// radix-2 FFT. Processing takes <1 ms at 50 MHz; samples during processing
// are deliberately not part of a frame. Magnitudes are relative/logarithmic,
// not calibrated dBFS. 32 increasingly wide bands cover bins 1..511.
module audio_fft_analyzer #(
 parameter integer HISTORY_HOP=8
)(
 input wire clk,rst_n,link_up,sample_valid,
 input wire signed [15:0] sample,
 input wire [4:0] spectrum_address,
 output reg [5:0] spectrum_value,
 input wire [5:0] history_column,
 input wire [4:0] history_band,
 output reg [5:0] history_value,
 output reg ready,
 output reg frame_valid,
 output reg [4:0] peak_band,
 output reg peak_valid,
 output reg [9:0] peak_bin,
 output reg [15:0] peak_hz,centroid_hz
);
 localparam CAPTURE=0,WINDOW=1,STORE=2,SETUP=3,READ_A=4,READ_B=5,MULT=6,
            ROTATE=7,SUM=8,WRITE_A=9,WRITE_B=10,SCAN_SET=11,SCAN_READ=12,
            SCAN_ACC=13,PUBLISH=14,SCAN_MAG=15,SCAN_LOG=16,
            SCAN_SCALE=17,SCAN_LEVEL=18,CENTROID_START=19,CENTROID_DIV=20;
 reg [4:0] state;
 // Single-write, synchronous-read ping-pong banks fit Gowin's block RAM
 // inference. A simultaneous two-write coding style expanded into flip-flops.
 reg signed [15:0] real_memory0[0:1023],imag_memory0[0:1023];
 reg signed [15:0] real_memory1[0:1023],imag_memory1[0:1023];
 reg signed [15:0] q0_r,q0_i,q1_r,q1_i;
 reg source_bank;
 reg [9:0] read_address;
 reg [9:0] address_a,address_b,capture_index;
 reg signed [15:0] captured;
 wire signed [15:0] qa_r=source_bank ? q1_r : q0_r;
 wire signed [15:0] qa_i=source_bank ? q1_i : q0_i;
 wire signed [15:0] window_value,twiddle_real,twiddle_imag;
 reg [8:0] twiddle_address;
 reg signed [31:0] window_product,rr,ii,ri,ir;
 reg signed [17:0] rotated_r,rotated_i;
 reg signed [15:0] saved_ar,saved_ai;
 reg signed [15:0] sum_r,sum_i,diff_r,diff_i;
 reg [3:0] stage;
 reg [9:0] group_base,offset;
 reg [10:0] half_size;
 wire [10:0] next_group={1'b0,group_base}+(half_size<<1);
 wire signed [32:0] rotation_real={rr[31],rr}-{ii[31],ii};
 wire signed [32:0] rotation_imag={ri[31],ri}+{ir[31],ir};
 wire signed [17:0] extended_ar={{2{saved_ar[15]}},saved_ar};
 wire signed [17:0] extended_ai={{2{saved_ai[15]}},saved_ai};
 wire signed [17:0] sum_real=extended_ar+rotated_r;
 wire signed [17:0] sum_imag=extended_ai+rotated_i;
 wire signed [17:0] difference_real=extended_ar-rotated_r;
 wire signed [17:0] difference_imag=extended_ai-rotated_i;
 function [9:0] reverse_bits;
  input [9:0] value;integer i;
  begin for(i=0;i<10;i=i+1)reverse_bits[i]=value[9-i];end
 endfunction
 audio_fft_tables u_tables(.clk(clk),.window_address(capture_index),
  .twiddle_address(twiddle_address),.window_value(window_value),
  .twiddle_real(twiddle_real),.twiddle_imag(twiddle_imag));

 wire memory_write=rst_n && link_up && (state==STORE || state==WRITE_A || state==WRITE_B);
 wire target_bank=state==STORE ? 1'b0 : !source_bank;
 wire [9:0] write_address=state==STORE ? reverse_bits(capture_index) :
                          state==WRITE_A ? address_a : address_b;
 wire signed [15:0] write_real=state==STORE ? (window_product>>>15) :
                              state==WRITE_A ? sum_r : diff_r;
 wire signed [15:0] write_imag=state==STORE ? 16'sd0 :
                              state==WRITE_A ? sum_i : diff_i;
 always @(posedge clk)begin
  q0_r<=real_memory0[read_address];q0_i<=imag_memory0[read_address];
  if(memory_write && !target_bank)begin
   real_memory0[write_address]<=write_real;imag_memory0[write_address]<=write_imag;
  end
 end
 always @(posedge clk)begin
  q1_r<=real_memory1[read_address];q1_i<=imag_memory1[read_address];
  if(memory_write && target_bank)begin
   real_memory1[write_address]<=write_real;imag_memory1[write_address]<=write_imag;
  end
 end

 // Edges are FFT bins, not invented notes or frequencies. The first bins
 // remain separate (93.75 Hz/bin); higher bands pool increasingly many bins.
 function [9:0] band_end;
  input [4:0] band;
  begin case(band)
   0:band_end=2;1:band_end=3;2:band_end=4;3:band_end=5;
   4:band_end=6;5:band_end=7;6:band_end=8;7:band_end=9;
   8:band_end=10;9:band_end=12;10:band_end=14;11:band_end=16;
   12:band_end=19;13:band_end=22;14:band_end=26;15:band_end=31;
   16:band_end=37;17:band_end=44;18:band_end=52;19:band_end=62;
   20:band_end=74;21:band_end=88;22:band_end=104;23:band_end=124;
   24:band_end=148;25:band_end=176;26:band_end=208;27:band_end=248;
   28:band_end=296;29:band_end=352;30:band_end=420;default:band_end=512;
  endcase end
 endfunction
 // Leading-bit exponent plus two mantissa bits. Keep this encoder in its
 // own cycle rather than combining RAM read, abs/sum, peak and scaling.
 function [6:0] log_code;
  input [16:0] value;
  begin
   casez(value)
    17'b1????????????????:log_code={5'd16,value[15:14]};
    17'b01???????????????:log_code={5'd15,value[14:13]};
    17'b001??????????????:log_code={5'd14,value[13:12]};
    17'b0001?????????????:log_code={5'd13,value[12:11]};
    17'b00001????????????:log_code={5'd12,value[11:10]};
    17'b000001???????????:log_code={5'd11,value[10:9]};
    17'b0000001??????????:log_code={5'd10,value[9:8]};
    17'b00000001?????????:log_code={5'd9,value[8:7]};
    17'b000000001????????:log_code={5'd8,value[7:6]};
    17'b0000000001???????:log_code={5'd7,value[6:5]};
    17'b00000000001??????:log_code={5'd6,value[5:4]};
    17'b000000000001?????:log_code={5'd5,value[4:3]};
    17'b0000000000001????:log_code={5'd4,value[3:2]};
    default:log_code=0;
   endcase
  end
 endfunction
 reg [9:0] scan_bin;
 reg [4:0] scan_band,publish_band;
 wire [15:0] abs_real=qa_r[15] ? (~qa_r+16'd1) : qa_r;
 wire [15:0] abs_imag=qa_i[15] ? (~qa_i+16'd1) : qa_i;
 wire [16:0] magnitude={1'b0,abs_real}+{1'b0,abs_imag};
 reg [16:0] band_peak,magnitude_registered,display_peak;
 reg [6:0] display_log_code;
 reg [8:0] display_scaled;
 reg display_floor;
 wire [16:0] next_peak=magnitude_registered>band_peak ? magnitude_registered : band_peak;
 reg [5:0] bands[0:31];
 reg [5:0] spectrum_memory[0:63];
 reg [5:0] history_memory[0:2047];
 reg spectrum_bank;
 reg [5:0] history_write;
 reg [6:0] history_count;
 reg [7:0] history_frames;
 reg [4:0] frame_peak_band;
 reg [9:0] frame_peak_bin;
 reg [16:0] frame_max;
 reg [26:0] magnitude_sum,weighted_registered;
 reg [35:0] weighted_sum;
 reg [47:0] centroid_dividend,centroid_quotient;
 reg [27:0] centroid_remainder;
 reg [5:0] centroid_step;
 wire [27:0] centroid_shift={centroid_remainder[26:0],centroid_dividend[47]};
 wire centroid_take=centroid_shift>={1'b0,magnitude_sum};
 wire [47:0] centroid_next={centroid_quotient[46:0],centroid_take};
 wire write_history=history_frames==HISTORY_HOP-1;
 wire [5:0] history_read_column=history_write+history_column;
 always @(posedge clk)begin
  spectrum_value<=spectrum_memory[{spectrum_bank,spectrum_address}];
  if({1'b0,history_column}>=(7'd64-history_count))
   history_value<=history_memory[{history_read_column,history_band}];
  else history_value<=0;
  if(rst_n && link_up && state==PUBLISH)begin
   spectrum_memory[{!spectrum_bank,publish_band}]<=bands[publish_band];
   if(write_history)history_memory[{history_write,publish_band}]<=bands[publish_band];
  end
 end

 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=CAPTURE;capture_index<=0;address_a<=0;address_b<=0;
   source_bank<=0;read_address<=0;
   twiddle_address<=0;stage<=0;group_base<=0;offset<=0;half_size<=1;
   ready<=0;frame_valid<=0;spectrum_bank<=0;history_write<=0;history_count<=0;
   history_frames<=0;publish_band<=0;scan_bin<=1;scan_band<=0;band_peak<=0;
   peak_band<=0;frame_peak_band<=0;
   peak_valid<=0;peak_bin<=0;peak_hz<=0;centroid_hz<=0;
   frame_max<=0;frame_peak_bin<=0;magnitude_sum<=0;weighted_sum<=0;
  end else if(!link_up)begin
   state<=CAPTURE;capture_index<=0;ready<=0;frame_valid<=0;
   source_bank<=0;
   spectrum_bank<=0;history_write<=0;history_count<=0;history_frames<=0;
   peak_band<=0;frame_peak_band<=0;
   peak_valid<=0;peak_bin<=0;peak_hz<=0;centroid_hz<=0;
   frame_max<=0;frame_peak_bin<=0;magnitude_sum<=0;weighted_sum<=0;
  end else begin
   frame_valid<=0;
   case(state)
    CAPTURE:if(sample_valid)begin captured<=sample;state<=WINDOW;end
    WINDOW:begin window_product<=captured*window_value;state<=STORE;end
    STORE:begin
     if(capture_index==1023)begin
      stage<=0;group_base<=0;offset<=0;half_size<=1;source_bank<=0;state<=SETUP;
     end else begin capture_index<=capture_index+1'b1;state<=CAPTURE;end
    end
    SETUP:begin
     address_a<=group_base+offset;address_b<=group_base+offset+half_size;
     read_address<=group_base+offset;
     twiddle_address<=offset<<(9-stage);state<=READ_A;
    end
    READ_A:begin read_address<=address_b;state<=READ_B;end
    READ_B:begin saved_ar<=qa_r;saved_ai<=qa_i;state<=MULT;end
    MULT:begin
     rr<=qa_r*twiddle_real;ii<=qa_i*twiddle_imag;
     ri<=qa_r*twiddle_imag;ir<=qa_i*twiddle_real;state<=ROTATE;
    end
    ROTATE:begin rotated_r<=rotation_real>>>15;rotated_i<=rotation_imag>>>15;state<=SUM;end
    SUM:begin
     sum_r<=sum_real>>>1;sum_i<=sum_imag>>>1;
     diff_r<=difference_real>>>1;diff_i<=difference_imag>>>1;state<=WRITE_A;
    end
    WRITE_A:state<=WRITE_B;
    WRITE_B:begin
     state<=SETUP;
     if({1'b0,offset}+11'd1<half_size)offset<=offset+1'b1;
     else begin
      offset<=0;
      if(next_group<1024)group_base<=next_group[9:0];
      else if(stage<9)begin
       stage<=stage+1'b1;half_size<=half_size<<1;group_base<=0;source_bank<=!source_bank;
      end else begin
       source_bank<=!source_bank;scan_bin<=1;scan_band<=0;band_peak<=0;state<=SCAN_SET;
       frame_max<=0;frame_peak_band<=0;frame_peak_bin<=0;magnitude_sum<=0;weighted_sum<=0;
      end
     end
    end
    SCAN_SET:begin read_address<=scan_bin;state<=SCAN_READ;end
    SCAN_READ:state<=SCAN_MAG;
    SCAN_MAG:begin
     magnitude_registered<=magnitude;weighted_registered<=scan_bin*magnitude;state<=SCAN_ACC;
    end
    SCAN_ACC:begin
     magnitude_sum<=magnitude_sum+{10'd0,magnitude_registered};
     weighted_sum<=weighted_sum+{9'd0,weighted_registered};
     if(magnitude_registered>frame_max)begin
      frame_max<=magnitude_registered;frame_peak_bin<=scan_bin;frame_peak_band<=scan_band;
     end
     if(scan_bin+10'd1==band_end(scan_band))begin
      display_peak<=next_peak;band_peak<=0;state<=SCAN_LOG;
     end else begin
      band_peak<=next_peak;scan_bin<=scan_bin+1'b1;state<=SCAN_SET;
     end
    end
    SCAN_LOG:begin
     display_log_code<=log_code(display_peak);display_floor<=display_peak<16;
     state<=SCAN_SCALE;
    end
    SCAN_SCALE:begin
     display_scaled<=(({2'b0,display_log_code}-9'd16)*9'd7)>>2;
     state<=SCAN_LEVEL;
    end
    SCAN_LEVEL:begin
     // Suppress the same quantization floor and retain the display curve.
     bands[scan_band]<=display_floor ? 6'd0 :
                       display_scaled>63 ? 6'd63 : display_scaled[5:0];
     scan_band<=scan_band+1'b1;
     if(scan_bin==511)begin publish_band<=0;state<=CENTROID_START;end
     else begin scan_bin<=scan_bin+1'b1;state<=SCAN_SET;end
    end
    CENTROID_START:begin
     // Magnitude-weighted centroid (L1 bin magnitude), not power centroid.
     // Native 96 kHz / 1024 = 375/4 Hz per FFT bin. Preserve fractional bins
     // through the weighted sum before the final integer-Hz division.
     centroid_dividend<=({12'd0,weighted_sum}*48'd375)>>2;
     centroid_quotient<=0;centroid_remainder<=0;centroid_step<=0;state<=CENTROID_DIV;
    end
    CENTROID_DIV:begin
     centroid_dividend<=centroid_dividend<<1;centroid_quotient<=centroid_next;
     centroid_remainder<=centroid_take ? centroid_shift-{1'b0,magnitude_sum} : centroid_shift;
     centroid_step<=centroid_step+1'b1;
     if(centroid_step==47)begin
      centroid_hz<=frame_max<16 || magnitude_sum==0 ? 16'd0 : centroid_next[15:0];
      state<=PUBLISH;
     end
    end
    PUBLISH:begin
     publish_band<=publish_band+1'b1;
     if(publish_band==31)begin
      peak_band<=frame_peak_band;peak_bin<=frame_peak_bin;peak_valid<=frame_max>=16;
      peak_hz<=frame_max<16 ? 16'd0 : ({22'd0,frame_peak_bin}*32'd375)>>2;
      spectrum_bank<=!spectrum_bank;ready<=1;frame_valid<=1;
      if(write_history)begin
       history_frames<=0;history_write<=history_write+1'b1;
       if(history_count<64)history_count<=history_count+1'b1;
      end else history_frames<=history_frames+1'b1;
      capture_index<=0;state<=CAPTURE;
     end
    end
    default:state<=CAPTURE;
   endcase
  end
 end
endmodule
