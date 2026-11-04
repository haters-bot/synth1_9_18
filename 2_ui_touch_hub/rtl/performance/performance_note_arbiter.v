// Independent queues preserve simultaneous score, remote and touch events.
// Round-robin selection preserves each source's order; UART ready prevents
// dequeuing into a full transmitter. Overload is explicit, never a silent mux.
module performance_note_arbiter #(
    parameter integer DEPTH=16
)(
    input wire clk,rst_n,
    input wire flush,
    output wire busy,
    input wire score_valid,score_on,
    output wire score_ready,
    input wire [6:0] score_note,score_velocity,
    input wire remote_valid,remote_on,
    input wire [6:0] remote_note,remote_velocity,
    input wire touch_valid,touch_on,
    input wire [6:0] touch_note,touch_velocity,
    output reg note_valid /* synthesis syn_preserve=1 syn_keep=1 */,
    input wire note_ready,
    output wire note_on,
    output wire [6:0] note_number,note_velocity,
    output reg overflow
);
    localparam integer BITS=$clog2(DEPTH);
    reg [14:0] score_mem[0:DEPTH-1],remote_mem[0:DEPTH-1],touch_mem[0:DEPTH-1];
    reg [BITS-1:0] sw,sr,rw,rr,tw,tr;
    reg [BITS:0] sc,rc,tc;
    reg [1:0] next_source,selected;
    reg [14:0] note_payload /* synthesis syn_preserve=1 syn_keep=1 */;
    reg [127:0] held_notes;
    reg cleaning;
    reg [6:0] clean_note;
    assign busy=(sc!=0 || rc!=0 || tc!=0 || note_valid || cleaning || |held_notes);
    always @(*)begin
        selected=3;
        case(next_source)
            0:if(sc!=0)selected=0;else if(rc!=0)selected=1;else if(tc!=0)selected=2;
            1:if(rc!=0)selected=1;else if(tc!=0)selected=2;else if(sc!=0)selected=0;
            default:if(tc!=0)selected=2;else if(sc!=0)selected=0;else if(rc!=0)selected=1;
        endcase
    end
    wire [14:0] record_data=selected==0 ? score_mem[sr] : selected==1 ? remote_mem[rr] : touch_mem[tr];
    assign {note_on,note_number,note_velocity}=note_payload;
    // One elastic output slot separates queue selection from UART FIFO/CC
    // arbitration. A stalled payload stays in registers until accepted.
    wire output_ready=!note_valid || note_ready;
    wire pop=selected!=3 && output_ready && !cleaning && !(flush===1'b1);
    wire sp=pop && selected==0,rp=pop && selected==1,tp=pop && selected==2;
    wire si=score_valid && (sc<DEPTH || sp) && !cleaning && !(flush===1'b1);
    assign score_ready=sc<DEPTH && !cleaning && !(flush===1'b1);
    wire ri=remote_valid && (rc<DEPTH || rp) && !cleaning && !(flush===1'b1);
    wire ti=touch_valid && (tc<DEPTH || tp) && !cleaning && !(flush===1'b1);
    always @(posedge clk)begin
        if(rst_n && si)score_mem[sw]<={score_on,score_note,score_velocity};
        if(rst_n && ri)remote_mem[rw]<={remote_on,remote_note,remote_velocity};
        if(rst_n && ti)touch_mem[tw]<={touch_on,touch_note,touch_velocity};
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            sw<=0;sr<=0;rw<=0;rr<=0;tw<=0;tr<=0;sc<=0;rc<=0;tc<=0;next_source<=0;overflow<=0;
            note_valid<=0;note_payload<=0;
            held_notes<=0;cleaning<=0;clean_note<=0;
        end else begin
            // Track only Notes accepted by the MIDI transmitter. A session
            // change discards unsent requests and releases every accepted On.
            if(note_valid && note_ready)held_notes[note_number]<=note_on && note_velocity!=0;
            if(flush===1'b1)begin
                sw<=0;sr<=0;rw<=0;rr<=0;tw<=0;tr<=0;sc<=0;rc<=0;tc<=0;
                note_valid<=0;cleaning<=1;clean_note<=0;next_source<=0;
            end else if(cleaning)begin
                if(output_ready)begin
                    note_valid<=held_notes[clean_note];
                    note_payload<={1'b0,clean_note,7'd0};
                    if(clean_note==127)cleaning<=0;
                    else clean_note<=clean_note+1'b1;
                end
            end else begin
            if((score_valid && !si)||(remote_valid && !ri)||(touch_valid && !ti))overflow<=1;
            if(si)sw<=sw+1'b1;if(sp)sr<=sr+1'b1;
            if(ri)rw<=rw+1'b1;if(rp)rr<=rr+1'b1;
            if(ti)tw<=tw+1'b1;if(tp)tr<=tr+1'b1;
            sc<=sc+si-sp;rc<=rc+ri-rp;tc<=tc+ti-tp;
            if(pop)next_source<=selected==2 ? 0 : selected+1'b1;
            if(output_ready)begin
                note_valid<=selected!=3;
                if(selected!=3)note_payload<=record_data;
            end
            end
        end
    end
endmodule
