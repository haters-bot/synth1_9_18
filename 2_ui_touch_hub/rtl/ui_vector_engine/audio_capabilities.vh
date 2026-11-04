// Include inside a module. Fixed Protocol V2 positions; never compact slots.
// Static CC support is independent (e.g. Unison/ADSR remain adjustable).
localparam [52:0] AUDIO_LFO_TARGET_MASK =
    (53'h1<<4)  | (53'h1<<6)  | (53'h1<<8)  | (53'h1<<9)  |
    (53'h1<<10) | (53'h1<<11) | (53'h1<<12) | (53'h1<<13) |
    (53'h1<<15) | (53'h1<<17) | (53'h1<<18) | (53'h1<<19) |
    (53'h1<<20) | (53'h1<<21) | (53'h1<<22) | (53'h1<<23) |
    (53'h1<<24) | (53'h1<<28) | (53'h1<<34) | (53'h1<<35) |
    (53'h1<<39) | (53'h1<<40) | (53'h1<<41) | (53'h1<<46);
function audio_lfo_connected;
    input integer target;
    begin audio_lfo_connected=(target>=0 && target<53) ? AUDIO_LFO_TARGET_MASK[target] : 1'b0; end
endfunction
