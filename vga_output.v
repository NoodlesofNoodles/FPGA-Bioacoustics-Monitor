`default_nettype wire


module vga_output(CLOCK_50, SW, KEY, LEDR, VGA_R, VGA_G, VGA_B,
                VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);

    parameter RESOLUTION = "160x120"; 

    parameter COLOR_DEPTH = 9;

    parameter nX = (RESOLUTION == "640x480") ? 10 : ((RESOLUTION == "320x240") ? 9 : 8);

    parameter nY = (RESOLUTION == "640x480") ? 9 : ((RESOLUTION == "320x240") ? 8 : 7);

    parameter Mn = (RESOLUTION == "640x480") ? 19 : ((RESOLUTION == "320x240") ? 17 : 15);

    parameter COLS = (RESOLUTION == "640x480") ? 640 : ((RESOLUTION == "320x240") ? 320 : 160);
    parameter ROWS = (RESOLUTION == "640x480") ? 480 : ((RESOLUTION == "320x240") ? 240 : 120);

    input wire CLOCK_50;
    input wire [9:0] SW;
    input wire [3:0] KEY;
    output wire [9:0] LEDR;
    output [7:0] VGA_R;
    output [7:0] VGA_G;
    output [7:0] VGA_B;
    output VGA_HS;
    output VGA_VS;
    output VGA_BLANK_N;
    output VGA_SYNC_N;
    output VGA_CLK;


    reg [1:0] sw_m, sw_s;
    reg rst_m, rst_s;
    always @(posedge CLOCK_50) begin
        sw_m  <= SW[1:0];
        sw_s  <= sw_m;
        rst_m <= KEY[0];
        rst_s <= rst_m;
    end

    wire [1:0] sel = sw_s; 
    wire resetn = rst_s;   

    assign LEDR[1:0] = sel; 
    assign LEDR[9:2] = 8'b0;

    reg [nX-1:0] x_scan = 0;
    reg [nY-1:0] y_scan = 0;
    reg drawing = 1'b1;
    reg [1:0] cur_sel = 2'b00;

    always @(posedge CLOCK_50) begin
        if (!resetn || (sel != cur_sel)) 
        begin
            cur_sel <= sel;
            x_scan <= 0;
            y_scan <= 0;
            drawing <= 1'b1;
        end
        else if (drawing) 
        begin
            if (x_scan == COLS-1) 
            begin
                x_scan <= 0;
                if (y_scan == ROWS-1)
                    drawing <= 1'b0;     
                else
                    y_scan <= y_scan + 1'b1;
            end
            else
                x_scan <= x_scan + 1'b1;
        end
    end

    wire [Mn-1:0] rom_address;
    vga_address_translator rom_translator (.x(x_scan), .y(y_scan), .mem_address(rom_address));
        defparam rom_translator.nX = nX;
        defparam rom_translator.nY = nY;
        defparam rom_translator.Mn = Mn;

    wire [COLOR_DEPTH-1:0] pix0, pix1, pix2, pix3;

    image_rom rom0 (.address(rom_address), .clock(CLOCK_50), .q(pix0));
        defparam rom0.DATA_WIDTH = COLOR_DEPTH;
        defparam rom0.ADDR_WIDTH = Mn;
        defparam rom0.NUM_WORDS  = COLS*ROWS;
        defparam rom0.INIT_FILE  = "./images/img0.mif";

    image_rom rom1 (.address(rom_address), .clock(CLOCK_50), .q(pix1));
        defparam rom1.DATA_WIDTH = COLOR_DEPTH;
        defparam rom1.ADDR_WIDTH = Mn;
        defparam rom1.NUM_WORDS  = COLS*ROWS;
        defparam rom1.INIT_FILE  = "./images/img1.mif";

    image_rom rom2 (.address(rom_address), .clock(CLOCK_50), .q(pix2));
        defparam rom2.DATA_WIDTH = COLOR_DEPTH;
        defparam rom2.ADDR_WIDTH = Mn;
        defparam rom2.NUM_WORDS  = COLS*ROWS;
        defparam rom2.INIT_FILE  = "./images/img2.mif";

    image_rom rom3 (.address(rom_address), .clock(CLOCK_50), .q(pix3));
        defparam rom3.DATA_WIDTH = COLOR_DEPTH;
        defparam rom3.ADDR_WIDTH = Mn;
        defparam rom3.NUM_WORDS  = COLS*ROWS;
        defparam rom3.INIT_FILE  = "./images/img3.mif";

    reg [nX-1:0] X_d;
    reg [nY-1:0] Y_d;
    reg write_d;
    reg [1:0] sel_d;

    always @(posedge CLOCK_50) begin
        X_d <= x_scan;
        Y_d <= y_scan;
        write_d <= drawing;
        sel_d <= cur_sel;
    end

    wire [COLOR_DEPTH-1:0] color;
    wire [nX-1:0] X;
    wire [nY-1:0] Y;
    wire write;

    assign color = (sel_d == 2'b00) ? pix0 :
                   (sel_d == 2'b01) ? pix1 :
                   (sel_d == 2'b10) ? pix2 : pix3;
    assign X = X_d;
    assign Y = Y_d;
    assign write = write_d;

   
    vga_adapter VGA (
        .resetn(KEY[0]),
        .clock(CLOCK_50),
        .color(color),
        .x(X),
        .y(Y),
        .write(write),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_CLK(VGA_CLK));
        defparam VGA.RESOLUTION = RESOLUTION;
        defparam VGA.BACKGROUND_IMAGE = "./images/img0.mif";
        defparam VGA.COLOR_DEPTH = COLOR_DEPTH;
endmodule