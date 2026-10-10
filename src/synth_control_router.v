// 将通用MIDI事件转换为本合成器内部的演奏事件和全局参数。
//
// 测试阶段约定：
//   MIDI通道1  （内部编号0）：Note On/Off与力度；
//   MIDI通道16 （内部编号15）：合成器全局Control Change。
//
// 以后改为双UART时，两个解析器仍可复用本模块之后的参数接口。
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
    output reg [6:0]  wt_position_target,
    output reg [1:0]  waveform_select,
    output reg [6:0]  detune_amount,
    output reg [3:0]  unison_count
);

    localparam [6:0] CC_PAN             = 7'd10;
    localparam [6:0] CC_WT_POSITION     = 7'd20;
    localparam [6:0] CC_WAVEFORM_SELECT = 7'd21;
    localparam [6:0] CC_DETUNE_AMOUNT   = 7'd22;
    localparam [6:0] CC_UNISON_COUNT    = 7'd23;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_event_valid    <= 1'b0;
            note_event_on       <= 1'b0;
            note_event_note     <= 7'd0;
            note_event_velocity <= 7'd0;
            pan_target          <= 7'd64;
            wt_position_target  <= 7'd0;
            waveform_select     <= 2'd2;
            detune_amount       <= 7'd64;
            unison_count        <= DEFAULT_UNISON_COUNT;
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
                    CC_WT_POSITION:
                        wt_position_target <= raw_control_change_value;
                    CC_WAVEFORM_SELECT:
                        waveform_select <= raw_control_change_value[6:5];
                    CC_DETUNE_AMOUNT:
                        detune_amount <= raw_control_change_value;
                    CC_UNISON_COUNT:
                        unison_count
                            <= clamp_unison_count(raw_control_change_value);
                    default: begin
                        // 未映射的CC由当前版本忽略。
                    end
                endcase
            end
        end
    end

endmodule
