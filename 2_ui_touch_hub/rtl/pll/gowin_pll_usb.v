// ==============================================================================
// Module: gowin_pll_usb.v
// Description: Dedicated 60.0MHz PLL for USB Full-Speed HID Host Core
//              Input: 50MHz onboard oscillator (V22)
//              Output: 60.0MHz exact (5x oversampling for 12Mbps USB Full-Speed)
//              Target Device: Gowin GW5AST-138B
// Project: 2_ui_touch_hub (1280x720 60Hz Vector Synthesizer UI)
// ==============================================================================

`timescale 1ns / 1ps

module Gowin_PLL_USB (
    output wire lock,
    output wire clkout0,
    input  wire clkin
);

    wire clkfbout;
    wire gw_vcc = 1'b1;
    wire gw_gnd = 1'b0;

    PLL PLL_inst (
        .LOCK(lock),
        .CLKOUT0(clkout0),
        .CLKOUT1(),
        .CLKOUT2(),
        .CLKOUT3(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBOUT(clkfbout),
        .CLKIN(clkin),
        .CLKFB(gw_gnd),
        .RESET(gw_gnd),
        .PLLPWD(gw_gnd),
        .RESET_I(gw_gnd),
        .RESET_O(gw_gnd),
        .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .MDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .MDSEL_FRAC({gw_gnd,gw_gnd,gw_gnd}),
        .ODSEL0({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .ODSEL0_FRAC({gw_gnd,gw_gnd,gw_gnd}),
        .ODSEL1({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .ODSEL2({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .ODSEL3({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .ODSEL4({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .ODSEL5({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .ODSEL6({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .DT0({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .DT1({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .DT2({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .DT3({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .ICPSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .LPFRES({gw_gnd,gw_gnd,gw_gnd}),
        .LPFCAP({gw_gnd,gw_gnd}),
        .PSSEL({gw_gnd,gw_gnd,gw_gnd}),
        .PSDIR(gw_gnd),
        .PSPULSE(gw_gnd),
        .ENCLK0(gw_vcc),
        .ENCLK1(gw_gnd),
        .ENCLK2(gw_gnd),
        .ENCLK3(gw_gnd),
        .ENCLK4(gw_gnd),
        .ENCLK5(gw_gnd),
        .ENCLK6(gw_gnd),
        .SSCPOL(gw_gnd),
        .SSCON(gw_gnd),
        .SSCMDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .SSCMDSEL_FRAC({gw_gnd,gw_gnd,gw_gnd})
    );

    defparam PLL_inst.FCLKIN = "50";
    defparam PLL_inst.IDIV_SEL = 1;
    defparam PLL_inst.FBDIV_SEL = 1;
    // VCO = 50MHz * 24 = 1200MHz (valid range 600~1300MHz)
    // CLKOUT0 = 1200MHz / 20 = 60.0MHz
    defparam PLL_inst.MDIV_SEL = 24;
    defparam PLL_inst.ODIV0_SEL = 20;
    defparam PLL_inst.CLKOUT0_EN = "TRUE";
    defparam PLL_inst.CLKFB_SEL = "INTERNAL";

endmodule
