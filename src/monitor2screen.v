`timescale 1ns / 1ps

module monitor2screen #(
    parameter PREFETCH = 3      // cycles d'anticipation (2,3,4...)
) (
    input  wire        resetn,
    input  wire        overlay,
    output reg  [7:0]  overlay_x,
    output reg  [7:0]  overlay_y,
    input  wire [14:0] overlay_color,   // BGR5
    input  wire        clk_pixel,
    output reg  [7:0]  r_out,
    output reg  [7:0]  g_out,
    output reg  [7:0]  b_out,
    output wire        sc_clk,
    output wire        sc_hs,
    output wire        sc_vs,
    output wire        sc_de
);

assign sc_clk = ~clk_pixel;

// ---------- TIMING 800x480 ----------
localparam H_SYNC = 2, H_VALID = 800, H_FP = 210, H_BP = 44, H_TOTAL = 1056;
localparam V_SYNC = 2, V_VALID = 480, V_FP = 22,  V_BP = 22, V_TOTAL = 526;

localparam H_ACT_START = H_SYNC + H_BP;
localparam H_ACT_END   = H_ACT_START + H_VALID;
localparam V_ACT_START = V_SYNC + V_BP;
localparam V_ACT_END   = V_ACT_START + V_VALID;

reg [11:0] hcount, vcount;
always @(posedge clk_pixel) begin
    if (!resetn) begin
        hcount <= 0;
        vcount <= 0;
    end else begin
        if (hcount == H_TOTAL - 1) begin
            hcount <= 0;
            vcount <= (vcount == V_TOTAL - 1) ? 0 : vcount + 1;
        end else begin
            hcount <= hcount + 1;
        end
    end
end

wire active_h = (hcount >= H_ACT_START) && (hcount < H_ACT_END);
wire active_v = (vcount >= V_ACT_START) && (vcount < V_ACT_END);
wire de = active_h && active_v;

// ---------- ZONE IMAGE CENTRÉE ----------
localparam IMG_W  = 512;
localparam IMG_H  = 448;
localparam H_CENTER_START = H_ACT_START + ((H_VALID - IMG_W) / 2);
localparam H_CENTER_END   = H_CENTER_START + IMG_W;
localparam V_CENTER_START = V_ACT_START + ((V_VALID - IMG_H) / 2);
localparam V_CENTER_END   = V_CENTER_START + IMG_H;

// ---------- GENERATION HORIZONTALE (pixel doubling fixe) ----------
// On anticipe le cycle d'enregistrement en évaluant (hcount + 1)
wire [11:0] next_hcount = hcount + 1;
wire next_prefetch = (next_hcount >= H_CENTER_START - PREFETCH) && (next_hcount < H_CENTER_END - PREFETCH);
wire [11:0] req_x = next_hcount - (H_CENTER_START - PREFETCH);

always @(posedge clk_pixel) begin
    if (!resetn) begin
        overlay_x <= 8'd255;
    end else begin
        if (active_v && next_prefetch) begin
            // Division par 2 exacte en utilisant un décalage binaire
            overlay_x <= req_x[8:1];
        end else begin
            overlay_x <= 8'd255;
        end
    end
end

// ---------- GENERATION VERTICALE (retard aligné) ----------
// On décale la génération de overlay_y pour qu'elle corresponde au même instant que overlay_x.
wire [7:0] src_y = (vcount >= V_CENTER_START) ? ((vcount - V_CENTER_START) >> 1) : 0;
reg [7:0] src_y_r;
always @(posedge clk_pixel) begin
    src_y_r <= src_y;
    overlay_y <= src_y_r;   // un cycle de retard (équivalent au pipeline de overlay_x)
end

// ---------- AFFICHAGE ----------
// La couleur overlay_color est valide PREFETCH cycles après la demande.
wire in_display = (hcount >= H_CENTER_START) && (hcount < H_CENTER_END) &&
                  (vcount >= V_CENTER_START) && (vcount < V_CENTER_END);

always @(posedge clk_pixel) begin
    if (!resetn) begin
        r_out <= 0;
        g_out <= 0;
        b_out <= 0;
    end else if (in_display && overlay && overlay_color != 15'h0000) begin
        r_out <= {overlay_color[4:0],   overlay_color[4:2]};
        g_out <= {overlay_color[9:5],   overlay_color[9:7]};
        b_out <= {overlay_color[14:10], overlay_color[14:12]};
    end else begin
        r_out <= 0;
        g_out <= 0;
        b_out <= 0;
    end
end

// ---------- SYNC ----------
assign sc_hs = (hcount < H_SYNC);
assign sc_vs = (vcount < V_SYNC);
assign sc_de = de;

endmodule