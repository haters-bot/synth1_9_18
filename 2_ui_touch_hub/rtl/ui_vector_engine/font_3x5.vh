// ==============================================================================
// Header: font_3x5.vh
// Description: Ultra-compact, High-speed Procedural 3x5 Font Engine & Label Decoder
//              Zero BRAM, Zero Block RAM, Pure Combinational Logic.
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`ifndef FONT_3X5_VH
`define FONT_3X5_VH

// Character IDs (6-bit)
`define CH_SPACE  6'd0
`define CH_A      6'd1
`define CH_B      6'd2
`define CH_C      6'd3
`define CH_D      6'd4
`define CH_E      6'd5
`define CH_F      6'd6
`define CH_G      6'd7
`define CH_H      6'd8
`define CH_I      6'd9
`define CH_J      6'd10
`define CH_K      6'd11
`define CH_L      6'd12
`define CH_M      6'd13
`define CH_N      6'd14
`define CH_O      6'd15
`define CH_P      6'd16
`define CH_Q      6'd17
`define CH_R      6'd18
`define CH_S      6'd19
`define CH_T      6'd20
`define CH_U      6'd21
`define CH_V      6'd22
`define CH_W      6'd23
`define CH_X      6'd24
`define CH_Y      6'd25
`define CH_Z      6'd26
`define CH_0      6'd27
`define CH_1      6'd28
`define CH_2      6'd29
`define CH_3      6'd30
`define CH_4      6'd31
`define CH_5      6'd32
`define CH_6      6'd33
`define CH_7      6'd34
`define CH_8      6'd35
`define CH_9      6'd36
`define CH_MINUS  6'd37
`define CH_PLUS   6'd38
`define CH_COLON  6'd39
`define CH_DOT    6'd40

// 3x5 Bitmap lookup: returns 1 if pixel at (rx, ry) is on.
// rx: 0..2 (left to right), ry: 0..4 (top to bottom)
function get_font_3x5;
    input [5:0] ch;
    input [1:0] rx; // 0..2
    input [2:0] ry; // 0..4
    reg [14:0] bitmap;
    reg [2:0] row_bits;
    begin
        case (ch)
            `CH_DOT:   bitmap = 15'b000_000_000_000_010;
            `CH_A:     bitmap = 15'b010_101_111_101_101;
            `CH_B:     bitmap = 15'b110_101_110_101_110;
            `CH_C:     bitmap = 15'b011_100_100_100_011;
            `CH_D:     bitmap = 15'b110_101_101_101_110;
            `CH_E:     bitmap = 15'b111_100_110_100_111;
            `CH_F:     bitmap = 15'b111_100_110_100_100;
            `CH_G:     bitmap = 15'b011_100_101_101_011;
            `CH_H:     bitmap = 15'b101_101_111_101_101;
            `CH_I:     bitmap = 15'b111_010_010_010_111;
            `CH_J:     bitmap = 15'b001_001_001_101_010;
            `CH_K:     bitmap = 15'b101_110_100_110_101;
            `CH_L:     bitmap = 15'b100_100_100_100_111;
            `CH_M:     bitmap = 15'b101_111_101_101_101;
            `CH_N:     bitmap = 15'b101_111_111_101_101;
            `CH_O:     bitmap = 15'b010_101_101_101_010;
            `CH_P:     bitmap = 15'b110_101_110_100_100;
            `CH_Q:     bitmap = 15'b010_101_101_110_011;
            `CH_R:     bitmap = 15'b110_101_110_110_101;
            `CH_S:     bitmap = 15'b011_100_010_001_110;
            `CH_T:     bitmap = 15'b111_010_010_010_010;
            `CH_U:     bitmap = 15'b101_101_101_101_111;
            `CH_V:     bitmap = 15'b101_101_101_101_010;
            `CH_W:     bitmap = 15'b101_101_101_111_101;
            `CH_X:     bitmap = 15'b101_101_010_101_101;
            `CH_Y:     bitmap = 15'b101_101_010_010_010;
            `CH_Z:     bitmap = 15'b111_001_010_100_111;
            `CH_0:     bitmap = 15'b111_101_101_101_111;
            `CH_1:     bitmap = 15'b010_110_010_010_111;
            `CH_2:     bitmap = 15'b110_001_010_100_111;
            `CH_3:     bitmap = 15'b110_001_010_001_110;
            `CH_4:     bitmap = 15'b101_101_111_001_001;
            `CH_5:     bitmap = 15'b111_100_110_001_110;
            `CH_6:     bitmap = 15'b011_100_110_101_010;
            `CH_7:     bitmap = 15'b111_001_010_010_010;
            `CH_8:     bitmap = 15'b010_101_010_101_010;
            `CH_9:     bitmap = 15'b010_101_011_001_110;
            `CH_MINUS: bitmap = 15'b000_000_111_000_000;
            `CH_PLUS:  bitmap = 15'b000_010_111_010_000;
            `CH_COLON: bitmap = 15'b000_010_000_010_000;
            default:   bitmap = 15'd0;
        endcase
        // Fixed slices avoid a wide multiply/subtract and variable bit selector
        // in the pixel path. Invalid rows/columns are explicitly blank.
        case(ry)
            0: row_bits=bitmap[14:12];
            1: row_bits=bitmap[11:9];
            2: row_bits=bitmap[8:6];
            3: row_bits=bitmap[5:3];
            4: row_bits=bitmap[2:0];
            default: row_bits=3'd0;
        endcase
        case(rx)
            0: get_font_3x5=row_bits[2];
            1: get_font_3x5=row_bits[1];
            2: get_font_3x5=row_bits[0];
            default: get_font_3x5=1'b0;
        endcase
    end
endfunction

// Map 8-bit parameter ID to 3-character label {char1, char2, char3} (18 bits)
function [17:0] get_param_label3;
    input [7:0] param_id;
    begin
        case (param_id)
            // Top deck
            `PARAM_ID_MACRO1:      get_param_label3 = {`CH_M, `CH_1, `CH_SPACE};
            `PARAM_ID_MACRO2:      get_param_label3 = {`CH_M, `CH_2, `CH_SPACE};
            `PARAM_ID_MACRO3:      get_param_label3 = {`CH_M, `CH_3, `CH_SPACE};
            `PARAM_ID_MACRO4:      get_param_label3 = {`CH_M, `CH_4, `CH_SPACE};
            `PARAM_ID_MASTER_VOL:  get_param_label3 = {`CH_V, `CH_O, `CH_L};

            // OSC A / B
            `PARAM_ID_OSCA_UNISON,
            `PARAM_ID_OSCB_UNISON: get_param_label3 = {`CH_U, `CH_N, `CH_I};
            `PARAM_ID_OSCA_DETUNE,
            `PARAM_ID_OSCB_DETUNE: get_param_label3 = {`CH_D, `CH_E, `CH_T};
            `PARAM_ID_OSCA_BLEND,
            `PARAM_ID_OSCB_BLEND:  get_param_label3 = {`CH_B, `CH_L, `CH_D};
            `PARAM_ID_OSCA_PHASE,
            `PARAM_ID_OSCB_PHASE:  get_param_label3 = {`CH_P, `CH_H, `CH_S};
            `PARAM_ID_OSCA_RAND,
            `PARAM_ID_OSCB_RAND:   get_param_label3 = {`CH_R, `CH_N, `CH_D};
            `PARAM_ID_OSCA_WT_POS,
            `PARAM_ID_OSCB_WT_POS: get_param_label3 = {`CH_P, `CH_O, `CH_S};
            `PARAM_ID_OSCA_WARP,
            `PARAM_ID_OSCB_WARP:   get_param_label3 = {`CH_W, `CH_R, `CH_P};
            `PARAM_ID_OSCA_PAN,
            `PARAM_ID_OSCB_PAN:    get_param_label3 = {`CH_P, `CH_A, `CH_N};
            `PARAM_ID_OSCA_VOL,
            `PARAM_ID_OSCB_VOL:    get_param_label3 = {`CH_V, `CH_O, `CH_L};

            // Filter
            `PARAM_ID_FLT_CUTOFF:  get_param_label3 = {`CH_C, `CH_U, `CH_T};
            `PARAM_ID_FLT_RES:     get_param_label3 = {`CH_R, `CH_E, `CH_S};
            `PARAM_ID_FLT_PAN:     get_param_label3 = {`CH_M, `CH_P, `CH_N};
            `PARAM_ID_FLT_DRIVE:   get_param_label3 = {`CH_D, `CH_R, `CH_V};
            `PARAM_ID_FLT_FAT:     get_param_label3 = {`CH_F, `CH_A, `CH_T};
            `PARAM_ID_FLT_MIX:     get_param_label3 = {`CH_M, `CH_I, `CH_X};

            // ADSR
            `PARAM_ID_ENV1_ATTACK:  get_param_label3 = {`CH_A, `CH_T, `CH_K};
            `PARAM_ID_ENV1_HOLD:    get_param_label3 = {`CH_H, `CH_L, `CH_D};
            `PARAM_ID_ENV1_DECAY:   get_param_label3 = {`CH_D, `CH_C, `CH_Y};
            `PARAM_ID_ENV1_SUSTAIN: get_param_label3 = {`CH_S, `CH_U, `CH_S};
            `PARAM_ID_ENV1_RELEASE: get_param_label3 = {`CH_R, `CH_E, `CH_L};

            // Master FX
            `PARAM_ID_FX_REVERB:    get_param_label3 = {`CH_R, `CH_E, `CH_V};
            `PARAM_ID_FX_DELAY:     get_param_label3 = {`CH_D, `CH_L, `CH_Y};
            `PARAM_ID_FX_CHORUS:    get_param_label3 = {`CH_C, `CH_H, `CH_O};
            `PARAM_ID_PORTAMENTO:   get_param_label3 = {`CH_P, `CH_R, `CH_T};

            // Steppers & Tabs
            `PARAM_ID_OSCA_OCT,
            `PARAM_ID_OSCB_OCT:     get_param_label3 = {`CH_O, `CH_C, `CH_T};
            `PARAM_ID_OSCA_SEMI,
            `PARAM_ID_OSCB_SEMI:    get_param_label3 = {`CH_S, `CH_E, `CH_M};
            `PARAM_ID_OSCA_FINE,
            `PARAM_ID_OSCB_FINE:    get_param_label3 = {`CH_F, `CH_I, `CH_N};
            `PARAM_ID_OSCA_WAVE,
            `PARAM_ID_OSCB_WAVE:    get_param_label3 = {`CH_W, `CH_A, `CH_V};
            `PARAM_ID_FLT_TYPE:     get_param_label3 = {`CH_T, `CH_Y, `CH_P};
            `PARAM_ID_ENV_TAB:      get_param_label3 = {`CH_T, `CH_A, `CH_B};

            default:                get_param_label3 = {`CH_MINUS, `CH_MINUS, `CH_MINUS};
        endcase
    end
endfunction

// Six-character names for enlarged knob captions (2 pixels per font dot).
function [35:0] get_param_label6;
    input [7:0] param_id;
    begin
        case (param_id)
            `PARAM_ID_OSCA_UNISON, `PARAM_ID_OSCB_UNISON:
                get_param_label6 = {`CH_U,`CH_N,`CH_I,`CH_S,`CH_O,`CH_N};
            `PARAM_ID_OSCA_DETUNE, `PARAM_ID_OSCB_DETUNE:
                get_param_label6 = {`CH_D,`CH_E,`CH_T,`CH_U,`CH_N,`CH_E};
            `PARAM_ID_OSCA_BLEND, `PARAM_ID_OSCB_BLEND:
                get_param_label6 = {`CH_B,`CH_L,`CH_E,`CH_N,`CH_D,`CH_SPACE};
            `PARAM_ID_OSCA_PHASE, `PARAM_ID_OSCB_PHASE:
                get_param_label6 = {`CH_P,`CH_H,`CH_A,`CH_S,`CH_E,`CH_SPACE};
            `PARAM_ID_OSCA_RAND, `PARAM_ID_OSCB_RAND:
                get_param_label6 = {`CH_SPACE,`CH_R,`CH_A,`CH_N,`CH_D,`CH_SPACE};
            `PARAM_ID_OSCA_WT_POS, `PARAM_ID_OSCB_WT_POS:
                get_param_label6 = {`CH_W,`CH_T,`CH_SPACE,`CH_P,`CH_O,`CH_S};
            `PARAM_ID_OSCA_WARP, `PARAM_ID_OSCB_WARP:
                get_param_label6 = {`CH_SPACE,`CH_W,`CH_A,`CH_R,`CH_P,`CH_SPACE};
            `PARAM_ID_OSCA_PAN, `PARAM_ID_OSCB_PAN:
                get_param_label6 = {`CH_SPACE,`CH_P,`CH_A,`CH_N,`CH_SPACE,`CH_SPACE};
            `PARAM_ID_OSCA_VOL, `PARAM_ID_OSCB_VOL:
                get_param_label6 = {`CH_V,`CH_O,`CH_L,`CH_U,`CH_M,`CH_E};
            `PARAM_ID_FLT_PAN:
                get_param_label6 = {`CH_M,`CH_S,`CH_T,`CH_P,`CH_A,`CH_N};
            `PARAM_ID_FLT_CUTOFF:
                get_param_label6 = {`CH_C,`CH_U,`CH_T,`CH_O,`CH_F,`CH_F};
            `PARAM_ID_FLT_RES:
                get_param_label6 = {`CH_SPACE,`CH_R,`CH_E,`CH_S,`CH_SPACE,`CH_SPACE};
            `PARAM_ID_FLT_DRIVE:
                get_param_label6 = {`CH_D,`CH_R,`CH_I,`CH_V,`CH_E,`CH_SPACE};
            `PARAM_ID_FLT_FAT:
                get_param_label6 = {`CH_SPACE,`CH_F,`CH_A,`CH_T,`CH_SPACE,`CH_SPACE};
            `PARAM_ID_FLT_MIX:
                get_param_label6 = {`CH_SPACE,`CH_M,`CH_I,`CH_X,`CH_SPACE,`CH_SPACE};
            `PARAM_ID_ENV1_ATTACK:
                get_param_label6 = {`CH_A,`CH_T,`CH_T,`CH_A,`CH_C,`CH_K};
            `PARAM_ID_ENV1_HOLD:
                get_param_label6 = {`CH_SPACE,`CH_H,`CH_O,`CH_L,`CH_D,`CH_SPACE};
            `PARAM_ID_ENV1_DECAY:
                get_param_label6 = {`CH_D,`CH_E,`CH_C,`CH_A,`CH_Y,`CH_SPACE};
            `PARAM_ID_ENV1_SUSTAIN:
                get_param_label6 = {`CH_S,`CH_U,`CH_S,`CH_T,`CH_SPACE,`CH_SPACE};
            `PARAM_ID_ENV1_RELEASE:
                get_param_label6 = {`CH_SPACE,`CH_R,`CH_E,`CH_L,`CH_SPACE,`CH_SPACE};
            `PARAM_ID_FX_REVERB:
                get_param_label6 = {`CH_R,`CH_E,`CH_V,`CH_E,`CH_R,`CH_B};
            `PARAM_ID_FX_DELAY:
                get_param_label6 = {`CH_D,`CH_E,`CH_L,`CH_A,`CH_Y,`CH_SPACE};
            `PARAM_ID_FX_CHORUS:
                get_param_label6 = {`CH_C,`CH_H,`CH_O,`CH_R,`CH_U,`CH_S};
            `PARAM_ID_PORTAMENTO:
                get_param_label6 = {`CH_P,`CH_O,`CH_R,`CH_T,`CH_A,`CH_SPACE};
            default: get_param_label6 = {get_param_label3(param_id),18'd0};
        endcase
    end
endfunction

`endif // FONT_3X5_VH
