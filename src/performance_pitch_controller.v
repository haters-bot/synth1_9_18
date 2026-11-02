// 演奏级音高控制器。
//
// 1. Portamento关闭时，Note事件原样送往复音任务调度器；
// 2. Portamento开启时，使用8键栈实现最后音符优先的单音Legato；
// 3. 滑音基础步进由OSC A/B共享，Vibrato以频率比例作用于所有活动槽位。
module performance_pitch_controller #(
    parameter [6:0] MIN_NOTE = 7'd21,
    parameter [6:0] MAX_NOTE = 7'd108,
    parameter integer NOTE_STACK_DEPTH = 8
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sample_tick,

    input  wire       note_event_valid,
    input  wire       note_event_on,
    input  wire [6:0] note_event_note,
    input  wire [6:0] note_event_velocity,

    input  wire       vibrato_enable,
    input  wire [6:0] vibrato_rate,
    input  wire [6:0] vibrato_depth,
    input  wire       portamento_enable,
    input  wire [6:0] portamento_time,

    output reg        routed_note_event_valid,
    output reg        routed_note_event_on,
    output reg [6:0]  routed_note_event_note,
    output reg [6:0]  routed_note_event_velocity,

    output wire       glide_override_enable,
    output reg [31:0] glide_base_step,
    output reg signed [12:0] vibrato_ratio_delta_q16,
    output wire [23:0] debug_current_pitch_q16,
    output wire [23:0] debug_target_pitch_q16
);

    reg [6:0] note_stack [0:NOTE_STACK_DEPTH-1];
    reg [3:0] held_note_count;
    reg       mono_owner_valid;
    reg [6:0] mono_owner_note;
    reg       mono_gate_active;
    reg       portamento_enable_d;

    reg [23:0] current_pitch_q16;
    reg [23:0] target_pitch_q16;
    wire [23:0] glide_increment_q16;
    reg  [23:0] next_pitch_q16;

    reg [31:0] vibrato_phase;
    wire [19:0] vibrato_rate_product;
    wire [31:0] vibrato_phase_increment;
    // 相位仅在sample_tick变化：提前求出下一相位的正弦值并寄存，
    // 把波表查找与深度乘法分开，同时保持颤音输出周期不变。
    reg signed [15:0] vibrato_sine;
    wire signed [15:0] vibrato_next_sine;
    wire [31:0] vibrato_next_phase = vibrato_phase + vibrato_phase_increment;
    wire signed [23:0] vibrato_depth_product;
    wire [23:0] vibrato_depth_product_abs;
    wire [30:0] vibrato_positive_scaled;
    wire [30:0] vibrato_negative_scaled;

    reg [6:0]  interp_note_0;
    reg [6:0]  interp_note_1;
    reg [15:0] interp_fraction_0;
    reg        interp_valid_0;
    wire [31:0] interp_step_0;
    wire [31:0] interp_step_1;
    reg [31:0] interp_base_step_1;
    reg [31:0] interp_step_delta_1;
    reg [15:0] interp_fraction_1;
    reg        interp_valid_1;
    reg [47:0] interp_product_2;
    reg [31:0] interp_base_step_2;
    reg        interp_valid_2;

    wire [31:0] event_note_step;
    reg stack_note_found;
    reg [3:0] stack_note_index;
    integer scan_index;
    integer reset_index;

    assign glide_override_enable = portamento_enable && mono_owner_valid;
    assign debug_current_pitch_q16 = current_pitch_q16;
    assign debug_target_pitch_q16 = target_pitch_q16;

    // 0.1～约12.1 Hz，控制值每增加1约增加0.0945 Hz。
    assign vibrato_rate_product = vibrato_rate * 13'd4227;
    assign vibrato_phase_increment = 32'd4474
                                    + {12'd0, vibrato_rate_product};
    assign vibrato_depth_product = $signed(vibrato_sine)
                                  * $signed({1'b0, vibrato_depth});
    assign vibrato_depth_product_abs = vibrato_depth_product[23]
                                      ? (~vibrato_depth_product + 24'd1)
                                      : vibrato_depth_product;
    // 深度127约等于正负100 cent。正负方向使用不同斜率，逼近
    // 2^(cents/1200)在正负一个半音处的不对称比例。
    assign vibrato_positive_scaled = vibrato_depth_product_abs * 7'd61;
    assign vibrato_negative_scaled = vibrato_depth_product_abs * 7'd58;

    sine_lut u_vibrato_sine_lut (
        .addr(vibrato_next_phase[31:24]),
        .data(vibrato_next_sine)
    );

    freq_lut u_event_note_freq_lut (
        .addr(note_event_note),
        .data(event_note_step)
    );

    freq_lut u_glide_low_freq_lut (
        .addr(interp_note_0),
        .data(interp_step_0)
    );

    freq_lut u_glide_high_freq_lut (
        .addr(interp_note_1),
        .data(interp_step_1)
    );

    // 固定速率滑音：表中时间表示跨越一个八度的大约耗时。
    // 5/10/20/50/100/250/500/1000/2000 ms分段避免动态除法器。
    function [23:0] decode_glide_increment;
        input [6:0] control_value;
        begin
            if (control_value == 7'd0)
                decode_glide_increment = 24'hFFFFFF;
            else if (control_value < 7'd16)
                decode_glide_increment = 24'd1638;
            else if (control_value < 7'd32)
                decode_glide_increment = 24'd819;
            else if (control_value < 7'd48)
                decode_glide_increment = 24'd410;
            else if (control_value < 7'd64)
                decode_glide_increment = 24'd164;
            else if (control_value < 7'd80)
                decode_glide_increment = 24'd82;
            else if (control_value < 7'd96)
                decode_glide_increment = 24'd33;
            else if (control_value < 7'd112)
                decode_glide_increment = 24'd16;
            else if (control_value < 7'd120)
                decode_glide_increment = 24'd8;
            else
                decode_glide_increment = 24'd4;
        end
    endfunction

    assign glide_increment_q16 = decode_glide_increment(portamento_time);

    always @(*) begin
        stack_note_found = 1'b0;
        stack_note_index = 4'd0;
        for (scan_index = 0;
             scan_index < NOTE_STACK_DEPTH;
             scan_index = scan_index + 1) begin
            if (!stack_note_found
                && (scan_index < held_note_count)
                && (note_stack[scan_index] == note_event_note)) begin
                stack_note_found = 1'b1;
                stack_note_index = scan_index[3:0];
            end
        end
    end

    // 先在Q7.16半音域中移动，再由相邻MIDI音符的phase step插值。
    always @(*) begin
        next_pitch_q16 = current_pitch_q16;
        if (portamento_time == 7'd0) begin
            next_pitch_q16 = target_pitch_q16;
        end else if (current_pitch_q16 < target_pitch_q16) begin
            if ((target_pitch_q16 - current_pitch_q16)
                <= glide_increment_q16)
                next_pitch_q16 = target_pitch_q16;
            else
                next_pitch_q16 = current_pitch_q16 + glide_increment_q16;
        end else if (current_pitch_q16 > target_pitch_q16) begin
            if ((current_pitch_q16 - target_pitch_q16)
                <= glide_increment_q16)
                next_pitch_q16 = target_pitch_q16;
            else
                next_pitch_q16 = current_pitch_q16 - glide_increment_q16;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            routed_note_event_valid <= 1'b0;
            routed_note_event_on <= 1'b0;
            routed_note_event_note <= 7'd0;
            routed_note_event_velocity <= 7'd0;
            held_note_count <= 4'd0;
            mono_owner_valid <= 1'b0;
            mono_owner_note <= 7'd0;
            mono_gate_active <= 1'b0;
            portamento_enable_d <= 1'b0;
            current_pitch_q16 <= {MIN_NOTE, 16'd0};
            target_pitch_q16 <= {MIN_NOTE, 16'd0};
            glide_base_step <= 32'd0;
            vibrato_phase <= 32'd0;
            vibrato_sine <= 16'sd0;
            vibrato_ratio_delta_q16 <= 13'sd0;
            interp_note_0 <= MIN_NOTE;
            interp_note_1 <= MIN_NOTE + 7'd1;
            interp_fraction_0 <= 16'd0;
            interp_valid_0 <= 1'b0;
            interp_base_step_1 <= 32'd0;
            interp_step_delta_1 <= 32'd0;
            interp_fraction_1 <= 16'd0;
            interp_valid_1 <= 1'b0;
            interp_product_2 <= 48'd0;
            interp_base_step_2 <= 32'd0;
            interp_valid_2 <= 1'b0;
            for (reset_index = 0;
                 reset_index < NOTE_STACK_DEPTH;
                 reset_index = reset_index + 1)
                note_stack[reset_index] <= 7'd0;
        end else begin
            routed_note_event_valid <= 1'b0;
            portamento_enable_d <= portamento_enable;
            interp_valid_0 <= 1'b0;
            interp_valid_1 <= interp_valid_0;
            if (interp_valid_0) begin
                interp_base_step_1 <= interp_step_0;
                interp_step_delta_1 <= interp_step_1 - interp_step_0;
                interp_fraction_1 <= interp_fraction_0;
            end

            interp_valid_2 <= interp_valid_1;
            if (interp_valid_1) begin
                interp_product_2
                    <= interp_step_delta_1 * interp_fraction_1;
                interp_base_step_2 <= interp_base_step_1;
            end

            if (interp_valid_2)
                glide_base_step <= interp_base_step_2
                                 + interp_product_2[47:16];

            // 关闭Portamento时先释放仍由单音控制器持有的任务，再恢复直通。
            if (portamento_enable_d && !portamento_enable
                && mono_gate_active) begin
                routed_note_event_valid <= 1'b1;
                routed_note_event_on <= 1'b0;
                routed_note_event_note <= mono_owner_note;
                routed_note_event_velocity <= 7'd0;
                mono_gate_active <= 1'b0;
                mono_owner_valid <= 1'b0;
                held_note_count <= 4'd0;
            end else if (!portamento_enable) begin
                held_note_count <= 4'd0;
                mono_gate_active <= 1'b0;
                mono_owner_valid <= 1'b0;
                if (note_event_valid) begin
                    routed_note_event_valid <= 1'b1;
                    routed_note_event_on <= note_event_on;
                    routed_note_event_note <= note_event_note;
                    routed_note_event_velocity <= note_event_velocity;
                end
            end else if (note_event_valid
                         && (note_event_note >= MIN_NOTE)
                         && (note_event_note <= MAX_NOTE)) begin
                if (note_event_on) begin
                    if (!stack_note_found
                        && (held_note_count < NOTE_STACK_DEPTH)) begin
                            note_stack[held_note_count] <= note_event_note;
                            held_note_count <= held_note_count + 4'd1;

                        if (!mono_gate_active) begin
                            routed_note_event_valid <= 1'b1;
                            routed_note_event_on <= 1'b1;
                            routed_note_event_note <= mono_owner_valid
                                                    ? mono_owner_note
                                                    : note_event_note;
                            routed_note_event_velocity <= note_event_velocity;
                            if (!mono_owner_valid) begin
                                mono_owner_valid <= 1'b1;
                                mono_owner_note <= note_event_note;
                            end
                            mono_gate_active <= 1'b1;
                            current_pitch_q16 <= {note_event_note, 16'd0};
                            target_pitch_q16 <= {note_event_note, 16'd0};
                            glide_base_step <= event_note_step;
                        end else begin
                            target_pitch_q16 <= {note_event_note, 16'd0};
                            if (portamento_time == 7'd0) begin
                                current_pitch_q16 <= {note_event_note, 16'd0};
                                glide_base_step <= event_note_step;
                            end
                        end
                    end
                end else if (stack_note_found) begin
                    for (reset_index = 0;
                         reset_index < NOTE_STACK_DEPTH-1;
                         reset_index = reset_index + 1) begin
                        if ((reset_index >= stack_note_index)
                            && (reset_index < held_note_count-1))
                            note_stack[reset_index]
                                <= note_stack[reset_index+1];
                    end
                    note_stack[held_note_count-1] <= 7'd0;
                    held_note_count <= held_note_count - 4'd1;

                    if (held_note_count == 4'd1) begin
                        routed_note_event_valid <= 1'b1;
                        routed_note_event_on <= 1'b0;
                        routed_note_event_note <= mono_owner_note;
                        routed_note_event_velocity <= 7'd0;
                        mono_gate_active <= 1'b0;
                    end else if (stack_note_index
                                 == held_note_count - 4'd1) begin
                        target_pitch_q16
                            <= {note_stack[held_note_count-2], 16'd0};
                        if (portamento_time == 7'd0)
                            current_pitch_q16
                                <= {note_stack[held_note_count-2], 16'd0};
                    end
                end
            end

            if (sample_tick) begin
                // Note事件与采样脉冲极少数同拍时，按键事件对当前音高的
                // 初始化优先，避免被基于旧目标计算的next_pitch覆盖。
                if (!(note_event_valid && portamento_enable))
                    current_pitch_q16 <= next_pitch_q16;

                if (mono_owner_valid
                    && !(note_event_valid && portamento_enable)) begin
                    if (next_pitch_q16[22:16] >= MAX_NOTE) begin
                        interp_note_0 <= MAX_NOTE;
                        interp_note_1 <= MAX_NOTE;
                        interp_fraction_0 <= 16'd0;
                    end else if (next_pitch_q16[22:16] <= MIN_NOTE) begin
                        interp_note_0 <= MIN_NOTE;
                        interp_note_1 <= MIN_NOTE + 7'd1;
                        interp_fraction_0 <= (next_pitch_q16[22:16]
                                              < MIN_NOTE)
                                             ? 16'd0
                                             : next_pitch_q16[15:0];
                    end else begin
                        interp_note_0 <= next_pitch_q16[22:16];
                        interp_note_1 <= next_pitch_q16[22:16] + 7'd1;
                        interp_fraction_0 <= next_pitch_q16[15:0];
                    end
                    interp_valid_0 <= 1'b1;
                end

                if (vibrato_enable) begin
                    vibrato_phase <= vibrato_next_phase;
                    vibrato_sine <= vibrato_next_sine;
                    if (vibrato_depth_product[23])
                        vibrato_ratio_delta_q16
                            <= -$signed({1'b0,
                                 vibrato_negative_scaled[27:16]});
                    else
                        vibrato_ratio_delta_q16
                            <= $signed({1'b0,
                                vibrato_positive_scaled[27:16]});
                end else begin
                    vibrato_phase <= 32'd0;
                    vibrato_sine <= 16'sd0;
                    vibrato_ratio_delta_q16 <= 13'sd0;
                end
            end

        end
    end

endmodule
