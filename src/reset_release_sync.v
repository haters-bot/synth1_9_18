// 50 MHz时钟域复位控制：外部复位异步拉低，PLL锁定信号先同步，
// 随后系统复位再经过两拍同步释放。
module reset_release_sync(
    input  wire clk,
    input  wire rst_n_async,
    input  wire release_enable_async,
    output wire rst_n_sync
);

    // 第一拍允许出现亚稳态，第二拍给出时钟域内稳定的锁定状态。
    reg [1:0] release_enable_pipe;
    reg [1:0] release_pipe;

    always @(posedge clk or negedge rst_n_async) begin
        if (!rst_n_async) begin
            release_enable_pipe <= 2'b00;
            release_pipe <= 2'b00;
        end else begin
            release_enable_pipe <= {release_enable_pipe[0], release_enable_async};

            // PLL未锁定时在时钟边沿同步保持复位；确认锁定后再释放两拍。
            if (!release_enable_pipe[1])
                release_pipe <= 2'b00;
            else
                release_pipe <= {release_pipe[0], 1'b1};
        end
    end

    assign rst_n_sync = release_pipe[1];

endmodule
