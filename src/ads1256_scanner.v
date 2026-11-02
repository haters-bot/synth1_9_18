// ADS1256六通道单端循环扫描控制器。
// 系统时钟默认50 MHz，SCLK默认1 MHz。SPI时序按ADS1256要求：SCLK空闲低，
// DIN和DOUT在下降沿采样。每次读完当前通道后写入下一路MUX，再发送
// SYNC/WAKEUP；因此下一次DRDY对应已经完全建立的下一通道结果。
module ads1256_scanner #(
    parameter integer SYS_CLK_HZ = 50000000,
    parameter integer SCLK_HZ = 1000000,
    parameter integer CHANNEL_COUNT = 6,
    parameter integer POWERUP_DELAY_CYCLES = 2500000,
    parameter integer RESET_DELAY_CYCLES = 50000,
    // SYNC后下一命令需至少24个7.68 MHz时钟，即约3.125 us。
    parameter integer COMMAND_DELAY_CYCLES = (SYS_CLK_HZ + 249999) / 250000,
    parameter integer RDATA_DELAY_CYCLES = 400
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               adc_drdy_n,
    input  wire               adc_dout,
    output reg                adc_cs_n,
    output reg                adc_sclk,
    output reg                adc_din,
    output reg                adc_reset_n,

    output reg                sample_valid,
    input  wire               sample_ready,
    output reg [2:0]          sample_channel,
    output reg signed [23:0]  sample_data,
    output reg                initialized,
    output wire [5:0]         debug_state,
    output wire               debug_drdy
);

    localparam integer SCLK_HALF_DIV = SYS_CLK_HZ / (SCLK_HZ * 2);
    // 末个SCLK下降沿后保持CS至少2 us，覆盖7.68 MHz时8个CLKIN的要求。
    localparam integer CS_HOLD_CYCLES = (SYS_CLK_HZ + 499999) / 500000;

    localparam [3:0] SEQ_RESET     = 4'd0;
    localparam [3:0] SEQ_SDATAC    = 4'd1;
    localparam [3:0] SEQ_WREG_INIT = 4'd2;
    localparam [3:0] SEQ_SELFCAL   = 4'd3;
    localparam [3:0] SEQ_WREG_MUX  = 4'd4;
    localparam [3:0] SEQ_SYNC      = 4'd5;
    localparam [3:0] SEQ_WAKEUP    = 4'd6;
    localparam [3:0] SEQ_RDATA     = 4'd7;
    localparam [3:0] SEQ_READ3     = 4'd8;

    localparam [5:0] ST_POWER_WAIT      = 6'd0;
    localparam [5:0] ST_SEND_RESET      = 6'd1;
    localparam [5:0] ST_WAIT_RESET      = 6'd2;
    localparam [5:0] ST_RESET_DELAY     = 6'd3;
    localparam [5:0] ST_SEND_SDATAC     = 6'd4;
    localparam [5:0] ST_WAIT_SDATAC     = 6'd5;
    localparam [5:0] ST_COMMAND_GAP     = 6'd6;
    localparam [5:0] ST_SEND_INIT       = 6'd7;
    localparam [5:0] ST_WAIT_INIT       = 6'd8;
    localparam [5:0] ST_SEND_SELFCAL    = 6'd9;
    localparam [5:0] ST_WAIT_SELFCAL    = 6'd10;
    localparam [5:0] ST_WAIT_CAL_DRDY   = 6'd11;
    localparam [5:0] ST_SEND_MUX        = 6'd12;
    localparam [5:0] ST_WAIT_MUX        = 6'd13;
    localparam [5:0] ST_SEND_SYNC       = 6'd14;
    localparam [5:0] ST_WAIT_SYNC       = 6'd15;
    localparam [5:0] ST_SEND_WAKEUP     = 6'd16;
    localparam [5:0] ST_WAIT_WAKEUP     = 6'd17;
    localparam [5:0] ST_WAIT_CONVERSION = 6'd18;
    localparam [5:0] ST_SEND_RDATA      = 6'd19;
    localparam [5:0] ST_WAIT_RDATA      = 6'd20;
    localparam [5:0] ST_RDATA_DELAY     = 6'd21;
    localparam [5:0] ST_SEND_READ3      = 6'd22;
    localparam [5:0] ST_WAIT_READ3      = 6'd23;
    localparam [5:0] ST_HOLD_SAMPLE     = 6'd24;

    localparam [1:0] Q_IDLE   = 2'd0;
    localparam [1:0] Q_LAUNCH = 2'd1;
    localparam [1:0] Q_WAIT   = 2'd2;
    localparam [1:0] Q_HOLD   = 2'd3;

    reg [5:0] state;
    assign debug_state = state;
    reg [5:0] state_after_gap;
    reg [31:0] delay_counter;
    reg [2:0] current_channel;
    reg [2:0] target_channel;
    reg drdy_meta;
    reg drdy_sync;
    assign debug_drdy = drdy_sync;
    reg drdy_seen_high;

    reg [1:0] sequence_state;
    reg [3:0] sequence_kind;
    reg [2:0] sequence_index;
    reg sequence_start;
    reg [3:0] sequence_start_kind;
    reg sequence_done;
    reg read_cs_held;
    reg [31:0] cs_hold_counter;
    reg [23:0] read_data_shift;

    reg spi_start;
    reg [7:0] spi_start_byte;
    reg spi_busy;
    reg spi_phase;
    reg [15:0] spi_divider;
    reg [2:0] spi_bit_index;
    reg [7:0] spi_tx_shift;
    reg spi_din_update_pending;
    reg [7:0] spi_rx_shift;
    reg [7:0] spi_rx_byte;
    reg spi_done;

    function [2:0] sequence_last_index;
        input [3:0] kind;
        begin
            case (kind)
                SEQ_WREG_INIT: sequence_last_index = 3'd5;
                SEQ_WREG_MUX:  sequence_last_index = 3'd2;
                SEQ_READ3:     sequence_last_index = 3'd2;
                default:       sequence_last_index = 3'd0;
            endcase
        end
    endfunction

    function [7:0] sequence_byte;
        input [3:0] kind;
        input [2:0] index;
        input [2:0] mux_channel;
        begin
            case (kind)
                SEQ_RESET:  sequence_byte = 8'hFE;
                SEQ_SDATAC: sequence_byte = 8'h0F;
                SEQ_SELFCAL: sequence_byte = 8'hF0;
                SEQ_SYNC:   sequence_byte = 8'hFC;
                SEQ_WAKEUP: sequence_byte = 8'h00;
                SEQ_RDATA:  sequence_byte = 8'h01;
                SEQ_READ3:  sequence_byte = 8'h00;
                SEQ_WREG_MUX: begin
                    case (index)
                        3'd0: sequence_byte = 8'h51;
                        3'd1: sequence_byte = 8'h00;
                        default: sequence_byte = {1'b0, mux_channel, 4'h8};
                    endcase
                end
                default: begin
                    // STATUS=ACAL、BUFEN关闭；MUX=AIN0/AINCOM；
                    // ADCON=PGA1；DRATE=15 kSPS。
                    case (index)
                        3'd0: sequence_byte = 8'h50;
                        3'd1: sequence_byte = 8'h03;
                        3'd2: sequence_byte = 8'h04;
                        3'd3: sequence_byte = 8'h08;
                        3'd4: sequence_byte = 8'h00;
                        default: sequence_byte = 8'hE0;
                    endcase
                end
            endcase
        end
    endfunction

    // DRDY异步输入同步到系统时钟域。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drdy_meta <= 1'b1;
            drdy_sync <= 1'b1;
        end else begin
            drdy_meta <= adc_drdy_n;
            drdy_sync <= drdy_meta;
        end
    end

    // 单字节SPI引擎。上升沿让ADS1256更新DOUT，下降沿同时采样DOUT
    // 并让ADS1256采样DIN。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_sclk <= 1'b0;
            adc_din <= 1'b0;
            spi_busy <= 1'b0;
            spi_phase <= 1'b0;
            spi_divider <= 16'd0;
            spi_bit_index <= 3'd7;
            spi_tx_shift <= 8'd0;
            spi_din_update_pending <= 1'b0;
            spi_rx_shift <= 8'd0;
            spi_rx_byte <= 8'd0;
            spi_done <= 1'b0;
        end else begin
            spi_done <= 1'b0;
            // DIN在下降沿之后保持一个系统时钟，再准备下一位。
            if (spi_din_update_pending) begin
                adc_din <= spi_tx_shift[spi_bit_index];
                spi_din_update_pending <= 1'b0;
            end
            if (spi_start && !spi_busy) begin
                spi_busy <= 1'b1;
                spi_phase <= 1'b0;
                spi_divider <= 16'd0;
                spi_bit_index <= 3'd7;
                spi_tx_shift <= spi_start_byte;
                spi_rx_shift <= 8'd0;
                adc_sclk <= 1'b0;
                adc_din <= spi_start_byte[7];
            end else if (spi_busy) begin
                if (spi_divider == SCLK_HALF_DIV-1) begin
                    spi_divider <= 16'd0;
                    if (!spi_phase) begin
                        adc_sclk <= 1'b1;
                        spi_phase <= 1'b1;
                    end else begin
                        adc_sclk <= 1'b0;
                        spi_phase <= 1'b0;
                        spi_rx_shift[spi_bit_index] <= adc_dout;
                        if (spi_bit_index == 3'd0) begin
                            spi_rx_byte <= {spi_rx_shift[7:1], adc_dout};
                            spi_busy <= 1'b0;
                            spi_done <= 1'b1;
                        end else begin
                            spi_bit_index <= spi_bit_index - 3'd1;
                            spi_din_update_pending <= 1'b1;
                        end
                    end
                end else begin
                    spi_divider <= spi_divider + 16'd1;
                end
            end
        end
    end

    // 多字节命令序列引擎，整个序列期间CS保持为低。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sequence_state <= Q_IDLE;
            sequence_kind <= SEQ_RESET;
            sequence_index <= 3'd0;
            sequence_done <= 1'b0;
            spi_start <= 1'b0;
            spi_start_byte <= 8'd0;
            adc_cs_n <= 1'b1;
            read_cs_held <= 1'b0;
            cs_hold_counter <= 0;
            read_data_shift <= 24'd0;
        end else begin
            sequence_done <= 1'b0;
            spi_start <= 1'b0;
            case (sequence_state)
                Q_IDLE: begin
                    adc_cs_n <= !read_cs_held;
                    if (sequence_start) begin
                        sequence_kind <= sequence_start_kind;
                        sequence_index <= 3'd0;
                        if (sequence_start_kind == SEQ_READ3)
                            read_data_shift <= 24'd0;
                        adc_cs_n <= 1'b0;
                        sequence_state <= Q_LAUNCH;
                    end
                end

                Q_LAUNCH: begin
                    if (!spi_busy) begin
                        spi_start_byte <= sequence_byte(
                            sequence_kind,
                            sequence_index,
                            target_channel);
                        spi_start <= 1'b1;
                        sequence_state <= Q_WAIT;
                    end
                end

                Q_WAIT: begin
                    if (spi_done) begin
                        if (sequence_kind == SEQ_READ3)
                            read_data_shift
                                <= {read_data_shift[15:0], spi_rx_byte};
                        if (sequence_index
                            == sequence_last_index(sequence_kind)) begin
                            cs_hold_counter <= 0;
                            sequence_state <= Q_HOLD;
                        end else begin
                            sequence_index <= sequence_index + 3'd1;
                            sequence_state <= Q_LAUNCH;
                        end
                    end
                end

                Q_HOLD: begin
                    if (cs_hold_counter >= CS_HOLD_CYCLES-1) begin
                        sequence_done <= 1'b1;
                        sequence_state <= Q_IDLE;
                        if (sequence_kind == SEQ_RDATA) begin
                            // RDATA命令、t6等待及24位数据属于同一CS事务。
                            read_cs_held <= 1'b1;
                            adc_cs_n <= 1'b0;
                        end else begin
                            read_cs_held <= 1'b0;
                            adc_cs_n <= 1'b1;
                        end
                    end else cs_hold_counter <= cs_hold_counter + 1'b1;
                end

                default: sequence_state <= Q_IDLE;
            endcase
        end
    end

    // ADS1256初始化与六通道扫描流程。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_POWER_WAIT;
            state_after_gap <= ST_SEND_INIT;
            delay_counter <= 32'd0;
            current_channel <= 3'd0;
            target_channel <= 3'd0;
            drdy_seen_high <= 1'b0;
            sequence_start <= 1'b0;
            sequence_start_kind <= SEQ_RESET;
            adc_reset_n <= 1'b0;
            sample_valid <= 1'b0;
            sample_channel <= 3'd0;
            sample_data <= 24'sd0;
            initialized <= 1'b0;
        end else begin
            sequence_start <= 1'b0;
            if (sample_valid && sample_ready)
                sample_valid <= 1'b0;

            case (state)
                ST_POWER_WAIT: begin
                    if (delay_counter >= POWERUP_DELAY_CYCLES-1) begin
                        delay_counter <= 32'd0;
                        adc_reset_n <= 1'b1;
                        state <= ST_SEND_RESET;
                    end else delay_counter <= delay_counter + 32'd1;
                end

                ST_SEND_RESET: begin
                    if (sequence_state == Q_IDLE) begin
                        sequence_start_kind <= SEQ_RESET;
                        sequence_start <= 1'b1;
                        state <= ST_WAIT_RESET;
                    end
                end
                ST_WAIT_RESET: if (sequence_done) begin
                    delay_counter <= 32'd0;
                    state <= ST_RESET_DELAY;
                end
                ST_RESET_DELAY: begin
                    if (delay_counter >= RESET_DELAY_CYCLES-1) begin
                        delay_counter <= 32'd0;
                        state <= ST_SEND_SDATAC;
                    end else delay_counter <= delay_counter + 32'd1;
                end
                ST_SEND_SDATAC: begin
                    if (sequence_state == Q_IDLE) begin
                        sequence_start_kind <= SEQ_SDATAC;
                        sequence_start <= 1'b1;
                        state <= ST_WAIT_SDATAC;
                    end
                end
                ST_WAIT_SDATAC: if (sequence_done) begin
                    delay_counter <= 32'd0;
                    state_after_gap <= ST_SEND_INIT;
                    state <= ST_COMMAND_GAP;
                end

                ST_COMMAND_GAP: begin
                    if (delay_counter >= COMMAND_DELAY_CYCLES-1) begin
                        delay_counter <= 32'd0;
                        state <= state_after_gap;
                    end else delay_counter <= delay_counter + 32'd1;
                end

                ST_SEND_INIT: begin
                    if (sequence_state == Q_IDLE) begin
                        sequence_start_kind <= SEQ_WREG_INIT;
                        sequence_start <= 1'b1;
                        state <= ST_WAIT_INIT;
                    end
                end
                ST_WAIT_INIT: if (sequence_done) begin
                    delay_counter <= 32'd0;
                    state_after_gap <= ST_SEND_SELFCAL;
                    state <= ST_COMMAND_GAP;
                end
                ST_SEND_SELFCAL: begin
                    if (sequence_state == Q_IDLE) begin
                        sequence_start_kind <= SEQ_SELFCAL;
                        sequence_start <= 1'b1;
                        state <= ST_WAIT_SELFCAL;
                    end
                end
                ST_WAIT_SELFCAL: if (sequence_done) begin
                    drdy_seen_high <= 1'b0;
                    state <= ST_WAIT_CAL_DRDY;
                end
                ST_WAIT_CAL_DRDY: begin
                    if (drdy_sync) drdy_seen_high <= 1'b1;
                    if (drdy_seen_high && !drdy_sync) begin
                        target_channel <= 3'd0;
                        state <= ST_SEND_MUX;
                    end
                end

                ST_SEND_MUX: begin
                    if (sequence_state == Q_IDLE) begin
                        sequence_start_kind <= SEQ_WREG_MUX;
                        sequence_start <= 1'b1;
                        state <= ST_WAIT_MUX;
                    end
                end
                ST_WAIT_MUX: if (sequence_done) begin
                    delay_counter <= 32'd0;
                    state_after_gap <= ST_SEND_SYNC;
                    state <= ST_COMMAND_GAP;
                end
                ST_SEND_SYNC: begin
                    if (sequence_state == Q_IDLE) begin
                        sequence_start_kind <= SEQ_SYNC;
                        sequence_start <= 1'b1;
                        state <= ST_WAIT_SYNC;
                    end
                end
                ST_WAIT_SYNC: if (sequence_done) begin
                    delay_counter <= 32'd0;
                    state_after_gap <= ST_SEND_WAKEUP;
                    state <= ST_COMMAND_GAP;
                end
                ST_SEND_WAKEUP: begin
                    if (sequence_state == Q_IDLE) begin
                        sequence_start_kind <= SEQ_WAKEUP;
                        sequence_start <= 1'b1;
                        state <= ST_WAIT_WAKEUP;
                    end
                end
                ST_WAIT_WAKEUP: if (sequence_done) begin
                    current_channel <= target_channel;
                    drdy_seen_high <= 1'b0;
                    initialized <= 1'b1;
                    state <= ST_WAIT_CONVERSION;
                end
                ST_WAIT_CONVERSION: begin
                    if (drdy_sync) drdy_seen_high <= 1'b1;
                    if (drdy_seen_high && !drdy_sync)
                        state <= ST_SEND_RDATA;
                end
                ST_SEND_RDATA: begin
                    if (sequence_state == Q_IDLE) begin
                        sequence_start_kind <= SEQ_RDATA;
                        sequence_start <= 1'b1;
                        state <= ST_WAIT_RDATA;
                    end
                end
                ST_WAIT_RDATA: if (sequence_done) begin
                    delay_counter <= 32'd0;
                    state <= ST_RDATA_DELAY;
                end
                ST_RDATA_DELAY: begin
                    if (delay_counter >= RDATA_DELAY_CYCLES-1) begin
                        delay_counter <= 32'd0;
                        state <= ST_SEND_READ3;
                    end else delay_counter <= delay_counter + 32'd1;
                end
                ST_SEND_READ3: begin
                    if (sequence_state == Q_IDLE) begin
                        sequence_start_kind <= SEQ_READ3;
                        sequence_start <= 1'b1;
                        state <= ST_WAIT_READ3;
                    end
                end
                ST_WAIT_READ3: if (sequence_done) begin
                    sample_channel <= current_channel;
                    sample_data <= read_data_shift;
                    sample_valid <= 1'b1;
                    state <= ST_HOLD_SAMPLE;
                end
                ST_HOLD_SAMPLE: begin
                    if (sample_valid && sample_ready) begin
                        if (current_channel == CHANNEL_COUNT-1)
                            target_channel <= 3'd0;
                        else
                            target_channel <= current_channel + 3'd1;
                        state <= ST_SEND_MUX;
                    end
                end

                default: state <= ST_POWER_WAIT;
            endcase
        end
    end

endmodule
