`default_nettype none

module image_rom (address, clock, q);
    parameter DATA_WIDTH = 9;                
    parameter ADDR_WIDTH = 15;                
    parameter NUM_WORDS  = 19200;               
    parameter INIT_FILE  = "./images/img0.mif";

    input wire [ADDR_WIDTH-1:0] address;
    input wire clock;
    output wire [DATA_WIDTH-1:0] q;

    altsyncram rom_block (
        .address_a (address),
        .clock0    (clock),
        .q_a       (q)
    );
    defparam
        rom_block.operation_mode         = "ROM",
        rom_block.width_a                = DATA_WIDTH,
        rom_block.widthad_a              = ADDR_WIDTH,
        rom_block.numwords_a             = NUM_WORDS,
        rom_block.init_file              = INIT_FILE,
        rom_block.intended_device_family = "Cyclone V",
        rom_block.outdata_reg_a          = "UNREGISTERED",
        rom_block.clock_enable_input_a   = "BYPASS",
        rom_block.clock_enable_output_a  = "BYPASS";
endmodule