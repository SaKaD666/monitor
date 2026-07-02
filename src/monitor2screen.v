`timescale 1ns / 1ps

module monitor2screen #(
    parameter LATENCY = 2 
)(
    input  wire        resetn,

    // Source interface (256x224, BGR5)
    input  wire        overlay,
    output reg  [7:0]  overlay_x, // 8 bits enough for 256
    output reg  [7:0]  overlay_y, // 8 bits enough for 224
    input  wire [14:0] overlay_color, // BGR5: B[14:10] G[9:5] R[4:0]

    // Screen interface (800x480)
    input  wire        clk_pixel,
    output reg  [7:0]  r_out,
    output reg  [7:0]  g_out,
    output reg  [7:0]  b_out,
    output wire        sc_clk,
    output wire        sc_hs,
    output wire        sc_vs,
    output wire        sc_de
);

assign sc_clk = clk_pixel;

// --- 1. TIMING VIDEO 800x480 ---
localparam H_SYNC = 2, H_VALID = 800, H_FP = 210, H_BP = 44, H_TOTAL = 1056;
localparam V_SYNC = 2, V_VALID = 480, V_FP = 22,  V_BP = 22, V_TOTAL = 526;

localparam H_ACT_START = H_SYNC + H_BP;
localparam H_ACT_END   = H_ACT_START + H_VALID;
localparam V_ACT_START = V_SYNC + V_BP;
localparam V_ACT_END   = V_ACT_START + V_VALID;

reg [11:0] hcount, vcount;

always @(posedge clk_pixel) begin
    if (!resetn) begin
        hcount <= 12'd0;
        vcount <= 12'd0;
    end else begin
        if (hcount == H_TOTAL - 1) begin
            hcount <= 12'd0;
            vcount <= (vcount == V_TOTAL - 1) ? 12'd0 : vcount + 12'd1;
        end else begin
            hcount <= hcount + 12'd1;
        end
    end
end

wire active_h = (hcount >= H_ACT_START) && (hcount < H_ACT_END);
wire active_v = (vcount >= V_ACT_START) && (vcount < V_ACT_END);

wire internal_hs = (hcount > (H_SYNC - 1));
wire internal_vs = (vcount > (V_SYNC - 1));
wire internal_de = active_h && active_v;


// --- 2. X/Y read logic (Centered x2 scale) ---
// Source size 256x224 -> Scale x2 = 512x448
localparam IMG_W = 512;
localparam IMG_H = 448;

// Automatic centering calculation
localparam [11:0] H_CENTER_START = H_ACT_START + ((H_VALID - IMG_W) / 2); // Starts at H_ACT_START + 144
localparam [11:0] H_CENTER_END   = H_CENTER_START + IMG_W;
localparam [11:0] V_CENTER_START = V_ACT_START + ((V_VALID - IMG_H) / 2); // Starts at V_ACT_START + 16
localparam [11:0] V_CENTER_END   = V_CENTER_START + IMG_H;

wire active_image_h = (hcount >= H_CENTER_START) && (hcount < H_CENTER_END);
wire active_image_v = (vcount >= V_CENTER_START) && (vcount < V_CENTER_END);

reg toggle_x, toggle_y;

// Update Y during horizontal blanking
always @(posedge clk_pixel) begin
    if (!resetn) begin
        overlay_y <= 0;
        toggle_y <= 0;
    end else if (hcount == 0) begin
        if (vcount == V_CENTER_START) begin
            overlay_y <= 0;
            toggle_y <= 0;
        end else if (active_image_v) begin
            toggle_y <= ~toggle_y;
            if (toggle_y)
                overlay_y <= overlay_y + 1'b1;
        end
    end
end

// Update X during the active image area
always @(posedge clk_pixel) begin
    if (!resetn || !active_image_h) begin
        overlay_x <= 0;
        toggle_x <= 0;
    end else if (active_image_h && active_image_v) begin
        toggle_x <= ~toggle_x;
        if (toggle_x)
            overlay_x <= overlay_x + 1'b1;
    end
end

// --- 3. LATENCY PIPELINE ---
reg [LATENCY-1:0] hs_pipe, vs_pipe, de_pipe, img_h_pipe, img_v_pipe;

always @(posedge clk_pixel) begin
    if (!resetn) begin
        hs_pipe <= 0; vs_pipe <= 0; de_pipe <= 0;
        img_h_pipe <= 0; img_v_pipe <= 0;
    end else begin
        hs_pipe <= {hs_pipe[LATENCY-2:0], internal_hs};
        vs_pipe <= {vs_pipe[LATENCY-2:0], internal_vs};
        de_pipe <= {de_pipe[LATENCY-2:0], internal_de};
        // Also delay the active image window for color output alignment
        img_h_pipe <= {img_h_pipe[LATENCY-2:0], active_image_h};
        img_v_pipe <= {img_v_pipe[LATENCY-2:0], active_image_v};
    end
end

assign sc_hs = hs_pipe[LATENCY-1];
assign sc_vs = vs_pipe[LATENCY-1];
assign sc_de = de_pipe[LATENCY-1];

wire show_image = img_h_pipe[LATENCY-1] && img_v_pipe[LATENCY-1];


// --- 4. COLOR OUTPUT (BGR5 15-bit -> RGB888) ---
always @(posedge clk_pixel) begin
    if (!resetn) begin
        r_out <= 8'h00; g_out <= 8'h00; b_out <= 8'h00;
    end else if (show_image && overlay && (overlay_color != 15'h0000)) begin
        // Decode BGR5 with bit replication for full intensity
        // Red: bits [4:0]
        r_out <= {overlay_color[4:0], overlay_color[4:2]};
        // Green: bits [9:5]
        g_out <= {overlay_color[9:5], overlay_color[9:7]};
        // Blue: bits [14:10]
        b_out <= {overlay_color[14:10], overlay_color[14:12]};
    end else if (sc_de) begin // Screen active area outside image (black borders)
        r_out <= 8'h00; g_out <= 8'h00; b_out <= 8'h00;
    end else begin // Outside display area (blanking)
        r_out <= 8'h00; g_out <= 8'h00; b_out <= 8'h00;
    end
end

endmodule