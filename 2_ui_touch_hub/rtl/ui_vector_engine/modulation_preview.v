// Local visual preview only: separate base values and routing are exported.
// Audio clock/note synchronization belongs in the audio engine adapter.
module modulation_preview # (parameter PREVIEW_BASE_TICKS=520833)(
    input wire clk,rst_n,
    input wire [146:0] nodes,
    input wire [8:0] rates,
    input wire [2:0] stepped,
    input wire [1:0] active_tab,
    input wire [8:0] active_phase,raster_index,
    input wire [105:0] sources,
    input wire [423:0] depths,
    input wire [370:0] base_values,
    output wire [370:0] preview_values,
    output wire [12:0] raster_q6
);
    reg [8:0] phase[0:2];
    reg [19:0] count[0:2];
    wire [20:0] samples;
    wire [38:0] raster_samples;
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(k=0;k<3;k=k+1) begin phase[k]<=0;count[k]<=0;end
        end else for(k=0;k<3;k=k+1) begin
            if(count[k]>=(PREVIEW_BASE_TICKS >> ((rates>>(k*3))&7))-1) begin
                count[k]<=0;phase[k]<=phase[k]==383 ? 0 : phase[k]+1'b1;
            end else count[k]<=count[k]+1'b1;
        end
    end
    genvar s,n;
    generate for(s=0;s<3;s=s+1) begin: curves
        lfo_smooth_table u_table(.clk(clk),.rst_n(rst_n),.nodes(nodes[s*49+:49]),
            .stepped(stepped[s]),.raster_index(raster_index),
            .preview_index(active_tab==s ? active_phase : phase[s]),
            .raster_q6(raster_samples[s*13+:13]),.preview_value(samples[s*7+:7]));
    end endgenerate
    assign raster_q6=active_tab==0 ? raster_samples[12:0] : active_tab==1 ? raster_samples[25:13] : raster_samples[38:26];
    // One shared multiplier updates all 53 visual values in 53 clocks (<1 us).
    // There is no reason to allocate an audio-rate DSP per UI destination.
    reg [5:0] scan,index0,index1,index2;
    reg [6:0] wave0,base0,base1;
    reg signed [7:0] depth0;
    reg signed [15:0] product1;
    reg signed [16:0] result2;
    reg [6:0] rendered[0:52];
    wire [1:0] scan_source=sources[scan*2+:2];
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scan<=0;index0<=0;index1<=0;index2<=0;
            wave0<=0;base0<=0;base1<=0;depth0<=0;product1<=0;result2<=0;
            for(j=0;j<53;j=j+1) rendered[j]<=0;
        end else begin
            scan<=scan==52 ? 0 : scan+1'b1;
            index0<=scan;index1<=index0;index2<=index1;
            wave0<=scan_source==1 ? samples[6:0] : scan_source==2 ? samples[13:7] : samples[20:14];
            base0<=base_values[scan*7+:7];depth0<=depths[scan*8+:8];
            base1<=base0;product1<=depth0*$signed({1'b0,wave0});
            result2<=$signed({10'd0,base1})+(product1>>>7);
            rendered[index2]<=result2<0 ? 7'd0 : result2>127 ? 7'd127 : result2[6:0];
        end
    end
    generate for(n=0;n<53;n=n+1) begin: destinations
        assign preview_values[n*7+:7]=sources[n*2+:2]==0 ? base_values[n*7+:7] : rendered[n];
    end endgenerate
endmodule
