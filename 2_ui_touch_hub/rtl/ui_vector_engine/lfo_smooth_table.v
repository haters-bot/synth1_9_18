// C1 monotone cubic Hermite with minmod tangents, not Serum proprietary math.
// Node lookup, secants, tangents and coefficients have separate pipeline stages.
// Horner intermediates retain precision; only the final Q7.6 result is truncated.
module lfo_smooth_table #(parameter PREVIEW_SYNC=0)(
    input wire clk,rst_n,
    input wire [48:0] nodes,
    input wire stepped,
    input wire [8:0] raster_index,preview_index,
    output wire [12:0] raster_q6,
    output wire [6:0] preview_value
);
    reg [12:0] table_mem[0:384];
    reg [8:0] build_index;
    wire [2:0] segment=build_index==384 ? 3'd5 : build_index[8:6];
    function [6:0] point;
        input [2:0] n;
        begin case(n)
            0:point=nodes[6:0];1:point=nodes[13:7];2:point=nodes[20:14];
            3:point=nodes[27:21];4:point=nodes[34:28];5:point=nodes[41:35];
            6:point=nodes[48:42];default:point=0;
        endcase end
    endfunction
    function signed [7:0] minmod;
        input signed [7:0] dl,dr;
        begin
            if(dl==0 || dr==0 || dl[7]!=dr[7]) minmod=0;
            else if(!dl[7]) minmod=dl<dr ? dl : dr;
            else minmod=dl>dr ? dl : dr;
        end
    endfunction
    reg [6:0] pa,aa,ba,na,ta,ab,tb,ac,tc;
    reg first_a,last_a,first_b,last_b,sa,sb,sc;
    reg [8:0] ia,ib,ic;
    reg va,vb,vc;
    reg signed [7:0] dl_b,dm_b,dr_b,m0_c,m1_c,dm_c;
    reg signed [10:0] c1_0,c2_0,c3_0,c1_1;
    reg [6:0] a0,a1,a2,t0,t1,t2;
    reg [8:0] index0,index1,index2,index3;
    reg step0,step1,step2,valid0,valid1,valid2,valid3;
    reg signed [17:0] h1;
    reg signed [23:0] h2;
    reg signed [14:0] h3;
    wire signed [31:0] final_sum=h2*$signed({1'b0,t2})+($signed({1'b0,a2})<<<18);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            build_index<=0;va<=0;vb<=0;vc<=0;valid0<=0;valid1<=0;valid2<=0;valid3<=0;
            pa<=0;aa<=0;ba<=0;na<=0;ta<=0;ab<=0;tb<=0;ac<=0;tc<=0;
            first_a<=0;last_a<=0;first_b<=0;last_b<=0;sa<=0;sb<=0;sc<=0;ia<=0;ib<=0;ic<=0;
            dl_b<=0;dm_b<=0;dr_b<=0;m0_c<=0;m1_c<=0;dm_c<=0;
            index0<=0;index1<=0;index2<=0;index3<=0;
            a0<=0;a1<=0;a2<=0;t0<=0;t1<=0;t2<=0;
            c1_0<=0;c2_0<=0;c3_0<=0;c1_1<=0;h1<=0;h2<=0;h3<=0;
            step0<=0;step1<=0;step2<=0;
        end else begin
            build_index<=build_index==384 ? 0 : build_index+1'b1;
            // A: bounded node muxes and exact segment/fraction.
            va<=1;ia<=build_index;
            pa<=point(segment-3'd1);aa<=point(segment);ba<=point(segment+3'd1);na<=point(segment+3'd2);
            first_a<=segment==0;last_a<=segment==5;
            ta<=build_index==384 ? 7'd64 : {1'b0,build_index[5:0]};
            sa<=stepped && build_index!=384;
            // B: signed adjacent secants, range -127..127.
            vb<=va;ib<=ia;ab<=aa;tb<=ta;sb<=sa;first_b<=first_a;last_b<=last_a;
            dl_b<=$signed({1'b0,aa})-$signed({1'b0,pa});
            dm_b<=$signed({1'b0,ba})-$signed({1'b0,aa});
            dr_b<=$signed({1'b0,na})-$signed({1'b0,ba});
            // C: shape-preserving tangents.
            vc<=vb;ic<=ib;ac<=ab;tc<=tb;sc<=sb;dm_c<=dm_b;
            m0_c<=first_b ? 8'sd0 : minmod(dl_b,dm_b);
            m1_c<=last_b ? 8'sd0 : minmod(dm_b,dr_b);
            // D: cubic coefficients, then three Horner stages and a RAM write.
            valid0<=vc;valid1<=valid0;valid2<=valid1;valid3<=valid2;
            index0<=ic;index1<=index0;index2<=index1;index3<=index2;
            a0<=ac;a1<=a0;a2<=a1;t0<=tc;t1<=t0;t2<=t1;
            step0<=sc;step1<=step0;step2<=step1;
            c1_0<=m0_c;c2_0<=11'sd3*dm_c-11'sd2*m0_c-m1_c;c3_0<=-11'sd2*dm_c+m0_c+m1_c;
            c1_1<=c1_0;
            h1<=c3_0*$signed({1'b0,t0})+($signed(c2_0)<<<6);
            h2<=h1*$signed({1'b0,t1})+($signed(c1_1)<<<12);
            h3<=step2 ? $signed({1'b0,a2,6'd0}) : final_sum>>>12;
        end
    end
    // RAM has no reset. Reset only the producer's valid pipeline above, so
    // global reset does not become a combinational RAM write-enable path.
    always @(posedge clk)
        if(valid3) table_mem[index3]<=h3<0 ? 0 : h3>8128 ? 13'd8128 : h3[12:0];
    assign raster_q6=table_mem[raster_index<=384 ? raster_index : 0];
    generate if(PREVIEW_SYNC)begin: synchronous_preview
        // Mirror only the seven preview bits into a single-write/synchronous-
        // read RAM. Raster retains its existing asynchronous Q7.6 port. This
        // avoids a third RAM port and the 385-word combinational preview mux.
        reg [6:0] preview_mem[0:384];
        reg [6:0] preview_sample;
        always @(posedge clk)begin
            if(valid3)preview_mem[index3]<=h3<0 ? 0 : h3>8128 ? 7'd127 : h3[12:6];
            preview_sample<=preview_mem[preview_index<=384 ? preview_index : 0];
        end
        assign preview_value=preview_sample;
    end else begin: asynchronous_preview
        assign preview_value=table_mem[preview_index<=384 ? preview_index : 0]>>6;
    end endgenerate
endmodule
