`include "params.vh"
`include "font_3x5.vh"
`include "pixel_coverage.vh"
// Five stages after raster entry; native font and PCM-driven visualizations.
module ui_navigation_renderer(
 input wire clk,rst_n,
 input wire [13:0] in_x,in_y,
 input wire [1:0] view,
 input wire [7:0] settings_section_id,
 input wire show_diagnostics,usb_connected,usb_error,
 input wire [27:0] macro_values,
 input wire audio_sample_valid,
 input wire signed [15:0] audio_sample,
 input wire signed [15:0] audio_right_sample,
 input wire audio_stereo_valid,
 input wire audio_link_up,
 output reg out_hit,
 output reg [23:0] out_rgb
);
 // Page state changes only in vertical blank. A preserved local text copy
 // isolates glyph selection from distant touch/menu control decode.
 reg [1:0] text_view /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=16 */;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)text_view<=0;else text_view<=view;
 // USB host state originates at clk_usb. Synchronize its two status bits
 // before they enter the pixel-domain text rectangle and character logic.
 reg text_usb_connected_meta,text_usb_error_meta /* synthesis syn_preserve=1 syn_keep=1 */;
 reg text_usb_connected,text_usb_error /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=16 */;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   text_usb_connected_meta<=0;text_usb_connected<=0;text_usb_error_meta<=0;text_usb_error<=0;
  end else begin
   text_usb_connected_meta<=usb_connected;text_usb_connected<=text_usb_connected_meta;
   text_usb_error_meta<=usb_error;text_usb_error<=text_usb_error_meta;
  end
 end
 `include "navigation_font_hd.vh"
 reg hit;reg [23:0] bg;
 reg [1:0] macro_row;
 reg macro_number;
 reg [6:0] number;
 reg [5:0] number_char;
 wire waveform_ready;

 reg [4:0] spectrum_address0,history_band0;
 reg [5:0] history_column0;
 reg [12:0] phase_address0;
 wire [5:0] spectrum_value,history_value;
 wire spectrum_ready,phase_ready,phase_pixel;
 wire [4:0] spectrum_peak_band;
 wire spectrum_peak_valid,spectrum_frame_valid;
 wire [9:0] spectrum_peak_bin;
 wire [15:0] spectrum_peak_hz,spectrum_centroid_hz;
 wire metrics_ready,metrics_frame_valid,metrics_corr_valid;
 wire [15:0] metrics_rms_l,metrics_rms_r,metrics_peak_l,metrics_peak_r,metrics_peak_hold;
 wire signed [11:0] metrics_rms_db,metrics_peak_db,metrics_hold_db;
 wire [11:0] metrics_crest;
 wire signed [7:0] metrics_corr,metrics_balance;
 wire [5:0] metrics_clip;
 wire [3:0] metrics_transient;
 `include "navigation_labels.vh"
 audio_pcm_metrics u_metrics(.clk(clk),.rst_n(rst_n),.link_up(audio_link_up),
  .pair_valid(audio_stereo_valid),.left_sample(audio_sample),.right_sample(audio_right_sample),
  .ready(metrics_ready),.frame_valid(metrics_frame_valid),.rms_left(metrics_rms_l),.rms_right(metrics_rms_r),
  .peak_left(metrics_peak_l),.peak_right(metrics_peak_r),.peak_hold(metrics_peak_hold),
  .rms_db10(metrics_rms_db),.peak_db10(metrics_peak_db),.hold_db10(metrics_hold_db),.crest_db10(metrics_crest),
  .correlation(metrics_corr),.balance(metrics_balance),.correlation_valid(metrics_corr_valid),
  .clip_hold(metrics_clip),.transient_hold(metrics_transient));
 audio_fft_analyzer u_spectrum(.clk(clk),.rst_n(rst_n),.link_up(audio_link_up),
  .sample_valid(audio_sample_valid),.sample(audio_sample),
  .spectrum_address(spectrum_address0),.spectrum_value(spectrum_value),
  .history_column(history_column0),.history_band(history_band0),
  .history_value(history_value),.ready(spectrum_ready),.frame_valid(spectrum_frame_valid),
  .peak_band(spectrum_peak_band),.peak_valid(spectrum_peak_valid),.peak_bin(spectrum_peak_bin),
  .peak_hz(spectrum_peak_hz),.centroid_hz(spectrum_centroid_hz));
 audio_phase_plot u_phase(.clk(clk),.rst_n(rst_n),.link_up(audio_link_up),
  .pair_valid(audio_stereo_valid),.left_sample(audio_sample),.right_sample(audio_right_sample),
  .read_address(phase_address0),.pixel(phase_pixel),.ready(phase_ready));

 // Convert seven changing values in parallel, one binary bit per clock.
 // The raster only selects precomputed digit nibbles; no / or log in pixels.
 function [19:0] decimal_step;
  input [19:0] digits;input bit_value;
  integer d;reg [19:0] adjusted;
  begin
   adjusted=digits;
   for(d=0;d<5;d=d+1)if(digits[d*4+:4]>=5)adjusted[d*4+:4]=digits[d*4+:4]+4'd3;
   decimal_step={adjusted[18:0],bit_value};
  end
 endfunction
 reg [16:0] decimal_binary[0:6];
 reg [19:0] decimal_work[0:6],audio_digits[0:6];
 reg decimal_busy;
 reg [4:0] decimal_bit;
 reg corr_negative,bal_negative,corr_pending_sign,bal_pending_sign;
 reg [7:0] peak_width,rms_width,hold_width,crest_width;
 reg [13:0] correlation_x;
 reg [12:0] energy_radius2;
 integer decimal_index;
 wire [15:0] energy_rms=metrics_rms_l>metrics_rms_r ? metrics_rms_l : metrics_rms_r;
 wire [6:0] energy_radius=7'd8+{1'b0,energy_rms[15:10]};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   decimal_busy<=0;decimal_bit<=0;corr_negative<=0;bal_negative<=0;
   peak_width<=0;rms_width<=0;hold_width<=0;crest_width<=0;correlation_x<=1058;energy_radius2<=64;
   for(decimal_index=0;decimal_index<7;decimal_index=decimal_index+1)audio_digits[decimal_index]<=0;
  end else if(!audio_link_up)begin
   decimal_busy<=0;peak_width<=0;rms_width<=0;hold_width<=0;crest_width<=0;
   correlation_x<=1058;energy_radius2<=64;corr_negative<=0;bal_negative<=0;
   for(decimal_index=0;decimal_index<7;decimal_index=decimal_index+1)audio_digits[decimal_index]<=0;
  end else begin
   if(metrics_frame_valid)begin
    peak_width<=(12'sd960+metrics_peak_db)/12'd6;
    rms_width<=(12'sd960+metrics_rms_db)/12'd6;
    hold_width<=metrics_hold_db>=0 ? 8'd159 : (12'sd960+metrics_hold_db)/12'd6;
    crest_width<=metrics_crest>=240 ? 8'd160 : (metrics_crest*12'd2)/12'd3;
    correlation_x<=32'sd1058+($signed(metrics_corr)*32'sd126)/32'sd100;
    energy_radius2<=energy_radius*energy_radius;
   end
   if(!decimal_busy && (metrics_frame_valid || spectrum_frame_valid))begin
    decimal_busy<=1;decimal_bit<=0;
    decimal_binary[0]<=-metrics_rms_db;decimal_binary[1]<=-metrics_peak_db;
    decimal_binary[2]<=metrics_crest;
    decimal_binary[3]<=spectrum_peak_hz;decimal_binary[4]<=spectrum_centroid_hz;
    decimal_binary[5]<=metrics_corr[7] ? -metrics_corr : metrics_corr;
    decimal_binary[6]<=metrics_balance[7] ? -metrics_balance : metrics_balance;
    corr_pending_sign<=metrics_corr[7];bal_pending_sign<=metrics_balance[7];
    for(decimal_index=0;decimal_index<7;decimal_index=decimal_index+1)decimal_work[decimal_index]<=0;
   end else if(decimal_busy)begin
    decimal_bit<=decimal_bit+1'b1;
    for(decimal_index=0;decimal_index<7;decimal_index=decimal_index+1)begin
     decimal_work[decimal_index]<=decimal_step(decimal_work[decimal_index],decimal_binary[decimal_index][16]);
     decimal_binary[decimal_index]<=decimal_binary[decimal_index]<<1;
     if(decimal_bit==16)audio_digits[decimal_index]<=decimal_step(decimal_work[decimal_index],decimal_binary[decimal_index][16]);
    end
    if(decimal_bit==16)begin
     decimal_busy<=0;corr_negative<=corr_pending_sign;bal_negative<=bal_pending_sign;
    end
   end
  end
 end

 wire master_hole=view==0 && in_x>=1140 && in_x<=1230 && in_y<44;
 wire [23:0] tile_color[0:5];
 wire [23:0] tile_demo_color[0:5];
 wire [5:0] tile_demo_hit;
 wire [5:0] tile_hit;
 genvar tile;
 generate for(tile=0;tile<6;tile=tile+1)begin: visual_tile
  localparam X=24+(tile%3)*418,Y=96+(tile/3)*296;
  wire inside_tile=in_x>=X && in_x<=X+396 && in_y>=Y && in_y<=Y+278;
  wire border=in_x==X || in_x==X+396 || in_y==Y || in_y==Y+278;
  wire plot=in_y>=Y+72 && in_y<Y+232 && in_x>=X+16 && in_x<X+380;
  wire axis=in_x==X+198 || in_y==Y+140;
  wire grid=in_x[5:0]==0 || in_y[5:0]==0;
  wire [8:0] gx=in_x-(X+16);
  wire [7:0] gy=in_y-(Y+80);
  wire graph_area=plot && in_y>=Y+80 && in_y<Y+232;
  if(tile==0)begin: live_overview
   // The measured energy ring is pipelined below with the other RAM plots.
   wire channel_l=audio_link_up&&metrics_ready&&metrics_rms_l>=8;
   wire channel_r=audio_link_up&&metrics_ready&&metrics_rms_r>=8;
   wire lamp_l=in_x>=262&&in_x<278&&in_y>=296&&in_y<308;
   wire lamp_r=in_x>=342&&in_x<358&&in_y>=296&&in_y<308;
   assign tile_demo_hit[tile]=lamp_l||lamp_r;
   assign tile_demo_color[tile]=(lamp_l&&channel_l)||(lamp_r&&channel_r) ? 24'h61DED1 : 24'h26394B;
  end else if(tile==1)begin: live_waveform
   wire live_wave=audio_link_up&&waveform_ready;
   wire [6:0] held_amplitude=metrics_peak_hold[15:9];
   wire hold_line=live_wave&&metrics_ready&&metrics_peak_hold!=0&&in_x>=496&&in_x<752&&
       in_x[3:0]<4&&(in_y==14'd248-held_amplitude||in_y==14'd248+held_amplitude);
   // The live trace is composed after the registered RAM read below.
   assign tile_demo_hit[tile]=hold_line||(graph_area && !live_wave && gy>=8'd70 && gy<=8'd74);
   assign tile_demo_color[tile]=hold_line ? 24'hF5D36A : 24'hD5AD78;
  end else if(tile==2)begin: live_phase
   wire strip=in_x>=932&&in_x<1186&&in_y>=322&&in_y<330;
   wire cursor=metrics_corr_valid&&audio_link_up&&in_x>=correlation_x&&in_x<correlation_x+4;
   assign tile_demo_hit[tile]=strip;
   assign tile_demo_color[tile]=cursor ? (metrics_corr<0 ? 24'hE87565 : 24'h65CDA4) : 24'h26394B;
  end else if(tile==3)begin: live_spectrum
   assign tile_demo_hit[tile]=1'b0;
   assign tile_demo_color[tile]=24'h65CDA4;
  end else if(tile==4)begin: live_spectrogram
   wire legend=in_x>=512&&in_x<768&&in_y>=618&&in_y<626;
   assign tile_demo_hit[tile]=legend;
   assign tile_demo_color[tile]=heat_color((in_x-14'd512)>>2);
  end else begin: live_levels
   wire bar1=in_y>=490&&in_y<506&&in_x>=1064&&in_x<1224;
   wire bar2=in_y>=530&&in_y<546&&in_x>=1064&&in_x<1224;
   wire bar3=in_y>=570&&in_y<586&&in_x>=1064&&in_x<1224;
   wire [8:0] level_x=in_x-1064;
   wire fill1=bar1&&audio_link_up&&metrics_ready&&level_x<{1'b0,peak_width};
   wire fill2=bar2&&audio_link_up&&metrics_ready&&level_x<{1'b0,rms_width};
   wire fill3=bar3&&audio_link_up&&metrics_ready&&level_x<{1'b0,crest_width};
   wire hold_marker=bar1&&audio_link_up&&metrics_ready&&level_x=={1'b0,hold_width};
   assign tile_demo_hit[tile]=graph_area&&(bar1||bar2||bar3);
   assign tile_demo_color[tile]=hold_marker ? 24'hFFFFFF : fill3 ? 24'hF5D36A : fill2 ? 24'h61DED1 : fill1 ? 24'h65CDA4 : 24'h26394B;
  end
  assign tile_hit[tile]=inside_tile;
  assign tile_color[tile]=!inside_tile ? 24'd0 : border ? 24'h35495F :
   in_y<Y+48 ? 24'h1B2B3C : plot ? (tile_demo_hit[tile] ? tile_demo_color[tile] : (axis ? 24'h26394B : grid ? 24'h152331 : 24'h0B131D)) : 24'h111B28;
 end endgenerate
 wire [23:0] visual_bg=(|tile_hit) ? tile_color[0]|tile_color[1]|tile_color[2]|tile_color[3]|tile_color[4]|tile_color[5] : 24'h101318;
 reg [11:0] bcd[0:3];
 genvar n;
 generate for(n=0;n<4;n=n+1)begin: decimal_cache
  wire [6:0] value=macro_values[n*7+:7];
  wire [3:0] hundreds=value/7'd100,tens=(value%7'd100)/7'd10,ones=value%7'd10;
  always @(posedge clk)bcd[n]<={hundreds,tens,ones};
 end endgenerate
 always @(*)begin
  hit=(in_y<44 && !master_hole) || view!=0;
  bg=24'h101318;
  if(in_y<44)begin
   bg=24'h151D29;
   if(in_y==42)bg=24'h2C94A8;
   if(in_x>=20 && in_x<=40 && (in_y==14 || in_y==19 || in_y==24 || in_y==29))bg=24'hC4D7E8;
   if((view==0 && in_x>=128 && in_x<320) ||
      (view==1 && in_x>=336 && in_x<576) ||
      (view==2 && in_x>=592 && in_x<800))bg=24'h204152;
  end else if(view==1)begin
   // All six PCM views are live. The first tile is an audio overview derived
   // from the same measured stream as the waveform and level meters.
   bg=visual_bg;
  end else if(view==2 && settings_section_id==8'd1)begin
   if(in_x>=32 && in_x<=680 && in_y>=120 && in_y<=616)bg=24'h142030;
   if(in_x>=712 && in_x<=1248 && in_y>=120 && in_y<=616)bg=24'h142030;
   if(in_x>=240 && in_x<=640 && in_y>=232 && in_y<=480)begin
    if((in_y-232)%64<=56)bg=24'h22374C;
    if(in_x>304 && in_x<576)bg=24'h101A27;
   end
   if(in_x>=880 && in_x<=1216 && in_y>=520 && in_y<=584)
    bg=show_diagnostics ? 24'h205148 : 24'h25384D;
  end else if(view==3)begin
   if(in_y>=160 && in_y<=480)begin
    if((in_x>=48 && in_x<=416)||(in_x>=456 && in_x<=824)||(in_x>=864 && in_x<=1232))begin
     bg=24'h17283B;
     if(in_y==160 || in_y==480)bg=24'h3E8495;
     if(in_y>=280 && in_y<=336 && in_x[5:0]>=16 && in_x[5:0]<=48)bg=24'h25465C;
    end
   end
  end else if(view==2)begin
   bg=24'h101820;
   if(in_x>=32&&in_x<=680&&in_y>=120&&in_y<=616)bg=24'h142030;
   if(in_x>=712&&in_x<=1248&&in_y>=120&&in_y<=616)bg=24'h142030;
   if(in_x==32||in_x==680||in_x==712||in_x==1248||in_y==120||in_y==616)bg=24'h35495F;
   if(settings_section_id!=8'd1 && in_x>=736 && in_x<=1216 && in_y>=196 && in_y<=552)bg=24'h192A3B;
   if(in_x>=712&&in_x<=1248&&in_y>=120&&in_y<=616&&
      (in_x==712||in_x==1248||in_y==120||in_y==616))bg=24'h35495F;
  end
  if(view==2 && in_y>=88 && in_y<120)begin
   bg=24'h1A2735;
   if((settings_section_id==8'd1&&in_x>=32&&in_x<336)||(settings_section_id==8'd2&&in_x>=336&&in_x<632)||
      (settings_section_id==8'd3&&in_x>=632&&in_x<928)||(settings_section_id==8'd4&&in_x>=928&&in_x<=1248))bg=24'h285064;
   if(in_y==119)bg=24'h347B90;
  end
  macro_row=(in_y-248)>>6;
  macro_number=view==2 && settings_section_id==8'd1 && in_y>=248 && in_y<460 && ((in_y-248)&63)<16 && in_x>=416 && in_x<464;
  case(macro_row)
   0:number=macro_values[0+:7];1:number=macro_values[7+:7];
   2:number=macro_values[14+:7];default:number=macro_values[21+:7];
  endcase
  case((in_x-416)>>4)
   0:number_char=number>=100 ? `CH_1 : `CH_SPACE;
   1:number_char=`CH_0+bcd[macro_row][7:4];
   default:number_char=`CH_0+bcd[macro_row][3:0];
  endcase
 end
 reg h0,h1,h2,h3;
 reg [23:0] b0,b1,b2,b3,fg0,fg1,fg2,fg3;
 reg [6:0] id0 /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=16 */;
 reg [5:0] col0 /* synthesis syn_preserve=1 syn_keep=1 syn_maxfan=16 */;
 reg [5:0] rom_ch1,digit1;
 reg number1;
 wire [5:0] ch1=number1 ? digit1 : rom_ch1;
 // Unconditional synchronous read lets Gowin map the character table to
 // block ROM, instead of another deep combinational case decoder.
 always @(posedge clk)rom_ch1<=navigation_char_rom[{id0,col0}];
 reg [3:0] rx0;reg [4:0] ry0;
 reg large0;
 reg tv0,tv1;reg [5:0] digit0;
 reg number0;
 reg audio_number;
 reg [5:0] audio_number_char;
 function [5:0] audio_digit;
  input [19:0] digits;input [2:0] place;input valid;
  reg [19:0] shifted;
  begin shifted=digits>>(place*4);audio_digit=valid ? `CH_0+shifted[3:0] : `CH_MINUS;end
 endfunction
 always @* begin
  audio_number=0;audio_number_char=`CH_SPACE;
  case(id0)
   NAV_OV_RMS,NAV_OV_PEAK:begin
    if(col0==5 || col0==6 || col0==8)begin
     audio_number=1;audio_number_char=audio_digit(audio_digits[id0==NAV_OV_RMS ? 0 : 1],
      col0==5 ? 3'd2 : col0==6 ? 3'd1 : 3'd0,metrics_ready&&audio_link_up);
    end
   end
   NAV_LEVEL_PEAK,NAV_LEVEL_RMS,NAV_LEVEL_CREST:begin
    if(col0==3 || col0==4 || col0==6)begin
     audio_number=1;audio_number_char=audio_digit(audio_digits[id0==NAV_LEVEL_PEAK ? 1 : id0==NAV_LEVEL_RMS ? 0 : 2],
      col0==3 ? 3'd2 : col0==4 ? 3'd1 : 3'd0,metrics_ready&&audio_link_up);
    end
   end
   NAV_OV_HZ:if(col0<5)begin
    audio_number=1;audio_number_char=audio_digit(audio_digits[3],3'd4-col0[2:0],audio_link_up&&spectrum_peak_valid);
   end
   NAV_PEAK_HZ:if(col0>=5 && col0<=9)begin
    audio_number=1;audio_number_char=audio_digit(audio_digits[3],3'd1-col0[2:0],audio_link_up&&spectrum_peak_valid);
   end
   NAV_CENTROID:if(col0>=7 && col0<=11)begin
    audio_number=1;audio_number_char=audio_digit(audio_digits[4],3'd3-col0[2:0],audio_link_up&&spectrum_peak_valid);
   end
   NAV_STEREO:begin
    if(col0==5 || col0==16)begin
     audio_number=1;
     audio_number_char=!(audio_link_up&&metrics_ready) || (col0==5&&!metrics_corr_valid) ? `CH_MINUS :
      (col0==5 ? corr_negative : bal_negative) ? `CH_MINUS : `CH_PLUS;
    end else if(col0>=6&&col0<=8)begin
     audio_number=1;audio_number_char=audio_digit(audio_digits[5],3'd0-(col0[2:0]),
       audio_link_up&&metrics_corr_valid);
    end else if(col0>=17&&col0<=19)begin
     audio_number=1;audio_number_char=audio_digit(audio_digits[6],3'd3-col0[2:0],
       audio_link_up&&metrics_ready);
    end
   end
  endcase
 end
 reg [2:0] glyph_x1,glyph_x2;
 reg [3:0] glyph_y1;
 reg [13:0] glyph_row2;
 reg glyph_valid2;
 reg [1:0] coverage3;
 // Keep the verified 7x10 font and mapping, but split row lookup from
 // column selection. Blend moves into the existing output register:
 // address -> character/map -> glyph row -> coverage -> blended output.
 function [2:0] glyph_x;
  input heading;input [3:0] rx;
  begin
   if(heading)glyph_x=rx[3:1];
   else case(rx)
    0,1:glyph_x=0;2,3:glyph_x=1;4,5:glyph_x=2;6,7:glyph_x=3;
    8,9:glyph_x=4;10:glyph_x=5;default:glyph_x=6;
   endcase
  end
 endfunction
 function [3:0] glyph_y;
  input heading;input [4:0] ry;
  begin
   if(heading)glyph_y=ry[4:1];
   else case(ry)
    0,1:glyph_y=0;2,3:glyph_y=1;4:glyph_y=2;5,6:glyph_y=3;
    7:glyph_y=4;8,9:glyph_y=5;10:glyph_y=6;11,12:glyph_y=7;
    13:glyph_y=8;default:glyph_y=9;
   endcase
  end
 endfunction
 function [1:0] glyph_column;
  input [13:0] row_bits;input [2:0] column;
  begin case(column)
   0:glyph_column=row_bits[13:12];1:glyph_column=row_bits[11:10];
   2:glyph_column=row_bits[9:8];3:glyph_column=row_bits[7:6];
   4:glyph_column=row_bits[5:4];5:glyph_column=row_bits[3:2];
   6:glyph_column=row_bits[1:0];default:glyph_column=0;
  endcase end
 endfunction
 reg [6:0] wave_addr0;
 wire [7:0] wave_sample1,wave_previous1;
 reg [7:0] wave_gy0,wave_gy1;
 wire triggered_wave;
 audio_waveform_capture u_waveform(.clk(clk),.rst_n(rst_n),.link_up(audio_link_up),
  .sample_valid(audio_sample_valid),.sample(audio_sample),.read_address(wave_addr0),
  .plot_sample(wave_sample1),.plot_previous(wave_previous1),.ready(waveform_ready),
  .frame_valid(),.triggered(triggered_wave));
 reg wave_area0,wave_area1,wave_hit2;
 wire [7:0] wave_y1=8'd72-{wave_sample1[7],wave_sample1[7:1]};
 wire [7:0] wave_previous_y1=8'd72-{wave_previous1[7],wave_previous1[7:1]};
 wire [7:0] wave_low1=wave_y1<wave_previous_y1 ? wave_y1 : wave_previous_y1;
 wire [7:0] wave_high1=wave_y1>wave_previous_y1 ? wave_y1 : wave_previous_y1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin wave_area0<=0;wave_area1<=0;wave_hit2<=0;end
  else begin
   wave_area0<=view==1 && audio_link_up && waveform_ready &&
       in_x>=14'd496 && in_x<14'd752 && in_y>=14'd176 && in_y<14'd328;
   wave_area1<=wave_area0;
   wave_hit2<=wave_area1 && ({1'b0,wave_gy1}+9'd2)>={1'b0,wave_low1} &&
       {1'b0,wave_gy1}<=({1'b0,wave_high1}+9'd2);
  end
 end
 always @(posedge clk) begin
  // x=496 is column zero in the immutable displayed capture bank.
  wave_addr0<=in_x[7:1]-7'd120;
  wave_gy0<=in_y[7:0]-8'd176;wave_gy1<=wave_gy0;
 end

 // Stage 0: raster -> RAM addresses; stage 1: synchronous RAM output;
 // stage 2: coverage/color; merge alongside the waveform at stage 3.
 // No extra video pipeline clocks and no asynchronous RAM lookup.
 wire [13:0] phase_dx=in_x-14'd930,phase_dy=in_y-14'd184;
 wire [13:0] spectrum_dx=in_x-14'd94;
 wire [13:0] history_dx=in_x-14'd512,history_dy=in_y-14'd480;
 reg phase_area0,phase_area1,phase_hit2;
 reg spectrum_area0,spectrum_area1,spectrum_hit2;
 reg spectrum_peak0,spectrum_peak1,spectrum_peak2;
 reg history_area0,history_area1,history_hit2;
 reg [7:0] spectrum_y0,spectrum_y1;
 reg [23:0] history_rgb2;
 wire signed [8:0] energy_dx=$signed({1'b0,in_x[7:0]})-9'sd140;
 wire signed [9:0] energy_dy=$signed({1'b0,in_y[8:0]})-10'sd248;
 reg [17:0] energy_x2_0,energy_y2_0;
 reg [18:0] energy_distance1;
 reg energy_area0,energy_area1,energy_hit2;
 reg [23:0] energy_rgb2;
 function [23:0] heat_color;
  input [5:0] level;
  begin case(level[5:3])
   0:heat_color=24'h17344D;1:heat_color=24'h245C83;
   2:heat_color=24'h368DAC;3:heat_color=24'h4ABCB9;
   4:heat_color=24'h70D6A2;5:heat_color=24'hD6CF79;
   6:heat_color=24'hE7A466;default:heat_color=24'hEF7060;
  endcase end
 endfunction
 always @(posedge clk)begin
  energy_x2_0<=energy_dx*energy_dx;energy_y2_0<=energy_dy*energy_dy;
  energy_distance1<={1'b0,energy_x2_0}+{1'b0,energy_y2_0};
  energy_rgb2<=energy_distance1<=energy_radius2 ? 24'h61DED1 :
    metrics_clip!=0 ? 24'hE87565 : metrics_transient!=0 ? 24'hF5D36A : 24'h368DAC;
  phase_address0<={phase_dy[6:1],phase_dx[7:1]};
  spectrum_address0<=spectrum_dx[7:3];
  history_column0<=history_dx[7:2];history_band0<=5'd31-history_dy[6:2];
  spectrum_y0<=14'd616-in_y;spectrum_y1<=spectrum_y0;
  history_rgb2<=heat_color(history_value);
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   energy_area0<=0;energy_area1<=0;energy_hit2<=0;
   phase_area0<=0;phase_area1<=0;phase_hit2<=0;
   spectrum_area0<=0;spectrum_area1<=0;spectrum_hit2<=0;
   spectrum_peak0<=0;spectrum_peak1<=0;spectrum_peak2<=0;
   history_area0<=0;history_area1<=0;history_hit2<=0;
  end else begin
   energy_area0<=view==1&&audio_link_up&&metrics_ready&&in_x>=64&&in_x<216&&in_y>=184&&in_y<312;
   energy_area1<=energy_area0;
   energy_hit2<=energy_area1 && ((energy_distance1>=2809&&energy_distance1<=3600)||
     (energy_rms>=8&&energy_distance1<=energy_radius2));
   phase_area0<=view==1 && audio_link_up && phase_ready &&
     in_x>=930 && in_x<1186 && in_y>=184 && in_y<312;
   phase_area1<=phase_area0;phase_hit2<=phase_area1 && phase_pixel;
   spectrum_area0<=view==1 && audio_link_up && spectrum_ready &&
     in_x>=94 && in_x<350 && spectrum_dx[2:0]<6 && in_y>=480 && in_y<=616;
   spectrum_area1<=spectrum_area0;
   spectrum_hit2<=spectrum_area1 && spectrum_value!=0 &&
     {1'b0,spectrum_y1}<{2'b00,spectrum_value,1'b0};
   spectrum_peak0<=view==1 && audio_link_up && spectrum_ready && spectrum_peak_valid &&
     in_x>=94 && in_x<350 && spectrum_dx[2:0]<6 &&
     in_y>=480 && in_y<=616 &&
     spectrum_dx[7:3]==spectrum_peak_band;
   spectrum_peak1<=spectrum_peak0;
   // Highlight only the measured bar. Silent frames have no winner marker.
   spectrum_peak2<=spectrum_peak1 && spectrum_value!=0 &&
     {1'b0,spectrum_y1}<{2'b00,spectrum_value,1'b0};
   history_area0<=view==1 && audio_link_up && spectrum_ready &&
     in_x>=512 && in_x<768 && in_y>=480 && in_y<608;
   history_area1<=history_area0;history_hit2<=history_area1 && history_value!=0;
  end
 end
 function [7:0] demo_wave;input [4:0] phase;begin case(phase)
 0:demo_wave=72;1:demo_wave=84;2:demo_wave=96;3:demo_wave=105;4:demo_wave=111;5:demo_wave=117;6:demo_wave=120;7:demo_wave=121;
 8:demo_wave=121;9:demo_wave=120;10:demo_wave=117;11:demo_wave=111;12:demo_wave=105;13:demo_wave=96;14:demo_wave=84;15:demo_wave=72;
 16:demo_wave=72;17:demo_wave=60;18:demo_wave=48;19:demo_wave=39;20:demo_wave=33;21:demo_wave=27;22:demo_wave=24;23:demo_wave=23;
 24:demo_wave=23;25:demo_wave=24;26:demo_wave=27;27:demo_wave=33;28:demo_wave=39;29:demo_wave=48;30:demo_wave=60;default:demo_wave=72;
 endcase end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   h0<=0;h1<=0;h2<=0;h3<=0;out_hit<=0;out_rgb<=0;
   glyph_valid2<=0;coverage3<=0;
  end
  else begin
   h0<=hit;b0<=bg;fg0<=text_color;id0<=text_id;col0<=text_col;
   tv0<=text_valid||macro_number;number0<=macro_number;digit0<=number_char;
   rx0<=macro_number ? in_x[3:0] : text_rx;ry0<=macro_number ? ((in_y-248)&63) : text_ry;
   large0<=!macro_number && text_large;
   h1<=h0;b1<=b0;fg1<=fg0;
   tv1<=tv0 && (large0 ? (rx0<14 && ry0<20) : (rx0<12 && ry0<16));
   number1<=number0||audio_number;digit1<=number0 ? digit0 : audio_number_char;
   glyph_x1<=glyph_x(large0,rx0);glyph_y1<=glyph_y(large0,ry0);
   h2<=h1;b2<=b1;fg2<=fg1;
   glyph_row2<=get_font_7x10_row(ch1,glyph_y1);glyph_x2<=glyph_x1;glyph_valid2<=tv1;
   h3<=h2;b3<=energy_hit2 ? energy_rgb2 : wave_hit2 ? 24'h61DED1 : phase_hit2 ? 24'h67CDE0 :
       spectrum_peak2 ? 24'hF5D36A : spectrum_hit2 ? 24'h65CDA4 :
       history_hit2 ? history_rgb2 : b2;fg3<=fg2;
   coverage3<=glyph_valid2 ? glyph_column(glyph_row2,glyph_x2) : 0;
   out_hit<=h3;out_rgb<=blend_rgb_q4(fg3,b3,font_alpha_q4(coverage3));
  end
 end
endmodule
