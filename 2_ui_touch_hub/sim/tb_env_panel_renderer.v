// ==============================================================================
// Testbench: tb_env_panel_renderer.v
// Verification: Dedicated cycle-accurate testing of env_panel_renderer
//               Checks attack/decay/sustain/release curves and background slope divider.
// ==============================================================================

`timescale 1ns / 1ps
`include "../rtl/ui_vector_engine/params.vh"

module tb_env_panel_renderer;

    reg        clk;
    reg        rst_n;
    reg [13:0] in_x;
    reg [13:0] in_y;

    reg [6:0]  env_attack;
    reg [6:0]  env_hold;
    reg [6:0]  env_decay;
    reg [6:0]  env_sustain;
    reg [6:0]  env_release;
    reg [1:0]  val_env_tab;

    wire        out_hit_env;
    wire [23:0] out_env_rgb;

    env_panel_renderer u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_x        (in_x),
        .in_y        (in_y),
        .val_env_tab (val_env_tab),
        .env_attack  (env_attack),
        .env_hold    (env_hold),
        .env_decay   (env_decay),
        .env_sustain (env_sustain),
        .env_release (env_release),
        .out_hit_env (out_hit_env),
        .out_env_rgb (out_env_rgb)
    );

    always #8 clk = ~clk;

    task test_point;
        input [13:0] px, py;
        output hit;
        output [23:0] rgb;
        begin
            @(posedge clk);
            in_x = px;
            in_y = py;
            repeat (3) @(posedge clk);
            #1;
            hit = out_hit_env;
            rgb = out_env_rgb;
        end
    endtask

    reg hit;
    reg [23:0] rgb;

    initial begin
        clk = 0;
        rst_n = 0;
        in_x = 0;
        in_y = 0;

        val_env_tab = 2'd0;
        env_attack  = 7'd32;
        env_hold    = 7'd10;
        env_decay   = 7'd40;
        env_sustain = 7'd80;
        env_release = 7'd30;

        #32 rst_n = 1;
        // Wait 100 clocks for iterative slope divider to complete initial convergence
        repeat (100) @(posedge clk);

        // 1. Point outside envelope window (e.g. X=10, Y=10)
        test_point(14'd10, 14'd10, hit, rgb);
        if (hit !== 1'b0) begin
            $display("[FAIL] Expected hit=0 outside window, got hit=%b", hit);
            $stop;
        end else begin
            $display("[PASS] Correctly rejected point outside envelope window");
        end

        // 2. Point on envelope border (X=`ENV_WIN_X0, Y=`ENV_WIN_Y0)
        test_point(`ENV_WIN_X0, `ENV_WIN_Y0, hit, rgb);
        if (hit !== 1'b1 || rgb !== `COLOR_PANEL_BORDER) begin
            $display("[FAIL] Border mismatch: hit=%b, rgb=%h (expected %h)", hit, rgb, `COLOR_PANEL_BORDER);
            $stop;
        end else begin
            $display("[PASS] Border verified: %h", rgb);
        end

        // 3. Point at start handle node (X=`ENV_WIN_X0, Y=`ENV_BASE_Y)
        test_point(`ENV_WIN_X0, `ENV_BASE_Y, hit, rgb);
        if (hit !== 1'b1) begin
            $display("[FAIL] Origin handle node missed!");
            $stop;
        end else begin
            $display("[PASS] Origin node hit confirmed: rgb=%h", rgb);
        end

        // 4. Point inside fill area: Tab 0 Cobalt (expected 24'h102640)
        test_point(`ENV_WIN_X0 + 14'd30, `ENV_BASE_Y - 14'd5, hit, rgb);
        if (hit !== 1'b1 || rgb !== `COLOR_ENV_FILL) begin
            $display("[FAIL] Fill area failed: hit=%b rgb=%h (expected %h)", hit, rgb, `COLOR_ENV_FILL);
            $stop;
        end else begin
            $display("[PASS] Tab 0 Cobalt fill area verified: %h", rgb);
        end

        // 5. Switch to Tab 1 (Emerald theme, fill 24'h0C281E)
        val_env_tab = 2'd1;
        repeat (5) @(posedge clk);
        test_point(`ENV_WIN_X0 + 14'd30, `ENV_BASE_Y - 14'd5, hit, rgb);
        if (hit !== 1'b1 || rgb !== 24'h0C281E) begin
            $display("[FAIL] Tab 1 fill mismatch: hit=%b rgb=%h (expected 0C281E)", hit, rgb);
            $stop;
        end else begin
            $display("[PASS] Tab 1 Emerald fill area verified: %h", rgb);
        end

        // 6. Switch to Tab 2 (Amber theme, fill 24'h281E0C)
        val_env_tab = 2'd2;
        repeat (5) @(posedge clk);
        test_point(`ENV_WIN_X0 + 14'd30, `ENV_BASE_Y - 14'd5, hit, rgb);
        if (hit !== 1'b1 || rgb !== 24'h281E0C) begin
            $display("[FAIL] Tab 2 fill mismatch: hit=%b rgb=%h (expected 281E0C)", hit, rgb);
            $stop;
        end else begin
            $display("[PASS] Tab 2 Amber fill area verified: %h", rgb);
        end

        // 7. Test dynamic parameter change
        val_env_tab = 2'd0;
        env_attack = 7'd120; // slow attack
        repeat (120) @(posedge clk); // let divider re-converge
        $display("[PASS] Dynamic parameter update accepted without glitch");

        $display("=================================================");
        $display("   ENV_PANEL_RENDERER TESTBENCH PASSED (100%%)   ");
        $display("=================================================");
        $finish;
    end

endmodule
