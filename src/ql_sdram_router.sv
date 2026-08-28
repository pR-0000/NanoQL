module ql_sdram_router(
    input  wire        clk,
    input  wire        reset,

    input  wire        host_req,
    input  wire        host_we,
    input  wire [21:0] host_addr,
    input  wire [1:0]  host_ds,
    input  wire [15:0] host_wdata,
    output wire        host_ready,
    output wire        host_data_valid,
    output wire [15:0] host_data,
    output wire        host_write_done,

    input  wire        loader_req,
    input  wire        loader_we,
    input  wire [21:0] loader_addr,
    input  wire [1:0]  loader_ds,
    input  wire [15:0] loader_wdata,
    output wire        loader_ready,
    output wire        loader_data_valid,
    output wire [15:0] loader_data,
    output wire        loader_write_done,

    input  wire        rom_req,
    input  wire [21:0] rom_addr,
    output wire        rom_ready,
    output wire        rom_data_valid,
    output wire [15:0] rom_data,

    input  wire        ram_req,
    input  wire        ram_we,
    input  wire [21:0] ram_addr,
    input  wire [1:0]  ram_ds,
    input  wire [15:0] ram_wdata,
    output wire        ram_ready,
    output wire        ram_data_valid,
    output wire [15:0] ram_data,
    output wire        ram_write_done,

    input  wire        snapshot_req,
    input  wire        snapshot_we,
    input  wire [21:0] snapshot_addr,
    input  wire [1:0]  snapshot_ds,
    input  wire [15:0] snapshot_wdata,
    output wire        snapshot_ready,
    output wire        snapshot_data_valid,
    output wire [15:0] snapshot_data,
    output wire        snapshot_write_done,

    output wire        system_req,
    output wire        system_we,
    output wire [21:0] system_addr,
    output wire [1:0]  system_ds,
    output wire [15:0] system_wdata,
    input  wire        system_ready,
    input  wire        system_data_valid,
    input  wire [15:0] system_data,
    input  wire        system_write_done
);

    localparam [2:0] OWNER_NONE   = 3'd0;
    localparam [2:0] OWNER_HOST   = 3'd1;
    localparam [2:0] OWNER_LOADER = 3'd2;
    localparam [2:0] OWNER_ROM    = 3'd3;
    localparam [2:0] OWNER_RAM    = 3'd4;
    localparam [2:0] OWNER_SNAPSHOT = 3'd5;

    reg [2:0] active_owner;

    wire [2:0] selected_owner = host_req ? OWNER_HOST :
                                loader_req ? OWNER_LOADER :
                                rom_req ? OWNER_ROM :
                                ram_req ? OWNER_RAM :
                                snapshot_req ? OWNER_SNAPSHOT : OWNER_NONE;
    wire idle = active_owner == OWNER_NONE;

    assign system_req = idle && (selected_owner != OWNER_NONE);
    assign system_we = selected_owner == OWNER_HOST ? host_we :
                       selected_owner == OWNER_LOADER ? loader_we :
                       selected_owner == OWNER_SNAPSHOT ? snapshot_we :
                       selected_owner == OWNER_RAM ? ram_we : 1'b0;
    assign system_addr = selected_owner == OWNER_HOST ? host_addr :
                         selected_owner == OWNER_LOADER ? loader_addr :
                         selected_owner == OWNER_ROM ? rom_addr :
                         selected_owner == OWNER_SNAPSHOT ? snapshot_addr :
                         ram_addr;
    assign system_ds = selected_owner == OWNER_HOST ? host_ds :
                       selected_owner == OWNER_LOADER ? loader_ds :
                       selected_owner == OWNER_SNAPSHOT ? snapshot_ds :
                       selected_owner == OWNER_RAM ? ram_ds : 2'b00;
    assign system_wdata = selected_owner == OWNER_HOST ? host_wdata :
                          selected_owner == OWNER_LOADER ? loader_wdata :
                          selected_owner == OWNER_SNAPSHOT ? snapshot_wdata :
                          ram_wdata;

    assign host_ready = idle && (selected_owner == OWNER_HOST) && system_ready;
    assign loader_ready = idle && (selected_owner == OWNER_LOADER) && system_ready;
    assign rom_ready = idle && (selected_owner == OWNER_ROM) && system_ready;
    assign ram_ready = idle && (selected_owner == OWNER_RAM) && system_ready;
    assign snapshot_ready = idle && (selected_owner == OWNER_SNAPSHOT) &&
                            system_ready;

    assign host_data_valid = (active_owner == OWNER_HOST) && system_data_valid;
    assign loader_data_valid = (active_owner == OWNER_LOADER) && system_data_valid;
    assign rom_data_valid = (active_owner == OWNER_ROM) && system_data_valid;
    assign ram_data_valid = (active_owner == OWNER_RAM) && system_data_valid;
    assign snapshot_data_valid = (active_owner == OWNER_SNAPSHOT) &&
                                 system_data_valid;
    assign host_write_done = (active_owner == OWNER_HOST) && system_write_done;
    assign loader_write_done = (active_owner == OWNER_LOADER) && system_write_done;
    assign ram_write_done = (active_owner == OWNER_RAM) && system_write_done;
    assign snapshot_write_done = (active_owner == OWNER_SNAPSHOT) &&
                                 system_write_done;

    assign host_data = system_data;
    assign loader_data = system_data;
    assign rom_data = system_data;
    assign ram_data = system_data;
    assign snapshot_data = system_data;

    always @(posedge clk) begin
        if (reset)
            active_owner <= OWNER_NONE;
        else begin
            if (system_data_valid || system_write_done)
                active_owner <= OWNER_NONE;
            if (system_req && system_ready)
                active_owner <= selected_owner;
        end
    end

endmodule
