// V2：53个固定目标，每目标绑定一个LFO。单乘法器流水扫描，整组输出提交。
// 参数总线第n项为[n*7+:7]，来源0=无、1/2/3=LFO1/2/3。
module lfo_target_router_v2 (
    input wire clk, rst_n, sample_tick,
    input wire [370:0] base_values,
    input wire [105:0] sources,
    input wire [423:0] depths,
    input wire [20:0] waves,
    output wire [370:0] mod_values,
    output reg output_valid, busy, overrun
);
    reg ready, issuing;
    reg [5:0] scan, index0, index1, index2;
    reg valid0, valid1, valid2;
    reg [370:0] base_snapshot, working, result;
    reg [105:0] source_snapshot;
    reg [423:0] depth_snapshot;
    reg [20:0] wave_snapshot;
    reg [6:0] wave0, base0, base1;
    reg signed [7:0] depth0;
    reg signed [15:0] product1;
    reg signed [16:0] sum2;
    wire [1:0] source_now=source_snapshot[scan*2+:2];
    wire [6:0] clipped=sum2<0 ? 7'd0 : sum2>127 ? 7'd127 : sum2[6:0];
    assign mod_values=ready ? result : base_values;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready<=0; issuing<=0; busy<=0; overrun<=0; output_valid<=0;
            scan<=0; index0<=0; index1<=0; index2<=0;
            valid0<=0; valid1<=0; valid2<=0;
            base_snapshot<=0; source_snapshot<=0; depth_snapshot<=0;
            wave_snapshot<=0; working<=0; result<=0;
            wave0<=0; base0<=0; base1<=0; depth0<=0; product1<=0; sum2<=0;
        end else begin
            output_valid<=0;
            valid0<=issuing; valid1<=valid0; valid2<=valid1;
            if (sample_tick) begin
                if (busy) overrun<=1;
                else begin
                    base_snapshot<=base_values; source_snapshot<=sources;
                    depth_snapshot<=depths; wave_snapshot<=waves;
                    scan<=0; issuing<=1; busy<=1;
                end
            end
            if (issuing) begin
                index0<=scan; base0<=base_snapshot[scan*7+:7];
                depth0<=depth_snapshot[scan*8+:8];
                case (source_now)
                    1: wave0<=wave_snapshot[6:0];
                    2: wave0<=wave_snapshot[13:7];
                    3: wave0<=wave_snapshot[20:14];
                    default: wave0<=0;
                endcase
                if (scan==6'd52) issuing<=0;
                else scan<=scan+6'd1;
            end
            if (valid0) begin
                index1<=index0; base1<=base0;
                product1<=depth0*$signed({1'b0,wave0});
            end
            if (valid1) begin
                index2<=index1;
                sum2<=$signed({10'd0,base1})+(product1>>>7);
            end
            if (valid2) begin
                working[index2*7+:7]<=clipped;
                if (index2==6'd52) begin
                    result<={clipped,working[363:0]};
                    output_valid<=1; ready<=1; busy<=0;
                end
            end
        end
    end
endmodule
