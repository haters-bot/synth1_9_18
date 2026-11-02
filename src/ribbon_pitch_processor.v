// 六通道电阻滑条音高处理器。
//
// 输入是ADS1256已经完成通道扫描后的24位有符号码。模块按通道保存历史、
// Gate状态和上次发送的音高，并输出带握手的连续音高事件。第一版按
// VREF=2.5 V、PGA=1、双极性满量程+/-5 V换算默认阈值；板测后可通过参数
// 替换为每条滑条的实测码值。
module ribbon_pitch_processor #(
    parameter integer CHANNEL_COUNT = 6,
    parameter integer CALIBRATED_REVERSED = 0,
    parameter signed [23:0] RAW_ACTIVE_MIN = 24'sd1409286,
    parameter signed [23:0] RAW_ACTIVE_MAX = 24'sd3858759,
    parameter signed [23:0] RAW_GATE_ON    = 24'sd922747,
    parameter signed [23:0] RAW_GATE_OFF   = 24'sd503316,
    parameter integer MAP_COEFFICIENT_Q20 = 2630,
    parameter [7:0] PITCH_DEADBAND_Q8 = 8'd4,
    parameter [6:0] DEFAULT_VELOCITY = 7'd100
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid,
    input  wire [2:0]         sample_channel,
    input  wire signed [23:0] sample_data,
    output wire               sample_ready,

    output reg                event_valid,
    input  wire               event_ready,
    output reg                event_on,
    output reg [2:0]          event_source,
    output reg [14:0]         event_pitch_q8,
    output reg [6:0]          event_velocity
);

    localparam [2:0] STATE_IDLE   = 3'd0;
    localparam [2:0] STATE_MAP    = 3'd1;
    localparam [2:0] STATE_COMMIT = 3'd2;
    localparam [2:0] STATE_MEDIAN = 3'd3;
    localparam [2:0] STATE_DELTA  = 3'd4;
    localparam [2:0] STATE_FILTER = 3'd5;
    localparam [2:0] STATE_MAG    = 3'd6;

    reg [2:0] state;
    reg signed [23:0] history_0 [0:CHANNEL_COUNT-1];
    reg signed [23:0] history_1 [0:CHANNEL_COUNT-1];
    reg signed [27:0] filtered_value [0:CHANNEL_COUNT-1];
    reg [1:0] history_count [0:CHANNEL_COUNT-1];
    reg [2:0] gate_on_count [0:CHANNEL_COUNT-1];
    reg [2:0] gate_off_count [0:CHANNEL_COUNT-1];
    reg gate_active [0:CHANNEL_COUNT-1];
    reg [14:0] last_pitch_q8 [0:CHANNEL_COUNT-1];

    reg [2:0] work_channel;
    reg signed [27:0] work_filtered;
    reg [35:0] map_product;
    reg [14:0] mapped_pitch_q8;
    reg [14:0] pitch_difference;

    wire sample_channel_valid = sample_channel < CHANNEL_COUNT;
    assign sample_ready = (state == STATE_IDLE) && !event_valid;

    function signed [23:0] median3;
        input signed [23:0] a;
        input signed [23:0] b;
        input signed [23:0] c;
        begin
            if (a > b) begin
                if (b > c) median3 = b;
                else if (a > c) median3 = c;
                else median3 = a;
            end else begin
                if (a > c) median3 = a;
                else if (b > c) median3 = c;
                else median3 = b;
            end
        end
    endfunction

    function [6:0] base_note_for_channel;
        input [2:0] channel;
        begin
            // C1、C2、C3、C4、C5、C6；每条覆盖两个八度。
            case (channel)
                3'd0: base_note_for_channel = 7'd24;
                3'd1: base_note_for_channel = 7'd36;
                3'd2: base_note_for_channel = 7'd48;
                3'd3: base_note_for_channel = 7'd60;
                3'd4: base_note_for_channel = 7'd72;
                default: base_note_for_channel = 7'd84;
            endcase
        end
    endfunction

    function signed [23:0] calibrated_min;
        input [2:0] ch;
        case (ch)
            0: calibrated_min=24'sd1568670; 1: calibrated_min=24'sd1538471;
            2: calibrated_min=24'sd1444518; default: calibrated_min=24'sd1353921;
        endcase
    endfunction
    function signed [23:0] calibrated_max;
        input [2:0] ch;
        case (ch)
            0: calibrated_max=24'sd3989622; 1: calibrated_max=24'sd3969489;
            2: calibrated_max=24'sd3920835; default: calibrated_max=24'sd3598713;
        endcase
    endfunction
    function [11:0] calibrated_coefficient;
        input [2:0] ch;
        case (ch)
            0: calibrated_coefficient=12'd2661; 1: calibrated_coefficient=12'd2650;
            2: calibrated_coefficient=12'd2602; default: calibrated_coefficient=12'd2870;
        endcase
    endfunction

    function [14:0] absolute_pitch_difference;
        input [14:0] a;
        input [14:0] b;
        begin
            absolute_pitch_difference = (a >= b) ? (a-b) : (b-a);
        end
    endfunction

    integer reset_index;
    // 锁存输入与对应历史，拆开通道选择、中值比较及滤波计算。
    // 每笔样本仍按原先的顺序处理，只增加四个系统时钟的处理延迟。
    reg signed [23:0] work_sample;
    reg signed [23:0] work_history_0;
    reg signed [23:0] work_history_1;
    reg signed [27:0] work_previous_filtered;
    reg [1:0] work_history_count;
    reg signed [23:0] selected_median;
    reg signed [28:0] filter_delta;
    reg signed [28:0] filter_increment;
    reg signed [28:0] filtered_candidate;
    reg [28:0] absolute_filter_delta;
    reg [27:0] active_delta;
    reg [14:0] pitch_candidate;
    reg [14:0] base_pitch_q8;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            event_valid <= 1'b0;
            event_on <= 1'b0;
            event_source <= 3'd0;
            event_pitch_q8 <= 15'd0;
            event_velocity <= DEFAULT_VELOCITY;
            work_channel <= 3'd0;
            work_sample <= 24'sd0;
            work_history_0 <= 24'sd0;
            work_history_1 <= 24'sd0;
            work_previous_filtered <= 28'sd0;
            work_history_count <= 2'd0;
            work_filtered <= 28'sd0;
            map_product <= 36'd0;
            mapped_pitch_q8 <= 15'd0;
            pitch_difference <= 15'd0;
            selected_median <= 24'sd0;
            filter_delta <= 29'sd0;
            filter_increment <= 29'sd0;
            filtered_candidate <= 29'sd0;
            absolute_filter_delta <= 29'd0;
            active_delta <= 28'd0;
            pitch_candidate <= 15'd0;
            base_pitch_q8 <= 15'd0;

            for (reset_index = 0;
                 reset_index < CHANNEL_COUNT;
                 reset_index = reset_index + 1) begin
                history_0[reset_index] <= 24'sd0;
                history_1[reset_index] <= 24'sd0;
                filtered_value[reset_index] <= 28'sd0;
                history_count[reset_index] <= 2'd0;
                gate_on_count[reset_index] <= 3'd0;
                gate_off_count[reset_index] <= 3'd0;
                gate_active[reset_index] <= 1'b0;
                last_pitch_q8[reset_index] <= 15'd0;
            end
        end else begin
            if (event_valid && event_ready)
                event_valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (sample_valid && sample_ready
                        && sample_channel_valid) begin
                        work_channel <= sample_channel;

                        work_sample <= sample_data;
                        work_history_0 <= history_0[sample_channel];
                        work_history_1 <= history_1[sample_channel];
                        work_previous_filtered <= filtered_value[sample_channel];
                        work_history_count <= history_count[sample_channel];
                        history_1[sample_channel] <= history_0[sample_channel];
                        history_0[sample_channel] <= sample_data;
                        if (history_count[sample_channel] < 2)
                            history_count[sample_channel]
                                <= history_count[sample_channel] + 2'd1;
                        state <= STATE_MEDIAN;
                    end
                end

                STATE_MEDIAN: begin
                    if (work_history_count < 2)
                        selected_median <= work_sample;
                    else
                        selected_median <= median3(work_sample, work_history_0, work_history_1);
                    state <= STATE_DELTA;
                end

                STATE_DELTA: begin
                    filter_delta <= $signed(selected_median) - work_previous_filtered;
                    state <= STATE_MAG;
                end

                STATE_MAG: begin
                    absolute_filter_delta <= filter_delta[28] ? -filter_delta : filter_delta;
                    state <= STATE_FILTER;
                end

                STATE_FILTER: begin
                    if (work_history_count == 0) begin
                        filtered_candidate = selected_median;
                    end else begin
                        // 保留原有阈值、算术右移和截断规则。
                        if (absolute_filter_delta >= 29'd8000)
                            filter_increment = filter_delta >>> 2;
                        else if (absolute_filter_delta >= 29'd2000)
                            filter_increment = filter_delta >>> 3;
                        else
                            filter_increment = filter_delta >>> 4;
                        filtered_candidate = work_previous_filtered + filter_increment;
                    end
                    filtered_value[work_channel] <= filtered_candidate[27:0];
                    work_filtered <= filtered_candidate[27:0];
                    state <= STATE_MAP;
                end

                STATE_MAP: begin
                    if (CALIBRATED_REVERSED != 0) begin
                        // 左端电压高，右端电压低。
                        if (work_filtered >= calibrated_max(work_channel))
                            map_product <= 36'd0;
                        else if (work_filtered <= calibrated_min(work_channel))
                            map_product <= 36'd6144 << 20;
                        else
                            map_product <= (calibrated_max(work_channel) - work_filtered)
                                           * calibrated_coefficient(work_channel);
                    end else if (work_filtered <= RAW_ACTIVE_MIN) begin
                        map_product <= 36'd0;
                    end else if (work_filtered >= RAW_ACTIVE_MAX) begin
                        map_product <= (RAW_ACTIVE_MAX - RAW_ACTIVE_MIN) * MAP_COEFFICIENT_Q20;
                    end else begin
                        map_product <= (work_filtered - RAW_ACTIVE_MIN) * MAP_COEFFICIENT_Q20;
                    end
                    state <= STATE_COMMIT;
                end

                STATE_COMMIT: begin
                    base_pitch_q8
                        = {base_note_for_channel(work_channel), 8'd0};
                    pitch_candidate = base_pitch_q8
                        + ((map_product + 36'd524288) >> 20);
                    if (pitch_candidate > {7'd108, 8'd0})
                        pitch_candidate = {7'd108, 8'd0};
                    mapped_pitch_q8 <= pitch_candidate;
                    pitch_difference <= absolute_pitch_difference(
                        pitch_candidate,
                        last_pitch_q8[work_channel]);

                    if (!gate_active[work_channel]) begin
                        gate_off_count[work_channel] <= 3'd0;
                        if (work_filtered >= RAW_GATE_ON) begin
                            if (gate_on_count[work_channel] >= 3'd2) begin
                                gate_on_count[work_channel] <= 3'd0;
                                gate_active[work_channel] <= 1'b1;
                                last_pitch_q8[work_channel]
                                    <= pitch_candidate;
                                event_valid <= 1'b1;
                                event_on <= 1'b1;
                                event_source <= work_channel;
                                event_pitch_q8 <= pitch_candidate;
                                event_velocity <= DEFAULT_VELOCITY;
                            end else begin
                                gate_on_count[work_channel]
                                    <= gate_on_count[work_channel] + 3'd1;
                            end
                        end else begin
                            gate_on_count[work_channel] <= 3'd0;
                        end
                    end else begin
                        gate_on_count[work_channel] <= 3'd0;
                        if (work_filtered <= RAW_GATE_OFF) begin
                            if (gate_off_count[work_channel] >= 3'd3) begin
                                gate_off_count[work_channel] <= 3'd0;
                                gate_active[work_channel] <= 1'b0;
                                event_valid <= 1'b1;
                                event_on <= 1'b0;
                                event_source <= work_channel;
                                // Release沿用最后一个有效音高，避免松手时下滑。
                                event_pitch_q8
                                    <= last_pitch_q8[work_channel];
                                event_velocity <= 7'd0;
                            end else begin
                                gate_off_count[work_channel]
                                    <= gate_off_count[work_channel] + 3'd1;
                            end
                        end else begin
                            gate_off_count[work_channel] <= 3'd0;
                            if (absolute_pitch_difference(
                                    pitch_candidate,
                                    last_pitch_q8[work_channel])
                                >= PITCH_DEADBAND_Q8) begin
                                last_pitch_q8[work_channel]
                                    <= pitch_candidate;
                                event_valid <= 1'b1;
                                event_on <= 1'b1;
                                event_source <= work_channel;
                                event_pitch_q8 <= pitch_candidate;
                                event_velocity <= DEFAULT_VELOCITY;
                            end
                        end
                    end
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
