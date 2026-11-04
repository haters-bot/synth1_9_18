// Disjoint shortcut rectangles select glyphs in parallel. A balanced masked
// OR tree replaces the raster-to-digit priority chain without adding clocks.
function [5:0] plot_shortcut_caption;
 input [1:0] column,gain;input [2:0] pos;
 begin
  case(pos)
   0:plot_shortcut_caption=column<2 ? `CH_Y : `CH_X;
   1:plot_shortcut_caption=(column==0||column==2) ? `CH_MINUS : `CH_PLUS;
   3:plot_shortcut_caption=`CH_0+(4'd1<<gain);
   4:plot_shortcut_caption=`CH_X;
   default:plot_shortcut_caption=`CH_SPACE;
  endcase
 end
endfunction
function [5:0] mode_caption;
 input [1:0] mode_index;input [3:0] pos;
 begin
  mode_caption=`CH_SPACE;
  case(mode_index)
   0:case(pos)0:mode_caption=`CH_A;1:mode_caption=`CH_U;2:mode_caption=`CH_D;3:mode_caption=`CH_I;4:mode_caption=`CH_T;5:mode_caption=`CH_I;6:mode_caption=`CH_O;7:mode_caption=`CH_N;endcase
   1:case(pos)0:mode_caption=`CH_F;1:mode_caption=`CH_O;2,3:mode_caption=`CH_L;4:mode_caption=`CH_O;5:mode_caption=`CH_W;endcase
   2:case(pos)0:mode_caption=`CH_P;1:mode_caption=`CH_E;2:mode_caption=`CH_R;3:mode_caption=`CH_F;4:mode_caption=`CH_O;5:mode_caption=`CH_R;6:mode_caption=`CH_M;endcase
  endcase
 end
endfunction
function [5:0] calibration_caption;
 input integer pos;
 begin case(pos)
  0:calibration_caption=`CH_C;1:calibration_caption=`CH_A;2:calibration_caption=`CH_L;
  3:calibration_caption=`CH_I;4:calibration_caption=`CH_B;5:calibration_caption=`CH_R;
  6:calibration_caption=`CH_A;7:calibration_caption=`CH_T;8:calibration_caption=`CH_E;
  default:calibration_caption=`CH_SPACE;
 endcase end
endfunction
function [5:0] calibration_status_caption;
 input [2:0] state;input [6:0] base;input integer pos;
 reg [55:0] label;reg [7:0] letter;
 reg [3:0] hex_digit;
 begin
  case(state)
   1:label="LEFTKEY";2:label="OK 0X00";3:label="RETRY  ";4:label="WAIT   ";default:label="NEEDCAL";
  endcase
  letter=label>>(48-pos*8);
  calibration_status_caption=letter>=65 && letter<=90 ? letter-64 :
      letter>=48 && letter<=57 ? `CH_0+letter-48 : `CH_SPACE;
  if(state==2 && pos>=5)begin
   hex_digit=pos==5 ? {1'b0,base[6:4]} : base[3:0];
   calibration_status_caption=hex_digit<10 ? `CH_0+hex_digit : `CH_A+hex_digit-10;
  end
 end
endfunction
function [5:0] keyboard_range_caption;
 input integer pos;
 input [6:0] base;
 input calibrated;
 reg [6:0] last_note;
 reg [3:0] digit;
 begin
  last_note=base+PERFORMANCE_KEY_COUNT-1;
  keyboard_range_caption=`CH_SPACE;
  case(pos)
   0:keyboard_range_caption=`CH_K;
   1:keyboard_range_caption=`CH_E;
   2:keyboard_range_caption=`CH_Y;
   4,9:keyboard_range_caption=`CH_0;
   5,10:keyboard_range_caption=`CH_X;
   8:keyboard_range_caption=`CH_MINUS;
   6,7,11,12:begin
    case(pos)
     6:digit={1'b0,base[6:4]};7:digit=base[3:0];
     11:digit={1'b0,last_note[6:4]};default:digit=last_note[3:0];
    endcase
    keyboard_range_caption=!calibrated ? `CH_MINUS :
       digit<10 ? `CH_0+digit : `CH_A+digit-10;
   end
  endcase
 end
endfunction
function [5:0] keyboard_warning_caption;
 input integer pos;
 reg [87:0] label;
 reg [7:0] letter;
 begin
  label="RECALIBRATE";
  letter=label>>(80-pos*8);
  keyboard_warning_caption=letter>=65 && letter<=90 ? letter-64 : `CH_SPACE;
 end
endfunction
wire [63:0] shortcut_hits;
wire [14:0] shortcut_tree[1:127];
genvar shortcut_tile,shortcut_column,shortcut_mode,shortcut_cell,shortcut_node;
generate
 for(shortcut_tile=0;shortcut_tile<6;shortcut_tile=shortcut_tile+1)begin: shortcut_plot_tile
  for(shortcut_column=0;shortcut_column<4;shortcut_column=shortcut_column+1)begin: column
   localparam integer I=shortcut_tile*4+shortcut_column;
   localparam [1:0] COLUMN=shortcut_column;
   localparam [13:0] X=48+(shortcut_tile%3)*418+shortcut_column*92;
   localparam [13:0] Y=356+(shortcut_tile/3)*296;
   wire [13:0] dx=in_x-X,dy=in_y-Y;
   // Reuse these leaves on the disjoint PERFORMANCE page rather than
   // growing the established 64-leaf reduction or changing raster latency.
   localparam integer RANGE_CELL=I<13 ? I : I-13;
   localparam [13:0] RANGE_X=I<13 ? 432+RANGE_CELL*14 : 848+RANGE_CELL*14;
   wire [13:0] range_dx=in_x-RANGE_X,range_dy=in_y-14'd400;
   wire range_hit=PERFORMANCE_CALIBRATION_ENABLE && view==2 &&
       (I<13 || performance_range_warning) &&
       in_x>=RANGE_X && in_x<RANGE_X+14 && in_y>=400 && in_y<420;
   wire [5:0] range_ch=I<13 ? keyboard_range_caption(RANGE_CELL,performance_base_note,performance_calibration_state==2) :
       keyboard_warning_caption(RANGE_CELL);
   wire [1:0] gain=plot_scales[shortcut_tile*4+(shortcut_column>=2 ? 2:0)+:2];
   wire plot_hit=view==1 && !((shortcut_tile==0||shortcut_tile==5)&&shortcut_column>=2) &&
    in_x>=X && in_x<X+64 && in_y>=Y && in_y<Y+16;
   assign shortcut_hits[I]=plot_hit || range_hit;
   assign shortcut_tree[64+I]=({15{plot_hit}} &
    {plot_shortcut_caption(COLUMN,gain,dx[5:3]),1'b0,dx[2:0],dy[4:0]}) |
    ({15{range_hit}} & {range_ch,1'b0,range_dx[3:1],range_dy[5:1]});
  end
 end
 // Each 14-pixel character cell is disjoint, so no /14 or %14 is needed
 // between the raster register and the first glyph pipeline register.
 for(shortcut_mode=0;shortcut_mode<3;shortcut_mode=shortcut_mode+1)begin: shortcut_mode_label
  for(shortcut_cell=0;shortcut_cell<8;shortcut_cell=shortcut_cell+1)begin: glyph_cell
   localparam integer I=24+shortcut_mode*8+shortcut_cell;
   localparam [1:0] MODE=shortcut_mode;
   localparam [3:0] CELL=shortcut_cell;
   localparam [13:0] X=328+shortcut_mode*176+shortcut_cell*14;
   wire [13:0] dx=in_x-X,dy=in_y-14'd142;
   assign shortcut_hits[I]=view==2 && in_x>=X && in_x<X+14 && in_y>=142 && in_y<162;
   assign shortcut_tree[64+I]={15{shortcut_hits[I]}} &
    {mode_caption(MODE,CELL),1'b0,dx[3:1],dy[5:1]};
  end
 end
 for(shortcut_node=48;shortcut_node<64;shortcut_node=shortcut_node+1)begin: shortcut_calibration
  localparam integer CELL=shortcut_node<57 ? shortcut_node-48 : shortcut_node-57;
  localparam [13:0] X=shortcut_node<57 ? 856+CELL*14 : 670+CELL*14;
  localparam [13:0] Y=shortcut_node<57 ? 142 : 100;
  wire [13:0] dx=in_x-X,dy=in_y-Y;
  wire [5:0] ch=shortcut_node<57 ? calibration_caption(CELL) :
     calibration_status_caption(performance_calibration_state,performance_base_note,CELL);
  assign shortcut_hits[shortcut_node]=PERFORMANCE_CALIBRATION_ENABLE && view==2 &&
      in_x>=X && in_x<X+14 && in_y>=Y && in_y<Y+20;
  assign shortcut_tree[64+shortcut_node]={15{shortcut_hits[shortcut_node]}} &
      {ch,1'b0,dx[3:1],dy[5:1]};
 end
 for(shortcut_node=1;shortcut_node<64;shortcut_node=shortcut_node+1)begin: shortcut_merge
  assign shortcut_tree[shortcut_node]=shortcut_tree[shortcut_node*2]|shortcut_tree[shortcut_node*2+1];
 end
endgenerate
wire shortcut=|shortcut_hits;
wire [5:0] shortcut_char=shortcut_tree[1][14:9];
wire [3:0] shortcut_x=shortcut_tree[1][8:5];
wire [4:0] shortcut_y=shortcut_tree[1][4:0];
