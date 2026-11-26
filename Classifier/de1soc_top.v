// de1soc_top.v
// Board-level top module for the DE1-SoC.
//
//   KEY0  reset (hold to reset)
//   KEY1  classify the currently selected clip
//   KEY2  select next test clip (ignored while a run is in progress)
//   LEDR[N_TMPL-1:0]  one-hot: which template (species) won
//   LEDR9             busy (classification in progress)
//   HEX1  selected clip number
//   HEX0  winning template number ("-" until a result exists)
//
// Set DEB_CYCLES small (e.g. 4) in simulation, keep 500_000 on the board.
module de1soc_top #(
    parameter N_FEAT     = 8,
    parameter N_TMPL     = 2,
    parameter N_CLIPS    = 4,
    parameter DEB_CYCLES = 500_000
)(
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,        // active low
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1
);
    localparam CLIP_W = $clog2(N_CLIPS);
    localparam TMPL_W = $clog2(N_TMPL);

    wire clk   = CLOCK_50;
    wire rst_n = KEY[0];

    // ---------- buttons -> clean one-cycle pulses ----------
    wire start_pulse, next_pulse;

    button_pulse #(.DEB_CYCLES(DEB_CYCLES)) u_btn_start (
        .clk(clk), .rst_n(rst_n), .btn_n(KEY[1]), .pulse(start_pulse));

    button_pulse #(.DEB_CYCLES(DEB_CYCLES)) u_btn_next (
        .clk(clk), .rst_n(rst_n), .btn_n(KEY[2]), .pulse(next_pulse));

    // ---------- classifier ----------
    wire                 busy, done;
    wire [TMPL_W-1:0]    result_idx;
    wire [15:0]          result_dist;     // unused for now
    reg  [CLIP_W-1:0]    clip_sel;

    classifier_core #(
        .N_FEAT(N_FEAT), .N_TMPL(N_TMPL), .N_CLIPS(N_CLIPS), .ACC_W(16)
    ) u_core (
        .clk(clk), .rst_n(rst_n),
        .start(start_pulse), .clip_sel(clip_sel),
        .busy(busy), .done(done),
        .result_idx(result_idx), .result_dist(result_dist)
    );

    // ---------- clip counter ----------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clip_sel <= 0;
        else if (next_pulse && !busy)
            clip_sel <= (clip_sel == N_CLIPS-1) ? {CLIP_W{1'b0}} : clip_sel + 1'b1;
    end

    // ---------- "a result exists" flag ----------
    // Cleared when a new run starts so stale answers aren't shown.
    reg have_result;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                       have_result <= 1'b0;
        else if (start_pulse && !busy)    have_result <= 1'b0;
        else if (done)                    have_result <= 1'b1;
    end

    // ---------- outputs ----------
    reg [N_TMPL-1:0] winner_led;
    always @(*) begin
        winner_led = {N_TMPL{1'b0}};
        if (have_result) winner_led[result_idx] = 1'b1;
    end

    assign LEDR = {busy, {(9-N_TMPL){1'b0}}, winner_led};

    wire [6:0] hex0_val, hex1_val;
    seg7 u_hex0 (.val({{(4-TMPL_W){1'b0}}, result_idx}), .seg(hex0_val));
    seg7 u_hex1 (.val({{(4-CLIP_W){1'b0}}, clip_sel}),   .seg(hex1_val));

    assign HEX0 = have_result ? hex0_val : 7'b0111111;   // "-" when no result
    assign HEX1 = hex1_val;
endmodule

// seg7.v
// 4-bit value -> 7-segment pattern for the DE-series HEX displays.
// Output bits are {g,f,e,d,c,b,a} and ACTIVE LOW (0 lights the segment).
module seg7 (
    input  wire [3:0] val,
    output reg  [6:0] seg
);
    always @(*) begin
        case (val)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
        endcase
    end
endmodule

// button_pulse.v
// Turns a raw, bouncy, active-low pushbutton into a clean one-clock pulse.
//   1. two flip-flops synchronize the asynchronous button to the clock
//   2. debounce: the input must hold a new value for DEB_CYCLES clocks
//      before it is accepted (500,000 clocks = 10 ms at 50 MHz)
//   3. edge detect: one-cycle pulse when the debounced value goes 0 -> 1
module button_pulse #(
    parameter DEB_CYCLES = 500_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire btn_n,     // raw KEY input, 0 when pressed
    output reg  pulse      // one clock wide, on press
);
    // 1. synchronizer (also inverts, so 1 = pressed)
    reg s1, s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin s1 <= 1'b0; s2 <= 1'b0; end
        else        begin s1 <= ~btn_n; s2 <= s1; end
    end

    // 2. debounce
    reg [$clog2(DEB_CYCLES+1)-1:0] cnt;
    reg stable, stable_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt    <= 0;
            stable <= 1'b0;
        end else if (s2 == stable) begin
            cnt <= 0;                         // no change pending
        end else if (cnt == DEB_CYCLES-1) begin
            stable <= s2;                     // held long enough: accept
            cnt    <= 0;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

    // 3. edge detect
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin stable_d <= 1'b0; pulse <= 1'b0; end
        else begin
            stable_d <= stable;
            pulse    <= stable & ~stable_d;
        end
    end
endmodule

