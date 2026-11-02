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
    parameter integer RDATA_DELAY_CYCLES = (SYS_CLK_HZ + 124999) / 125000,
    // 复位、校准及转换等待上限100 ms；超时锁存，系统复位后重试。
    parameter integer DRDY_TIMEOUT_CYCLES = SYS_CLK_HZ / 10
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

    localparam [3:0] SEQ_SDATAC    = 4'd1;
    localparam [3:0] SEQ_WREG_INIT = 4'd2;
    localparam [3:0] SEQ_SELFCAL   = 4'd3;
    localparam [3:0] SEQ_WREG_MUX  = 4'd4;
    localparam [3:0] SEQ_SYNC      = 4'd5;
    localparam [3:0] SEQ_WAKEUP    = 4'd6;
    localparam [3:0] SEQ_RDATA     = 4'd7;
    localparam [3:0] SEQ_READ3     = 4'd8;

    localparam [3:0] SEQ_RREG = 4'd9;
    localparam [3:0] SEQ_READ4 = 4'd10;

    localparam [5:0] ST_POWER_WAIT      = 6'd0;
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

    localparam [5:0] ST_SEND_RREG = 6'd25;
    localparam [5:0] ST_WAIT_RREG = 6'd26;
    localparam [5:0] ST_REG_DELAY = 6'd27;
    localparam [5:0] ST_SEND_READ4 = 6'd28;
    localparam [5:0] ST_WAIT_READ4 = 6'd29;
    localparam [5:0] ST_RESET_TIMEOUT = 6'h3A;
    localparam [5:0] ST_CAL_TIMEOUT = 6'h3B;
    localparam [5:0] ST_CONFIG_ERROR = 6'h3C;
    localparam [5:0] ST_MUX_ERROR = 6'h3D;
    localparam [5:0] ST_CONVERSION_TIMEOUT = 6'h3E;
    localparam [5:0] ST_INTERNAL_ERROR = 6'h3F;

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
    // 顺序为STATUS/MUX/ADCON/DRATE，可用片上分析仪观察实际读回值。
    reg [31:0] read_register_shift;
    reg checking_initial_config;

    reg spi_start;
    reg [7:0] spi_start_byte;
    reg spi_busy;
    reg spi_phase;
    reg [15:0] spi_divider;
    reg [2:0] spi_bit_index;
    reg [7:0] spi_tx_shift;
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
                SEQ_RREG:      sequence_last_index = 3'd1;
                SEQ_READ4:     sequence_last_index = 3'd3;
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
                SEQ_SDATAC: sequence_byte = 8'h0F;
                SEQ_SELFCAL: sequence_byte = 8'hF0;
                SEQ_SYNC:   sequence_byte = 8'hFC;
                SEQ_WAKEUP: sequence_byte = 8'h00;
                SEQ_RDATA:  sequence_byte = 8'h01;
                SEQ_READ3, SEQ_READ4: sequence_byte = 8'h00;
                SEQ_RREG: sequence_byte = (index == 0) ? 8'h10 : 8'h03;
                SEQ_WREG_MUX: begin
                    case (index)
                        3'd0: sequence_byte = 8'h51;
                        3'd1: sequence_byte = 8'h00;
                        default: sequence_byte = {1'b0, mux_channel, 4'h8};
                    endcase
                end
                default: begin
                    // STATUS=00：关闭ACAL和BUFEN，仅执行一次手动校准；MUX=AIN0/AINCOM；
                    // ADCON=PGA1；DRATE=15 kSPS。
                    case (index)
                        3'd0: sequence_byte = 8'h50;
                        3'd1: sequence_byte = 8'h03;
                        3'd2: sequence_byte = 8'h00;
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

    // 单字节SPI引擎。上升沿准备DIN并让ADS1256更新DOUT，
    // 下降沿接收DOUT，同时ADS1256采样DIN。DIN保持至下一上升沿。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_sclk <= 1'b0;
            adc_din <= 1'b0;
            spi_busy <= 1'b0;
            spi_phase <= 1'b0;
            spi_divider <= 16'd0;
            spi_bit_index <= 3'd7;
            spi_tx_shift <= 8'd0;
            spi_rx_shift <= 8'd0;
            spi_rx_byte <= 8'd0;
            spi_done <= 1'b0;
        end else begin
            spi_done <= 1'b0;
            if (spi_start && !spi_busy) begin
                spi_busy <= 1'b1;
                spi_phase <= 1'b0;
                spi_divider <= 16'd0;
                spi_bit_index <= 3'd7;
                spi_tx_shift <= spi_start_byte;
                spi_rx_shift <= 8'd0;
                adc_sclk <= 1'b0;
            end else if (spi_busy) begin
                if (spi_divider == SCLK_HALF_DIV-1) begin
                    spi_divider <= 16'd0;
                    if (!spi_phase) begin
                        // 上升沿准备DIN，下降沿前后均保留半个SCLK周期。
                        adc_din <= spi_tx_shift[spi_bit_index];
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
            sequence_kind <= SEQ_SDATAC;
            sequence_index <= 3'd0;
            sequence_done <= 1'b0;
            spi_start <= 1'b0;
            spi_start_byte <= 8'd0;
            adc_cs_n <= 1'b1;
            read_cs_held <= 1'b0;
            cs_hold_counter <= 0;
            read_data_shift <= 24'd0;
            read_register_shift <= 32'd0;
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
                        if (sequence_start_kind == SEQ_READ4)
                            read_register_shift <= 32'd0;
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
                        if (sequence_kind == SEQ_READ4)
                            read_register_shift <= {read_register_shift[23:0], spi_rx_byte};
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
                        if (sequence_kind == SEQ_RDATA || sequence_kind == SEQ_RREG) begin
                            // RDATA/RREG命令、t6等待及数据属于同一CS事务。
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
            sequence_start_kind <= SEQ_SDATAC;
            adc_reset_n <= 1'b0;
            sample_valid <= 1'b0;
            sample_channel <= 3'd0;
            sample_data <= 24'sd0;
            initialized <= 1'b0;
            checking_initial_config <= 1'b1;
        end else begin
            sequence_start <= 1'b0;
            if (sample_valid && sample_ready)
                sample_valid <= 1'b0;

            case (state)
                ST_POWER_WAIT: begin
                    if (delay_counter >= POWERUP_DELAY_CYCLES-1) begin
                        delay_counter <= 32'd0;
                        adc_reset_n <= 1'b1;
                        drdy_seen_high <= 1'b0;
                        state <= ST_RESET_DELAY;
                    end else delay_counter <= delay_counter + 32'd1;
                end

                // 硬复位释放会自动校准，不再紧接着发送软件RESET。
                ST_RESET_DELAY: begin
                    if (drdy_sync) drdy_seen_high <= 1'b1;
                    if (drdy_seen_high && !drdy_sync
                        && delay_counter >= RESET_DELAY_CYCLES-1) begin
                        delay_counter <= 0;
                        state <= ST_SEND_SDATAC;
                    end else if (delay_counter >= DRDY_TIMEOUT_CYCLES-1)
                        state <= ST_RESET_TIMEOUT;
                    else delay_counter <= delay_counter + 1'b1;
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
                    checking_initial_config <= 1'b1;
                    state_after_gap <= ST_SEND_RREG;
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
                    drdy_seen_high <= drdy_sync;
                    delay_counter <= 0;
                    state <= ST_WAIT_CAL_DRDY;
                end
                ST_WAIT_CAL_DRDY: begin
                    if (drdy_sync) drdy_seen_high <= 1'b1;
                    if (drdy_seen_high && !drdy_sync) begin
                        target_channel <= 3'd0;
                        initialized <= 1'b1;
                        delay_counter <= 0;
                        state <= ST_SEND_MUX;
                    end else if (delay_counter >= DRDY_TIMEOUT_CYCLES-1)
                        state <= ST_CAL_TIMEOUT;
                    else delay_counter <= delay_counter + 1'b1;
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
                    checking_initial_config <= 1'b0;
                    state_after_gap <= ST_SEND_RREG;
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
                    drdy_seen_high <= drdy_sync;
                    delay_counter <= 0;
                    state <= ST_WAIT_CONVERSION;
                end
                ST_WAIT_CONVERSION: begin
                    if (drdy_sync) drdy_seen_high <= 1'b1;
                    if (drdy_seen_high && !drdy_sync)
                        state <= ST_SEND_RDATA;
                    else if (delay_counter >= DRDY_TIMEOUT_CYCLES-1)
                        state <= ST_CONVERSION_TIMEOUT;
                    else delay_counter <= delay_counter + 1'b1;
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

                ST_SEND_RREG: if (sequence_state == Q_IDLE) begin
                    sequence_start_kind <= SEQ_RREG;
                    sequence_start <= 1'b1;
                    state <= ST_WAIT_RREG;
                end
                ST_WAIT_RREG: if (sequence_done) begin
                    delay_counter <= 0;
                    state <= ST_REG_DELAY;
                end
                ST_REG_DELAY: begin
                    if (delay_counter >= RDATA_DELAY_CYCLES-1) begin
                        delay_counter <= 0;
                        state <= ST_SEND_READ4;
                    end else delay_counter <= delay_counter + 1'b1;
                end
                ST_SEND_READ4: if (sequence_state == Q_IDLE) begin
                    sequence_start_kind <= SEQ_READ4;
                    sequence_start <= 1'b1;
                    state <= ST_WAIT_READ4;
                end
                ST_WAIT_READ4: if (sequence_done) begin
                    // ID为厂设只读值，DRDY会变化；仅比较STATUS可写位。
                    // 不把未在手册中规定的ID常数作为拒绝合法芯片的条件。
                    if ((read_register_shift[31:24] & 8'h0E) != 0
                        || read_register_shift[15:0] != 16'h00E0)
                        state <= ST_CONFIG_ERROR;
                    else if (read_register_shift[23:16] != {1'b0, target_channel, 4'h8})
                        state <= ST_MUX_ERROR;
                    else begin
                        delay_counter <= 0;
                        state_after_gap <= checking_initial_config ? ST_SEND_SELFCAL : ST_SEND_SYNC;
                        state <= ST_COMMAND_GAP;
                    end
                end
                ST_RESET_TIMEOUT, ST_CAL_TIMEOUT, ST_CONFIG_ERROR,
                ST_MUX_ERROR, ST_CONVERSION_TIMEOUT, ST_INTERNAL_ERROR: begin
                    initialized <= 1'b0;
                    sample_valid <= 1'b0;
                    // 锁存故障，保留状态供串口上报，等待系统复位。
                end
                default: state <= ST_INTERNAL_ERROR;
            endcase
        end
    end

endmodule
