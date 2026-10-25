`timescale 1ns/1ps

module tb_sd_ddr_wavetable_path;
    reg sd_clk = 1'b0;
    reg ddr_clk = 1'b0;
    reg audio_clk = 1'b0;
    reg sd_rst_n = 1'b0;
    reg ddr_rst_n = 1'b0;
    reg audio_rst_n = 1'b0;

    reg file_byte_valid;
    reg [7:0] file_byte;
    reg file_done;

    wire loader_req_valid;
    wire loader_req_ready;
    wire loader_req_write;
    wire [28:0] loader_req_addr;
    wire [255:0] loader_req_wdata;
    wire [31:0] loader_req_wmask;
    wire loader_rsp_valid;
    wire loader_rsp_write;
    wire [255:0] loader_rsp_rdata;
    wire loader_rsp_error;
    wire storage_ready;
    wire storage_error;
    wire [4:0] table_count;
    wire [16:0] words_written;

    reg [3:0] desired_table;
    reg [6:0] desired_position;
    wire cache_req_valid;
    wire cache_req_ready;
    wire cache_req_write;
    wire [28:0] cache_req_addr;
    wire [255:0] cache_req_wdata;
    wire [31:0] cache_req_wmask;
    wire cache_rsp_valid;
    wire cache_rsp_write;
    wire [255:0] cache_rsp_rdata;
    wire cache_rsp_error;
    wire cache_write_enable;
    wire cache_write_bank;
    wire cache_write_frame;
    wire [7:0] cache_write_address;
    wire [15:0] cache_write_data;
    wire cache_commit_toggle;
    wire cache_commit_bank;
    wire [7:0] cache_commit_fraction;
    wire cache_loader_ready;
    wire cache_load_error;

    reg sample_req_valid;
    reg [7:0] sample_phase;
    wire sample_valid;
    wire signed [15:0] sample_data;
    wire audio_cache_ready;

    wire ddr_req_valid;
    reg ddr_req_ready;
    wire ddr_req_write;
    wire [28:0] ddr_req_addr;
    wire [255:0] ddr_req_wdata;
    wire [31:0] ddr_req_wmask;
    reg ddr_rsp_valid;
    reg ddr_rsp_write;
    reg [255:0] ddr_rsp_rdata;
    reg ddr_rsp_error;

    reg pending_rsp;
    reg pending_write;
    reg [12:0] pending_word_index;
    reg [255:0] ddr_memory [0:8191];
    integer errors;
    integer table_index;
    integer frame_index;
    integer phase_index;
    integer wait_cycles;
    reg [15:0] generated_sample;
    reg previous_commit_toggle;

    always #10 sd_clk = ~sd_clk;
    always #5 ddr_clk = ~ddr_clk;
    always #10 audio_clk = ~audio_clk;

    sd_wavetable_loader u_loader (
        .sd_clk(sd_clk), .sd_rst_n(sd_rst_n),
        .file_byte_valid(file_byte_valid), .file_byte(file_byte),
        .file_done(file_done), .ddr_clk(ddr_clk), .ddr_rst_n(ddr_rst_n),
        .req_valid(loader_req_valid), .req_ready(loader_req_ready),
        .req_write(loader_req_write), .req_addr(loader_req_addr),
        .req_wdata(loader_req_wdata), .req_wmask(loader_req_wmask),
        .rsp_valid(loader_rsp_valid), .rsp_write(loader_rsp_write),
        .rsp_error(loader_rsp_error), .storage_ready(storage_ready),
        .load_error(storage_error), .table_count(table_count),
        .words_written(words_written)
    );

    wavetable_cache_loader u_cache_loader (
        .clk(ddr_clk), .rst_n(ddr_rst_n), .storage_ready(storage_ready),
        .table_count(table_count), .desired_table(desired_table),
        .desired_position(desired_position), .req_valid(cache_req_valid),
        .req_ready(cache_req_ready), .req_write(cache_req_write),
        .req_addr(cache_req_addr), .req_wdata(cache_req_wdata),
        .req_wmask(cache_req_wmask), .rsp_valid(cache_rsp_valid),
        .rsp_write(cache_rsp_write), .rsp_rdata(cache_rsp_rdata),
        .rsp_error(cache_rsp_error), .cache_write_enable(cache_write_enable),
        .cache_write_bank(cache_write_bank),
        .cache_write_frame(cache_write_frame),
        .cache_write_address(cache_write_address),
        .cache_write_data(cache_write_data),
        .cache_commit_toggle(cache_commit_toggle),
        .cache_commit_bank(cache_commit_bank),
        .cache_commit_fraction(cache_commit_fraction),
        .cache_ready(cache_loader_ready), .cache_load_error(cache_load_error)
    );

    wavetable_frame_cache u_frame_cache (
        .audio_clk(audio_clk), .audio_rst_n(audio_rst_n),
        .req_valid(sample_req_valid), .phase_address(sample_phase),
        .sample_valid(sample_valid), .sample_data(sample_data),
        .load_clk(ddr_clk), .load_rst_n(ddr_rst_n),
        .load_write_enable(cache_write_enable),
        .load_write_bank(cache_write_bank),
        .load_write_frame(cache_write_frame),
        .load_write_address(cache_write_address),
        .load_write_data(cache_write_data),
        .load_commit_toggle(cache_commit_toggle),
        .load_commit_bank(cache_commit_bank),
        .load_commit_fraction(cache_commit_fraction), .ready(audio_cache_ready)
    );

    ddr3_transaction_arbiter u_arbiter (
        .clk(ddr_clk), .rst_n(ddr_rst_n),
        .m0_req_valid(cache_req_valid), .m0_req_ready(cache_req_ready),
        .m0_req_write(cache_req_write), .m0_req_addr(cache_req_addr),
        .m0_req_wdata(cache_req_wdata), .m0_req_wmask(cache_req_wmask),
        .m0_rsp_valid(cache_rsp_valid), .m0_rsp_write(cache_rsp_write),
        .m0_rsp_rdata(cache_rsp_rdata), .m0_rsp_error(cache_rsp_error),
        .m1_req_valid(1'b0), .m1_req_ready(), .m1_req_write(1'b0),
        .m1_req_addr(29'd0), .m1_req_wdata(256'd0), .m1_req_wmask(32'd0),
        .m1_rsp_valid(), .m1_rsp_write(), .m1_rsp_rdata(), .m1_rsp_error(),
        .m2_req_valid(loader_req_valid), .m2_req_ready(loader_req_ready),
        .m2_req_write(loader_req_write), .m2_req_addr(loader_req_addr),
        .m2_req_wdata(loader_req_wdata), .m2_req_wmask(loader_req_wmask),
        .m2_rsp_valid(loader_rsp_valid), .m2_rsp_write(loader_rsp_write),
        .m2_rsp_rdata(loader_rsp_rdata), .m2_rsp_error(loader_rsp_error),
        .ddr_req_valid(ddr_req_valid), .ddr_req_ready(ddr_req_ready),
        .ddr_req_write(ddr_req_write), .ddr_req_addr(ddr_req_addr),
        .ddr_req_wdata(ddr_req_wdata), .ddr_req_wmask(ddr_req_wmask),
        .ddr_rsp_valid(ddr_rsp_valid), .ddr_rsp_write(ddr_rsp_write),
        .ddr_rsp_rdata(ddr_rsp_rdata), .ddr_rsp_error(ddr_rsp_error)
    );

    // 单拍延迟的DDR事务模型。
    always @(posedge ddr_clk or negedge ddr_rst_n) begin
        if (!ddr_rst_n) begin
            ddr_req_ready <= 1'b1;
            ddr_rsp_valid <= 1'b0;
            ddr_rsp_write <= 1'b0;
            ddr_rsp_rdata <= 256'd0;
            ddr_rsp_error <= 1'b0;
            pending_rsp <= 1'b0;
            pending_write <= 1'b0;
            pending_word_index <= 13'd0;
        end else begin
            ddr_rsp_valid <= pending_rsp;
            ddr_rsp_write <= pending_write;
            ddr_rsp_error <= 1'b0;
            if (pending_rsp && !pending_write)
                ddr_rsp_rdata <= ddr_memory[pending_word_index];
            pending_rsp <= 1'b0;

            if (ddr_req_valid && ddr_req_ready) begin
                pending_rsp <= 1'b1;
                pending_write <= ddr_req_write;
                pending_word_index <= ddr_req_addr[15:3];
                if (ddr_req_write)
                    ddr_memory[ddr_req_addr[15:3]] <= ddr_req_wdata;
            end
        end
    end

    task send_byte;
        input [7:0] value;
        begin
            @(negedge sd_clk);
            file_byte <= value;
            file_byte_valid <= 1'b1;
            @(negedge sd_clk);
            file_byte_valid <= 1'b0;
        end
    endtask

    task request_and_check;
        input [7:0] phase_value;
        input signed [15:0] expected;
        begin
            @(negedge audio_clk);
            sample_phase <= phase_value;
            sample_req_valid <= 1'b1;
            @(negedge audio_clk);
            sample_req_valid <= 1'b0;
            wait(sample_valid);
            #1;
            if (sample_data !== expected) begin
                $display("ERROR: phase=%0d expected=%0d actual=%0d",
                         phase_value, expected, sample_data);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        file_byte_valid = 1'b0;
        file_byte = 8'd0;
        file_done = 1'b0;
        desired_table = 4'd0;
        desired_position = 7'd0;
        sample_req_valid = 1'b0;
        sample_phase = 8'd0;
        errors = 0;

        #100;
        sd_rst_n = 1'b1;
        ddr_rst_n = 1'b1;
        audio_rst_n = 1'b1;

        // 32字节WTB1头，声明包含两张波表。
        send_byte(8'h57); send_byte(8'h54); send_byte(8'h42); send_byte(8'h31);
        send_byte(8'd1);  send_byte(8'd2);
        send_byte(8'h00); send_byte(8'h01);
        send_byte(8'h00); send_byte(8'h01);
        send_byte(8'd16); send_byte(8'd1);
        repeat (20) send_byte(8'd0);

        // 每张表均为256帧、每帧256个16位小端样本。
        // 两张表使用不同直流偏移，便于确认表编号确实改变了DDR读取地址。
        for (table_index = 0; table_index < 2; table_index = table_index + 1) begin
            for (frame_index = 0; frame_index < 256; frame_index = frame_index + 1) begin
                for (phase_index = 0; phase_index < 256; phase_index = phase_index + 1) begin
                    generated_sample = frame_index * 256 + phase_index
                                     + table_index * 16'h4000;
                    send_byte(generated_sample[7:0]);
                    send_byte(generated_sample[15:8]);
                end
            end
        end
        @(negedge sd_clk);
        file_done <= 1'b1;
        @(negedge sd_clk);
        file_done <= 1'b0;

        wait_cycles = 0;
        while (!storage_ready && !storage_error && wait_cycles < 200000) begin
            @(posedge ddr_clk);
            wait_cycles = wait_cycles + 1;
        end
        if (!storage_ready || storage_error || (table_count != 5'd2)
                || (words_written != 17'd8192)) begin
            $display("ERROR: storage load failed ready=%b error=%b words=%0d",
                     storage_ready, storage_error, words_written);
            errors = errors + 1;
        end

        wait(cache_loader_ready);
        wait(audio_cache_ready);
        repeat (4) @(posedge audio_clk);
        request_and_check(8'd5, 16'sd5);
        request_and_check(8'd200, 16'sd200);

        // 位置64映射到frame128 + 0.5*(frame129-frame128)。
        desired_position = 7'd64;
        wait(cache_commit_fraction == 8'd128 && cache_loader_ready);
        repeat (8) @(posedge audio_clk);
        request_and_check(8'd5, -16'sd32635);

        // 切换到表1并回到第0帧；必须出现一次新的缓存提交。
        previous_commit_toggle = cache_commit_toggle;
        desired_table = 4'd1;
        desired_position = 7'd0;
        wait(cache_commit_toggle != previous_commit_toggle);
        wait(cache_loader_ready);
        repeat (8) @(posedge audio_clk);
        request_and_check(8'd5, 16'sh4005);
        request_and_check(8'd200, 16'sh40C8);

        if (cache_load_error) begin
            $display("ERROR: cache loader reported an error");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: SD byte stream -> DDR -> dual-frame wavetable cache");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
