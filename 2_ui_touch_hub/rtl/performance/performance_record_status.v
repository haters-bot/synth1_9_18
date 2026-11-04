// Pixel-domain recorder status. A command request never means "recording".
// Status codes: ready, unavailable, recording, flushing, saved, full,
// source fault, storage fault, command rejected.
module performance_record_status(
    input wire clk,rst_n,
    input wire start_accepted,recording,busy,done,full,
    input wire backend_available,link_up,
    input wire capture_error,storage_error,protocol_error,command_error,
    output reg [3:0] status
);
    reg saved;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)saved<=0;
        else if(start_accepted || !backend_available)saved<=0;
        else if(done && !capture_error && !storage_error && !protocol_error)saved<=1;
    end
    always @(*)begin
        if(capture_error)status=4'd6;
        else if(storage_error)status=4'd7;
        else if(protocol_error)status=4'd7;
        else if(command_error)status=4'd8;
        else if(recording)status=4'd2;
        else if(busy)status=4'd3;
        else if(full && saved)status=4'd5;
        else if(saved && backend_available)status=4'd4;
        else if(!backend_available || !link_up)status=4'd1;
        else status=4'd0;
    end
endmodule
