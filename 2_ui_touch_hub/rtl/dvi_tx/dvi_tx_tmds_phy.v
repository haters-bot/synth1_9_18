module dvi_tx_tmds_phy(
	
	input				pixel_clock,
	input				ddr_bit_clock,
	input				reset,
	input	[9 : 0]		data,
	output	[1 : 0]		tmds_lane
);
	
	wire dq_tmds;

	// Assert asynchronously when clocks are unavailable; release only after
	// two rising FCLK edges followed by a falling edge. This keeps release
	// away from the coincident PCLK/FCLK rising edges. Preserve a local chain
	// per lane so the final stage
	// can be placed near its serializer. Its RESET recovery/removal is timed.
	reg [2:0] reset_pipe = 3'b111 /* synthesis syn_preserve=1 syn_keep=1 */;
	always @(posedge ddr_bit_clock or posedge reset) begin
		if (reset) reset_pipe[1:0] <= 2'b11;
		else reset_pipe[1:0] <= {reset_pipe[0],1'b0};
	end
	always @(negedge ddr_bit_clock or posedge reset) begin
		if (reset) reset_pipe[2] <= 1'b1;
		else reset_pipe[2] <= reset_pipe[1];
	end

	OSER10 tmds_serdes_inst0 (
		.Q(dq_tmds),
		.D0(data[0]),
		.D1(data[1]),
		.D2(data[2]),
		.D3(data[3]),
		.D4(data[4]),
		.D5(data[5]),
		.D6(data[6]),
		.D7(data[7]),
		.D8(data[8]),
		.D9(data[9]),
		.PCLK(pixel_clock),
		.FCLK(ddr_bit_clock),
		.RESET(reset_pipe[2])
	);
	
	ELVDS_OBUF tmds_bufds_isnt0 (
		.I(dq_tmds),
		.O(tmds_lane[1]),
		.OB(tmds_lane[0])
	);
	
endmodule
