#include "nanoql_screenshot.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "bflb_mtimer.h"
#include "../ff.h"
#include "../mcu_hw.h"
#include "../sdc.h"

#define LINK_TARGET 4
#define SCREEN_START 0x11
#define SCREEN_INFO 0x12
#define SCREEN_END 0x13
#define READ_START 0x06
#define READ_RESULT 0x07
#define SCREEN_BASE 0x7d8000u
#define OUTPUT_WIDTH 1024u
#define OUTPUT_HEIGHT 698u
#define SOURCE_STRIDE 128u
#define ROW_BYTES (1u + OUTPUT_WIDTH * 3u)
#define SCREEN_ROOT "/sd/NanoQL/Screenshots"

static uint8_t source_row[SOURCE_STRIDE];
static uint8_t png_row[ROW_BYTES];

static const uint8_t palette[8][3] = {
    {0x00, 0x00, 0x00}, {0x20, 0x40, 0xd0},
    {0xd0, 0x20, 0x20}, {0xd0, 0x30, 0xd0},
    {0x20, 0xb0, 0x40}, {0x20, 0xc0, 0xc0},
    {0xe0, 0xd0, 0x40}, {0xff, 0xff, 0xff},
};
static const uint8_t mode4_palette[4] = {0, 2, 4, 7};

static void link_begin(uint8_t command)
{
    mcu_hw_spi_begin();
    (void)mcu_hw_spi_tx_u08(LINK_TARGET);
    (void)mcu_hw_spi_tx_u08(command);
}

static void link_command(uint8_t command)
{
    link_begin(command);
    mcu_hw_spi_end();
}

static bool screenshot_info(uint8_t *flags)
{
    uint8_t response[8];
    link_begin(SCREEN_INFO);
    for (unsigned index = 0; index < sizeof(response); ++index)
        response[index] = mcu_hw_spi_tx_u08(0);
    mcu_hw_spi_end();
    for (unsigned index = 0; index + 4 < sizeof(response); ++index) {
        if (response[index] == 'S' && response[index + 1] == 'C' &&
            response[index + 2] == '1') {
            *flags = response[index + 4];
            return response[index + 3] != 0;
        }
    }
    return false;
}

static bool link_idle(void)
{
    uint8_t response[12];
    link_begin(0x00);
    for (unsigned index = 0; index < sizeof(response); ++index)
        response[index] = mcu_hw_spi_tx_u08(0);
    mcu_hw_spi_end();
    for (unsigned index = 0; index + 4 < sizeof(response); ++index)
        if (memcmp(&response[index], "NQL1", 4) == 0)
            return (response[index + 4] & 0x02) == 0;
    return false;
}

static bool read_source(uint32_t address, uint8_t *output, unsigned length)
{
    while (length != 0) {
        unsigned count = length > 8 ? 8 : length;
        link_begin(READ_START);
        (void)mcu_hw_spi_tx_u08((uint8_t)(address >> 16));
        (void)mcu_hw_spi_tx_u08((uint8_t)(address >> 8));
        (void)mcu_hw_spi_tx_u08((uint8_t)address);
        (void)mcu_hw_spi_tx_u08((uint8_t)count);
        mcu_hw_spi_end();

        bool idle = false;
        for (unsigned attempt = 0; attempt < 100; ++attempt) {
            if (link_idle()) {
                idle = true;
                break;
            }
            bflb_mtimer_delay_ms(1);
        }
        if (!idle)
            return false;

        link_begin(READ_RESULT);
        for (unsigned index = 0; index < count; ++index)
            output[index] = mcu_hw_spi_tx_u08(0);
        mcu_hw_spi_end();
        output += count;
        address += count;
        length -= count;
    }
    return true;
}

static uint32_t crc32_update(uint32_t crc, const uint8_t *data, unsigned length)
{
    while (length--) {
        crc ^= *data++;
        for (unsigned bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ ((crc & 1) ? UINT32_C(0xedb88320) : 0);
    }
    return crc;
}

static uint32_t adler32_update(uint32_t adler, const uint8_t *data, unsigned length)
{
    uint32_t a = adler & 0xffff;
    uint32_t b = adler >> 16;
    while (length--) {
        a = (a + *data++) % 65521u;
        b = (b + a) % 65521u;
    }
    return (b << 16) | a;
}

static bool write_bytes(FIL *file, const void *data, unsigned length)
{
    if (length == 0)
        return true;
    UINT written = 0;
    return f_write(file, data, length, &written) == FR_OK && written == length;
}

static void put_be32(uint8_t output[4], uint32_t value)
{
    output[0] = (uint8_t)(value >> 24);
    output[1] = (uint8_t)(value >> 16);
    output[2] = (uint8_t)(value >> 8);
    output[3] = (uint8_t)value;
}

static bool write_chunk(FIL *file, const char type[4],
                        const uint8_t *data, uint32_t length)
{
    uint8_t header[8], crc_bytes[4];
    put_be32(header, length);
    memcpy(&header[4], type, 4);
    uint32_t crc = crc32_update(UINT32_C(0xffffffff),
                                (const uint8_t *)type, 4);
    crc = crc32_update(crc, data, length) ^ UINT32_C(0xffffffff);
    put_be32(crc_bytes, crc);
    return write_bytes(file, header, sizeof(header)) &&
           write_bytes(file, data, length) &&
           write_bytes(file, crc_bytes, sizeof(crc_bytes));
}

static void append_pixel(unsigned *at, uint8_t color)
{
    memcpy(&png_row[*at], palette[color], 3);
    memcpy(&png_row[*at + 3], palette[color], 3);
    *at += 6;
}

static void decode_row(uint8_t flags)
{
    unsigned at = 1;
    bool flash_latch = false;
    uint8_t flash_color = 0;
    png_row[0] = 0;
    if (flags & 2) {
        memset(&png_row[1], 0, ROW_BYTES - 1);
        return;
    }
    for (unsigned offset = 0; offset < SOURCE_STRIDE; offset += 2) {
        uint8_t high = source_row[offset], low = source_row[offset + 1];
        if (flags & 1) {
            for (int shift = 6; shift >= 0; shift -= 2) {
                uint8_t color = (uint8_t)((((high >> (shift + 1)) & 1) << 2) |
                    (((low >> (shift + 1)) & 1) << 1) | ((low >> shift) & 1));
                uint8_t displayed = flash_latch && (flags & 4) ?
                                    flash_color : color;
                append_pixel(&at, displayed);
                append_pixel(&at, displayed);
                if ((high >> shift) & 1) {
                    flash_latch = !flash_latch;
                    flash_color = color;
                }
            }
        } else {
            for (int shift = 7; shift >= 0; --shift) {
                uint8_t color = (uint8_t)((((high >> shift) & 1) << 1) |
                                           ((low >> shift) & 1));
                append_pixel(&at, mode4_palette[color]);
            }
        }
    }
}

static bool write_png(FIL *file, uint8_t flags)
{
    static const uint8_t signature[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    uint8_t ihdr[13] = {0};
    put_be32(&ihdr[0], OUTPUT_WIDTH);
    put_be32(&ihdr[4], OUTPUT_HEIGHT);
    ihdr[8] = 8;
    ihdr[9] = 2;
    uint32_t idat_length = 2 + OUTPUT_HEIGHT * (5 + ROW_BYTES) + 4;
    uint8_t idat_header[8];
    put_be32(idat_header, idat_length);
    memcpy(&idat_header[4], "IDAT", 4);
    uint32_t idat_crc = crc32_update(UINT32_C(0xffffffff),
                                     (const uint8_t *)"IDAT", 4);
    uint32_t adler = 1;
    uint8_t zlib_header[2] = {0x78, 0x01};
    idat_crc = crc32_update(idat_crc, zlib_header, sizeof(zlib_header));
    if (!write_bytes(file, signature, sizeof(signature)) ||
        !write_chunk(file, "IHDR", ihdr, sizeof(ihdr)) ||
        !write_bytes(file, idat_header, sizeof(idat_header)) ||
        !write_bytes(file, zlib_header, sizeof(zlib_header)))
        return false;

    unsigned cached_source_y = 256;
    for (unsigned y = 0; y < OUTPUT_HEIGHT; ++y) {
        unsigned source_y = y * 256u / OUTPUT_HEIGHT;
        if (source_y != cached_source_y) {
            if (!read_source(SCREEN_BASE + source_y * SOURCE_STRIDE,
                             source_row, sizeof(source_row)))
                return false;
            decode_row(flags);
            cached_source_y = source_y;
        }
        uint16_t length = ROW_BYTES;
        uint16_t inverse = (uint16_t)~length;
        uint8_t block[5] = {
            y + 1 == OUTPUT_HEIGHT ? 1 : 0,
            (uint8_t)length, (uint8_t)(length >> 8),
            (uint8_t)inverse, (uint8_t)(inverse >> 8),
        };
        idat_crc = crc32_update(idat_crc, block, sizeof(block));
        idat_crc = crc32_update(idat_crc, png_row, sizeof(png_row));
        adler = adler32_update(adler, png_row, sizeof(png_row));
        if (!write_bytes(file, block, sizeof(block)) ||
            !write_bytes(file, png_row, sizeof(png_row)))
            return false;
    }
    uint8_t adler_bytes[4], crc_bytes[4];
    put_be32(adler_bytes, adler);
    idat_crc = crc32_update(idat_crc, adler_bytes, sizeof(adler_bytes)) ^
               UINT32_C(0xffffffff);
    put_be32(crc_bytes, idat_crc);
    return write_bytes(file, adler_bytes, sizeof(adler_bytes)) &&
           write_bytes(file, crc_bytes, sizeof(crc_bytes)) &&
           write_chunk(file, "IEND", NULL, 0);
}

const char *nanoql_screenshot_save(void)
{
    static char result[96];
    uint8_t flags = 0;
    link_command(SCREEN_START);
    bool ready = false;
    for (unsigned attempt = 0; attempt < 500; ++attempt) {
        if (screenshot_info(&flags)) {
            ready = true;
            break;
        }
        bflb_mtimer_delay_ms(10);
    }
    if (!ready) {
        link_command(SCREEN_END);
        return "FPGA screenshot unavailable.";
    }

    sdc_lock();
    FRESULT status = f_mkdir("/sd/NanoQL");
    if (status == FR_OK || status == FR_EXIST)
        status = f_mkdir(SCREEN_ROOT);
    char path[96] = {0};
    FIL file;
    bool opened = false;
    if (status == FR_OK || status == FR_EXIST) {
        for (unsigned number = 1; number <= 9999; ++number) {
            snprintf(path, sizeof(path), SCREEN_ROOT "/NanoQL%04u.png", number);
            status = f_open(&file, path, FA_CREATE_NEW | FA_WRITE);
            if (status == FR_OK) {
                opened = true;
                break;
            }
            if (status != FR_EXIST)
                break;
        }
    }
    bool written = opened && write_png(&file, flags);
    if (opened) {
        if (written)
            written = f_sync(&file) == FR_OK;
        if (f_close(&file) != FR_OK)
            written = false;
        if (!written)
            (void)f_unlink(path);
    }
    sdc_unlock();
    link_command(SCREEN_END);
    if (!written)
        return "Unable to write screenshot.";
    snprintf(result, sizeof(result), "[OK] Saved %s", strrchr(path, '/') + 1);
    return result;
}
