// 两帧双缓冲波表缓存。
// load_clk写入非活动bank，audio_clk读取活动bank；commit_toggle负责原子切换。
module wavetable_frame_cache(
    input  wire               audio_clk,
    input  wire               audio_rst_n,
    input  wire               req_valid,
    input  wire [7:0]         phase_address,
    output reg                sample_valid,
    output wire signed [15:0] sample_data,

    input  wire               load_clk,
    input  wire               load_rst_n,
    input  wire               load_write_enable,
    input  wire               load_write_bank,
    input  wire               load_write_frame,
    input  wire [7:0]         load_write_address,
    input  wire [15:0]        load_write_data,
    input  wire               load_commit_toggle,
    input  wire               load_commit_bank,
    input  wire [7:0]         load_commit_fraction,
    output reg                ready
);

    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg [15:0] bank0_frame0 [0:255];
    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg [15:0] bank0_frame1 [0:255];
    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg [15:0] bank1_frame0 [0:255];
    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg [15:0] bank1_frame1 [0:255];

    reg commit_toggle_sync_1;
    reg commit_toggle_sync_2;
    reg commit_toggle_seen;
    reg commit_bank_sync_1;
    reg commit_bank_sync_2;
    reg [7:0] commit_fraction_sync_1;
    reg [7:0] commit_fraction_sync_2;
    reg active_bank;
    reg [7:0] active_fraction;
    reg signed [15:0] frame0_data;
    reg signed [15:0] frame1_data;
    reg [7:0] fraction_d1;

    wire signed [16:0] frame0_extended = {frame0_data[15], frame0_data};
    wire signed [16:0] sample_difference =
        $signed({frame1_data[15], frame1_data}) - frame0_extended;
    wire signed [8:0] fraction_signed = $signed({1'b0, fraction_d1});
    wire signed [25:0] interpolation_product =
        sample_difference * fraction_signed;
    wire signed [17:0] interpolation_sum = frame0_extended
                                               + (interpolation_product >>> 8);
    assign sample_data = interpolation_sum[15:0];

    always @(posedge load_clk) begin
        if (load_write_enable) begin
            case ({load_write_bank, load_write_frame})
                2'b00: bank0_frame0[load_write_address] <= load_write_data;
                2'b01: bank0_frame1[load_write_address] <= load_write_data;
                2'b10: bank1_frame0[load_write_address] <= load_write_data;
                2'b11: bank1_frame1[load_write_address] <= load_write_data;
            endcase
        end
    end

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            commit_toggle_sync_1 <= 1'b0;
            commit_toggle_sync_2 <= 1'b0;
            commit_toggle_seen <= 1'b0;
            commit_bank_sync_1 <= 1'b0;
            commit_bank_sync_2 <= 1'b0;
            commit_fraction_sync_1 <= 8'd0;
            commit_fraction_sync_2 <= 8'd0;
            active_bank <= 1'b0;
            active_fraction <= 8'd0;
            frame0_data <= 16'sd0;
            frame1_data <= 16'sd0;
            fraction_d1 <= 8'd0;
            sample_valid <= 1'b0;
            ready <= 1'b0;
        end else begin
            commit_toggle_sync_1 <= load_commit_toggle;
            commit_toggle_sync_2 <= commit_toggle_sync_1;
            commit_bank_sync_1 <= load_commit_bank;
            commit_bank_sync_2 <= commit_bank_sync_1;
            commit_fraction_sync_1 <= load_commit_fraction;
            commit_fraction_sync_2 <= commit_fraction_sync_1;

            if (commit_toggle_sync_2 != commit_toggle_seen) begin
                commit_toggle_seen <= commit_toggle_sync_2;
                active_bank <= commit_bank_sync_2;
                active_fraction <= commit_fraction_sync_2;
                ready <= 1'b1;
            end

            sample_valid <= req_valid && ready;
            if (req_valid) begin
                fraction_d1 <= active_fraction;
                if (active_bank) begin
                    frame0_data <= bank1_frame0[phase_address];
                    frame1_data <= bank1_frame1[phase_address];
                end else begin
                    frame0_data <= bank0_frame0[phase_address];
                    frame1_data <= bank0_frame1[phase_address];
                end
            end
        end
    end

    // load_rst_n保留在接口中，用于明确两个时钟域的复位关系。
    wire unused_load_reset = load_rst_n;

endmodule
