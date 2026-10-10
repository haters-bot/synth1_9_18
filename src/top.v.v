// MIDI控制的32槽位时分复用振荡器与MAX98357A音频输出顶层。
module top #(
    parameter integer UART_BAUD_RATE = 31250,
    parameter integer DEFAULT_UNISON_COUNT = 3
)(
    input  wire sys_clk,       // 50 MHz板载时钟，引脚V22
    input  wire rst_n,         // 低电平有效的板载复位，引脚AA13
    input  wire uart_rx,       // 板载USB-UART接收，引脚V14
    output wire MAX_SD,        // MAX98357A使能，引脚AB20
    output wire MAX_GAIN,      // MAX98357A增益选择，引脚AA21
    output wire MAX_DIN,       // MAX98357A串行音频数据，引脚AB22
    output wire MAX_BCLK,      // MAX98357A位时钟，引脚Y22
    output wire MAX_LRC,       // MAX98357A左右声道时钟，引脚Y21
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
    wire [6:0]  task_update_velocity;
    wire        task_update_enable;
    wire        task_update_phase_reset;
    wire        task_scheduler_busy;

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

    // 使用外接MAX98357A，关闭板载NS4263。SD和GAIN保持高电平。
    assign PA_EN    = 1'b1;
    assign MAX_SD   = 1'b1;
    assign MAX_GAIN = 1'b1;

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

    oscillator_task_scheduler #(
        .ENGINE_COUNT    (ENGINE_COUNT),
        .SLOTS_PER_ENGINE(SLOTS_PER_ENGINE)
    ) u_oscillator_task_scheduler (
        .clk                     (sys_clk),
        .rst_n                   (rst_n_sys),
        .note_event_valid        (midi_note_event_valid),
        .note_event_on           (midi_note_event_on),
        .note_event_note         (midi_note_event_note),
        .note_event_velocity     (midi_note_event_velocity),
        .unison_count            (UNISON_COUNT_SETTING),
        .task_idle_mask          (task_idle_mask),
        .task_update_valid       (task_update_valid),
        .task_update_slot        (task_update_slot),
        .task_update_phase_step  (task_update_phase_step),
        .task_update_velocity    (task_update_velocity),
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
        .task_update_velocity      (task_update_velocity),
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

    i2s_tx u_max98357a_i2s_tx (
        .sys_clk        (sys_clk),
        .rst_n          (rst_n_sys),
        .sample_data    (filtered_sample),
        .bclk           (MAX_BCLK),
        .lrck           (MAX_LRC),
        .sdata          (MAX_DIN),
        .sample_tick    (sample_tick),
        .oversample_tick(oversample_tick)
    );

endmodule
