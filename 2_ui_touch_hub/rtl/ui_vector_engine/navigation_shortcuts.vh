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
   wire [1:0] gain=plot_scales[shortcut_tile*4+(shortcut_column>=2 ? 2:0)+:2];
   assign shortcut_hits[I]=view==1 && !((shortcut_tile==0||shortcut_tile==5)&&shortcut_column>=2) &&
    in_x>=X && in_x<X+64 && in_y>=Y && in_y<Y+16;
   assign shortcut_tree[64+I]={15{shortcut_hits[I]}} &
    {plot_shortcut_caption(COLUMN,gain,dx[5:3]),1'b0,dx[2:0],dy[4:0]};
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
 for(shortcut_node=48;shortcut_node<64;shortcut_node=shortcut_node+1)begin: shortcut_unused
  assign shortcut_hits[shortcut_node]=1'b0;
  assign shortcut_tree[64+shortcut_node]=15'd0;
 end
 for(shortcut_node=1;shortcut_node<64;shortcut_node=shortcut_node+1)begin: shortcut_merge
  assign shortcut_tree[shortcut_node]=shortcut_tree[shortcut_node*2]|shortcut_tree[shortcut_node*2+1];
 end
endgenerate
wire shortcut=|shortcut_hits;
wire [5:0] shortcut_char=shortcut_tree[1][14:9];
wire [3:0] shortcut_x=shortcut_tree[1][8:5];
wire [4:0] shortcut_y=shortcut_tree[1][4:0];
