// Human-readable C14 stream for physical knob and SPI link events.
// No idle heartbeat is emitted; SPI link lines arrive only on state changes.
`include "params.vh"
module knob_ascii_trace #(parameter integer CLK_FREQ=50000000,parameter integer BAUD=115200,parameter integer FIFO_BITS=5)(
    input wire clk,input wire rst_n,
    input wire knob_valid,input wire [7:0] knob_id,input wire knob_cw,
    input wire button_valid,input wire [7:0] button_id,input wire [1:0] button_action,
    input wire link_valid,input wire link_chip,input wire link_up,
    output wire uart_tx);
    localparam integer DEPTH=1<<FIFO_BITS;
    localparam [2:0] EVT_CW=0,EVT_CCW=1,EVT_PRESS=2,EVT_RELEASE=3,EVT_LINK_UP=4,EVT_LINK_DOWN=5;
    reg [2:0] fifo_type[0:DEPTH-1]; reg [5:0] fifo_id[0:DEPTH-1];
    reg [FIFO_BITS-1:0] wr_ptr,rd_ptr; reg [FIFO_BITS:0] count;
    reg msg_active; reg [5:0] msg_pos,msg_len; reg [7:0] msg[0:23];
    wire uart_busy; wire msg_start=!msg_active && (count!=0);
    wire uart_send=msg_active && !uart_busy && (msg_pos<msg_len); wire [7:0] uart_data=msg[msg_pos];
    integer i,push_n; reg [FIFO_BITS-1:0] push_ptr;
    function [5:0] physical_knob; input [7:0] id; begin
        case(id)
            `PARAM_ID_OSCA_WT_POS:physical_knob=0; `PARAM_ID_OSCA_WARP:physical_knob=1;
            `PARAM_ID_OSCA_PAN:physical_knob=2; `PARAM_ID_OSCA_VOL:physical_knob=3;
            `PARAM_ID_OSCA_UNISON:physical_knob=4; `PARAM_ID_OSCA_DETUNE:physical_knob=5;
            `PARAM_ID_OSCA_BLEND:physical_knob=6; `PARAM_ID_OSCA_PHASE:physical_knob=7;
            `PARAM_ID_ENV1_ATTACK:physical_knob=8; `PARAM_ID_ENV1_HOLD:physical_knob=9;
            `PARAM_ID_ENV1_DECAY:physical_knob=10; `PARAM_ID_ENV1_SUSTAIN:physical_knob=11;
            `PARAM_ID_ENV1_RELEASE:physical_knob=12; `PARAM_ID_MASTER_VOL:physical_knob=13;
            `PARAM_ID_MACRO1:physical_knob=14; `PARAM_ID_MACRO2:physical_knob=15;
            `PARAM_ID_OSCB_WT_POS:physical_knob=16; `PARAM_ID_OSCB_WARP:physical_knob=17;
            `PARAM_ID_OSCB_PAN:physical_knob=18; `PARAM_ID_OSCB_VOL:physical_knob=19;
            `PARAM_ID_OSCB_UNISON:physical_knob=20; `PARAM_ID_OSCB_DETUNE:physical_knob=21;
            `PARAM_ID_OSCB_BLEND:physical_knob=22; `PARAM_ID_OSCB_PHASE:physical_knob=23;
            `PARAM_ID_FLT_CUTOFF:physical_knob=24; `PARAM_ID_FLT_RES:physical_knob=25;
            `PARAM_ID_FLT_PAN:physical_knob=26; `PARAM_ID_FLT_DRIVE:physical_knob=27;
            `PARAM_ID_FLT_FAT:physical_knob=28; `PARAM_ID_FLT_MIX:physical_knob=29;
            `PARAM_ID_FX_REVERB:physical_knob=30; `PARAM_ID_FX_DELAY:physical_knob=31;
            default:physical_knob=0;
        endcase
    end endfunction
    function [7:0] dec_digit; input integer value; begin dec_digit=8'h30+value; end endfunction

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr<=0;rd_ptr<=0;count<=0;msg_active<=0;msg_pos<=0;msg_len<=0;
            for(i=0;i<24;i=i+1) msg[i]<=0;
        end else begin
            push_n=0;push_ptr=wr_ptr;
            // Preserve simultaneous link, switch and rotation events.
            if(link_valid && (count+push_n<DEPTH)) begin
                fifo_type[push_ptr] <= link_up ? EVT_LINK_UP : EVT_LINK_DOWN;
                fifo_id[push_ptr] <= link_chip ? 6'd1 : 6'd0;push_ptr=push_ptr+1'b1;push_n=push_n+1;
            end
            if(button_valid && (count+push_n<DEPTH)) begin
                fifo_type[push_ptr] <= (button_action==2'd1) ? EVT_PRESS : EVT_RELEASE;
                fifo_id[push_ptr]<=physical_knob(button_id);push_ptr=push_ptr+1'b1;push_n=push_n+1;
            end
            if(knob_valid && (count+push_n<DEPTH)) begin
                fifo_type[push_ptr] <= knob_cw ? EVT_CW : EVT_CCW;
                fifo_id[push_ptr]<=physical_knob(knob_id);push_ptr=push_ptr+1'b1;push_n=push_n+1;
            end
            if(push_n!=0) wr_ptr<=wr_ptr+push_n;

            if(msg_start) begin
                rd_ptr<=rd_ptr+1'b1;msg_active<=1;msg_pos<=0;
                if(fifo_type[rd_ptr]==EVT_LINK_UP || fifo_type[rd_ptr]==EVT_LINK_DOWN) begin
                    msg[0]<="U";msg[1]<=dec_digit(fifo_id[rd_ptr]+1);msg[2]<=" ";msg[3]<="S";msg[4]<="P";msg[5]<="I";msg[6]<=" ";
                    if(fifo_type[rd_ptr]==EVT_LINK_UP) begin
                        msg[7]<="C";msg[8]<="O";msg[9]<="N";msg[10]<="N";msg[11]<="E";msg[12]<="C";msg[13]<="T";msg[14]<="E";msg[15]<="D";msg[16]<=13;msg[17]<=10;msg_len<=18;
                    end else begin
                        msg[7]<="D";msg[8]<="I";msg[9]<="S";msg[10]<="C";msg[11]<="O";msg[12]<="N";msg[13]<="N";msg[14]<="E";msg[15]<="C";msg[16]<="T";msg[17]<="E";msg[18]<="D";msg[19]<=13;msg[20]<=10;msg_len<=21;
                    end
                end else begin
                    msg[0]<="K";msg[1]<=dec_digit((fifo_id[rd_ptr]+1)/10);msg[2]<=dec_digit((fifo_id[rd_ptr]+1)%10);msg[3]<=" ";
                    if(fifo_type[rd_ptr]==EVT_CW) begin
                        msg[4]<="C";msg[5]<="W";msg[6]<=" ";msg[7]<="U";msg[8]<=dec_digit((fifo_id[rd_ptr]<16)?1:2);msg[9]<=13;msg[10]<=10;msg_len<=11;
                    end else if(fifo_type[rd_ptr]==EVT_CCW) begin
                        msg[4]<="C";msg[5]<="C";msg[6]<="W";msg[7]<=" ";msg[8]<="U";msg[9]<=dec_digit((fifo_id[rd_ptr]<16)?1:2);msg[10]<=13;msg[11]<=10;msg_len<=12;
                    end else if(fifo_type[rd_ptr]==EVT_PRESS) begin
                        msg[4]<="P";msg[5]<="R";msg[6]<="E";msg[7]<="S";msg[8]<="S";msg[9]<=" ";msg[10]<="U";msg[11]<=dec_digit((fifo_id[rd_ptr]<16)?1:2);msg[12]<=13;msg[13]<=10;msg_len<=14;
                    end else begin
                        msg[4]<="R";msg[5]<="E";msg[6]<="L";msg[7]<="E";msg[8]<="A";msg[9]<="S";msg[10]<="E";msg[11]<=" ";msg[12]<="U";msg[13]<=dec_digit((fifo_id[rd_ptr]<16)?1:2);msg[14]<=13;msg[15]<=10;msg_len<=16;
                    end
                end
            end else if(uart_send) msg_pos<=msg_pos+1'b1;
            else if(msg_active && !uart_busy && msg_pos>=msg_len) msg_active<=0;

            case({(push_n!=0),msg_start})
                2'b10:count<=count+push_n;
                2'b01:count<=count-1'b1;
                2'b11:count<=count+push_n-1'b1;
                default:count<=count;
            endcase
        end
    end

    knob_ascii_uart_byte #(.CLK_FREQ(CLK_FREQ),.BAUD(BAUD)) u_byte(
        .clk(clk),.rst_n(rst_n),.send(uart_send),.data(uart_data),.busy(uart_busy),.tx(uart_tx));
endmodule

module knob_ascii_uart_byte #(parameter integer CLK_FREQ=50000000,parameter integer BAUD=115200)(
    input wire clk,input wire rst_n,input wire send,input wire [7:0] data,output reg busy,output reg tx);
    localparam integer DIV=(CLK_FREQ+BAUD/2)/BAUD; reg [31:0] timer;reg [3:0] bits_left;reg [8:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin timer<=0;bits_left<=0;shift<=9'h1ff;busy<=0;tx<=1;end
        else if(!busy) begin
            tx<=1;
            if(send) begin tx<=0;shift<={1'b1,data};timer<=DIV-1;bits_left<=10;busy<=1;end
        end else if(timer!=0) timer<=timer-1'b1;
        else if(bits_left==1) begin busy<=0;tx<=1;bits_left<=0;end
        else begin tx<=shift[0];shift<={1'b1,shift[8:1]};bits_left<=bits_left-1'b1;timer<=DIV-1;end
    end
endmodule
