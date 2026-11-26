// classifier_core.v
// Nearest-template classifier (L1 distance).
//   controller : classifier_fsm
//   datapath   : two ROMs, feature/template counters, subtract+abs,
//                accumulator, best-so-far comparator, result registers
//
// Defaults are the 8-feature "floor" version. For the real design change
// N_FEAT=64, N_TMPL=3, N_CLIPS=<your clip count> (nothing else changes).
module classifier_core #(
    parameter N_FEAT        = 8,
    parameter N_TMPL        = 2,
    parameter N_CLIPS       = 4,
    parameter ACC_W         = 16,   // 14 is enough for 64 features; 16 gives margin
    parameter TEMPLATE_FILE = "templates.hex",
    parameter TEST_FILE     = "test_vectors.hex"
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,     // one-cycle pulse
    input  wire [$clog2(N_CLIPS)-1:0]   clip_sel,  // which test clip to classify

    output wire                         busy,
    output reg                          done,      // one-cycle pulse; result_* valid
    output reg  [$clog2(N_TMPL)-1:0]    result_idx,
    output reg  [ACC_W-1:0]             result_dist
);
    localparam FEAT_AW = $clog2(N_FEAT);
    localparam TMPL_AW = $clog2(N_TMPL);
    localparam T_AW    = $clog2(N_TMPL  * N_FEAT);
    localparam X_AW    = $clog2(N_CLIPS * N_FEAT);

    // ---------------- controller ----------------
    wire init_best, clr_k, clr_i, clr_acc, acc_en, inc_i, cmp_en, inc_k, latch_res;
    wire i_last, k_last;

    classifier_fsm u_fsm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .i_last(i_last), .k_last(k_last),
        .init_best(init_best), .clr_k(clr_k), .clr_i(clr_i), .clr_acc(clr_acc),
        .acc_en(acc_en), .inc_i(inc_i), .cmp_en(cmp_en), .inc_k(inc_k),
        .latch_res(latch_res), .busy(busy)
    );

    // ---------------- counters ----------------
    reg [FEAT_AW-1:0] i;   // feature index
    reg [TMPL_AW-1:0] k;   // template index

    assign i_last = (i == N_FEAT - 1);
    assign k_last = (k == N_TMPL - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      i <= 0;
        else if (clr_i)  i <= 0;
        else if (inc_i)  i <= i + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      k <= 0;
        else if (clr_k)  k <= 0;
        else if (inc_k)  k <= k + 1'b1;
    end

    // ---------------- ROMs ----------------
    wire [X_AW-1:0] x_addr = clip_sel * N_FEAT + i;
    wire [T_AW-1:0] t_addr = k        * N_FEAT + i;
    wire signed [7:0] x_data, t_data;

    rom_sync #(.DATA_W(8), .DEPTH(N_CLIPS*N_FEAT), .ADDR_W(X_AW), .FILE(TEST_FILE))
        u_test_rom (.clk(clk), .addr(x_addr), .data(x_data));

    rom_sync #(.DATA_W(8), .DEPTH(N_TMPL*N_FEAT), .ADDR_W(T_AW), .FILE(TEMPLATE_FILE))
        u_tmpl_rom (.clk(clk), .addr(t_addr), .data(t_data));

    // ---------------- subtract, abs, accumulate ----------------
    // Sign-extend both to 9 bits so 127 - (-128) = 255 and -128 - 127 = -255 fit.
    wire signed [8:0] diff     = {x_data[7], x_data} - {t_data[7], t_data};
    wire        [8:0] abs_diff = diff[8] ? (~diff + 1'b1) : diff;   // 0..255

    reg [ACC_W-1:0] acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       acc <= 0;
        else if (clr_acc) acc <= 0;
        else if (acc_en)  acc <= acc + abs_diff;   // abs_diff zero-extends
    end

    // ---------------- best-so-far ----------------
    reg [ACC_W-1:0]  best_dist;
    reg [TMPL_AW-1:0] best_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            best_dist <= {ACC_W{1'b1}};
            best_idx  <= 0;
        end else if (init_best) begin
            best_dist <= {ACC_W{1'b1}};
            best_idx  <= 0;
        end else if (cmp_en && (acc < best_dist)) begin   // strict <: first template wins ties
            best_dist <= acc;
            best_idx  <= k;
        end
    end

    // ---------------- result registers ----------------
    // Latched in the FSM's DONE state; `done` goes high the cycle after,
    // when result_* already hold the final values.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_idx  <= 0;
            result_dist <= 0;
            done        <= 1'b0;
        end else begin
            done <= latch_res;
            if (latch_res) begin
                result_idx  <= best_idx;
                result_dist <= best_dist;
            end
        end
    end
endmodule

// classifier_fsm.v
// Controller only: it does no math. It sequences the datapath in
// classifier_core.v.
//
//   IDLE --start--> INIT --> CLEAR --> ADDR --> ACC --+--> COMPARE --+--> DONE --> IDLE
//                             ^          ^            |              |
//                             |          +-- not i_last              | not k_last
//                             |                                      v
//                             +------------------------------------ NEXT_K
//
// ADDR : the ROM address (set by the counters) is stable; ROM latches data
// ACC  : ROM data is now valid; accumulate |x - t|, advance feature counter
module classifier_fsm (
    input  wire clk,
    input  wire rst_n,      // active-low (DE1-SoC KEYs are active-low)
    input  wire start,      // one-cycle pulse
    input  wire i_last,     // feature counter is on its last feature
    input  wire k_last,     // template counter is on its last template

    output reg  init_best,  // best_dist <= all ones, best_idx <= 0
    output reg  clr_k,
    output reg  clr_i,
    output reg  clr_acc,
    output reg  acc_en,
    output reg  inc_i,
    output reg  cmp_en,
    output reg  inc_k,
    output reg  latch_res,  // copy best_* into the result registers
    output reg  busy
);
    localparam [2:0] S_IDLE    = 3'd0,
                     S_INIT    = 3'd1,
                     S_CLEAR   = 3'd2,
                     S_ADDR    = 3'd3,
                     S_ACC     = 3'd4,
                     S_COMPARE = 3'd5,
                     S_NEXT_K  = 3'd6,
                     S_DONE    = 3'd7;

    reg [2:0] state, next_state;

    // State register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:    if (start)  next_state = S_INIT;
            S_INIT:                next_state = S_CLEAR;
            S_CLEAR:               next_state = S_ADDR;
            S_ADDR:                next_state = S_ACC;
            S_ACC:     next_state = i_last ? S_COMPARE : S_ADDR;
            S_COMPARE: next_state = k_last ? S_DONE    : S_NEXT_K;
            S_NEXT_K:              next_state = S_CLEAR;
            S_DONE:                next_state = S_IDLE;
            default:               next_state = S_IDLE;
        endcase
    end

    // Output logic (depends only on state and i_last, so glitch-free enough
    // for registered use in the datapath)
    always @(*) begin
        init_best = 1'b0;
        clr_k     = 1'b0;
        clr_i     = 1'b0;
        clr_acc   = 1'b0;
        acc_en    = 1'b0;
        inc_i     = 1'b0;
        cmp_en    = 1'b0;
        inc_k     = 1'b0;
        latch_res = 1'b0;
        busy      = (state != S_IDLE);

        case (state)
            S_INIT:    begin init_best = 1'b1; clr_k = 1'b1; end
            S_CLEAR:   begin clr_acc = 1'b1;   clr_i = 1'b1; end
            S_ACC:     begin acc_en = 1'b1;    inc_i = ~i_last; end
            S_COMPARE: cmp_en = 1'b1;
            S_NEXT_K:  inc_k = 1'b1;
            S_DONE:    latch_res = 1'b1;
            default: ;
        endcase
    end
endmodule

// rom_sync.v
// Synchronous-read ROM. Contents come from a hex file (one byte per line,
// two's complement). Read data appears ONE clock after the address, which
// is how Cyclone V M10K block RAM behaves.
module rom_sync #(
    parameter DATA_W = 8,
    parameter DEPTH  = 16,
    parameter ADDR_W = 4,
    parameter FILE   = "templates.hex"
)(
    input  wire                      clk,
    input  wire [ADDR_W-1:0]         addr,
    output reg  signed [DATA_W-1:0]  data
);
    reg signed [DATA_W-1:0] mem [0:DEPTH-1];

    initial $readmemh(FILE, mem);

    always @(posedge clk)
        data <= mem[addr];
endmodule

