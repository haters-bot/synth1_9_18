// Stereo PCM statistics over non-overlapping 1024-pair (10.667 ms at 96 kHz)
// windows. RMS is floor(sqrt(mean(x*x))). Correlation is the cosine of L/R
// vectors, NOT centered Pearson correlation; DC is deliberately retained.
// dBFS uses 32768 as full-scale amplitude, -96.0 dBFS as the display floor.
// Sequential sqrt and division keep arithmetic out of the raster path.
module audio_pcm_metrics(
 input wire clk,rst_n,link_up,pair_valid,
 input wire signed [15:0] left_sample,right_sample,
 output reg ready,frame_valid,
 output reg [15:0] rms_left,rms_right,peak_left,peak_right,peak_hold,
 output reg signed [11:0] rms_db10,peak_db10,hold_db10,
 output reg [11:0] crest_db10,
 output reg signed [7:0] correlation,balance,
 output reg correlation_valid,
 output reg [5:0] clip_hold,
 output reg [3:0] transient_hold
);
 reg product_valid;
 reg [31:0] square_l,square_r;
 reg signed [31:0] product_lr;
 reg [15:0] abs_l,abs_r;
 reg [9:0] count;
 reg [40:0] sum_l,sum_r;
 reg signed [41:0] sum_lr;
 reg [15:0] peak_l_acc,peak_r_acc;
 wire [40:0] next_l=sum_l+{9'd0,square_l};
 wire [40:0] next_r=sum_r+{9'd0,square_r};
 wire signed [41:0] next_lr=sum_lr+{{10{product_lr[31]}},product_lr};
 wire [15:0] next_peak_l=abs_l>peak_l_acc ? abs_l : peak_l_acc;
 wire [15:0] next_peak_r=abs_r>peak_r_acc ? abs_r : peak_r_acc;
 reg snapshot;
 reg [31:0] mean_l,mean_r;
 reg signed [31:0] mean_lr;
 reg [15:0] frame_peak_l,frame_peak_r;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   product_valid<=0;count<=0;sum_l<=0;sum_r<=0;sum_lr<=0;
   peak_l_acc<=0;peak_r_acc<=0;snapshot<=0;
  end else if(!link_up)begin
   product_valid<=0;count<=0;sum_l<=0;sum_r<=0;sum_lr<=0;
   peak_l_acc<=0;peak_r_acc<=0;snapshot<=0;
  end else begin
   product_valid<=pair_valid;snapshot<=0;
   if(pair_valid)begin
    square_l<=$signed(left_sample)*$signed(left_sample);
    square_r<=$signed(right_sample)*$signed(right_sample);
    product_lr<=left_sample*right_sample;
    abs_l<=left_sample[15] ? (~left_sample+16'd1) : left_sample;
    abs_r<=right_sample[15] ? (~right_sample+16'd1) : right_sample;
   end
   if(product_valid)begin
    count<=count+1'b1;
    if(count==1023)begin
     mean_l<={1'b0,next_l[40:10]};mean_r<={1'b0,next_r[40:10]};
     mean_lr<=next_lr>>>10;
     frame_peak_l<=next_peak_l;frame_peak_r<=next_peak_r;
     sum_l<=0;sum_r<=0;sum_lr<=0;peak_l_acc<=0;peak_r_acc<=0;snapshot<=1;
    end else begin
     sum_l<=next_l;sum_r<=next_r;sum_lr<=next_lr;
     peak_l_acc<=next_peak_l;peak_r_acc<=next_peak_r;
    end
   end
  end
 end

 // 20*log10(1+i/32), tenths of dB. Truncated mantissa gives <0.27 dB error.
 function [6:0] log_fraction;
  input [4:0] i;
  begin case(i)
   0:log_fraction=0;1:log_fraction=3;2:log_fraction=5;3:log_fraction=8;
   4:log_fraction=10;5:log_fraction=13;6:log_fraction=15;7:log_fraction=17;
   8:log_fraction=19;9:log_fraction=22;10:log_fraction=24;11:log_fraction=26;
   12:log_fraction=28;13:log_fraction=30;14:log_fraction=32;15:log_fraction=33;
   16:log_fraction=35;17:log_fraction=37;18:log_fraction=39;19:log_fraction=40;
   20:log_fraction=42;21:log_fraction=44;22:log_fraction=45;23:log_fraction=47;
   24:log_fraction=49;25:log_fraction=50;26:log_fraction=52;27:log_fraction=53;
   28:log_fraction=55;29:log_fraction=56;30:log_fraction=57;default:log_fraction=59;
  endcase end
 endfunction
 localparam IDLE=0,SQRT_L=1,SQRT_R=2,DENOM=3,CORR_START=4,
            DIVIDE=5,BALANCE_START=6,PUBLISH=7;
 reg [3:0] state;
 reg [4:0] sqrt_step;
 reg [31:0] radicand;
 reg [33:0] remainder;
 reg [15:0] root,tmp_l,tmp_r;
 wire [33:0] shifted_remainder={remainder[31:0],radicand[31:30]};
 wire [33:0] trial={16'd0,root,2'b01};
 wire take_bit=shifted_remainder>=trial;
 wire [15:0] next_root={root[14:0],take_bit};
 reg [31:0] denominator,divisor;
 reg [47:0] dividend,quotient;
 reg [32:0] div_remainder;
 reg [5:0] div_step;
 reg div_negative,div_balance;
 reg signed [7:0] tmp_correlation;
 wire [32:0] div_shift={div_remainder[31:0],dividend[47]};
 wire div_take=div_shift>={1'b0,divisor};
 wire [47:0] next_quotient={quotient[46:0],div_take};
 wire [7:0] bounded_quotient=next_quotient>100 ? 8'd100 : next_quotient[7:0];
 wire [16:0] rms_sum={1'b0,tmp_l}+{1'b0,tmp_r};
 wire [15:0] rms_difference=tmp_r>=tmp_l ? tmp_r-tmp_l : tmp_l-tmp_r;
 reg [15:0] tmp_peak_l,tmp_peak_r;
 reg signed [31:0] tmp_lr;
 reg [6:0] hold_count;
 wire [15:0] current_peak=tmp_peak_l>tmp_peak_r ? tmp_peak_l : tmp_peak_r;
 wire signed [11:0] current_peak_db,current_rms_db,current_hold_db;
 // Operands settle >96 cycles before PUBLISH (two sequential divisions).
 // Register each maximum selection before the three-stage priority encoder.
 // Two selection stages plus encoding finish without adding any capture gap.
 reg [15:0] peak_amplitude,rms_amplitude,held_amplitude;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin peak_amplitude<=0;rms_amplitude<=0;held_amplitude<=0;end
  else if(!link_up)begin peak_amplitude<=0;rms_amplitude<=0;held_amplitude<=0;end
  else begin
   peak_amplitude<=current_peak;
   rms_amplitude<=tmp_l>tmp_r ? tmp_l : tmp_r;
   held_amplitude<=peak_amplitude>=peak_hold ? peak_amplitude : peak_hold;
  end
 end
 audio_dbfs_encoder u_peak_db(.clk(clk),.amplitude(peak_amplitude),.db10(current_peak_db));
 audio_dbfs_encoder u_rms_db(.clk(clk),.amplitude(rms_amplitude),.db10(current_rms_db));
 audio_dbfs_encoder u_hold_db(.clk(clk),.amplitude(held_amplitude),.db10(current_hold_db));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;ready<=0;frame_valid<=0;rms_left<=0;rms_right<=0;
   peak_left<=0;peak_right<=0;peak_hold<=0;hold_count<=0;
   rms_db10<=-960;peak_db10<=-960;hold_db10<=-960;crest_db10<=0;
   correlation<=0;balance<=0;correlation_valid<=0;clip_hold<=0;transient_hold<=0;
  end else if(!link_up)begin
   state<=IDLE;ready<=0;frame_valid<=0;rms_left<=0;rms_right<=0;
   peak_left<=0;peak_right<=0;peak_hold<=0;hold_count<=0;
   rms_db10<=-960;peak_db10<=-960;hold_db10<=-960;crest_db10<=0;
   correlation<=0;balance<=0;correlation_valid<=0;clip_hold<=0;transient_hold<=0;
  end else begin
   frame_valid<=0;
   case(state)
    IDLE:if(snapshot)begin
     radicand<=mean_l;remainder<=0;root<=0;sqrt_step<=0;
     tmp_peak_l<=frame_peak_l;tmp_peak_r<=frame_peak_r;tmp_lr<=mean_lr;state<=SQRT_L;
    end
    SQRT_L,SQRT_R:begin
     root<=next_root;radicand<=radicand<<2;
     remainder<=take_bit ? shifted_remainder-trial : shifted_remainder;
     sqrt_step<=sqrt_step+1'b1;
     if(sqrt_step==15)begin
      if(state==SQRT_L)begin
       tmp_l<=next_root;radicand<=mean_r;remainder<=0;root<=0;sqrt_step<=0;state<=SQRT_R;
      end else begin tmp_r<=next_root;state<=DENOM;end
     end
    end
    DENOM:begin denominator<=tmp_l*tmp_r;state<=CORR_START;end
    CORR_START:begin
     divisor<=denominator;div_negative<=tmp_lr[31];div_balance<=0;
     dividend<=(tmp_lr[31] ? -$signed({{16{tmp_lr[31]}},tmp_lr}) : {16'd0,tmp_lr})*48'd100;
     quotient<=0;div_remainder<=0;div_step<=0;state<=DIVIDE;
    end
    DIVIDE:begin
     dividend<=dividend<<1;quotient<=next_quotient;
     div_remainder<=div_take ? div_shift-{1'b0,divisor} : div_shift;
     div_step<=div_step+1'b1;
     if(div_step==47)begin
      if(div_balance)begin
       balance<=divisor==0 ? 8'sd0 : div_negative ? -$signed(bounded_quotient) : $signed(bounded_quotient);
       state<=PUBLISH;
      end else begin
       tmp_correlation<=denominator==0 ? 8'sd0 : div_negative ? -$signed(bounded_quotient) : $signed(bounded_quotient);
       state<=BALANCE_START;
      end
     end
    end
    BALANCE_START:begin
     divisor<={15'd0,rms_sum};div_negative<=tmp_r<tmp_l;div_balance<=1;
     dividend<={32'd0,rms_difference}*48'd100;
     quotient<=0;div_remainder<=0;div_step<=0;state<=DIVIDE;
    end
    PUBLISH:begin
     ready<=1;frame_valid<=1;state<=IDLE;
     rms_left<=tmp_l;rms_right<=tmp_r;peak_left<=tmp_peak_l;peak_right<=tmp_peak_r;
     rms_db10<=current_rms_db;peak_db10<=current_peak_db;
     hold_db10<=current_hold_db;
     crest_db10<=current_peak==0 ? 12'd0 : current_peak_db-current_rms_db;
     correlation<=tmp_correlation;correlation_valid<=tmp_l>=8 && tmp_r>=8;
     if(current_peak>=peak_hold)begin peak_hold<=current_peak;hold_count<=94;end
     else if(hold_count!=0)hold_count<=hold_count-1'b1;
     else peak_hold<=peak_hold<128 ? current_peak : peak_hold-(peak_hold>>4);
     if(current_peak>=32752)clip_hold<=48;
     else if(clip_hold!=0)clip_hold<=clip_hold-1'b1;
     if(current_peak>512 && {1'b0,current_peak}>({1'b0,rms_left}<<1))transient_hold<=8;
     else if(transient_hold!=0)transient_hold<=transient_hold-1'b1;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule

// Leading-bit/mantissa decode -> two small ROMs -> signed sum. Constant
// exponent bases replace the old 32-bit multiply/divide in one cycle.
module audio_dbfs_encoder(input wire clk,input wire [15:0] amplitude,
 output reg signed [11:0] db10);
 reg [3:0] exponent0;
 reg [4:0] fraction0;
 reg zero0,zero1;
 reg signed [11:0] base1;
 reg [6:0] mantissa1;
 always @(posedge clk)begin
  zero0<=amplitude==0;zero1<=zero0;
  casez(amplitude)
   16'b1???????????????:begin exponent0<=15;fraction0<=amplitude[14:10];end
   16'b01??????????????:begin exponent0<=14;fraction0<=amplitude[13:9];end
   16'b001?????????????:begin exponent0<=13;fraction0<=amplitude[12:8];end
   16'b0001????????????:begin exponent0<=12;fraction0<=amplitude[11:7];end
   16'b00001???????????:begin exponent0<=11;fraction0<=amplitude[10:6];end
   16'b000001??????????:begin exponent0<=10;fraction0<=amplitude[9:5];end
   16'b0000001?????????:begin exponent0<=9;fraction0<=amplitude[8:4];end
   16'b00000001????????:begin exponent0<=8;fraction0<=amplitude[7:3];end
   16'b000000001???????:begin exponent0<=7;fraction0<=amplitude[6:2];end
   16'b0000000001??????:begin exponent0<=6;fraction0<=amplitude[5:1];end
   16'b00000000001?????:begin exponent0<=5;fraction0<=amplitude[4:0];end
   16'b000000000001????:begin exponent0<=4;fraction0<={amplitude[3:0],1'b0};end
   16'b0000000000001???:begin exponent0<=3;fraction0<={amplitude[2:0],2'b0};end
   16'b00000000000001??:begin exponent0<=2;fraction0<={amplitude[1:0],3'b0};end
   16'b000000000000001?:begin exponent0<=1;fraction0<={amplitude[0],4'b0};end
   default:begin exponent0<=0;fraction0<=0;end
  endcase
  case(exponent0)
   15:base1<=0;14:base1<=-60;13:base1<=-120;12:base1<=-181;
   11:base1<=-241;10:base1<=-301;9:base1<=-361;8:base1<=-421;
   7:base1<=-482;6:base1<=-542;5:base1<=-602;4:base1<=-662;
   3:base1<=-723;2:base1<=-783;1:base1<=-843;default:base1<=-903;
  endcase
  case(fraction0)
   0:mantissa1<=0;1:mantissa1<=3;2:mantissa1<=5;3:mantissa1<=8;
   4:mantissa1<=10;5:mantissa1<=13;6:mantissa1<=15;7:mantissa1<=17;
   8:mantissa1<=19;9:mantissa1<=22;10:mantissa1<=24;11:mantissa1<=26;
   12:mantissa1<=28;13:mantissa1<=30;14:mantissa1<=32;15:mantissa1<=33;
   16:mantissa1<=35;17:mantissa1<=37;18:mantissa1<=39;19:mantissa1<=40;
   20:mantissa1<=42;21:mantissa1<=44;22:mantissa1<=45;23:mantissa1<=47;
   24:mantissa1<=49;25:mantissa1<=50;26:mantissa1<=52;27:mantissa1<=53;
   28:mantissa1<=55;29:mantissa1<=56;30:mantissa1<=57;default:mantissa1<=59;
  endcase
  db10<=zero1 ? -12'sd960 : base1+$signed({5'd0,mantissa1});
 end
endmodule
