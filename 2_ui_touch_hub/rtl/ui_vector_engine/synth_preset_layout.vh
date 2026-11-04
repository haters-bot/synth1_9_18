// Stable original preset IDs. Only the Acoustic display order gains a card.
localparam integer SYNTH_PRESET_COUNT=13;
function synth_preset_row_visible;
 input [2:0] c;input integer row;
 begin synth_preset_row_visible=(c==0 || c==4) ? row<3 : c==5 ? row==0 : row<2;end
endfunction
function [3:0] synth_preset_row_index;
 input [2:0] c;input integer row;
 begin case(c)
  0:case(row) 0:synth_preset_row_index=0;1:synth_preset_row_index=12;default:synth_preset_row_index=1;endcase
  1:synth_preset_row_index=2+row;
  2:synth_preset_row_index=4+row;
  3:synth_preset_row_index=6+row;
  4:synth_preset_row_index=8+row;
  default:synth_preset_row_index=11;
 endcase end
endfunction
