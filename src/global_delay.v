// 96 kHz 单声道反馈延迟。
// 32768 点循环缓冲提供约 5～336 ms 的可调延迟，RAM 不在复位时清零；
// 写入计数用于屏蔽尚未写过的地址，避免上电后的未知数据进入音频流。
module global_delay (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] sample_in,
    output wire               in_ready,
    input  wire [6:0]         time_control,
    input  wire [6:0]         feedback_control,
    input  wire [6:0]         mix_control,
    output reg                out_valid,
    output reg signed [15:0]  sample_out,
    output reg                input_overrun
);

    localparam integer DELAY_DEPTH = 32768;

    (* syn_ramstyle = "block_ram" *)
    reg signed [15:0] delay_memory [0:DELAY_DEPTH-1];

    reg busy;
    reg [14:0] write_pointer;
    reg [15:0] samples_written;
    reg signed [15:0] dry_sample_latched;
    reg signed [15:0] delay_read_data;
    reg delay_read_valid;
    reg [6:0] feedback_latched;
    reg [6:0] mix_latched;

    wire [14:0] delay_offset = 15'd480
                             + (time_control * 8'd250);
    wire [14:0] read_address = write_pointer - delay_offset;
    wire history_available = (samples_written >= {1'b0, delay_offset});
    wire signed [15:0] wet_sample = delay_read_valid
                                   ? delay_read_data : 16'sd0;
    wire signed [23:0] feedback_product =
        wet_sample * $signed({1'b0, feedback_latched});
    // 最大反馈约为 0.868，给定点舍入和满幅输入留出稳定余量。
    wire signed [24:0] feedback_scaled =
        ($signed(feedback_product) >>> 7)
        - ($signed(feedback_product) >>> 10);
    wire signed [24:0] write_value_wide =
        $signed({{9{dry_sample_latched[15]}}, dry_sample_latched})
        + feedback_scaled;
    wire signed [16:0] wet_dry_difference =
        $signed({wet_sample[15], wet_sample})
        - $signed({dry_sample_latched[15], dry_sample_latched});
    wire signed [24:0] mix_product =
        wet_dry_difference * $signed({1'b0, mix_latched});
    wire signed [25:0] mixed_sample_wide =
        $signed({{10{dry_sample_latched[15]}}, dry_sample_latched})
        + ($signed(mix_product) >>> 7);

    assign in_ready = !busy;

    function signed [15:0] saturate_s25_to_s16;
        input signed [24:0] value;
        begin
            if (value > 25'sd32767)
                saturate_s25_to_s16 = 16'sh7FFF;
            else if (value < -25'sd32768)
                saturate_s25_to_s16 = 16'sh8000;
            else
                saturate_s25_to_s16 = value[15:0];
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy               <= 1'b0;
            write_pointer      <= 15'd0;
            samples_written    <= 16'd0;
            dry_sample_latched <= 16'sd0;
            delay_read_data    <= 16'sd0;
            delay_read_valid   <= 1'b0;
            feedback_latched   <= 7'd0;
            mix_latched        <= 7'd0;
            out_valid          <= 1'b0;
            sample_out         <= 16'sd0;
            input_overrun      <= 1'b0;
        end else begin
            out_valid <= 1'b0;

            if (in_valid && !in_ready)
                input_overrun <= 1'b1;

            if (in_valid && in_ready) begin
                busy               <= 1'b1;
                dry_sample_latched <= sample_in;
                feedback_latched   <= feedback_control;
                mix_latched        <= mix_control;
                delay_read_data    <= delay_memory[read_address];
                delay_read_valid   <= history_available;
            end else if (busy) begin
                delay_memory[write_pointer]
                    <= saturate_s25_to_s16(write_value_wide);
                write_pointer <= write_pointer + 15'd1;
                if (samples_written < 16'd32768)
                    samples_written <= samples_written + 16'd1;

                if (mix_latched == 7'd0)
                    sample_out <= dry_sample_latched;
                else if (mix_latched == 7'd127)
                    sample_out <= wet_sample;
                else
                    sample_out <= saturate_s26_to_s16(mixed_sample_wide);
                out_valid <= 1'b1;
                busy <= 1'b0;
            end
        end
    end

endmodule
