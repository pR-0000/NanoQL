/*
 * Persistent GW2AR-18 configuration-Flash writer for NanoQL Link.
 *
 * The implementation follows the GW2A SPI-over-JTAG path used by
 * openFPGALoader. It deliberately supports only the Tang Nano 20K FPGA and
 * performs sequential, page-verified writes from address zero.
 */

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include <FreeRTOS.h>
#include "task.h"

#include "../debug.h"
#include "../gowin.h"
#include "../jtag.h"
#include "../mcu_hw.h"
#include "nanoql_flash.h"

#define FLASH_WRSR 0x01
#define FLASH_PP   0x02
#define FLASH_READ 0x03
#define FLASH_WRDI 0x04
#define FLASH_RDSR 0x05
#define FLASH_WREN 0x06
#define FLASH_RSTEN 0x66
#define FLASH_RST   0x99
#define FLASH_BE64  0xd8
#define FLASH_RDID  0x9f
#define FLASH_POWER_UP 0xab

#define FLASH_STATUS_WIP 0x01
#define FLASH_STATUS_WEL 0x02
#define FLASH_STATUS_BP  0x7c
#define FLASH_PAGE_SIZE 256u
#define FLASH_ERASE_SIZE 65536u
#define FLASH_SPI_MAX_BYTES (1u + 3u + FLASH_PAGE_SIZE + 1u)

/* Tang Nano 20K BL616 GPIO registers. Both supported board revisions use
   TCK=GPIO10, TDI=GPIO12, TDO=GPIO14 and TMS=GPIO16. Direct register access
   avoids several ROM calls per JTAG bit and is substantially faster while the
   Companion task is suspended for programming. */
#define NANOQL_GPIO_OUTPUT_ADDRESS UINT32_C(0x20000ae4)
#define NANOQL_GPIO_TDO_CFG_ADDRESS UINT32_C(0x200008fc)
#define NANOQL_GPIO_TCK_MASK (UINT32_C(1) << 10)
#define NANOQL_GPIO_TDI_MASK (UINT32_C(1) << 12)
#define NANOQL_GPIO_TMS_MASK (UINT32_C(1) << 16)
#define NANOQL_GPIO_TDO_INPUT (UINT32_C(1) << 28)

#define FLASH_DIAG_NONE          0u
#define FLASH_DIAG_WREN_COMMAND  1u
#define FLASH_DIAG_WREN_STATUS   2u
#define FLASH_DIAG_ERASE_COMMAND 3u
#define FLASH_DIAG_ERASE_STATUS  4u
#define FLASH_DIAG_ERASE_VERIFY  5u
#define FLASH_DIAG_PAGE_COMMAND  6u
#define FLASH_DIAG_PAGE_STATUS   7u
#define FLASH_DIAG_READ_COMMAND  8u
#define FLASH_DIAG_VERIFY_DATA   9u
#define FLASH_DIAG_WRDI_COMMAND  10u
#define FLASH_DIAG_WRDI_STATUS   11u
#define FLASH_DIAG_IDENTIFY      12u

static bool flash_active;
static uint32_t flash_length;
static uint32_t flash_address;
static uint16_t flash_page_used;
static uint8_t flash_page[FLASH_PAGE_SIZE];
static uint8_t flash_spi_tx[FLASH_SPI_MAX_BYTES + 1u];
static uint8_t flash_spi_rx[FLASH_SPI_MAX_BYTES + 1u];
static nanoql_flash_diagnostic_t flash_diagnostic;

static void set_diagnostic(uint8_t stage, uint32_t address,
                           uint8_t expected, uint8_t actual)
{
    flash_diagnostic.stage = stage;
    flash_diagnostic.address = address;
    flash_diagnostic.expected = expected;
    flash_diagnostic.actual = actual;
}

static inline uint8_t reverse_byte(uint8_t value)
{
    value = ((value & 0x55u) << 1) | ((value & 0xaau) >> 1);
    value = ((value & 0x33u) << 2) | ((value & 0xccu) >> 2);
    return (uint8_t)(((value & 0x0fu) << 4) | ((value & 0xf0u) >> 4));
}

static void shift_spi_dr_fast(
    const uint8_t *tx, uint8_t *rx, uint16_t bit_length)
{
    volatile uint32_t *const gpio_output =
        (volatile uint32_t *)NANOQL_GPIO_OUTPUT_ADDRESS;
    volatile uint32_t *const gpio_tdo =
        (volatile uint32_t *)NANOQL_GPIO_TDO_CFG_ADDRESS;

    /* Command 0x16 requires entering SHIFT-DR through PAUSE/EXIT2-DR. */
    mcu_hw_jtag_tms(1, 0b10101, 5);
    mcu_hw_jtag_tms(1, 0, 1);
    mcu_hw_jtag_enter_gpio_out_mode();

    uint32_t base = *gpio_output &
        ~(NANOQL_GPIO_TCK_MASK | NANOQL_GPIO_TDI_MASK |
          NANOQL_GPIO_TMS_MASK);
    for (uint16_t bit = 0; bit < bit_length; ++bit) {
        uint32_t pins = base;
        if (tx && (tx[bit >> 3] & (UINT8_C(1) << (bit & 7))))
            pins |= NANOQL_GPIO_TDI_MASK;
        if (bit + 1u == bit_length)
            pins |= NANOQL_GPIO_TMS_MASK;

        *gpio_output = pins;
        *gpio_output = pins | NANOQL_GPIO_TCK_MASK;
        if (rx && (*gpio_tdo & NANOQL_GPIO_TDO_INPUT))
            rx[bit >> 3] |= (uint8_t)(UINT8_C(1) << (bit & 7));
        *gpio_output = pins;
    }

    mcu_hw_jtag_exit_gpio_out_mode();
    /* EXIT1-DR -> UPDATE-DR -> RUN-TEST/IDLE. */
    mcu_hw_jtag_tms(1, 0b01, 2);
}

static uint32_t read_fpga_status(void)
{
    return jtag_command_u08_read32(GOWIN_COMMAND_STATUS);
}

static bool poll_fpga_status(uint32_t mask, uint32_t expected)
{
    for (unsigned attempt = 0; attempt < 2000; ++attempt) {
        if ((read_fpga_status() & mask) == expected)
            return true;
    }
    return false;
}

static void force_gw2a_state(void)
{
    /* A partially erased external Flash does not always leave CRC_ERROR set,
       although command 0x16 remains disconnected. Run Gowin's recovery
       sequence unconditionally before erasing SRAM and opening the bridge. */
    (void)read_fpga_status();
    jtag_command_u08(GOWIN_COMMAND_CONFIG_DISABLE);
    jtag_command_u08(0);
    (void)jtag_command_u08_read32(GOWIN_COMMAND_IDCODE);
    (void)read_fpga_status();
    jtag_command_u08(GOWIN_COMMAND_CONFIG_DISABLE);
    jtag_command_u08(0);
    (void)read_fpga_status();
    (void)jtag_command_u08_read32(GOWIN_COMMAND_IDCODE);
    jtag_command_u08(GOWIN_COMMAND_CONFIG_ENABLE);
    jtag_command_u08(GOWIN_COMMAND_RECONFIG);
    jtag_command_u08(GOWIN_COMMAND_NOOP);
    jtag_clk_us(10000);
    jtag_command_u08(GOWIN_COMMAND_CONFIG_DISABLE);
    jtag_command_u08(GOWIN_COMMAND_NOOP);
    (void)jtag_command_u08_read32(GOWIN_COMMAND_IDCODE);
    jtag_command_u08(GOWIN_COMMAND_NOOP);
    (void)jtag_command_u08_read32(GOWIN_COMMAND_IDCODE);
}

static bool prepare_spi_bridge(void)
{
    uint32_t idcode = jtag_open();
    if (idcode != IDCODE_GW2AR18) {
        debugf("NanoQL Flash: unexpected FPGA ID %08lx", (unsigned long)idcode);
        jtag_close();
        return false;
    }

    (void)jtag_command_u08_read32(GOWIN_COMMAND_USERCODE);
    force_gw2a_state();
    jtag_command_u08(GOWIN_COMMAND_CONFIG_ENABLE);
    if (!poll_fpga_status(GOWIN_STATUS_SYSTEM_EDIT_MODE,
                          GOWIN_STATUS_SYSTEM_EDIT_MODE))
        goto failure;

    jtag_command_u08(GOWIN_COMMAND_ERASE_SRAM);
    jtag_command_u08(GOWIN_COMMAND_NOOP);
    jtag_clk_us(10000);
    if (!poll_fpga_status(GOWIN_STATUS_MEMORY_ERASE,
                          GOWIN_STATUS_MEMORY_ERASE))
        goto failure;

    jtag_command_u08(GOWIN_COMMAND_XFER_DONE);
    jtag_command_u08(GOWIN_COMMAND_NOOP);
    jtag_command_u08(GOWIN_COMMAND_CONFIG_DISABLE);
    jtag_command_u08(GOWIN_COMMAND_NOOP);
    if (!poll_fpga_status(GOWIN_STATUS_SYSTEM_EDIT_MODE, 0))
        goto failure;
    return true;

failure:
    debugf("NanoQL Flash: unable to prepare GW2A SPI bridge");
    jtag_close();
    return false;
}

static bool spi_transfer(const uint8_t *tx, uint8_t *rx, uint16_t length)
{
    if (!length || length > FLASH_SPI_MAX_BYTES)
        return false;

    uint16_t wire_length = (uint16_t)(length + (rx ? 1u : 0u));
    for (uint16_t index = 0; index < wire_length; ++index)
        flash_spi_tx[index] = reverse_byte(index < length && tx ? tx[index] : 0);
    memset(flash_spi_rx, 0, wire_length);

    jtag_command_u08(GOWIN_COMMAND_TRANSFER_SPI);
    shift_spi_dr_fast(
        flash_spi_tx, rx ? flash_spi_rx : NULL,
        (uint16_t)(wire_length * 8u));

    if (rx) {
        for (uint16_t index = 0; index < length; ++index) {
            rx[index] = (uint8_t)(
                reverse_byte((uint8_t)(flash_spi_rx[index] >> 1)) |
                (flash_spi_rx[index + 1u] & 0x01u));
        }
    }
    return true;
}

static bool spi_command(uint8_t command, const uint8_t *tx, uint8_t *rx,
                        uint16_t length)
{
    if ((uint32_t)length + 1u > FLASH_SPI_MAX_BYTES)
        return false;
    flash_spi_tx[0] = command;
    if (tx)
        memcpy(&flash_spi_tx[1], tx, length);
    else
        memset(&flash_spi_tx[1], 0, length);
    if (!spi_transfer(flash_spi_tx, rx ? flash_spi_rx : NULL,
                      (uint16_t)(length + 1u)))
        return false;
    if (rx)
        memcpy(rx, &flash_spi_rx[1], length);
    return true;
}

static bool read_flash_status(uint8_t *status)
{
    bool valid = spi_command(FLASH_RDSR, NULL, status, 1);
    if (valid)
        flash_diagnostic.status = *status;
    return valid;
}

static bool wait_flash_status(uint8_t mask, uint8_t expected,
                              uint32_t timeout_ms)
{
    TickType_t deadline = xTaskGetTickCount() + pdMS_TO_TICKS(timeout_ms);
    do {
        uint8_t status;
        if (!read_flash_status(&status))
            return false;
        if ((status & mask) == expected)
            return true;
        vTaskDelay(pdMS_TO_TICKS(1));
    } while ((int32_t)(deadline - xTaskGetTickCount()) > 0);
    return false;
}

static bool write_enable(uint32_t address)
{
    if (!spi_command(FLASH_WREN, NULL, NULL, 0)) {
        set_diagnostic(FLASH_DIAG_WREN_COMMAND, address, 0, 0);
        return false;
    }
    if (!wait_flash_status(
            FLASH_STATUS_WEL, FLASH_STATUS_WEL, 100)) {
        set_diagnostic(FLASH_DIAG_WREN_STATUS, address,
                       FLASH_STATUS_WEL, flash_diagnostic.status);
        return false;
    }
    return true;
}

static bool write_disable(uint32_t address)
{
    if (!spi_command(FLASH_WRDI, NULL, NULL, 0)) {
        set_diagnostic(FLASH_DIAG_WRDI_COMMAND, address, 0, 0);
        return false;
    }
    if (!wait_flash_status(FLASH_STATUS_WEL, 0, 100)) {
        set_diagnostic(FLASH_DIAG_WRDI_STATUS, address, 0,
                       flash_diagnostic.status);
        return false;
    }
    return true;
}

static bool read_flash(uint32_t address, uint8_t *data, uint16_t length)
{
    uint8_t payload[3 + FLASH_PAGE_SIZE + 1];
    uint8_t result[3 + FLASH_PAGE_SIZE + 1];
    if (!length || length > FLASH_PAGE_SIZE)
        return false;
    payload[0] = (uint8_t)(address >> 16);
    payload[1] = (uint8_t)(address >> 8);
    payload[2] = (uint8_t)address;
    /* Command 0x16 returns SPI data one JTAG bit late. Its final reconstructed
       byte can therefore lose bit zero at EXIT1-DR. Clock one disposable byte
       after the requested data so every byte we verify is fully sampled. */
    memset(&payload[3], 0, (size_t)length + 1u);
    if (!spi_command(FLASH_READ, payload, result,
                     (uint16_t)(length + 4u))) {
        set_diagnostic(FLASH_DIAG_READ_COMMAND, address, 0, 0);
        return false;
    }
    memcpy(data, &result[3], length);
    return true;
}

static bool erase_block(uint32_t address)
{
    uint8_t command_address[3] = {
        (uint8_t)(address >> 16),
        (uint8_t)(address >> 8),
        (uint8_t)address
    };
    if (!write_enable(address))
        return false;
    if (!spi_command(
            FLASH_BE64, command_address, NULL, sizeof(command_address))) {
        set_diagnostic(FLASH_DIAG_ERASE_COMMAND, address, 0, 0);
        return false;
    }
    /* A completed write/erase clears both WIP and WEL. Checking WIP alone
       can falsely succeed before an unsupported command has done anything,
       because a rejected command leaves WIP=0 and WEL=1. */
    if (!wait_flash_status(
            FLASH_STATUS_WIP | FLASH_STATUS_WEL, 0, 10000)) {
        set_diagnostic(FLASH_DIAG_ERASE_STATUS, address, 0,
                       flash_diagnostic.status);
        return false;
    }

    uint8_t erased[16];
    if (!read_flash(address, erased, sizeof(erased)))
        return false;
    for (unsigned index = 0; index < sizeof(erased); ++index) {
        if (erased[index] != 0xff) {
            set_diagnostic(FLASH_DIAG_ERASE_VERIFY, address + index,
                           0xff, erased[index]);
            return false;
        }
    }
    return true;
}

static bool program_page(uint32_t address, const uint8_t *data, uint16_t length)
{
    if (!length || length > FLASH_PAGE_SIZE ||
        ((address & (FLASH_PAGE_SIZE - 1u)) + length > FLASH_PAGE_SIZE))
        return false;

    uint8_t payload[3 + FLASH_PAGE_SIZE];
    payload[0] = (uint8_t)(address >> 16);
    payload[1] = (uint8_t)(address >> 8);
    payload[2] = (uint8_t)address;
    memcpy(&payload[3], data, length);
    if (!write_enable(address))
        return false;
    if (!spi_command(FLASH_PP, payload, NULL,
                     (uint16_t)(length + 3u))) {
        set_diagnostic(FLASH_DIAG_PAGE_COMMAND, address, 0, 0);
        return false;
    }
    if (!wait_flash_status(
            FLASH_STATUS_WIP | FLASH_STATUS_WEL, 0, 1000)) {
        set_diagnostic(FLASH_DIAG_PAGE_STATUS, address, 0,
                       flash_diagnostic.status);
        return false;
    }

    uint8_t read_result[FLASH_PAGE_SIZE];
    if (!read_flash(address, read_result, length))
        return false;
    for (uint16_t index = 0; index < length; ++index) {
        if (read_result[index] != data[index]) {
            set_diagnostic(FLASH_DIAG_VERIFY_DATA, address + index,
                           data[index], read_result[index]);
            return false;
        }
    }
    return true;
}

static bool flush_page(void)
{
    if (!flash_page_used)
        return true;
    if ((flash_address & (FLASH_ERASE_SIZE - 1u)) == 0 &&
        !erase_block(flash_address))
        return false;
    if (!program_page(flash_address, flash_page, flash_page_used))
        return false;
    flash_address += flash_page_used;
    flash_page_used = 0;
    return true;
}

static bool identify_flash(uint32_t *jedec_id, uint8_t *status)
{
    uint8_t reset_bytes[8];
    uint8_t id[4];
    memset(reset_bytes, 0xff, sizeof(reset_bytes));
    if (!spi_command(0xff, reset_bytes, NULL, sizeof(reset_bytes)) ||
        !spi_command(FLASH_RSTEN, NULL, NULL, 0) ||
        !spi_command(FLASH_RST, NULL, NULL, 0))
        return false;
    vTaskDelay(pdMS_TO_TICKS(1));
    if (!spi_command(FLASH_POWER_UP, NULL, NULL, 0))
        return false;
    vTaskDelay(pdMS_TO_TICKS(1));
    if (!spi_command(FLASH_RDID, NULL, id, sizeof(id)) ||
        !read_flash_status(status))
        return false;

    *jedec_id = ((uint32_t)id[0] << 16) |
                ((uint32_t)id[1] << 8) | id[2];
    if (*jedec_id == 0 || *jedec_id == UINT32_C(0xffffff)) {
        set_diagnostic(FLASH_DIAG_IDENTIFY, read_fpga_status(), 0, *status);
        return false;
    }
    return true;
}

static void reload_and_close(void)
{
    jtag_command_u08(GOWIN_COMMAND_RECONFIG);
    jtag_command_u08(GOWIN_COMMAND_NOOP);
    jtag_close();
}

bool nanoql_flash_probe(uint32_t *jedec_id, uint8_t *status)
{
    if (!jedec_id || !status || flash_active || !prepare_spi_bridge())
        return false;
    memset(&flash_diagnostic, 0, sizeof(flash_diagnostic));
    bool valid = identify_flash(jedec_id, status);
    if (valid)
        valid = write_enable(0) && write_disable(0);
    if (valid)
        valid = read_flash_status(status);
    reload_and_close();
    return valid;
}

bool nanoql_flash_begin(uint32_t length, uint32_t *jedec_id, uint8_t *status)
{
    memset(&flash_diagnostic, 0, sizeof(flash_diagnostic));
    if (!length || !jedec_id || !status || flash_active ||
        !prepare_spi_bridge())
        return false;
    if (!identify_flash(jedec_id, status)) {
        reload_and_close();
        return false;
    }

    uint8_t capacity_code = (uint8_t)(*jedec_id);
    uint32_t capacity = capacity_code < 32u ? (UINT32_C(1) << capacity_code) : 0;
    if (!capacity || length > capacity || (*status & FLASH_STATUS_BP) != 0) {
        debugf("NanoQL Flash: rejected JEDEC %06lx status %02x length %lu",
               (unsigned long)*jedec_id, *status, (unsigned long)length);
        reload_and_close();
        return false;
    }

    flash_length = length;
    flash_address = 0;
    flash_page_used = 0;
    flash_active = true;
    return true;
}

bool nanoql_flash_write(const uint8_t *data, uint16_t length)
{
    if (!flash_active || !data || !length ||
        flash_address + flash_page_used + length > flash_length)
        return false;

    while (length) {
        uint16_t available = (uint16_t)(FLASH_PAGE_SIZE - flash_page_used);
        uint16_t amount = length < available ? length : available;
        memcpy(&flash_page[flash_page_used], data, amount);
        flash_page_used += amount;
        data += amount;
        length -= amount;
        if (flash_page_used == FLASH_PAGE_SIZE && !flush_page())
            return false;
    }
    return true;
}

bool nanoql_flash_finish(void)
{
    if (!flash_active || flash_address + flash_page_used != flash_length)
        return false;
    bool valid = flush_page();
    flash_active = false;
    reload_and_close();
    return valid;
}

void nanoql_flash_abort(void)
{
    if (!flash_active)
        return;
    flash_active = false;
    flash_page_used = 0;
    reload_and_close();
}

void nanoql_flash_get_diagnostic(nanoql_flash_diagnostic_t *diagnostic)
{
    if (diagnostic)
        *diagnostic = flash_diagnostic;
}
