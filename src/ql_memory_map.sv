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

    output reg         mc_stat_wr,
    output reg  [7:0]  mc_stat_data,

    output reg         zx8302_wr,
    output wire [1:0]  zx8302_addr,
    output wire [1:0]  zx8302_ds,
    output wire [15:0] zx8302_wdata,
    input  wire [15:0] zx8302_rdata,

    output wire        ram_req,
    output wire        ram_we,
    output wire [21:0] ram_addr,
    output wire [1:0]  ram_ds,
    output wire [15:0] ram_wdata,
    input  wire        ram_ready,
    input  wire        ram_data_valid,
    input  wire [15:0] ram_data
);

    // The original QL ROM occupies byte addresses 0x000000-0x00bfff.
    localparam [21:0] ROM_LAST_WORD = 22'h005fff;
    // ZX8301 MC_STAT is the low byte at byte address 0x018063.
    localparam [21:0] MC_STAT_WORD = 22'h00c031;

    wire rom_selected = bus_addr <= ROM_LAST_WORD;
    wire mc_stat_selected = bus_addr == MC_STAT_WORD;
    wire zx8302_selected = (bus_addr >= 22'h00c000) &&
                           (bus_addr <= 22'h00c01f);
    reg rom_read_pending;
    reg [14:0] rom_addr;
    reg rom_data_valid;
    reg [15:0] rom_data_latched;
    wire [15:0] rom_data;
    reg io_read_pending;
    reg io_data_valid;
    reg [15:0] io_data_latched;

    ql_boot_rom boot_rom (
        .word_addr(rom_addr),
        .data(rom_data)
    );

    // ROM writes are acknowledged and ignored, like writes to physical ROM.
    assign bus_ready = rom_selected ? !rom_read_pending :
                       (mc_stat_selected || zx8302_selected) ?
                         !io_read_pending : ram_ready;
    assign bus_data_valid = rom_data_valid || io_data_valid || ram_data_valid;
    assign bus_data = rom_data_valid ? rom_data_latched :
                      io_data_valid ? io_data_latched : ram_data;

    assign ram_req = bus_req && !rom_selected &&
                     !mc_stat_selected && !zx8302_selected;
    assign ram_we = bus_we;
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
            mc_stat_wr <= 1'b0;
            mc_stat_data <= 8'd0;
            zx8302_wr <= 1'b0;
        end else begin
            rom_data_valid <= 1'b0;
            io_data_valid <= 1'b0;
            mc_stat_wr <= 1'b0;
            zx8302_wr <= 1'b0;

            if (rom_read_pending) begin
                rom_data_latched <= rom_data;
                rom_data_valid <= 1'b1;
                rom_read_pending <= 1'b0;
            end else if (bus_req && rom_selected && !bus_we) begin
                rom_addr <= bus_addr[14:0];
                rom_read_pending <= 1'b1;
            end

            if (io_read_pending) begin
                io_data_valid <= 1'b1;
                io_read_pending <= 1'b0;
            end else if (bus_req && mc_stat_selected) begin
                if (bus_we) begin
                    if (!bus_ds[0]) begin
                        mc_stat_data <= bus_wdata[7:0];
                        mc_stat_wr <= 1'b1;
                    end
                end else begin
                    // MC_STAT is write-only; reads return an open-bus value.
                    io_data_latched <= 16'hffff;
                    io_read_pending <= 1'b1;
                end
            end else if (bus_req && zx8302_selected) begin
                if (bus_we) begin
                    zx8302_wr <= 1'b1;
                end else begin
                    io_data_latched <= zx8302_rdata;
                    io_read_pending <= 1'b1;
                end
            end
        end
    end

endmodule
