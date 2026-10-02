// Asynchronous assertion and synchronous release for the 50 MHz domain.
module reset_release_sync(
    input  wire clk,
    input  wire rst_n_async,
    output wire rst_n_sync
);

    reg [1:0] release_pipe;

    always @(posedge clk or negedge rst_n_async) begin
        if (!rst_n_async)
            release_pipe <= 2'b00;
        else
            release_pipe <= {release_pipe[0], 1'b1};
    end

    assign rst_n_sync = release_pipe[1];

endmodule
