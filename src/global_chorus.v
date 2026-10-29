// 96 kHz单声道Chorus。4096点循环缓冲、分拍线性插值与反馈运算。
module global_chorus (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,
    input  wire               enable,
    input  wire [6:0]         rate_control,
    input  wire [6:0]         depth_control,
    input  wire [6:0]         delay_control,
    input  wire [6:0]         feedback_control,
    input  wire [6:0]         mix_control,
    output reg                out_valid,
    output reg signed [15:0]  sample_out,
    output reg                input_overrun
);

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_READ_SECOND = 2'd1;
    localparam [1:0] STATE_PROCESS = 2'd2;
    localparam [1:0] STATE_INTERPOLATE = 2'd3;
    reg signed [15:0] wet_sample;

    (* syn_ramstyle = "block_ram" *)
    reg signed [15:0] delay_memory [0:4095];

    reg [1:0] state;
    reg [11:0] write_pointer;
    reg [12:0] samples_written;
    reg [23:0] lfo_phase;
    reg signed [15:0] dry_sample_latched;
    reg signed [15:0] read_sample_0;
    reg signed [15:0] read_sample_1;
    reg read_valid_latched;
    reg [7:0] fraction_latched;
    reg [11:0] second_read_address;
    reg enable_latched;
    reg [6:0] feedback_latched;
    reg [6:0] mix_latched;
    reg [6:0] depth_current;
    reg [6:0] delay_current;
    reg [6:0] mix_current;

    wire [7:0] triangle_unsigned = lfo_phase[23]
                                 ? ~lfo_phase[22:15]
                                 :  lfo_phase[22:15];
    wire signed [8:0] triangle_signed =
        $signed({1'b0, triangle_unsigned}) - 9'sd128;
    wire signed [15:0] modulation_product =
        triangle_signed * $signed({1'b0, depth_current});
    wire signed [20:0] base_delay_q8 =
        (21'sd192 + $signed({1'b0, delay_current}) * 21'sd16) <<< 8;
    wire signed [20:0] requested_delay_q8 =
        base_delay_q8 + ($signed(modulation_product) <<< 3);
    wire [20:0] clamped_delay_q8 =
        (requested_delay_q8 < 21'sd4096) ? 21'd4096 :
        (requested_delay_q8 > 21'sd896000) ? 21'd896000 :
        requested_delay_q8[20:0];
    wire [11:0] delay_integer = clamped_delay_q8[19:8];
    wire [7:0] delay_fraction = clamped_delay_q8[7:0];
    wire [11:0] first_read_address = write_pointer - delay_integer;
    wire [11:0] next_read_address = first_read_address - 12'd1;
    wire history_available = (delay_fraction == 8'd0)
                           ? (samples_written >= {1'b0, delay_integer})
                           : (samples_written > {1'b0, delay_integer});
    wire [23:0] lfo_increment = 24'd17 + rate_control * 4'd7;

    wire signed [16:0] interpolation_difference =
        $signed({read_sample_1[15], read_sample_1})
        - $signed({read_sample_0[15], read_sample_0});
    wire signed [24:0] interpolation_product =
        interpolation_difference * $signed({1'b0, fraction_latched});
    wire signed [17:0] interpolated_wide =
        $signed({{2{read_sample_0[15]}}, read_sample_0})
        + ($signed(interpolation_product) >>> 8);
    wire signed [15:0] interpolated_sample =
        (fraction_latched == 8'd0)
        ? read_sample_0 : saturate_s18_to_s16(interpolated_wide);
    wire signed [15:0] wet_interpolated = read_valid_latched
                                   ? interpolated_sample : 16'sd0;
    wire signed [23:0] feedback_product =
        wet_sample * $signed({1'b0, feedback_latched});
    wire signed [24:0] write_wide =
        $signed({{9{dry_sample_latched[15]}}, dry_sample_latched})
        + ($signed(feedback_product) >>> 8);
    wire signed [16:0] wet_dry_difference =
        $signed({wet_sample[15], wet_sample})
        - $signed({dry_sample_latched[15], dry_sample_latched});
    wire signed [24:0] mix_product =
        wet_dry_difference * $signed({1'b0, mix_latched});
    wire signed [25:0] mixed_wide =
        $signed({{10{dry_sample_latched[15]}}, dry_sample_latched})
        + ($signed(mix_product) >>> 7);

    assign in_ready = state == STATE_IDLE;

    function signed [15:0] saturate_s18_to_s16;
        input signed [17:0] value;
        begin
            if (value > 18'sd32767) saturate_s18_to_s16 = 16'sh7FFF;
            else if (value < -18'sd32768) saturate_s18_to_s16 = 16'sh8000;
            else saturate_s18_to_s16 = value[15:0];
        end
    endfunction

    function signed [15:0] saturate_s25_to_s16;
        input signed [24:0] value;
        begin
            if (value > 25'sd32767) saturate_s25_to_s16 = 16'sh7FFF;
            else if (value < -25'sd32768) saturate_s25_to_s16 = 16'sh8000;
            else saturate_s25_to_s16 = value[15:0];
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
            state <= STATE_IDLE;
            wet_sample <= 0;
            write_pointer <= 12'd0;
            samples_written <= 13'd0;
            lfo_phase <= 24'd0;
            dry_sample_latched <= 16'sd0;
            read_sample_0 <= 16'sd0;
            read_sample_1 <= 16'sd0;
            read_valid_latched <= 1'b0;
            fraction_latched <= 8'd0;
            second_read_address <= 12'd0;
            enable_latched <= 1'b0;
            feedback_latched <= 7'd0;
            mix_latched <= 7'd0;
            depth_current <= 7'd0;
            delay_current <= 7'd0;
            mix_current <= 7'd0;
            out_valid <= 1'b0;
            sample_out <= 16'sd0;
            input_overrun <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            if (in_valid && !in_ready)
                input_overrun <= 1'b1;

            case (state)
                STATE_IDLE: if (in_valid) begin
                    dry_sample_latched <= sample_in;
                    read_sample_0 <= delay_memory[first_read_address];
                    second_read_address <= next_read_address;
                    read_valid_latched <= history_available;
                    fraction_latched <= delay_fraction;
                    enable_latched <= enable;
                    feedback_latched <= feedback_control;
                    mix_latched <= mix_current;
                    lfo_phase <= lfo_phase + lfo_increment;
                    if (depth_current < depth_control)
                        depth_current <= depth_current + 7'd1;
                    else if (depth_current > depth_control)
                        depth_current <= depth_current - 7'd1;
                    if (delay_current < delay_control)
                        delay_current <= delay_current + 7'd1;
                    else if (delay_current > delay_control)
                        delay_current <= delay_current - 7'd1;
                    if (mix_current < mix_control)
                        mix_current <= mix_current + 7'd1;
                    else if (mix_current > mix_control)
                        mix_current <= mix_current - 7'd1;
                    state <= STATE_READ_SECOND;
                end

                STATE_READ_SECOND: begin
                    read_sample_1 <= delay_memory[second_read_address];
                    state <= STATE_INTERPOLATE;
                end

                // 插值结果独立保存，反馈仍只在每个音频样本写回一次。
                STATE_INTERPOLATE: begin
                    wet_sample <= wet_interpolated;
                    state <= STATE_PROCESS;
                end
                STATE_PROCESS: begin
                    delay_memory[write_pointer]
                        <= saturate_s25_to_s16(write_wide);
                    write_pointer <= write_pointer + 12'd1;
                    if (samples_written < 13'd4096)
                        samples_written <= samples_written + 13'd1;
                    if (!enable_latched || mix_latched == 7'd0)
                        sample_out <= dry_sample_latched;
                    else if (mix_latched == 7'd127)
                        sample_out <= wet_sample;
                    else
                        sample_out <= saturate_s26_to_s16(mixed_wide);
                    out_valid <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
