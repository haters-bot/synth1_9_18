// Low-rate 16-bit progress: floor(elapsed_ms * 65535 / duration_ms).
// A 48-cycle restoring divider avoids a large combinational divider and
// the 32-bit numerator overflow present beyond about 65.5 seconds.
module performance_progress(
    input wire clk, rst_n, refresh,
    input wire [31:0] elapsed_ms, duration_ms,
    output reg [15:0] progress,
    output wire busy
);
    reg [47:0] dividend;
    reg [31:0] divisor;
    reg [32:0] remainder;
    reg [15:0] quotient;
    reg [5:0] remaining;
    assign busy = remaining != 0;
    wire [32:0] trial = {remainder[31:0],dividend[47]};
    wire subtract = trial >= {1'b0,divisor};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            progress<=0;dividend<=0;divisor<=0;remainder<=0;quotient<=0;remaining<=0;
        end else if (busy) begin
            remainder <= subtract ? trial - {1'b0,divisor} : trial;
            dividend <= {dividend[46:0],1'b0};
            quotient <= {quotient[14:0],subtract};
            remaining <= remaining-1'b1;
            if (remaining==1)progress<={quotient[14:0],subtract};
        end else if (refresh) begin
            if (duration_ms==0)progress<=0;
            else if (elapsed_ms>=duration_ms)progress<=16'hFFFF;
            else begin
                dividend<={elapsed_ms,16'd0}-{16'd0,elapsed_ms};
                divisor<=duration_ms;
                remainder<=0;quotient<=0;remaining<=48;
            end
        end
    end
endmodule
