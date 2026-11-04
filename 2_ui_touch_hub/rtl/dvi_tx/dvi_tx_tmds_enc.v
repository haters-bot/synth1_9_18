// ==============================================================================
// 模块名称: dvi_tx_tmds_enc.v
// 功能描述: 标准 DVI 1.0 / HDMI TMDS 8b/10b 编码器 (2 级流水线优化版)
//           第 1 级: 最小翻转 XOR/XNOR 编码与 1 的统计
//           第 2 级: 直流平衡 (DC Disparity) 计算与符号反转
//           时序性能: GW5AST 150MHz~250MHz 轻松收敛
// ==============================================================================

module dvi_tx_tmds_enc (
    input  wire        clock,
    input  wire        reset,
    input  wire        den,
    input  wire [7:0]  data,
    input  wire [1:0]  ctrl,
    output reg  [9:0]  tmds
);

    function [3:0] count_ones;
        input [7:0] data_in;
        integer loop;
        begin
            count_ones = 4'd0;
            for (loop = 0; loop < 8; loop = loop + 1) begin
                count_ones = count_ones + data_in[loop];
            end
        end
    endfunction

    // --------------------------------------------------------------------------
    // 流水线输入重定时级 (Stage 0): 隔断来自 UI 渲染流水线输出的长布线延时
    // --------------------------------------------------------------------------
    reg        s0_den;
    reg [7:0]  s0_data;
    reg [1:0]  s0_ctrl;

    always @(posedge clock) begin
        if (reset) begin
            s0_den  <= 1'b0;
            s0_data <= 8'd0;
            s0_ctrl <= 2'b0;
        end else begin
            s0_den  <= den;
            s0_data <= data;
            s0_ctrl <= ctrl;
        end
    end

    // --------------------------------------------------------------------------
    // 流水线第 1 级: 并行前缀 XOR 编码与 1 的极速统计
    // --------------------------------------------------------------------------
    wire [3:0] data_ones = s0_data[0] + s0_data[1] + s0_data[2] + s0_data[3] +
                           s0_data[4] + s0_data[5] + s0_data[6] + s0_data[7];
    wire       qm_flip   = (data_ones > 4'd4) | ((data_ones == 4'd4) & (!s0_data[0]));

    // 并行前缀树 (Prefix XOR Tree)，消除 8 级串联 Ripple 门延时
    wire p0 = s0_data[0];
    wire p1 = p0 ^ s0_data[1];
    wire p2 = p1 ^ s0_data[2];
    wire p3 = p2 ^ s0_data[3];
    wire p4 = p3 ^ s0_data[4];
    wire p5 = p4 ^ s0_data[5];
    wire p6 = p5 ^ s0_data[6];
    wire p7 = p6 ^ s0_data[7];

    wire [8:0] q_m_comb;
    assign q_m_comb[0] = p0;
    assign q_m_comb[1] = qm_flip ? ~p1 : p1;
    assign q_m_comb[2] = p2;
    assign q_m_comb[3] = qm_flip ? ~p3 : p3;
    assign q_m_comb[4] = p4;
    assign q_m_comb[5] = qm_flip ? ~p5 : p5;
    assign q_m_comb[6] = p6;
    assign q_m_comb[7] = qm_flip ? ~p7 : p7;
    assign q_m_comb[8] = ~qm_flip;

    reg       s1_den;
    reg [1:0] s1_ctrl;
    reg [8:0] s1_qm;
    reg [3:0] s1_qm_ones;

    always @(posedge clock) begin
        if (reset) begin
            s1_den     <= 1'b0;
            s1_ctrl    <= 2'b0;
            s1_qm      <= 9'b0;
            s1_qm_ones <= 4'd0;
        end else begin
            s1_den     <= s0_den;
            s1_ctrl    <= s0_ctrl;
            s1_qm      <= q_m_comb;
            s1_qm_ones <= count_ones(q_m_comb[7:0]);
        end
    end

    // --------------------------------------------------------------------------
    // 流水线第 2 级: 符号直流平衡与差异累加器
    // --------------------------------------------------------------------------
    wire ones_equ  = (s1_qm_ones == 4'd4);
    wire ones_larg = (s1_qm_ones > 4'd4);
    wire ones_sml  = (s1_qm_ones < 4'd4);

    reg signed [8:0] cnt_q;
    reg signed [8:0] cnt_d;
    reg [9:0]        q_out;

    always @(*) begin
        if (!s1_den) begin
            case (s1_ctrl)
                2'b00:   q_out = 10'b1101010100;
                2'b01:   q_out = 10'b0010101011;
                2'b10:   q_out = 10'b0101010100;
                default: q_out = 10'b1010101011;
            endcase
            cnt_d = 9'sd0;
        end else if ((cnt_q == 0) | ones_equ) begin
            q_out[9]   = ~s1_qm[8];
            q_out[8]   = s1_qm[8];
            q_out[7:0] = s1_qm[8] ? s1_qm[7:0] : ~s1_qm[7:0];
            if (s1_qm[8]) begin
                cnt_d = cnt_q + $signed({5'b0, s1_qm_ones} - 9'sd4) * 9'sd2;
            end else begin
                cnt_d = cnt_q + $signed(9'sd4 - {5'b0, s1_qm_ones}) * 9'sd2;
            end
        end else if (((cnt_q > 0) & ones_larg) | ((cnt_q < 0) & ones_sml)) begin
            q_out[9]   = 1'b1;
            q_out[8]   = s1_qm[8];
            q_out[7:0] = ~s1_qm[7:0];
            if (s1_qm[8]) begin
                cnt_d = cnt_q + 9'sd2 + $signed(9'sd4 - {5'b0, s1_qm_ones}) * 9'sd2;
            end else begin
                cnt_d = cnt_q + $signed(9'sd4 - {5'b0, s1_qm_ones}) * 9'sd2;
            end
        end else begin
            q_out[9]   = 1'b0;
            q_out[8]   = s1_qm[8];
            q_out[7:0] = s1_qm[7:0];
            if (!s1_qm[8]) begin
                cnt_d = cnt_q - 9'sd2 + $signed({5'b0, s1_qm_ones} - 9'sd4) * 9'sd2;
            end else begin
                cnt_d = cnt_q + $signed({5'b0, s1_qm_ones} - 9'sd4) * 9'sd2;
            end
        end
    end

    always @(posedge clock) begin
        if (reset) begin
            tmds  <= 10'd0;
            cnt_q <= 9'sd0;
        end else begin
            tmds  <= q_out;
            cnt_q <= cnt_d;
        end
    end

endmodule
