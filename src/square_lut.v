// 256-phase, 16-bit signed hard-square-wave lookup module.
//
// The two half-cycles use +328 and -328 so the waveform has exactly zero DC
// offset and approximately 1/100 of full-scale amplitude. This intentionally
// non-band-limited waveform is used as a temporary diagnostic source.
module square_lut(
    input  wire [7:0]        addr,
    output wire signed [15:0] data
);

    assign data = addr[7] ? -16'sd328 : 16'sd328;

endmodule
