// 七个等距节点展开为385项Q7.6曲线；后台逐项生成，前台同步读表。
// 两份独立块RAM避免运行中读到半张新表，active_bank仅由统一Commit切换。
module lfo_hermite_table (
    input wire clk, rst_n,
    input wire build_start,
    input wire [48:0] build_nodes,
    input wire build_stepped, build_bank, active_bank,
    input wire [8:0] read_index,
    output wire [12:0] read_q6,
    output reg build_done,
    output wire busy
);
    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg [12:0] table_0 [0:511];
    (* syn_ramstyle = "block_ram", ram_style = "block" *)
    reg [12:0] table_1 [0:511];
    reg [12:0] read_0, read_1;
    assign read_q6 = active_bank ? read_1 : read_0;
    reg [3:0] state;
    reg [48:0] nodes;
    reg stepped, write_bank;
    reg [8:0] index;
    wire [2:0] segment = index == 9'd384 ? 3'd5 : index[8:6];
    reg [6:0] a, t;
    reg signed [7:0] dl, dm, dr, m0, m1;
    reg signed [10:0] c1, c2, c3;
    reg signed [17:0] h1;
    reg signed [24:0] h2;
    // Gowin在原h2乘加/符号移位推断中出现SP00019/10CSHIFT1内部错误。
    // 每级先寄存完整乘积，再显式扩位相加；不依赖移位表达式的上下文扩位。
    reg signed [18:0] product_h1;
    reg signed [25:0] product_h2;
    reg signed [32:0] product_h3;
    reg signed [32:0] final_sum;
    wire signed [7:0] fraction = {1'b0,t};
    wire signed [10:0] dm_ext = {{3{dm[7]}},dm};
    wire signed [10:0] m0_ext = {{3{m0[7]}},m0};
    wire signed [10:0] m1_ext = {{3{m1[7]}},m1};
    wire signed [18:0] c2_scaled = {{2{c2[10]}},c2,6'd0};
    wire signed [25:0] c1_scaled = {{3{c1[10]}},c1,12'd0};
    wire signed [32:0] node_scaled = {8'd0,a,18'd0};
    wire signed [18:0] h1_sum = product_h1+c2_scaled;
    wire signed [25:0] h2_sum = product_h2+c1_scaled;
    // Q6只在最后去掉12位小数，符号位保留。合法节点范围内h1/h2截取不溢出。
    wire signed [20:0] result_q6 = final_sum[32:12];
    wire [12:0] clipped_q6 = stepped && index != 9'd384 ? {a,6'd0}
        : result_q6 < 0 ? 13'd0 : result_q6 > 8128 ? 13'd8128
        : result_q6[12:0];
    always @(posedge clk) begin
        // 后台写时输出直接旁路写入值，明确为write-first；避免要求器件不支持的
        // read-before-write模式。写入的一份表此时不会被前台选中。
        if (state==4'd8 && !write_bank) begin
            table_0[index]<=clipped_q6; read_0<=clipped_q6;
        end else read_0<=table_0[read_index];
        if (state==4'd8 && write_bank) begin
            table_1[index]<=clipped_q6; read_1<=clipped_q6;
        end else read_1<=table_1[read_index];
    end
    assign busy = state != 0;
    function [6:0] point;
        input [2:0] n;
        begin
            case (n)
                0: point=nodes[6:0]; 1: point=nodes[13:7];
                2: point=nodes[20:14]; 3: point=nodes[27:21];
                4: point=nodes[34:28]; 5: point=nodes[41:35];
                6: point=nodes[48:42]; default: point=0;
            endcase
        end
    endfunction
    function signed [7:0] minmod;
        input signed [7:0] x,y;
        begin
            if (x==0 || y==0 || x[7]!=y[7]) minmod=0;
            else if (!x[7]) minmod=x<y ? x : y;
            else minmod=x>y ? x : y;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=0; nodes<=0; stepped<=0; write_bank<=0;
            index<=0; a<=0; t<=0; dl<=0; dm<=0; dr<=0;
            m0<=0; m1<=0; c1<=0; c2<=0; c3<=0; h1<=0; h2<=0;
            product_h1<=0; product_h2<=0; product_h3<=0; final_sum<=0;
            build_done<=0;
        end else begin
            build_done<=0;
            case (state)
                0: if (build_start) begin
                    nodes<=build_nodes; stepped<=build_stepped;
                    write_bank<=build_bank; index<=0; state<=1;
                end
                1: begin
                    a<=point(segment);
                    t<=index==9'd384 ? 7'd64 : {1'b0,index[5:0]};
                    dl<=$signed({1'b0,point(segment)})
                        -$signed({1'b0,point(segment-3'd1)});
                    dm<=$signed({1'b0,point(segment+3'd1)})
                        -$signed({1'b0,point(segment)});
                    dr<=$signed({1'b0,point(segment+3'd2)})
                        -$signed({1'b0,point(segment+3'd1)});
                    state<=2;
                end
                2: begin
                    m0<=segment==0 ? 8'sd0 : minmod(dl,dm);
                    m1<=segment==5 ? 8'sd0 : minmod(dm,dr); state<=3;
                end
                3: begin
                    c1<=m0_ext;
                    c2<=dm_ext+dm_ext+dm_ext-m0_ext-m0_ext-m1_ext;
                    c3<=m0_ext+m1_ext-dm_ext-dm_ext; state<=4;
                end
                4: begin
                    product_h1<=c3*fraction; state<=5;
                end
                5: begin
                    h1<=h1_sum[17:0]; state<=6;
                end
                6: begin
                    product_h2<=h1*fraction; state<=7;
                end
                7: begin
                    h2<=h2_sum[24:0]; state<=9;
                end
                9: begin
                    product_h3<=h2*fraction; state<=10;
                end
                10: begin
                    final_sum<=product_h3+node_scaled; state<=8;
                end
                8: begin
                    // RAM写入由上方独立时序块完成，不复位RAM内容。
                    if (index==9'd384) begin build_done<=1; state<=0; end
                    else begin index<=index+9'd1; state<=1; end
                end
                default: state<=0;
            endcase
        end
    end
endmodule
