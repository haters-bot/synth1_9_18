// 96 kHz单声道失真。包含软削波、硬削波和折返三种波形整形方式。
module global_distortion (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,
    input  wire               enable,
    input  wire [1:0]         distortion_type,
    input  wire [6:0]         drive_control,
    input  wire [6:0]         tone_control,
    input  wire [6:0]         mix_control,
    output reg                out_valid,
    output reg signed [15:0]  sample_out,
    output reg                input_overrun
);

    // 每个样本独占状态机；寄存器边界切断多个乘法器串联。
    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_GAIN = 3'd1;
    localparam [2:0] STATE_DRIVE = 3'd2;
    localparam [2:0] STATE_SHAPE = 3'd3;
    localparam [2:0] STATE_TONE_PRODUCT = 3'd4;
    localparam [2:0] STATE_TONE_STATE = 3'd5;
    localparam [2:0] STATE_MIX_PRODUCT = 3'd6;
    localparam [2:0] STATE_OUTPUT = 3'd7;
    reg [2:0] state;
    reg signed [15:0] dry_latched, shaped_latched, wet_latched;
    reg enable_latched;
    reg [1:0] type_latched;
    reg [6:0] drive_latched, tone_latched, mix_latched;
    reg [11:0] gain_latched;
    reg signed [27:0] drive_registered;
    reg signed [24:0] tone_registered, mix_registered;
    reg signed [15:0] tone_state;

    wire [11:0] drive_gain_q8 = 12'd256 + drive_latched * 5'd14;
    wire signed [27:0] drive_product =
        $signed(dry_latched) * $signed({1'b0, gain_latched});
    wire signed [27:0] driven_wide = drive_registered >>> 8;
    wire signed [15:0] shaped_sample = shape_sample(
        driven_wide, type_latched
    );
    wire [7:0] tone_coefficient = {1'b0, tone_latched} + 8'd1;
    wire signed [16:0] tone_difference =
        $signed({shaped_latched[15], shaped_latched})
        - $signed({tone_state[15], tone_state});
    wire signed [24:0] tone_product =
        tone_difference * $signed({1'b0, tone_coefficient});
    wire signed [17:0] tone_next_wide =
        $signed({{2{tone_state[15]}}, tone_state})
        + ($signed(tone_registered) >>> 7);
    wire signed [15:0] tone_next = saturate_s18_to_s16(tone_next_wide);
    wire signed [16:0] wet_dry_difference =
        $signed({wet_latched[15], wet_latched})
        - $signed({dry_latched[15], dry_latched});
    wire signed [24:0] mix_product =
        wet_dry_difference * $signed({1'b0, mix_latched});
    wire signed [25:0] mixed_wide =
        $signed({{10{dry_latched[15]}}, dry_latched})
        + ($signed(mix_registered) >>> 7);

    assign in_ready = (state == STATE_IDLE);

    function signed [15:0] saturate_s18_to_s16;
        input signed [17:0] value;
        begin
            if (value > 18'sd32767)
                saturate_s18_to_s16 = 16'sh7FFF;
            else if (value < -18'sd32768)
                saturate_s18_to_s16 = 16'sh8000;
            else
                saturate_s18_to_s16 = value[15:0];
        end
    endfunction

    function signed [15:0] saturate_s26_to_s16;
        input signed [25:0] value;
        begin
            if (value > 26'sd32767)
                saturate_s26_to_s16 = 16'sh7FFF;
            else if (value < -26'sd32768)
                saturate_s26_to_s16 = 16'sh8000;
            else
                saturate_s26_to_s16 = value[15:0];
        end
    endfunction

    function signed [15:0] shape_sample;
        input signed [27:0] value;
        input [1:0] shape_type;
        reg signed [27:0] shaped;
        begin
            case (shape_type)
                2'd1: begin
                    if (value > 28'sd24576)
                        shaped = 28'sd24576;
                    else if (value < -28'sd24576)
                        shaped = -28'sd24576;
                    else
                        shaped = value;
                end
                2'd2: begin
                    if (value > 28'sd49152)
                        shaped = 28'sd0;
                    else if (value > 28'sd24576)
                        shaped = 28'sd49152 - value;
                    else if (value < -28'sd49152)
                        shaped = 28'sd0;
                    else if (value < -28'sd24576)
                        shaped = -28'sd49152 - value;
                    else
                        shaped = value;
                end
                default: begin
                    if (value > 28'sd24576)
                        shaped = 28'sd20480 + ((value - 28'sd24576) >>> 3);
                    else if (value > 28'sd8192)
                        shaped = 28'sd8192 + ((value - 28'sd8192) >>> 1);
                    else if (value < -28'sd24576)
                        shaped = -28'sd20480 + ((value + 28'sd24576) >>> 3);
                    else if (value < -28'sd8192)
                        shaped = -28'sd8192 + ((value + 28'sd8192) >>> 1);
                    else
                        shaped = value;
                end
            endcase

            if (shaped > 28'sd32767)
                shape_sample = 16'sh7FFF;
            else if (shaped < -28'sd32768)
                shape_sample = 16'sh8000;
            else
                shape_sample = shaped[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            dry_latched <= 0; shaped_latched <= 0; wet_latched <= 0;
            enable_latched <= 0; type_latched <= 0;
            drive_latched <= 0; tone_latched <= 0; mix_latched <= 0;
            gain_latched <= 0; drive_registered <= 0;
            tone_registered <= 0; mix_registered <= 0;
            tone_state <= 0; out_valid <= 0; sample_out <= 0;
            input_overrun <= 0;
        end else begin
            out_valid <= 0;
            if (in_valid && !in_ready) input_overrun <= 1;
            case (state)
                STATE_IDLE: if (in_valid) begin
                    dry_latched <= sample_in;
                    enable_latched <= enable; type_latched <= distortion_type;
                    drive_latched <= drive_control; tone_latched <= tone_control;
                    mix_latched <= mix_control;
                    state <= STATE_GAIN;
                end
                STATE_GAIN: begin
                    gain_latched <= drive_gain_q8;
                    state <= STATE_DRIVE;
                end
                STATE_DRIVE: begin
                    drive_registered <= drive_product;
                    state <= STATE_SHAPE;
                end
                STATE_SHAPE: begin
                    shaped_latched <= shaped_sample;
                    state <= STATE_TONE_PRODUCT;
                end
                STATE_TONE_PRODUCT: begin
                    tone_registered <= tone_product;
                    state <= STATE_TONE_STATE;
                end
                STATE_TONE_STATE: begin
                    // 即使旁路也保持原来的音色滤波状态递推。
                    tone_state <= tone_next;
                    wet_latched <= tone_next;
                    state <= STATE_MIX_PRODUCT;
                end
                STATE_MIX_PRODUCT: begin
                    mix_registered <= mix_product;
                    state <= STATE_OUTPUT;
                end
                STATE_OUTPUT: begin
                    if (!enable_latched || mix_latched == 0)
                        sample_out <= dry_latched;
                    else if (mix_latched == 127) sample_out <= wet_latched;
                    else sample_out <= saturate_s26_to_s16(mixed_wide);
                    out_valid <= 1'b1;
                    state <= STATE_IDLE;
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
