// 96 kHz单声道四级全通Phaser。四级共享同一条乘法数据路径。
module global_phaser (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,
    input  wire               enable,
    input  wire [6:0]         rate_control,
    input  wire [6:0]         depth_control,
    input  wire [6:0]         center_control,
    input  wire [6:0]         feedback_control,
    input  wire [6:0]         mix_control,
    output reg                out_valid,
    output reg signed [15:0]  sample_out,
    output reg                input_overrun
);

    reg busy;
    reg signed [15:0] wet_registered;
    reg [2:0] stage_index;
    reg [23:0] lfo_phase;
    reg signed [15:0] x_state [0:3];
    reg signed [15:0] y_state [0:3];
    reg signed [15:0] chain_sample;
    reg signed [15:0] dry_sample_latched;
    reg signed [15:0] feedback_state;
    reg [14:0] coefficient_latched;
    reg enable_latched;
    reg [6:0] mix_latched;
    reg [6:0] depth_current;
    reg [6:0] center_current;
    reg [6:0] mix_current;
    integer reset_index;

    wire [7:0] triangle_unsigned = lfo_phase[23]
                                 ? ~lfo_phase[22:15]
                                 :  lfo_phase[22:15];
    wire signed [8:0] triangle_signed =
        $signed({1'b0, triangle_unsigned}) - 9'sd128;
    wire signed [15:0] modulation_product =
        triangle_signed * $signed({1'b0, depth_current});
    wire signed [8:0] modulation_delta = modulation_product >>> 7;
    wire signed [9:0] requested_position =
        $signed({1'b0, center_current}) + modulation_delta;
    wire [6:0] clamped_position =
        (requested_position < 0) ? 7'd0 :
        (requested_position > 10'sd127) ? 7'd127 :
        requested_position[6:0];
    wire [14:0] requested_coefficient =
        15'd1024 + clamped_position * 7'd112;
    wire [23:0] lfo_increment = 24'd17 + rate_control * 4'd7;

    wire signed [23:0] feedback_product =
        feedback_state * $signed({1'b0, feedback_control});
    wire signed [17:0] phaser_input_wide =
        $signed({{2{sample_in[15]}}, sample_in})
        + ($signed(feedback_product) >>> 8);
    wire signed [15:0] phaser_input = saturate_s18_to_s16(phaser_input_wide);

    wire signed [30:0] ax_product =
        chain_sample * $signed({1'b0, coefficient_latched});
    wire signed [30:0] ay_product =
        y_state[stage_index[1:0]] * $signed({1'b0, coefficient_latched});
    wire signed [18:0] stage_output_wide =
        $signed({{3{x_state[stage_index[1:0]][15]}},
                 x_state[stage_index[1:0]]})
        - ($signed(ax_product) >>> 14)
        + ($signed(ay_product) >>> 14);
    wire signed [15:0] stage_output =
        saturate_s19_to_s16(stage_output_wide);
    wire signed [16:0] wet_dry_difference =
        $signed({wet_registered[15], wet_registered})
        - $signed({dry_sample_latched[15], dry_sample_latched});
    wire signed [24:0] mix_product =
        wet_dry_difference * $signed({1'b0, mix_latched});
    wire signed [25:0] mixed_wide =
        $signed({{10{dry_sample_latched[15]}}, dry_sample_latched})
        + ($signed(mix_product) >>> 7);

    assign in_ready = !busy;

    function signed [15:0] saturate_s18_to_s16;
        input signed [17:0] value;
        begin
            if (value > 18'sd32767) saturate_s18_to_s16 = 16'sh7FFF;
            else if (value < -18'sd32768) saturate_s18_to_s16 = 16'sh8000;
            else saturate_s18_to_s16 = value[15:0];
        end
    endfunction

    function signed [15:0] saturate_s19_to_s16;
        input signed [18:0] value;
        begin
            if (value > 19'sd32767) saturate_s19_to_s16 = 16'sh7FFF;
            else if (value < -19'sd32768) saturate_s19_to_s16 = 16'sh8000;
            else saturate_s19_to_s16 = value[15:0];
        end
    endfunction

    function signed [15:0] saturate_s26_to_s16;
        input signed [25:0] value;
        begin
            if (value > 26'sd32767) saturate_s26_to_s16 = 16'sh7FFF;
            else if (value < -26'sd32768) saturate_s26_to_s16 = 16'sh8000;
            else saturate_s26_to_s16 = value[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            wet_registered <= 0;
            stage_index <= 3'd0;
            lfo_phase <= 24'd0;
            chain_sample <= 16'sd0;
            dry_sample_latched <= 16'sd0;
            feedback_state <= 16'sd0;
            coefficient_latched <= 15'd8192;
            enable_latched <= 1'b0;
            mix_latched <= 7'd0;
            depth_current <= 7'd0;
            center_current <= 7'd64;
            mix_current <= 7'd0;
            out_valid <= 1'b0;
            sample_out <= 16'sd0;
            input_overrun <= 1'b0;
            for (reset_index = 0; reset_index < 4;
                 reset_index = reset_index + 1) begin
                x_state[reset_index] <= 16'sd0;
                y_state[reset_index] <= 16'sd0;
            end
        end else begin
            out_valid <= 1'b0;
            if (in_valid && !in_ready)
                input_overrun <= 1'b1;

            if (in_valid && in_ready) begin
                busy <= 1'b1;
                stage_index <= 3'd0;
                chain_sample <= phaser_input;
                dry_sample_latched <= sample_in;
                coefficient_latched <= requested_coefficient;
                enable_latched <= enable;
                mix_latched <= mix_current;
                lfo_phase <= lfo_phase + lfo_increment;
                if (depth_current < depth_control)
                    depth_current <= depth_current + 7'd1;
                else if (depth_current > depth_control)
                    depth_current <= depth_current - 7'd1;
                if (center_current < center_control)
                    center_current <= center_current + 7'd1;
                else if (center_current > center_control)
                    center_current <= center_current - 7'd1;
                if (mix_current < mix_control)
                    mix_current <= mix_current + 7'd1;
                else if (mix_current > mix_control)
                    mix_current <= mix_current - 7'd1;
            end else if (busy) begin
                if (stage_index == 3'd4) begin
                    // 最后一级全通与干湿混合分开，避免串联乘法器。
                    if (!enable_latched || mix_latched == 7'd0)
                        sample_out <= dry_sample_latched;
                    else if (mix_latched == 7'd127)
                        sample_out <= wet_registered;
                    else sample_out <= saturate_s26_to_s16(mixed_wide);
                    out_valid <= 1'b1; busy <= 1'b0;
                end else begin
                    x_state[stage_index[1:0]] <= chain_sample;
                    y_state[stage_index[1:0]] <= stage_output;
                    chain_sample <= stage_output;
                    stage_index <= stage_index + 3'd1;
                    if (stage_index == 3'd3) begin
                        feedback_state <= stage_output;
                        wet_registered <= stage_output;
                    end
                end
            end
        end
    end

endmodule
