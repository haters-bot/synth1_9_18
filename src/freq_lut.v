module freq_lut(
    input  wire [6:0]  addr,       // MIDI note number: 21 (A0) to 108 (C8)
    output reg  [31:0] data        // phase step for Fs = 768 kHz
);

    // 32-bit phase step = round(f_note * 2^32 / 768000).
    // A4 (MIDI 69) is 440 Hz; equal temperament is used.
    always @(*) begin
        case (addr)
            7'd21: data = 32'h000258BF; // MIDI 21, f ~= 27.500000 Hz
            7'd22: data = 32'h00027C78; // MIDI 22, f ~= 29.135235 Hz
            7'd23: data = 32'h0002A251; // MIDI 23, f ~= 30.867706 Hz
            7'd24: data = 32'h0002CA6A; // MIDI 24, f ~= 32.703196 Hz
            7'd25: data = 32'h0002F4E5; // MIDI 25, f ~= 34.647829 Hz
            7'd26: data = 32'h000321E7; // MIDI 26, f ~= 36.708096 Hz
            7'd27: data = 32'h00035196; // MIDI 27, f ~= 38.890873 Hz
            7'd28: data = 32'h0003841A; // MIDI 28, f ~= 41.203445 Hz
            7'd29: data = 32'h0003B9A0; // MIDI 29, f ~= 43.653529 Hz
            7'd30: data = 32'h0003F255; // MIDI 30, f ~= 46.249303 Hz
            7'd31: data = 32'h00042E69; // MIDI 31, f ~= 48.999429 Hz
            7'd32: data = 32'h00046E0F; // MIDI 32, f ~= 51.913087 Hz
            7'd33: data = 32'h0004B17E; // MIDI 33, f ~= 55.000000 Hz
            7'd34: data = 32'h0004F8F0; // MIDI 34, f ~= 58.270470 Hz
            7'd35: data = 32'h000544A1; // MIDI 35, f ~= 61.735413 Hz
            7'd36: data = 32'h000594D3; // MIDI 36, f ~= 65.406391 Hz
            7'd37: data = 32'h0005E9C9; // MIDI 37, f ~= 69.295658 Hz
            7'd38: data = 32'h000643CD; // MIDI 38, f ~= 73.416192 Hz
            7'd39: data = 32'h0006A32B; // MIDI 39, f ~= 77.781746 Hz
            7'd40: data = 32'h00070835; // MIDI 40, f ~= 82.406889 Hz
            7'd41: data = 32'h00077340; // MIDI 41, f ~= 87.307058 Hz
            7'd42: data = 32'h0007E4AA; // MIDI 42, f ~= 92.498606 Hz
            7'd43: data = 32'h00085CD1; // MIDI 43, f ~= 97.998859 Hz
            7'd44: data = 32'h0008DC1E; // MIDI 44, f ~= 103.826174 Hz
            7'd45: data = 32'h000962FD; // MIDI 45, f ~= 110.000000 Hz
            7'd46: data = 32'h0009F1E0; // MIDI 46, f ~= 116.540940 Hz
            7'd47: data = 32'h000A8943; // MIDI 47, f ~= 123.470825 Hz
            7'd48: data = 32'h000B29A6; // MIDI 48, f ~= 130.812783 Hz
            7'd49: data = 32'h000BD393; // MIDI 49, f ~= 138.591315 Hz
            7'd50: data = 32'h000C879A; // MIDI 50, f ~= 146.832384 Hz
            7'd51: data = 32'h000D4656; // MIDI 51, f ~= 155.563492 Hz
            7'd52: data = 32'h000E1069; // MIDI 52, f ~= 164.813778 Hz
            7'd53: data = 32'h000EE681; // MIDI 53, f ~= 174.614116 Hz
            7'd54: data = 32'h000FC953; // MIDI 54, f ~= 184.997211 Hz
            7'd55: data = 32'h0010B9A3; // MIDI 55, f ~= 195.997718 Hz
            7'd56: data = 32'h0011B83C; // MIDI 56, f ~= 207.652349 Hz
            7'd57: data = 32'h0012C5F9; // MIDI 57, f ~= 220.000000 Hz
            7'd58: data = 32'h0013E3C0; // MIDI 58, f ~= 233.081881 Hz
            7'd59: data = 32'h00151286; // MIDI 59, f ~= 246.941651 Hz
            7'd60: data = 32'h0016534C; // MIDI 60, f ~= 261.625565 Hz
            7'd61: data = 32'h0017A726; // MIDI 61, f ~= 277.182631 Hz
            7'd62: data = 32'h00190F34; // MIDI 62, f ~= 293.664768 Hz
            7'd63: data = 32'h001A8CAC; // MIDI 63, f ~= 311.126984 Hz
            7'd64: data = 32'h001C20D3; // MIDI 64, f ~= 329.627557 Hz
            7'd65: data = 32'h001DCD02; // MIDI 65, f ~= 349.228231 Hz
            7'd66: data = 32'h001F92A7; // MIDI 66, f ~= 369.994423 Hz
            7'd67: data = 32'h00217345; // MIDI 67, f ~= 391.995436 Hz
            7'd68: data = 32'h00237078; // MIDI 68, f ~= 415.304698 Hz
            7'd69: data = 32'h00258BF2; // MIDI 69, f ~= 440.000000 Hz
            7'd70: data = 32'h0027C781; // MIDI 70, f ~= 466.163762 Hz
            7'd71: data = 32'h002A250C; // MIDI 71, f ~= 493.883301 Hz
            7'd72: data = 32'h002CA698; // MIDI 72, f ~= 523.251131 Hz
            7'd73: data = 32'h002F4E4B; // MIDI 73, f ~= 554.365262 Hz
            7'd74: data = 32'h00321E69; // MIDI 74, f ~= 587.329536 Hz
            7'd75: data = 32'h00351958; // MIDI 75, f ~= 622.253967 Hz
            7'd76: data = 32'h003841A6; // MIDI 76, f ~= 659.255114 Hz
            7'd77: data = 32'h003B9A04; // MIDI 77, f ~= 698.456463 Hz
            7'd78: data = 32'h003F254E; // MIDI 78, f ~= 739.988845 Hz
            7'd79: data = 32'h0042E68B; // MIDI 79, f ~= 783.990872 Hz
            7'd80: data = 32'h0046E0F0; // MIDI 80, f ~= 830.609395 Hz
            7'd81: data = 32'h004B17E5; // MIDI 81, f ~= 880.000000 Hz
            7'd82: data = 32'h004F8F01; // MIDI 82, f ~= 932.327523 Hz
            7'd83: data = 32'h00544A17; // MIDI 83, f ~= 987.766603 Hz
            7'd84: data = 32'h00594D31; // MIDI 84, f ~= 1,046.502261 Hz
            7'd85: data = 32'h005E9C96; // MIDI 85, f ~= 1,108.730524 Hz
            7'd86: data = 32'h00643CD2; // MIDI 86, f ~= 1,174.659072 Hz
            7'd87: data = 32'h006A32B1; // MIDI 87, f ~= 1,244.507935 Hz
            7'd88: data = 32'h0070834C; // MIDI 88, f ~= 1,318.510228 Hz
            7'd89: data = 32'h00773407; // MIDI 89, f ~= 1,396.912926 Hz
            7'd90: data = 32'h007E4A9B; // MIDI 90, f ~= 1,479.977691 Hz
            7'd91: data = 32'h0085CD15; // MIDI 91, f ~= 1,567.981744 Hz
            7'd92: data = 32'h008DC1E1; // MIDI 92, f ~= 1,661.218790 Hz
            7'd93: data = 32'h00962FC9; // MIDI 93, f ~= 1,760.000000 Hz
            7'd94: data = 32'h009F1E03; // MIDI 94, f ~= 1,864.655046 Hz
            7'd95: data = 32'h00A8942E; // MIDI 95, f ~= 1,975.533205 Hz
            7'd96: data = 32'h00B29A62; // MIDI 96, f ~= 2,093.004522 Hz
            7'd97: data = 32'h00BD392D; // MIDI 97, f ~= 2,217.461048 Hz
            7'd98: data = 32'h00C879A3; // MIDI 98, f ~= 2,349.318143 Hz
            7'd99: data = 32'h00D46562; // MIDI 99, f ~= 2,489.015870 Hz
            7'd100: data = 32'h00E10697; // MIDI 100, f ~= 2,637.020455 Hz
            7'd101: data = 32'h00EE680F; // MIDI 101, f ~= 2,793.825851 Hz
            7'd102: data = 32'h00FC9536; // MIDI 102, f ~= 2,959.955382 Hz
            7'd103: data = 32'h010B9A2B; // MIDI 103, f ~= 3,135.963488 Hz
            7'd104: data = 32'h011B83C2; // MIDI 104, f ~= 3,322.437581 Hz
            7'd105: data = 32'h012C5F93; // MIDI 105, f ~= 3,520.000000 Hz
            7'd106: data = 32'h013E3C06; // MIDI 106, f ~= 3,729.310092 Hz
            7'd107: data = 32'h0151285D; // MIDI 107, f ~= 3,951.066410 Hz
            7'd108: data = 32'h016534C3; // MIDI 108, f ~= 4,186.009045 Hz
            default: data = 32'd0;
        endcase
    end

endmodule
