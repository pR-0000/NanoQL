#include "nanoql_drive.h"

#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "FreeRTOS.h"

#include "../ff.h"
#include "../inifile.h"
#include "../sdc.h"

#define QLAY_SECTOR_COUNT 255
#define QLAY_SECTOR_SIZE 686
#define QL_DATA_SIZE 512
#define QL_HEADER_SIZE 64
#define QL_MAX_FILES 126
#define QL_FREE_SECTOR 0xfd
#define QL_DAMAGED_SECTOR 0xff
#define QL_MAP_FILE 0xf8

#define NANOQL_MDV_TARGET "/sd/NanoQL/Drive1/MDV1.mdv"
#define NANOQL_MDV_TEMP "/sd/NQLMDV.TMP"
#define NANOQL_MDV_BACKUP "/sd/NQLMDV.BAK"

typedef struct {
    char path[FF_LFN_BUF + 1];
    char name[37];
    uint32_t size;
    uint32_t data_space;
    bool executable;
} nanoql_file_t;

typedef struct {
    nanoql_file_t *files;
    unsigned file_count;
    uint8_t map_file[QLAY_SECTOR_COUNT];
    uint8_t map_block[QLAY_SECTOR_COUNT];
    uint8_t current_sector;
    uint8_t medium_name[10];
    uint16_t medium_id;
} nanoql_builder_t;

static int ascii_case_compare(const char *left, const char *right)
{
    while (*left && *right) {
        int a = tolower((unsigned char)*left++);
        int b = tolower((unsigned char)*right++);
        if (a != b)
            return a - b;
    }
    return (unsigned char)*left - (unsigned char)*right;
}

static int compare_files(const void *left, const void *right)
{
    const nanoql_file_t *a = left;
    const nanoql_file_t *b = right;
    return ascii_case_compare(a->name, b->name);
}

static bool path_is_generated_file(const char *path)
{
    return ascii_case_compare(path, NANOQL_MDV_TARGET) == 0 ||
           ascii_case_compare(path, NANOQL_MDV_TEMP) == 0 ||
           ascii_case_compare(path, NANOQL_MDV_BACKUP) == 0;
}

static int make_directory_locked(const char *path)
{
    FRESULT result = f_mkdir(path);
    return result == FR_OK || result == FR_EXIST ? NANOQL_DRIVE_OK
                                                  : NANOQL_DRIVE_IO;
}

static int prepare_root_locked(void)
{
    int result = make_directory_locked("/sd/NanoQL");
    if (result == NANOQL_DRIVE_OK)
        result = make_directory_locked(NANOQL_MDV_SOURCE_ROOT);
    if (result == NANOQL_DRIVE_OK)
        result = make_directory_locked("/sd/NanoQL/Drive1");
    return result;
}

int nanoql_drive_prepare_root(void)
{
    sdc_lock();
    int result = prepare_root_locked();
    sdc_unlock();
    return result;
}

static int make_qdos_name(const char *relative, char output[37])
{
    size_t length = strlen(relative);
    if (length == 0 || length > 36)
        return NANOQL_DRIVE_INVALID_NAME;

    for (size_t index = 0; index < length; ++index) {
        unsigned char value = (unsigned char)relative[index];
        if (value < 0x20 || value > 0x7e)
            return NANOQL_DRIVE_INVALID_NAME;
        output[index] = value == '/' || value == '.' ? '_' : (char)value;
    }
    output[length] = '\0';
    return NANOQL_DRIVE_OK;
}

static int inspect_file_locked(nanoql_file_t *file)
{
    file->executable = false;
    file->data_space = 0;
    if (file->size < 8)
        return NANOQL_DRIVE_OK;

    FIL input;
    if (f_open(&input, file->path, FA_READ) != FR_OK)
        return NANOQL_DRIVE_IO;
    uint8_t trailer[8];
    UINT read = 0;
    FRESULT result = f_lseek(&input, file->size - sizeof(trailer));
    if (result == FR_OK)
        result = f_read(&input, trailer, sizeof(trailer), &read);
    (void)f_close(&input);
    if (result != FR_OK || read != sizeof(trailer))
        return NANOQL_DRIVE_IO;

    if (memcmp(trailer, "XTcc", 4) == 0) {
        file->executable = true;
        file->data_space = ((uint32_t)trailer[4] << 24) |
                           ((uint32_t)trailer[5] << 16) |
                           ((uint32_t)trailer[6] << 8) | trailer[7];
    }
    return NANOQL_DRIVE_OK;
}

static int collect_files_locked(
    nanoql_builder_t *builder, const char *directory, const char *relative,
    unsigned depth)
{
    if (depth > 8)
        return NANOQL_DRIVE_INVALID_NAME;

    DIR handle;
    if (f_opendir(&handle, directory) != FR_OK)
        return NANOQL_DRIVE_IO;

    int status = NANOQL_DRIVE_OK;
    for (;;) {
        FILINFO information;
        FRESULT result = f_readdir(&handle, &information);
        if (result != FR_OK) {
            status = NANOQL_DRIVE_IO;
            break;
        }
        if (information.fname[0] == '\0')
            break;
        if ((information.fattrib & (AM_HID | AM_SYS)) != 0 ||
            strcmp(information.fname, ".") == 0 ||
            strcmp(information.fname, "..") == 0)
            continue;

        char path[FF_LFN_BUF + 1];
        char child_relative[FF_LFN_BUF + 1];
        int path_length = snprintf(
            path, sizeof(path), "%s/%s", directory, information.fname);
        int relative_length = relative[0]
            ? snprintf(child_relative, sizeof(child_relative), "%s/%s",
                       relative, information.fname)
            : snprintf(child_relative, sizeof(child_relative), "%s",
                       information.fname);
        if (path_length < 0 || path_length >= (int)sizeof(path) ||
            relative_length < 0 ||
            relative_length >= (int)sizeof(child_relative)) {
            status = NANOQL_DRIVE_INVALID_NAME;
            break;
        }

        if ((information.fattrib & AM_DIR) != 0) {
            status = collect_files_locked(
                builder, path, child_relative, depth + 1);
            if (status != NANOQL_DRIVE_OK)
                break;
            continue;
        }
        if (path_is_generated_file(path))
            continue;
        if (information.fsize > UINT32_MAX) {
            status = NANOQL_DRIVE_FULL;
            break;
        }
        if (builder->file_count >= QL_MAX_FILES) {
            status = NANOQL_DRIVE_TOO_MANY_FILES;
            break;
        }

        nanoql_file_t *file = &builder->files[builder->file_count];
        memcpy(file->path, path, (size_t)path_length + 1);
        file->size = (uint32_t)information.fsize;
        status = make_qdos_name(child_relative, file->name);
        if (status == NANOQL_DRIVE_OK)
            status = inspect_file_locked(file);
        if (status != NANOQL_DRIVE_OK)
            break;
        builder->file_count++;
    }
    (void)f_closedir(&handle);
    return status;
}

static uint32_t crc32_continue(
    uint32_t previous, const uint8_t *data, size_t length)
{
    uint32_t value = previous ^ UINT32_C(0xffffffff);
    while (length--) {
        value ^= *data++;
        for (unsigned bit = 0; bit < 8; ++bit)
            value = (value >> 1) ^
                    ((value & 1) ? UINT32_C(0xedb88320) : 0);
    }
    return value ^ UINT32_C(0xffffffff);
}

static int compute_medium_id_locked(nanoql_builder_t *builder)
{
    uint32_t fingerprint = crc32_continue(0, builder->medium_name, 10);
    uint8_t buffer[512];

    for (unsigned index = 0; index < builder->file_count; ++index) {
        nanoql_file_t *file = &builder->files[index];
        fingerprint = crc32_continue(
            fingerprint, (const uint8_t *)file->name, strlen(file->name));
        FIL input;
        if (f_open(&input, file->path, FA_READ) != FR_OK)
            return NANOQL_DRIVE_IO;
        FRESULT result = FR_OK;
        for (;;) {
            UINT read = 0;
            result = f_read(&input, buffer, sizeof(buffer), &read);
            if (result != FR_OK || read == 0)
                break;
            fingerprint = crc32_continue(fingerprint, buffer, read);
        }
        (void)f_close(&input);
        if (result != FR_OK)
            return NANOQL_DRIVE_IO;
    }
    builder->medium_id = (uint16_t)fingerprint;
    return NANOQL_DRIVE_OK;
}

static void write_be16(uint8_t *output, uint16_t value)
{
    output[0] = (uint8_t)(value >> 8);
    output[1] = (uint8_t)value;
}

static void write_be32(uint8_t *output, uint32_t value)
{
    output[0] = (uint8_t)(value >> 24);
    output[1] = (uint8_t)(value >> 16);
    output[2] = (uint8_t)(value >> 8);
    output[3] = (uint8_t)value;
}

static void qdos_header(
    uint8_t output[QL_HEADER_SIZE], const nanoql_file_t *file,
    uint32_t total_length)
{
    memset(output, 0, QL_HEADER_SIZE);
    write_be32(output, total_length);
    if (file != NULL) {
        output[5] = file->executable ? 1 : 0;
        if (file->executable)
            write_be32(&output[6], file->data_space);
        uint16_t name_length = (uint16_t)strlen(file->name);
        write_be16(&output[14], name_length);
        memcpy(&output[16], file->name, name_length);
    }
}

static int allocate_sector(nanoql_builder_t *builder, int after)
{
    int candidate = after;
    for (unsigned count = 0; count < QLAY_SECTOR_COUNT; ++count) {
        if (builder->map_file[candidate] == QL_FREE_SECTOR)
            return candidate;
        candidate = candidate == 0 ? QLAY_SECTOR_COUNT - 1 : candidate - 1;
    }
    return -1;
}

static int allocate_streams(nanoql_builder_t *builder)
{
    memset(builder->map_file, QL_FREE_SECTOR, sizeof(builder->map_file));
    memset(builder->map_block, 0, sizeof(builder->map_block));
    builder->map_file[0] = QL_MAP_FILE;
    builder->map_file[254] = QL_DAMAGED_SECTOR;
    builder->current_sector = 245;

    for (unsigned file_number = 0;
         file_number <= builder->file_count; ++file_number) {
        uint32_t length = file_number == 0
            ? (uint32_t)(builder->file_count + 1) * QL_HEADER_SIZE
            : builder->files[file_number - 1].size + QL_HEADER_SIZE;
        uint32_t blocks = (length + QL_DATA_SIZE - 1) / QL_DATA_SIZE;
        for (uint32_t block = 0; block < blocks; ++block) {
            int sector = allocate_sector(builder, builder->current_sector);
            if (sector < 0 || block > UINT8_MAX)
                return NANOQL_DRIVE_FULL;
            builder->map_file[sector] = (uint8_t)file_number;
            builder->map_block[sector] = (uint8_t)block;
            int next = allocate_sector(
                builder, (sector + QLAY_SECTOR_COUNT - 13) % QLAY_SECTOR_COUNT);
            if (next < 0)
                return NANOQL_DRIVE_FULL;
            builder->current_sector = (uint8_t)next;
        }
    }
    return NANOQL_DRIVE_OK;
}

static void copy_header_range(
    uint8_t payload[QL_DATA_SIZE], uint32_t payload_offset,
    uint32_t header_offset, const uint8_t header[QL_HEADER_SIZE])
{
    uint32_t payload_end = payload_offset + QL_DATA_SIZE;
    uint32_t header_end = header_offset + QL_HEADER_SIZE;
    uint32_t start = payload_offset > header_offset ? payload_offset : header_offset;
    uint32_t end = payload_end < header_end ? payload_end : header_end;
    if (start < end)
        memcpy(&payload[start - payload_offset], &header[start - header_offset],
               end - start);
}

static int directory_payload(
    nanoql_builder_t *builder, uint8_t block,
    uint8_t payload[QL_DATA_SIZE])
{
    memset(payload, 0, QL_DATA_SIZE);
    uint32_t payload_offset = (uint32_t)block * QL_DATA_SIZE;
    uint8_t header[QL_HEADER_SIZE];
    qdos_header(
        header, NULL, (uint32_t)(builder->file_count + 1) * QL_HEADER_SIZE);
    copy_header_range(payload, payload_offset, 0, header);
    for (unsigned index = 0; index < builder->file_count; ++index) {
        qdos_header(
            header, &builder->files[index],
            builder->files[index].size + QL_HEADER_SIZE);
        copy_header_range(
            payload, payload_offset, (uint32_t)(index + 1) * QL_HEADER_SIZE,
            header);
    }
    return NANOQL_DRIVE_OK;
}

static int file_payload_locked(
    nanoql_builder_t *builder, uint8_t file_number, uint8_t block,
    uint8_t payload[QL_DATA_SIZE])
{
    nanoql_file_t *file = &builder->files[file_number - 1];
    memset(payload, 0, QL_DATA_SIZE);
    uint32_t stream_offset = (uint32_t)block * QL_DATA_SIZE;
    uint8_t header[QL_HEADER_SIZE];
    qdos_header(header, file, file->size + QL_HEADER_SIZE);
    copy_header_range(payload, stream_offset, 0, header);

    uint32_t stream_end = stream_offset + QL_DATA_SIZE;
    if (stream_end <= QL_HEADER_SIZE || stream_offset >= file->size + QL_HEADER_SIZE)
        return NANOQL_DRIVE_OK;
    uint32_t data_start = stream_offset > QL_HEADER_SIZE
        ? stream_offset - QL_HEADER_SIZE : 0;
    uint32_t payload_start = stream_offset < QL_HEADER_SIZE
        ? QL_HEADER_SIZE - stream_offset : 0;
    uint32_t available = file->size - data_start;
    uint32_t wanted = QL_DATA_SIZE - payload_start;
    if (wanted > available)
        wanted = available;

    FIL input;
    if (f_open(&input, file->path, FA_READ) != FR_OK)
        return NANOQL_DRIVE_IO;
    FRESULT result = f_lseek(&input, data_start);
    UINT read = 0;
    if (result == FR_OK)
        result = f_read(&input, &payload[payload_start], wanted, &read);
    (void)f_close(&input);
    return result == FR_OK && read == wanted ? NANOQL_DRIVE_OK
                                              : NANOQL_DRIVE_IO;
}

static uint16_t ql_checksum(const uint8_t *data, size_t length)
{
    uint32_t value = 0x0f0f;
    while (length--)
        value += *data++;
    return (uint16_t)value;
}

static void write_checksum_le(uint8_t *output, const uint8_t *data, size_t length)
{
    uint16_t value = ql_checksum(data, length);
    output[0] = (uint8_t)value;
    output[1] = (uint8_t)(value >> 8);
}

static int make_sector_locked(
    nanoql_builder_t *builder, uint8_t number,
    uint8_t sector[QLAY_SECTOR_SIZE])
{
    memset(sector, 0, QLAY_SECTOR_SIZE);
    sector[10] = 0xff;
    sector[11] = 0xff;
    sector[12] = 0xff;
    sector[13] = number;
    memcpy(&sector[14], builder->medium_name, 10);
    write_be16(&sector[24], builder->medium_id);
    write_checksum_le(&sector[26], &sector[12], 14);
    sector[38] = 0xff;
    sector[39] = 0xff;
    sector[40] = builder->map_file[number];
    sector[41] = builder->map_block[number];
    write_checksum_le(&sector[42], &sector[40], 2);
    sector[50] = 0xff;
    sector[51] = 0xff;

    uint8_t *payload = &sector[52];
    for (unsigned index = 0; index < QL_DATA_SIZE; ++index)
        payload[index] = (index & 1) ? 0x55 : 0xaa;

    int status = NANOQL_DRIVE_OK;
    uint8_t file_number = builder->map_file[number];
    if (number == 0) {
        for (unsigned index = 0; index < QLAY_SECTOR_COUNT; ++index) {
            payload[index * 2] = builder->map_file[index];
            payload[index * 2 + 1] = builder->map_block[index];
        }
        payload[510] = 1;
        payload[511] = builder->current_sector;
        sector[40] = 0x80;
        sector[41] = 0;
        write_checksum_le(&sector[42], &sector[40], 2);
    } else if (file_number == 0) {
        status = directory_payload(builder, builder->map_block[number], payload);
    } else if (file_number <= builder->file_count) {
        status = file_payload_locked(
            builder, file_number, builder->map_block[number], payload);
    }
    if (status != NANOQL_DRIVE_OK)
        return status;

    write_checksum_le(&sector[564], payload, QL_DATA_SIZE);
    for (unsigned index = 0; index < 84; ++index)
        sector[566 + index] = (index & 1) ? 0x55 : 0xaa;
    sector[650] = 0x19;
    sector[651] = 0x3b;
    memset(&sector[652], 'Z', 34);
    return NANOQL_DRIVE_OK;
}

static int write_image_locked(nanoql_builder_t *builder)
{
    FIL output;
    if (f_open(&output, NANOQL_MDV_TEMP, FA_CREATE_ALWAYS | FA_WRITE) != FR_OK)
        return NANOQL_DRIVE_IO;

    uint8_t *sector = pvPortMalloc(QLAY_SECTOR_SIZE);
    if (sector == NULL) {
        (void)f_close(&output);
        (void)f_unlink(NANOQL_MDV_TEMP);
        return NANOQL_DRIVE_MEMORY;
    }

    int status = NANOQL_DRIVE_OK;
    for (unsigned physical = 0; physical < QLAY_SECTOR_COUNT; ++physical) {
        uint8_t number = physical == 0 ? 0 : (uint8_t)(QLAY_SECTOR_COUNT - physical);
        status = make_sector_locked(builder, number, sector);
        if (status != NANOQL_DRIVE_OK)
            break;
        UINT written = 0;
        FRESULT result = f_write(&output, sector, QLAY_SECTOR_SIZE, &written);
        if (result != FR_OK || written != QLAY_SECTOR_SIZE) {
            status = NANOQL_DRIVE_IO;
            break;
        }
    }
    if (status == NANOQL_DRIVE_OK && f_sync(&output) != FR_OK)
        status = NANOQL_DRIVE_IO;
    (void)f_close(&output);
    vPortFree(sector);
    if (status != NANOQL_DRIVE_OK)
        (void)f_unlink(NANOQL_MDV_TEMP);
    return status;
}

static int generate_image_locked(nanoql_builder_t *builder, const char *source)
{
    int status = collect_files_locked(builder, source, "", 0);
    if (status != NANOQL_DRIVE_OK)
        return status;
    qsort(builder->files, builder->file_count, sizeof(builder->files[0]),
          compare_files);
    for (unsigned index = 1; index < builder->file_count; ++index) {
        if (ascii_case_compare(
                builder->files[index - 1].name,
                builder->files[index].name) == 0)
            return NANOQL_DRIVE_DUPLICATE_NAME;
    }
    status = compute_medium_id_locked(builder);
    if (status == NANOQL_DRIVE_OK)
        status = allocate_streams(builder);
    if (status == NANOQL_DRIVE_OK)
        status = write_image_locked(builder);
    return status;
}

int nanoql_drive_build_folder(const char *source)
{
    if (source == NULL || strncmp(source, "/sd/", 4) != 0)
        return NANOQL_DRIVE_INVALID_NAME;
    if (sdc_image_open(2, NULL) != 0)
        return NANOQL_DRIVE_IO;

    nanoql_builder_t *builder = pvPortMalloc(sizeof(*builder));
    if (builder == NULL)
        return NANOQL_DRIVE_MEMORY;
    memset(builder, 0, sizeof(*builder));
    builder->files = pvPortMalloc(sizeof(nanoql_file_t) * QL_MAX_FILES);
    if (builder->files == NULL) {
        vPortFree(builder);
        return NANOQL_DRIVE_MEMORY;
    }
    memcpy(builder->medium_name, "NANOQL    ", 10);

    sdc_lock();
    int status = prepare_root_locked();
    (void)f_unlink(NANOQL_MDV_TEMP);
    if (status == NANOQL_DRIVE_OK)
        status = generate_image_locked(builder, source);

    bool backup_created = false;
    if (status == NANOQL_DRIVE_OK) {
        (void)f_unlink(NANOQL_MDV_BACKUP);
        FILINFO information;
        FRESULT existing = f_stat(NANOQL_MDV_TARGET, &information);
        if (existing == FR_OK) {
            if ((information.fattrib & AM_DIR) != 0 ||
                f_rename(NANOQL_MDV_TARGET, NANOQL_MDV_BACKUP) != FR_OK)
                status = NANOQL_DRIVE_IO;
            else
                backup_created = true;
        } else if (existing != FR_NO_FILE && existing != FR_NO_PATH) {
            status = NANOQL_DRIVE_IO;
        }
    }
    if (status == NANOQL_DRIVE_OK &&
        f_rename(NANOQL_MDV_TEMP, NANOQL_MDV_TARGET) != FR_OK) {
        status = NANOQL_DRIVE_IO;
        if (backup_created)
            (void)f_rename(NANOQL_MDV_BACKUP, NANOQL_MDV_TARGET);
    }
    sdc_unlock();

    vPortFree(builder->files);
    vPortFree(builder);

    if (status == NANOQL_DRIVE_OK) {
        char image_name[] = "MDV1.mdv";
        sdc_set_cwd(2, "/sd/NanoQL/Drive1");
        if (sdc_image_open(2, image_name) != 0) {
            sdc_lock();
            (void)f_unlink(NANOQL_MDV_TARGET);
            if (backup_created)
                (void)f_rename(NANOQL_MDV_BACKUP, NANOQL_MDV_TARGET);
            sdc_unlock();
            if (backup_created)
                (void)sdc_image_open(2, image_name);
            return NANOQL_DRIVE_MOUNT_FAILED;
        }
        sdc_lock();
        if (backup_created)
            (void)f_unlink(NANOQL_MDV_BACKUP);
        sdc_unlock();
        inifile_write("nanoql.ini");
        return NANOQL_DRIVE_OK;
    }

    sdc_lock();
    (void)f_unlink(NANOQL_MDV_TEMP);
    sdc_unlock();
    char image_name[] = "MDV1.mdv";
    sdc_set_cwd(2, "/sd/NanoQL/Drive1");
    (void)sdc_image_open(2, image_name);
    return status;
}

const char *nanoql_drive_result_text(int result)
{
    switch (result) {
    case NANOQL_DRIVE_OK:
        return "MDV1 is ready.";
    case NANOQL_DRIVE_MEMORY:
        return "Not enough BL616 memory.";
    case NANOQL_DRIVE_TOO_MANY_FILES:
        return "More than 126 files.";
    case NANOQL_DRIVE_INVALID_NAME:
        return "Use short ASCII file names.";
    case NANOQL_DRIVE_DUPLICATE_NAME:
        return "Two QL names are identical.";
    case NANOQL_DRIVE_FULL:
        return "Files do not fit on MDV1.";
    case NANOQL_DRIVE_MOUNT_FAILED:
        return "MDV1 could not be mounted.";
    default:
        return "microSD read/write failed.";
    }
}
