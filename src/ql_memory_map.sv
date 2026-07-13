module ql_memory_map(
    input  wire        clk,
    input  wire        reset,

    input  wire        bus_req,
    input  wire        bus_we,
    input  wire [21:0] bus_addr,
    input  wire [1:0]  bus_ds,
    input  wire [15:0] bus_wdata,
    output wire        bus_ready,
    output wire        bus_data_valid,
    output wire [15:0] bus_data,
    output wire        bus_write_done,
    output wire        rom_is_diagnostic,
    output wire        rom_is_dynamic,

    output wire        dynamic_rom_req,
    output wire [14:0] dynamic_rom_addr,
    input  wire        dynamic_rom_ready,
    input  wire        dynamic_rom_data_valid,
    input  wire [15:0] dynamic_rom_data,

    output reg         mc_stat_wr,
    output reg  [7:0]  mc_stat_data,

    output reg         zx8302_wr,
    output wire [1:0]  zx8302_addr,
    output wire [1:0]  zx8302_ds,
    output wire [15:0] zx8302_wdata,
    input  wire [15:0] zx8302_rdata,
    input  wire        zx8302_write_done,

    output wire        ram_req,
    output wire        ram_we,
    output wire [21:0] ram_addr,
    output wire [1:0]  ram_ds,
    output wire [15:0] ram_wdata,
    input  wire        ram_ready,
    input  wire        ram_data_valid,
    input  wire [15:0] ram_data,
    input  wire        ram_write_done
);

    // System ROM and expansion ROM window: byte addresses 0x000000-0x00ffff.
    localparam [21:0] ROM_LAST_WORD = 22'h007fff;
    // Base Sinclair QL RAM: byte addresses 0x020000-0x03ffff (128 KiB).
    localparam [21:0] RAM_FIRST_WORD = 22'h010000;
    localparam [21:0] RAM_LAST_WORD  = 22'h01ffff;
    // Internal QL I/O window: byte addresses 0x018000-0x01bfff.
    localparam [21:0] IO_FIRST_WORD = 22'h00c000;
    localparam [21:0] IO_LAST_WORD  = 22'h00dfff;
    // ZX8301 MC_STAT is the low byte at byte address 0x018063.
    localparam [21:0] MC_STAT_WORD = 22'h00c031;

    wire rom_selected = bus_addr <= ROM_LAST_WORD;
    wire dynamic_rom_read = rom_selected && rom_is_dynamic && !bus_we;
    wire ram_selected = (bus_addr >= RAM_FIRST_WORD) &&
                        (bus_addr <= RAM_LAST_WORD);
    wire internal_io_selected = (bus_addr >= IO_FIRST_WORD) &&
                                (bus_addr <= IO_LAST_WORD);
    wire mc_stat_selected = bus_addr == MC_STAT_WORD;
    wire zx8302_selected = (bus_addr >= 22'h00c000) &&
                           (bus_addr <= 22'h00c01f);
    wire local_selected = !rom_selected && !ram_selected;
    reg rom_read_pending;
    reg [14:0] rom_addr;
    reg rom_data_valid;
    reg [15:0] rom_data_latched;
    wire [15:0] rom_data;
    reg io_read_pending;
    reg io_data_valid;
    reg [15:0] io_data_latched;
    reg local_write_done;

    ql_boot_rom boot_rom (
        .word_addr(rom_addr),
        .data(rom_data),
        .is_diagnostic(rom_is_diagnostic),
        .is_dynamic(rom_is_dynamic)
    );

    // ROM writes are acknowledged and ignored, like writes to physical ROM.
    assign bus_ready = rom_selected ?
                         (rom_is_dynamic ?
                           (bus_we ? 1'b1 : dynamic_rom_ready) :
                           !rom_read_pending) :
                       ram_selected ? ram_ready : !io_read_pending;
    assign bus_data_valid = rom_data_valid || dynamic_rom_data_valid ||
                            io_data_valid || ram_data_valid;
    assign bus_write_done = local_write_done || zx8302_write_done ||
                            ram_write_done;
    assign bus_data = rom_data_valid ? rom_data_latched :
                      dynamic_rom_data_valid ? dynamic_rom_data :
                      io_data_valid ? io_data_latched : ram_data;

    assign dynamic_rom_req = bus_req && dynamic_rom_read;
    assign dynamic_rom_addr = bus_addr[14:0];
    assign ram_req = bus_req && ram_selected;
    assign ram_we = ram_selected && bus_we;
    assign ram_addr = bus_addr;
    assign ram_ds = bus_ds;
    assign ram_wdata = bus_wdata;
    assign zx8302_addr = {bus_addr[4], bus_addr[0]};
    assign zx8302_ds = bus_ds;
    assign zx8302_wdata = bus_wdata;

    always @(posedge clk) begin
        if (reset) begin
            rom_read_pending <= 1'b0;
            rom_addr <= 15'd0;
            rom_data_valid <= 1'b0;
            rom_data_latched <= 16'd0;
            io_read_pending <= 1'b0;
            io_data_valid <= 1'b0;
            io_data_latched <= 16'hffff;
            local_write_done <= 1'b0;
            mc_stat_wr <= 1'b0;
            mc_stat_data <= 8'd0;
            zx8302_wr <= 1'b0;
        end else begin
            rom_data_valid <= 1'b0;
            io_data_valid <= 1'b0;
            local_write_done <= 1'b0;
            mc_stat_wr <= 1'b0;
            zx8302_wr <= 1'b0;

            if (bus_req && bus_we && !ram_selected && !zx8302_selected)
                local_write_done <= 1'b1;

            if (rom_read_pending) begin
                rom_data_latched <= rom_data;
                rom_data_valid <= 1'b1;
                rom_read_pending <= 1'b0;
            end else if (bus_req && rom_selected && !rom_is_dynamic &&
                         !bus_we) begin
                rom_addr <= bus_addr[14:0];
                rom_read_pending <= 1'b1;
            end

            if (io_read_pending) begin
                io_data_valid <= 1'b1;
                io_read_pending <= 1'b0;
            end else if (bus_req && local_selected) begin
                if (bus_we) begin
                    if (mc_stat_selected && !bus_ds[0]) begin
                        mc_stat_data <= bus_wdata[7:0];
                        mc_stat_wr <= 1'b1;
                    end else if (zx8302_selected) begin
                        zx8302_wr <= 1'b1;
                    end
                end else begin
                    if (zx8302_selected)
                        io_data_latched <= zx8302_rdata;
                    else if (internal_io_selected)
                        // Unimplemented internal registers read as zero, as
                        // in the original MiST QL address multiplexer.
                        io_data_latched <= 16'h0000;
                    else
                        // Unmapped expansion space behaves as an open bus.
                        io_data_latched <= 16'hffff;
                    io_read_pending <= 1'b1;
                end
            end
        end
    end

endmodule
