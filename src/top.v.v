// 32槽位时分复用振荡器与板载音频输出的工程顶层。
module top #(
    parameter integer UART_BAUD_RATE = 31250
)(
    input  wire sys_clk,       // 50 MHz板载时钟，引脚V22
    input  wire rst_n,         // 低电平有效的板载复位，引脚AA13
    input  wire uart_rx,       // 板载USB-UART接收，引脚V14
    output wire HP_BCK,        // 板载PT8211位时钟，引脚Y17
    output wire HP_WS,         // 板载PT8211字选择信号，引脚AB17
    output wire HP_DIN,        // 板载PT8211串行数据，引脚AA16
    output wire PA_EN          // 板载NS4263使能，低电平有效，引脚AB16
);

    localparam integer ENGINE_COUNT      = 1;
    localparam integer SLOTS_PER_ENGINE  = 32;
    localparam integer TOTAL_OSC_SLOTS   = ENGINE_COUNT * SLOTS_PER_ENGINE;
    localparam integer UNISON_COUNT      = 3;

    wire rst_n_sys;
    wire sample_tick;
    wire oversample_tick;
    wire oscillator_start_tick;

    wire signed [15:0] oscillator_mix;
    wire signed [15:0] fir_input_sample;
    wire               oscillator_mix_valid;
    wire               oscillator_schedule_overrun;
    wire [TOTAL_OSC_SLOTS-1:0] voice_idle_mask;
    wire [5:0] active_voice_count;
    wire signed [15:0] filtered_sample;

    wire       debug_osc_busy;
    wire [7:0] debug_osc_slot;
    wire       debug_osc_slot_commit;

    wire       voice_update_valid;
    wire [7:0] voice_update_slot;
    wire [6:0] voice_update_note;
    wire       voice_update_enable;
    wire       voice_update_phase_reset;
    wire [1:0] voice_update_unison_lane;

    wire [7:0] uart_byte;
    wire       uart_byte_valid;
    wire       uart_framing_error;
    wire       midi_note_event_valid;
    wire       midi_note_event_on;
    wire [6:0] midi_note_event_note;
    wire [6:0] midi_note_event_velocity;

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

    uart_rx #(
        .CLK_HZ   (50000000),
        .BAUD_RATE(UART_BAUD_RATE)
    ) u_uart_rx (
        .clk          (sys_clk),
        .rst_n        (rst_n_sys),
        .rx           (uart_rx),
        .data         (uart_byte),
        .data_valid   (uart_byte_valid),
        .framing_error(uart_framing_error)
    );

    midi_note_parser u_midi_note_parser (
        .clk                (sys_clk),
        .rst_n              (rst_n_sys),
        .byte_data          (uart_byte),
        .byte_valid         (uart_byte_valid),
        .note_event_valid   (midi_note_event_valid),
        .note_event_on      (midi_note_event_on),
        .note_event_note    (midi_note_event_note),
        .note_event_velocity(midi_note_event_velocity)
    );

    midi_voice_allocator #(
        .VOICE_COUNT (TOTAL_OSC_SLOTS),
        .UNISON_COUNT(UNISON_COUNT)
    ) u_midi_voice_allocator (
        .clk                     (sys_clk),
        .rst_n                   (rst_n_sys),
        .note_event_valid        (midi_note_event_valid),
        .note_event_on           (midi_note_event_on),
        .note_event_note         (midi_note_event_note),
        .voice_idle_mask         (voice_idle_mask),
        .voice_update_valid      (voice_update_valid),
        .voice_update_slot       (voice_update_slot),
        .voice_update_note       (voice_update_note),
        .voice_update_enable     (voice_update_enable),
        .voice_update_phase_reset(voice_update_phase_reset),
        .voice_update_unison_lane(voice_update_unison_lane),
        .active_voice_count      (active_voice_count)
    );

    oscillator_tdm_bank #(
        .ENGINE_COUNT      (ENGINE_COUNT),
        .SLOTS_PER_ENGINE  (SLOTS_PER_ENGINE)
    ) u_oscillator_tdm_bank (
        .clk                       (sys_clk),
        .rst_n                     (rst_n_sys),
        .start_tick                (oscillator_start_tick),
        .clear_phase               (1'b0),
        .voice_update_valid        (voice_update_valid),
        .voice_update_slot         (voice_update_slot),
        .voice_update_note         (voice_update_note),
        .voice_update_enable       (voice_update_enable),
        .voice_update_phase_reset  (voice_update_phase_reset),
        .voice_update_unison_lane  (voice_update_unison_lane),
        .active_voice_count        (active_voice_count),
        .sample_out                (oscillator_mix),
        .sample_valid              (oscillator_mix_valid),
        .schedule_overrun          (oscillator_schedule_overrun),
        .voice_idle_mask           (voice_idle_mask),
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
