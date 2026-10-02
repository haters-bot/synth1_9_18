// Active-low push-button synchronizer and debounce filter.
// At 50 MHz, 2^19 clock cycles are approximately 10.49 ms.
module key_debounce(
    input  wire clk,
    input  wire rst_n,
    input  wire key_n_async,
    output wire key_pressed
);

    localparam integer COUNTER_WIDTH = 19;

    reg key_meta;
    reg key_sync;
    reg key_n_debounced;
    reg [COUNTER_WIDTH-1:0] stable_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1'b1;
            key_sync <= 1'b1;
        end else begin
            key_meta <= key_n_async;
            key_sync <= key_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_n_debounced <= 1'b1;
            stable_count    <= {COUNTER_WIDTH{1'b0}};
        end else if (key_sync == key_n_debounced) begin
            stable_count <= {COUNTER_WIDTH{1'b0}};
        end else if (&stable_count) begin
            key_n_debounced <= key_sync;
            stable_count    <= {COUNTER_WIDTH{1'b0}};
        end else begin
            stable_count <= stable_count + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
        end
    end

    assign key_pressed = ~key_n_debounced;

endmodule
