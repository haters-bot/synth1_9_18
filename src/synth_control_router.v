// 将通用MIDI事件转换为演奏事件和两组独立振荡器参数。
//
// 测试阶段约定：
//   MIDI通道1  （内部编号0）：Note On/Off与力度；
//   MIDI通道16 （内部编号15）：OSC A、OSC B和全局Control Change。
//
// 两个振荡器共享键盘事件，但拥有独立的音色参数和任务调度器。
module synth_control_router #(
    parameter [3:0] PERFORMANCE_CHANNEL = 4'd0,
    parameter [3:0] CONTROL_CHANNEL     = 4'd15,
    parameter [3:0] DEFAULT_UNISON_COUNT = 4'd1
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       raw_note_event_valid,
    input  wire       raw_note_event_on,
    input  wire [3:0] raw_note_event_channel,
    input  wire [6:0] raw_note_event_note,
    input  wire [6:0] raw_note_event_velocity,

    input  wire       raw_control_change_valid,
    input  wire [3:0] raw_control_change_channel,
    input  wire [6:0] raw_control_change_number,
    input  wire [6:0] raw_control_change_value,

    output reg        note_event_valid,
    output reg        note_event_on,
    output reg [6:0]  note_event_note,
    output reg [6:0]  note_event_velocity,

    output reg [6:0]  pan_target,

    output reg [6:0]  osc_a_wt_position_target,
    output reg [2:0]  osc_a_waveform_select,
    output reg [6:0]  osc_a_detune_amount,
    output reg [3:0]  osc_a_unison_count,
    output reg [6:0]  osc_a_attack_control,
    output reg [6:0]  osc_a_decay_control,
    output reg [6:0]  osc_a_sustain_control,
    output reg [6:0]  osc_a_release_control,
    output reg        osc_a_enabled,

    output reg [6:0]  osc_b_wt_position_target,
    output reg [2:0]  osc_b_waveform_select,
    output reg [6:0]  osc_b_detune_amount,
    output reg [3:0]  osc_b_unison_count,
    output reg [6:0]  osc_b_attack_control,
    output reg [6:0]  osc_b_decay_control,
    output reg [6:0]  osc_b_sustain_control,
    output reg [6:0]  osc_b_release_control,
    output reg        osc_b_enabled
);

    localparam [6:0] CC_PAN = 7'd10;

    localparam [6:0] CC_A_WT_POSITION     = 7'd20;
    localparam [6:0] CC_A_WAVEFORM_SELECT = 7'd21;
    localparam [6:0] CC_A_DETUNE_AMOUNT   = 7'd22;
    localparam [6:0] CC_A_UNISON_COUNT    = 7'd23;
    localparam [6:0] CC_A_ATTACK          = 7'd24;
    localparam [6:0] CC_A_DECAY           = 7'd25;
    localparam [6:0] CC_A_SUSTAIN         = 7'd26;
    localparam [6:0] CC_A_RELEASE         = 7'd27;

    localparam [6:0] CC_B_WT_POSITION     = 7'd28;
    localparam [6:0] CC_B_WAVEFORM_SELECT = 7'd29;
    localparam [6:0] CC_B_DETUNE_AMOUNT   = 7'd30;
    localparam [6:0] CC_B_UNISON_COUNT    = 7'd31;
    localparam [6:0] CC_B_ATTACK          = 7'd32;
    localparam [6:0] CC_B_DECAY           = 7'd33;
    localparam [6:0] CC_B_SUSTAIN         = 7'd34;
    localparam [6:0] CC_B_RELEASE         = 7'd35;
    localparam [6:0] CC_A_ENABLE          = 7'd36;
    localparam [6:0] CC_B_ENABLE          = 7'd37;

    function [3:0] clamp_unison_count;
        input [6:0] requested_count;
        begin
            if (requested_count < 7'd1)
                clamp_unison_count = 4'd1;
            else if (requested_count > 7'd8)
                clamp_unison_count = 4'd8;
            else
                clamp_unison_count = requested_count[3:0];
        end
    endfunction

    function [2:0] decode_waveform;
        input [6:0] requested_waveform;
        begin
            // 0/32/64/96保持四种基本波形；127选择Acid波表。
            decode_waveform = (requested_waveform == 7'd127)
                            ? 3'd4
                            : {1'b0, requested_waveform[6:5]};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_event_valid    <= 1'b0;
            note_event_on       <= 1'b0;
            note_event_note     <= 7'd0;
            note_event_velocity <= 7'd0;
            pan_target          <= 7'd64;

            osc_a_wt_position_target <= 7'd0;
            osc_a_waveform_select    <= 3'd2;
            osc_a_detune_amount      <= 7'd64;
            osc_a_unison_count       <= DEFAULT_UNISON_COUNT;
            osc_a_attack_control     <= 7'd27;
            osc_a_decay_control      <= 7'd54;
            osc_a_sustain_control    <= 7'd89;
            osc_a_release_control    <= 7'd67;
            osc_a_enabled            <= 1'b1;

            osc_b_wt_position_target <= 7'd0;
            osc_b_waveform_select    <= 3'd2;
            osc_b_detune_amount      <= 7'd64;
            osc_b_unison_count       <= DEFAULT_UNISON_COUNT;
            osc_b_attack_control     <= 7'd27;
            osc_b_decay_control      <= 7'd54;
            osc_b_sustain_control    <= 7'd89;
            osc_b_release_control    <= 7'd67;
            osc_b_enabled            <= 1'b1;
        end else begin
            note_event_valid <= 1'b0;

            if (raw_note_event_valid
                && (raw_note_event_channel == PERFORMANCE_CHANNEL)) begin
                note_event_valid    <= 1'b1;
                note_event_on       <= raw_note_event_on;
                note_event_note     <= raw_note_event_note;
                note_event_velocity <= raw_note_event_velocity;
            end

            if (raw_control_change_valid
                && (raw_control_change_channel == CONTROL_CHANNEL)) begin
                case (raw_control_change_number)
                    CC_PAN:
                        pan_target <= raw_control_change_value;

                    CC_A_WT_POSITION:
                        osc_a_wt_position_target <= raw_control_change_value;
                    CC_A_WAVEFORM_SELECT:
                        osc_a_waveform_select
                            <= decode_waveform(raw_control_change_value);
                    CC_A_DETUNE_AMOUNT:
                        osc_a_detune_amount <= raw_control_change_value;
                    CC_A_UNISON_COUNT:
                        osc_a_unison_count
                            <= clamp_unison_count(raw_control_change_value);
                    CC_A_ATTACK:
                        osc_a_attack_control <= raw_control_change_value;
                    CC_A_DECAY:
                        osc_a_decay_control <= raw_control_change_value;
                    CC_A_SUSTAIN:
                        osc_a_sustain_control <= raw_control_change_value;
                    CC_A_RELEASE:
                        osc_a_release_control <= raw_control_change_value;

                    CC_B_WT_POSITION:
                        osc_b_wt_position_target <= raw_control_change_value;
                    CC_B_WAVEFORM_SELECT:
                        osc_b_waveform_select
                            <= decode_waveform(raw_control_change_value);
                    CC_B_DETUNE_AMOUNT:
                        osc_b_detune_amount <= raw_control_change_value;
                    CC_B_UNISON_COUNT:
                        osc_b_unison_count
                            <= clamp_unison_count(raw_control_change_value);
                    CC_B_ATTACK:
                        osc_b_attack_control <= raw_control_change_value;
                    CC_B_DECAY:
                        osc_b_decay_control <= raw_control_change_value;
                    CC_B_SUSTAIN:
                        osc_b_sustain_control <= raw_control_change_value;
                    CC_B_RELEASE:
                        osc_b_release_control <= raw_control_change_value;
                    CC_A_ENABLE:
                        osc_a_enabled <= (raw_control_change_value != 7'd0);
                    CC_B_ENABLE:
                        osc_b_enabled <= (raw_control_change_value != 7'd0);
                    default: begin
                        // 未映射的CC由当前版本忽略。
                    end
                endcase
            end
        end
    end

endmodule
