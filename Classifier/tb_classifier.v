`timescale 1ns/1ps
// tb_classifier.v
// Runs every stored test clip through the classifier and checks both the
// winning template index and the winning distance against the Python golden
// model (expected_idx.hex, expected_dist.hex).
module tb_classifier;
    parameter N_FEAT  = 8;
    parameter N_TMPL  = 2;
    parameter N_CLIPS = 4;
    parameter ACC_W   = 16;

    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [$clog2(N_CLIPS)-1:0] clip_sel = 0;

    wire busy, done;
    wire [$clog2(N_TMPL)-1:0] result_idx;
    wire [ACC_W-1:0]          result_dist;

    classifier_core #(
        .N_FEAT(N_FEAT), .N_TMPL(N_TMPL), .N_CLIPS(N_CLIPS), .ACC_W(ACC_W)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .clip_sel(clip_sel),
        .busy(busy), .done(done),
        .result_idx(result_idx), .result_dist(result_dist)
    );

    always #10 clk = ~clk;   // 50 MHz

    reg [7:0]       exp_idx  [0:N_CLIPS-1];
    reg [ACC_W-1:0] exp_dist [0:N_CLIPS-1];

    integer n, errors, timeout;

    task run_clip(input integer c);
    begin
        @(negedge clk); clip_sel = c; start = 1;
        @(negedge clk); start = 0;
        timeout = 0;
        while (!done && timeout < 10000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (timeout >= 10000) begin
            $display("clip %0d: TIMEOUT (FSM never finished)", c);
            errors = errors + 1;
        end else if (result_idx !== exp_idx[c][$clog2(N_TMPL)-1:0] ||
                     result_dist !== exp_dist[c]) begin
            $display("clip %0d: MISMATCH  got idx=%0d dist=%0d   expected idx=%0d dist=%0d",
                     c, result_idx, result_dist, exp_idx[c], exp_dist[c]);
            errors = errors + 1;
        end else begin
            $display("clip %0d: ok        idx=%0d dist=%0d", c, result_idx, result_dist);
        end
    end
    endtask

    initial begin
        $readmemh("expected_idx.hex",  exp_idx);
        $readmemh("expected_dist.hex", exp_dist);
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        for (n = 0; n < N_CLIPS; n = n + 1)
            run_clip(n);

        if (errors == 0) $display("ALL %0d CLIPS PASSED", N_CLIPS);
        else             $display("%0d ERROR(S)", errors);
        $finish;
    end
endmodule
