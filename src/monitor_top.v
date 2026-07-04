// "Monitor" core that is loaded as the default core on power-up.
// nand2mario, 2025.2

`ifndef VERILATOR
`ifndef MEGA
`ifndef CONSOLE
`ifndef PRIMER
`ifndef NANO
`error "config.v must be read before monitor_top.v"
`endif
`endif
`endif
`endif
`endif

import configPackage::*;

module monitor_top (
    input        sys_clk,
    input        s0,

    // UART
    input        UART_RXD,
    output       UART_TXD,

    // HDMI TX
    output       tmds_clk_p,    
    output       tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n,
    
    // HDMI cable detect (1 = plugged, 0 = unplugged)
    input        hdmi_hpd,
    
    // RGB screen output
    output [7:0] r_out,
    output [7:0] g_out,
    output [7:0] b_out,
    output       sc_clk,
    output       sc_hs,
    output       sc_vs,
    output       sc_de,

    // USB1 and USB2
`ifdef USB1
    inout usb1_dp,
    inout usb1_dn,
`endif
`ifdef USB2
    inout usb2_dp,
    inout usb2_dn,
`endif

`ifdef CONTROLLER_SNES
    // snes controllers
    output       joy1_strb,
    output       joy1_clk,
    input        joy1_data,
    output       joy2_strb,
    output       joy2_clk,
    input        joy2_data,
`endif

`ifdef CONTROLLER_DS2
    // dualshock controllers
    output       ds_clk,
    input        ds_miso,
    output       ds_mosi,
    output       ds_cs,
    output       ds_clk2,
    input        ds_miso2,
    output       ds_mosi2,
    output       ds_cs2,
`endif

    // LED
    output [7:0] led
);

// Clock signals
wire clk;                       // main clock 50Mhz
wire clk27;                     // 27Mhz for HDMI
wire hclk5, hclk;               // 720p pixel clock at 74.25Mhz, and 5x high-speed
wire clk33;                     // 33Mhz pixel clock for RGB screen

reg resetn = 0;                 // reset is cleared after 4 cycles
wire pll_33_lock;
wire screen_resetn = resetn & pll_33_lock; // Native LCD safeguard

// --- Clock Generation ---
`ifdef NANO
// GW2A Nano20K
assign clk27 = sys_clk;       
assign clk = sys_clk;
localparam FREQ = 27_000_000;

gowin_pll_hdmi pll_hdmi (.clkin(clk27), .clkout(hclk5));
CLKDIV #(.DIV_MODE(5)) div5 (
    .CLKOUT(hclk),
    .HCLKIN(hclk5),
    .RESETN(1'b1),
    .CALIB(1'b0)
);

// FIX: missing 33MHz PLL instantiation for the Nano
pll_33 pll_33_inst (
    .clkin(clk27),
    .clkout(clk33), // Use .clkout or .clkout0 depending on your generated file
    .lock(pll_33_lock)
);

`else
// GW5 devices
assign clk = sys_clk;
localparam FREQ = 50_000_000;
pll_27 pll_27 (
    .clkin(sys_clk),
    .clkout0(clk27)
);
pll_74 pll_74 (
    .clkin(clk27),              // 27 Mhz input
    .clkout0(hclk), .clkout1(hclk5)
);
`ifdef CONSOLE60K
pll_33 pll_33_inst (
    .clkin(sys_clk),
    .mdclk(sys_clk),
    .clkout0(clk33),
    .lock(pll_33_lock)
);
`else
pll_33 pll_33_inst (
    .clkin(sys_clk),
    .init_clk(sys_clk),
    .clkout0(clk33),
    .lock(pll_33_lock)
);
`endif
`endif

reg [15:0] resetcnt = 16'hffff;
always @(posedge clk) begin
    resetcnt <= resetcnt == 0 ? 0 : resetcnt - 1;
    if (resetcnt == 0)
        resetn <= 1'b1;
end

// --- Controllers & USB (Unchanged) ---
wor [11:0] joy1_btns, joy2_btns;

`ifdef CONTROLLER_SNES
controller_snes #(.FREQ(FREQ)) joy1_snes (.clk(clk), .resetn(resetn), .buttons(joy1_btns), .joy_strb(joy1_strb), .joy_clk(joy1_clk), .joy_data(joy1_data));
controller_snes #(.FREQ(FREQ)) joy2_snes (.clk(clk), .resetn(resetn), .buttons(joy2_btns), .joy_strb(joy2_strb), .joy_clk(joy2_clk), .joy_data(joy2_data));
`endif

`ifdef CONTROLLER_DS2
controller_ds2 #(.FREQ(FREQ)) joy1_ds2 (.clk(clk), .snes_buttons(joy1_btns), .ds_clk(ds_clk), .ds_miso(ds_miso), .ds_mosi(ds_mosi), .ds_cs(ds_cs));
controller_ds2 #(.FREQ(FREQ)) joy2_ds2 (.clk(clk), .snes_buttons(joy2_btns), .ds_clk(ds_clk2), .ds_miso(ds_miso2), .ds_mosi(ds_mosi2), .ds_cs(ds_cs2));
`endif

wire [11:0] joy_usb1, joy_usb2;

`ifdef USB1
wire clk12;
wire pll_lock_12;
wire usb_conerr;
wire [1:0] usb_type;
pll_12 pll12(.clkin(sys_clk), .clkout0(clk12), .lock(pll_lock_12));
usb_hid_host usb_hid_host (.usbclk(clk12), .usbrst_n(pll_lock_12), .usb_dm(usb1_dn), .usb_dp(usb1_dp), .game_snes(joy_usb1), .typ(usb_type), .conerr(usb_conerr));
assign led = ~{joy_usb1[4:0], usb_type, usb_conerr};
`else
assign joy_usb1 = 12'b0;
`endif

`ifdef USB2
usb_hid_host usb_hid_host2 (.usbclk(clk12), .usbrst_n(pll_lock_12), .usb_dm(usb2_dn), .usb_dp(usb2_dp), .game_snes(joy_usb2));
`else
assign joy_usb2 = 12'b0;
`endif


// =========================================================================
// VIDEO ARCHITECTURE (Automatic HDMI <-> LCD switch)
// =========================================================================

wire overlay;
wire [14:0] overlay_color;
wire [7:0] overlay_x_hdmi, overlay_y_hdmi;
wire [7:0] overlay_x_screen, overlay_y_screen;

// 0 = cable plugged (HDMI active) | 1 = cable unplugged (LCD active)
wire USE_SCREEN = !hdmi_hpd;

// Multiplexing read addresses for the OS
wire [7:0] overlay_x = USE_SCREEN ? overlay_x_screen : overlay_x_hdmi;
wire [7:0] overlay_y = USE_SCREEN ? overlay_y_screen : overlay_y_hdmi;

// Clock MUX for the OS generator
wire active_pixel_clk = USE_SCREEN ? clk33 : hclk;


// --- 1. HDMI Engine (74.25 MHz) ---
monitor2hdmi s2h(
    .clk(clk), 
    .resetn(1'b1), 
    .overlay(USE_SCREEN ? 1'b0 : overlay),              // Off when LCD is active
    .overlay_x(overlay_x_hdmi), 
    .overlay_y(overlay_y_hdmi),
    .overlay_color(USE_SCREEN ? 15'b0 : overlay_color), // Black when LCD is active
    
    .clk_pixel(hclk), .clk_5x_pixel(hclk5),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);


// --- 2. LCD Engine (33.333 MHz) ---
monitor2screen s2s (
    .resetn(screen_resetn), // Protected by PLL lock
    .overlay(USE_SCREEN ? overlay : 1'b0),              // Off when HDMI is active
    .overlay_x(overlay_x_screen), 
    .overlay_y(overlay_y_screen),
    .overlay_color(USE_SCREEN ? overlay_color : 15'b0), // Black when HDMI is active
    
    .clk_pixel(clk33),
    .r_out(r_out), .g_out(g_out), .b_out(b_out),
    .sc_clk(sc_clk), .sc_hs(sc_hs), .sc_vs(sc_vs), .sc_de(sc_de)
);


// --- 3. Menu Generator ---
iosys_bl616 #(.CORE_ID(0), .FREQ(FREQ), .COLOR_LOGO(15'b11011_10010_00011)) sys (
    .clk(clk), 
    .hclk(active_pixel_clk),
    .resetn(resetn),
    
    .overlay(overlay), 
    .overlay_x(overlay_x), 
    .overlay_y(overlay_y), 
    .overlay_color(overlay_color),
    
    .joy1(joy1_btns | joy_usb1), .joy2(joy2_btns | joy_usb2),
    .uart_rx(UART_RXD), .uart_tx(UART_TXD)
);

endmodule