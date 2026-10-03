// 256-phase, 16-bit signed hard-square-wave lookup module.
//
// The two half-cycles use +32767 and -32767 so the waveform has exactly
// zero DC offset. This intentionally non-band-limited waveform is used as a
// temporary diagnostic source; its strong odd harmonics should be obvious.
module square_lut(
    input  wire [7:0]        addr,
    output wire signed [15:0] data
);

    assign data = addr[7] ? -16'sd32767 : 16'sd32767;

endmodule
