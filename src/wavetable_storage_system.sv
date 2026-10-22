// SD卡、DDR3和两组振荡器双帧缓存之间的完整存储控制层。
// SD卡根目录第0个文件在DDR校准完成后自动读取。
module wavetable_storage_system(
    input  wire        sys_clk,
    input  wire        rst_n,
    input  wire [3:0]  osc_a_table,
    input  wire [6:0]  osc_a_position,
    input  wire [3:0]  osc_b_table,
    input  wire [6:0]  osc_b_position,

    output wire        sd_clk,
    inout  wire        sd_cmd,
    input  wire        sd_dat0,

    output wire [14:0] ddr_addr,
    output wire [2:0]  ddr_bank,
    output wire        ddr_cs,
    output wire        ddr_ras,
    output wire        ddr_cas,
    output wire        ddr_we,
    output wire        ddr_ck,
    output wire        ddr_ck_n,
    output wire        ddr_cke,
    output wire        ddr_odt,
    output wire        ddr_reset_n,
    output wire [3:0]  ddr_dm,
    inout  wire [31:0] ddr_dq,
    inout  wire [3:0]  ddr_dqs,
    inout  wire [3:0]  ddr_dqs_n,

    output wire        cache_load_clk,
    output wire        cache_load_rst_n,
    output wire        cache_a_write_enable,
    output wire        cache_a_write_bank,
    output wire        cache_a_write_frame,
    output wire [7:0]  cache_a_write_address,
    output wire [15:0] cache_a_write_data,
    output wire        cache_a_commit_toggle,
    output wire        cache_a_commit_bank,
    output wire [7:0]  cache_a_commit_fraction,
    output wire        cache_b_write_enable,
    output wire        cache_b_write_bank,
    output wire        cache_b_write_frame,
    output wire [7:0]  cache_b_write_address,
    output wire [15:0] cache_b_write_data,
    output wire        cache_b_commit_toggle,
    output wire        cache_b_commit_bank,
    output wire [7:0]  cache_b_commit_fraction,

    output wire        ddr_init_done,
    output wire        wavetable_storage_ready,
    output wire        wavetable_storage_error,
    output wire [4:0]  wavetable_table_count,
    output wire        cache_a_ready,
    output wire        cache_b_ready
);

    wire user_clk;
    wire user_rst_n;
    wire pll_locked;
    wire init_done;
    assign cache_load_clk = user_clk;
    assign cache_load_rst_n = user_rst_n;
    assign ddr_init_done = init_done;

    wire ddr_req_valid;
    wire ddr_req_ready;
    wire ddr_req_write;
    wire [28:0] ddr_req_addr;
    wire [255:0] ddr_req_wdata;
    wire [31:0] ddr_req_wmask;
    wire ddr_rsp_valid;
    wire ddr_rsp_write;
    wire [255:0] ddr_rsp_rdata;
    wire ddr_rsp_error;

    ddr3_wavetable_wrapper u_ddr3_wrapper (
        .clk_ref(sys_clk), .rst_n_async(rst_n),
        .user_clk(user_clk), .user_rst_n(user_rst_n),
        .pll_locked(pll_locked), .init_done(init_done),
        .req_valid(ddr_req_valid), .req_ready(ddr_req_ready),
        .req_write(ddr_req_write), .req_addr(ddr_req_addr),
        .req_wdata(ddr_req_wdata), .req_wmask(ddr_req_wmask),
        .rsp_valid(ddr_rsp_valid), .rsp_write(ddr_rsp_write),
        .rsp_rdata(ddr_rsp_rdata), .rsp_error(ddr_rsp_error),
        .ddr_addr(ddr_addr), .ddr_bank(ddr_bank), .ddr_cs(ddr_cs),
        .ddr_ras(ddr_ras), .ddr_cas(ddr_cas), .ddr_we(ddr_we),
        .ddr_ck(ddr_ck), .ddr_ck_n(ddr_ck_n), .ddr_cke(ddr_cke),
        .ddr_odt(ddr_odt), .ddr_reset_n(ddr_reset_n), .ddr_dm(ddr_dm),
        .ddr_dq(ddr_dq), .ddr_dqs(ddr_dqs), .ddr_dqs_n(ddr_dqs_n)
    );

    reg init_done_sync_1;
    reg init_done_sync_2;
    wire sd_reader_rst_n;
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            init_done_sync_1 <= 1'b0;
            init_done_sync_2 <= 1'b0;
        end else begin
            init_done_sync_1 <= init_done;
            init_done_sync_2 <= init_done_sync_1;
        end
    end
    assign sd_reader_rst_n = rst_n && init_done_sync_2;

    wire [2:0] sd_done;
    wire [1:0] sd_card_type;
    wire [1:0] sd_filesystem_type;
    wire sd_file_found;
    wire [7:0] sd_list_name [0:51];
    wire [7:0] sd_list_name_length;
    wire [11:0] sd_list_file_number;
    wire sd_list_enable;
    wire sd_byte_valid;
    wire [7:0] sd_byte;

    sd_file_list_reader #(
        .CLK_DIV(3'd2),
        .SIMULATE(0)
    ) u_sd_file_reader (
        .rstn(sd_reader_rst_n), .clk(sys_clk),
        .sdclk(sd_clk), .sdcmd(sd_cmd), .sddat0(sd_dat0),
        .op(1'b1), .read_file(12'd0), .done(sd_done),
        .card_stat(), .card_type(sd_card_type),
        .filesystem_type(sd_filesystem_type), .file_found(sd_file_found),
        .list_name(sd_list_name), .list_namelen(sd_list_name_length),
        .list_file_num(sd_list_file_number), .list_en(sd_list_enable),
        .outen(sd_byte_valid), .outbyte(sd_byte),
        .debug_read_done(), .debug_read_sector_no(),
        .debug_filesystem_state()
    );

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
    wire loader_error;
    wire [16:0] loader_words_written;

    sd_wavetable_loader u_sd_wavetable_loader (
        .sd_clk(sys_clk), .sd_rst_n(sd_reader_rst_n),
        .file_byte_valid(sd_byte_valid), .file_byte(sd_byte),
        .file_done(|sd_done), .ddr_clk(user_clk), .ddr_rst_n(user_rst_n),
        .req_valid(loader_req_valid), .req_ready(loader_req_ready),
        .req_write(loader_req_write), .req_addr(loader_req_addr),
        .req_wdata(loader_req_wdata), .req_wmask(loader_req_wmask),
        .rsp_valid(loader_rsp_valid), .rsp_write(loader_rsp_write),
        .rsp_error(loader_rsp_error),
        .storage_ready(wavetable_storage_ready), .load_error(loader_error),
        .table_count(wavetable_table_count), .words_written(loader_words_written)
    );

    reg [3:0] osc_a_table_sync_1, osc_a_table_sync_2;
    reg [6:0] osc_a_position_sync_1, osc_a_position_sync_2;
    reg [3:0] osc_b_table_sync_1, osc_b_table_sync_2;
    reg [6:0] osc_b_position_sync_1, osc_b_position_sync_2;
    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n) begin
            osc_a_table_sync_1 <= 4'd0; osc_a_table_sync_2 <= 4'd0;
            osc_a_position_sync_1 <= 7'd0; osc_a_position_sync_2 <= 7'd0;
            osc_b_table_sync_1 <= 4'd0; osc_b_table_sync_2 <= 4'd0;
            osc_b_position_sync_1 <= 7'd0; osc_b_position_sync_2 <= 7'd0;
        end else begin
            osc_a_table_sync_1 <= osc_a_table;
            osc_a_table_sync_2 <= osc_a_table_sync_1;
            osc_a_position_sync_1 <= osc_a_position;
            osc_a_position_sync_2 <= osc_a_position_sync_1;
            osc_b_table_sync_1 <= osc_b_table;
            osc_b_table_sync_2 <= osc_b_table_sync_1;
            osc_b_position_sync_1 <= osc_b_position;
            osc_b_position_sync_2 <= osc_b_position_sync_1;
        end
    end

    wire cache_a_req_valid, cache_a_req_ready, cache_a_req_write;
    wire [28:0] cache_a_req_addr;
    wire [255:0] cache_a_req_wdata;
    wire [31:0] cache_a_req_wmask;
    wire cache_a_rsp_valid, cache_a_rsp_write, cache_a_rsp_error;
    wire [255:0] cache_a_rsp_rdata;
    wire cache_a_error;

    wire cache_b_req_valid, cache_b_req_ready, cache_b_req_write;
    wire [28:0] cache_b_req_addr;
    wire [255:0] cache_b_req_wdata;
    wire [31:0] cache_b_req_wmask;
    wire cache_b_rsp_valid, cache_b_rsp_write, cache_b_rsp_error;
    wire [255:0] cache_b_rsp_rdata;
    wire cache_b_error;

    wavetable_cache_loader u_cache_a_loader (
        .clk(user_clk), .rst_n(user_rst_n),
        .storage_ready(wavetable_storage_ready),
        .table_count(wavetable_table_count),
        .desired_table(osc_a_table_sync_2),
        .desired_position(osc_a_position_sync_2),
        .req_valid(cache_a_req_valid), .req_ready(cache_a_req_ready),
        .req_write(cache_a_req_write), .req_addr(cache_a_req_addr),
        .req_wdata(cache_a_req_wdata), .req_wmask(cache_a_req_wmask),
        .rsp_valid(cache_a_rsp_valid), .rsp_write(cache_a_rsp_write),
        .rsp_rdata(cache_a_rsp_rdata), .rsp_error(cache_a_rsp_error),
        .cache_write_enable(cache_a_write_enable),
        .cache_write_bank(cache_a_write_bank),
        .cache_write_frame(cache_a_write_frame),
        .cache_write_address(cache_a_write_address),
        .cache_write_data(cache_a_write_data),
        .cache_commit_toggle(cache_a_commit_toggle),
        .cache_commit_bank(cache_a_commit_bank),
        .cache_commit_fraction(cache_a_commit_fraction),
        .cache_ready(cache_a_ready), .cache_load_error(cache_a_error)
    );

    wavetable_cache_loader u_cache_b_loader (
        .clk(user_clk), .rst_n(user_rst_n),
        .storage_ready(wavetable_storage_ready),
        .table_count(wavetable_table_count),
        .desired_table(osc_b_table_sync_2),
        .desired_position(osc_b_position_sync_2),
        .req_valid(cache_b_req_valid), .req_ready(cache_b_req_ready),
        .req_write(cache_b_req_write), .req_addr(cache_b_req_addr),
        .req_wdata(cache_b_req_wdata), .req_wmask(cache_b_req_wmask),
        .rsp_valid(cache_b_rsp_valid), .rsp_write(cache_b_rsp_write),
        .rsp_rdata(cache_b_rsp_rdata), .rsp_error(cache_b_rsp_error),
        .cache_write_enable(cache_b_write_enable),
        .cache_write_bank(cache_b_write_bank),
        .cache_write_frame(cache_b_write_frame),
        .cache_write_address(cache_b_write_address),
        .cache_write_data(cache_b_write_data),
        .cache_commit_toggle(cache_b_commit_toggle),
        .cache_commit_bank(cache_b_commit_bank),
        .cache_commit_fraction(cache_b_commit_fraction),
        .cache_ready(cache_b_ready), .cache_load_error(cache_b_error)
    );

    ddr3_transaction_arbiter u_ddr_arbiter (
        .clk(user_clk), .rst_n(user_rst_n),
        .m0_req_valid(cache_a_req_valid), .m0_req_ready(cache_a_req_ready),
        .m0_req_write(cache_a_req_write), .m0_req_addr(cache_a_req_addr),
        .m0_req_wdata(cache_a_req_wdata), .m0_req_wmask(cache_a_req_wmask),
        .m0_rsp_valid(cache_a_rsp_valid), .m0_rsp_write(cache_a_rsp_write),
        .m0_rsp_rdata(cache_a_rsp_rdata), .m0_rsp_error(cache_a_rsp_error),
        .m1_req_valid(cache_b_req_valid), .m1_req_ready(cache_b_req_ready),
        .m1_req_write(cache_b_req_write), .m1_req_addr(cache_b_req_addr),
        .m1_req_wdata(cache_b_req_wdata), .m1_req_wmask(cache_b_req_wmask),
        .m1_rsp_valid(cache_b_rsp_valid), .m1_rsp_write(cache_b_rsp_write),
        .m1_rsp_rdata(cache_b_rsp_rdata), .m1_rsp_error(cache_b_rsp_error),
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

    assign wavetable_storage_error = loader_error || cache_a_error || cache_b_error;

endmodule
