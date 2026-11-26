`timescale 1ns/1ps
// tb_top.v -- exercises the board-level top: button presses in, LEDs out.
module tb_top;
    parameter N_FEAT  = 8;
    parameter N_TMPL  = 2;
    parameter N_CLIPS = 4;

    reg        CLOCK_50 = 0;
    reg  [3:0] KEY = 4'b1111;           // all released
    wire [9:0] LEDR;
    wire [6:0] HEX0, HEX1;

    de1soc_top #(.N_FEAT(N_FEAT), .N_TMPL(N_TMPL), .N_CLIPS(N_CLIPS),
                 .DEB_CYCLES(4)) dut (
        .CLOCK_50(CLOCK_50), .KEY(KEY), .LEDR(LEDR), .HEX0(HEX0), .HEX1(HEX1));

    always #10 CLOCK_50 = ~CLOCK_50;

    reg [7:0] exp_idx [0:N_CLIPS-1];
    integer c, errors;

    // hold a key down for `cycles` clocks, then release and settle
    task press(input integer which, input integer cycles);
    begin
        @(negedge CLOCK_50); KEY[which] = 1'b0;
        repeat (cycles) @(negedge CLOCK_50);
        KEY[which] = 1'b1;
        repeat (10) @(negedge CLOCK_50);
    end
    endtask

    initial begin
        $readmemh("expected_idx.hex", exp_idx);
        errors = 0;

        // reset
        KEY[0] = 1'b0; repeat (4) @(negedge CLOCK_50);
        KEY[0] = 1'b1; repeat (4) @(negedge CLOCK_50);

        // a 2-cycle glitch on START is shorter than the debounce time: ignored
        press(1, 2);
        repeat (20) @(negedge CLOCK_50);
        if (LEDR[9] !== 1'b0 || LEDR[N_TMPL-1:0] !== 0) begin
            $display("FAIL: glitch on KEY1 started a run"); errors = errors + 1;
        end else
            $display("glitch rejected: ok");

        // classify every clip
        for (c = 0; c < N_CLIPS; c = c + 1) begin
            press(1, 20);                          // start
            repeat (200) @(negedge CLOCK_50);      // plenty for the FSM
            if (LEDR[9] !== 1'b0) begin
                $display("clip %0d: FAIL still busy", c); errors = errors + 1;
            end else if (LEDR[N_TMPL-1:0] !== (1 << exp_idx[c])) begin
                $display("clip %0d: FAIL LEDR=%b expected template %0d",
                         c, LEDR[N_TMPL-1:0], exp_idx[c]);
                errors = errors + 1;
            end else
                $display("clip %0d: ok  winner LED = %b  HEX1 shows clip %0d",
                         c, LEDR[N_TMPL-1:0], c);
            press(2, 20);                          // next clip
        end

        if (errors == 0) $display("TOP LEVEL: ALL PASSED");
        else             $display("TOP LEVEL: %0d ERROR(S)", errors);
        $finish;
    end
endmodule
