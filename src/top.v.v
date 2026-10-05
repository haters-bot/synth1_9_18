// 32槽位时分复用振荡器与板载音频输出的工程顶层。
module top #(
    parameter [6:0] FIXED_MIDI_NOTE = 7'd69,
    parameter integer DEFAULT_UNISON_COUNT = 1
)(
    input  wire sys_clk,       // 50 MHz板载时钟，引脚V22
    input  wire rst_n,         // 低电平有效的板载复位，引脚AA13
    output wire HP_BCK,        // 板载PT8211位时钟，引脚Y17
    output wire HP_WS,         // 板载PT8211字选择信号，引脚AB17
    output wire HP_DIN,        // 板载PT8211串行数据，引脚AA16
    output wire PA_EN          // 板载NS4263使能，低电平有效，引脚AB16
);

    localparam integer ENGINE_COUNT      = 4;
    localparam integer SLOTS_PER_ENGINE  = 8;
    localparam integer TOTAL_OSC_SLOTS   = ENGINE_COUNT * SLOTS_PER_ENGINE;
    localparam [3:0] UNISON_COUNT_SETTING = DEFAULT_UNISON_COUNT;

    wire rst_n_sys;
    wire sample_tick;
    wire oversample_tick;
    wire oscillator_start_tick;

    wire signed [15:0] oscillator_mix;
    wire signed [15:0] fir_input_sample;
    wire               oscillator_mix_valid;
    wire               oscillator_schedule_overrun;
    wire [TOTAL_OSC_SLOTS-1:0] task_idle_mask;
    wire [5:0] active_task_count;
    wire signed [15:0] filtered_sample;

    wire       debug_osc_busy;
    wire [7:0] debug_osc_slot;
    wire       debug_osc_slot_commit;

    wire        task_update_valid;
    wire [7:0]  task_update_slot;
    wire [31:0] task_update_phase_step;
    wire        task_update_enable;
    wire        task_update_phase_reset;
    wire        task_scheduler_busy;

    reg fixed_note_event_valid;
    reg fixed_note_pending;

    wire fir_input_ready;
    wire fir_output_valid;
    wire fir_input_overrun;

    // 根据开发板原理图，PA_EN=0时功率放大器开启。
    assign PA_EN = 1'b0;

    reset_release_sync u_reset_release_sync (
        .clk        (sys_clk),
        .rst_n_async(rst_n),
        .rst_n_sync (rst_n_sys)
    );

    assign oscillator_start_tick = oversample_tick;

    // Debug mode: emit one Note On after synchronized reset release. This
    // removes the UART/MIDI input dependency while inspecting live waveforms.
    always @(posedge sys_clk or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            fixed_note_event_valid <= 1'b0;
            fixed_note_pending <= 1'b1;
        end else begin
            fixed_note_event_valid <= fixed_note_pending;
            fixed_note_pending <= 1'b0;
        end
    end

    oscillator_task_scheduler #(
        .ENGINE_COUNT    (ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE)
    ) u_oscillator_task_scheduler (
        .clk                     (sys_clk),
        .rst_n                   (rst_n_sys),
        .note_event_valid        (fixed_note_event_valid),
        .note_event_on           (1'b1),
        .note_event_note         (FIXED_MIDI_NOTE),
        .unison_count            (UNISON_COUNT_SETTING),
        .task_idle_mask          (task_idle_mask),
        .task_update_valid       (task_update_valid),
        .task_update_slot        (task_update_slot),
        .task_update_phase_step  (task_update_phase_step),
        .task_update_enable      (task_update_enable),
        .task_update_phase_reset (task_update_phase_reset),
        .active_task_count       (active_task_count),
        .scheduler_busy          (task_scheduler_busy)
    );

    oscillator_tdm_bank #(
        .ENGINE_COUNT      (ENGINE_COUNT),
        .SLOTS_PER_ENGINE  (SLOTS_PER_ENGINE)
    ) u_oscillator_tdm_bank (
        .clk                       (sys_clk),
        .rst_n                     (rst_n_sys),
        .start_tick                (oscillator_start_tick),
        .clear_phase               (1'b0),
        .task_update_valid         (task_update_valid),
        .task_update_slot          (task_update_slot),
        .task_update_phase_step    (task_update_phase_step),
        .task_update_enable        (task_update_enable),
        .task_update_phase_reset   (task_update_phase_reset),
        .active_task_count         (active_task_count),
        .sample_out                (oscillator_mix),
        .sample_valid              (oscillator_mix_valid),
        .schedule_overrun          (oscillator_schedule_overrun),
        .task_idle_mask            (task_idle_mask),
        .debug_engine0_busy        (debug_osc_busy),
        .debug_engine0_slot        (debug_osc_slot),
        .debug_engine0_slot_commit (debug_osc_slot_commit)
    );

    // 引擎组按活动声部数完成平滑1/N归一化，此处不再额外衰减。
    assign fir_input_sample = oscillator_mix;

    fir_decimator_8x_wrapper u_fir_decimator_8x_wrapper (
        .clk          (sys_clk),
        .rst_n        (rst_n_sys),
        .in_valid     (oscillator_mix_valid),
        .sample_in    (fir_input_sample),
        .in_ready     (fir_input_ready),
        .out_valid    (fir_output_valid),
        .sample_out   (filtered_sample),
        .input_overrun(fir_input_overrun)
    );

    pt8211_tx u_pt8211_tx (
        .sys_clk        (sys_clk),
        .rst_n          (rst_n_sys),
        .sample_data    (filtered_sample),
        .bck            (HP_BCK),
        .ws             (HP_WS),
        .din            (HP_DIN),
        .sample_tick    (sample_tick),
        .oversample_tick(oversample_tick)
    );

endmodule
