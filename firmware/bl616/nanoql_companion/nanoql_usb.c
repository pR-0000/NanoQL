/*
 * NanoQL development-mode selector and USB CDC to FPGA SPI bridge.
 *
 * S1 is sampled through the standard FPGA Companion BUTTONS command. The
 * autonomous USB host remains the default; S1 can switch it to CDC at boot
 * or later without resetting the FPGA.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <FreeRTOS.h>
#include "task.h"
#include "portmacro.h"

#include "bflb_irq.h"
#include "bflb_mtimer.h"
#include "bflb_name.h"
#include "bflb_core.h"
#include "board.h"
#include "usbd_core.h"
#include "usbd_cdc_acm.h"
#include "usbh_core.h"

#include "../debug.h"
#include "../gowin.h"
#include "../inifile.h"
#include "../mcu_hw.h"
#include "../menu.h"
#include "../osd.h"
#include "../sdc.h"
#include "../spi.h"
#include "../sysctrl.h"
#include "nanoql_usb.h"

#define USB_BUS_ID 0
#define CDC_IN_EP  0x81
#define CDC_OUT_EP 0x02
#define CDC_INT_EP 0x83
#ifdef CONFIG_USB_HS
#define CDC_MAX_MPS 512
#else
#define CDC_MAX_MPS 64
#endif

#define NANOQL_USB_VID 0xffff
#define NANOQL_USB_PID 0x4e51
#define NANOQL_PROTOCOL_VERSION 1
#define NANOQL_MAX_PAYLOAD 245
#define NANOQL_SPI_MAX_PAYLOAD 17
#if NANOQL_SPI_MAX_PAYLOAD < 17
#error "NanoQL status and diagnostics require 17 SPI payload bytes"
#endif
#define NANOQL_SPI_TARGET 4
#define NANOQL_S1_MASK 0x01
#define NANOQL_CMD_KEY 0x05
#define NANOQL_CMD_QDOS 0x04
#define NANOQL_CMD_FS_INFO 0xe0
#define NANOQL_CMD_FS_LIST_BEGIN 0xe1
#define NANOQL_CMD_FS_LIST_NEXT 0xe2
#define NANOQL_CMD_FS_PUT_BEGIN 0xe3
#define NANOQL_CMD_FS_PUT_DATA 0xe4
#define NANOQL_CMD_FS_PUT_COMMIT 0xe5
#define NANOQL_CMD_FS_GET_BEGIN 0xe6
#define NANOQL_CMD_FS_GET_DATA 0xe7
#define NANOQL_CMD_FS_GET_END 0xe8
#define NANOQL_CMD_FS_DELETE 0xe9
#define NANOQL_CMD_FS_MKDIR 0xea
#define NANOQL_CMD_FS_CANCEL 0xeb
#define NANOQL_CMD_FS_MDV_CONTROL 0xec
#define NANOQL_CMD_FPGA_BEGIN 0xf0
#define NANOQL_CMD_FPGA_DATA 0xf1
#define NANOQL_CMD_FPGA_PROGRAM 0xf2
#define NANOQL_CMD_FPGA_FLASH_BEGIN 0xf3
#define NANOQL_CMD_FPGA_FLASH_PROGRAM 0xf4
#define NANOQL_FPGA_MAX_SIZE (2u * 1024u * 1024u)

#define NANOQL_FS_ROOT CARD_MOUNTPOINT "/NanoQL/Drive1"
#define NANOQL_FS_TEMP CARD_MOUNTPOINT "/NQLTMP.BIN"
#define NANOQL_FS_BACKUP CARD_MOUNTPOINT "/NQLBAK.BIN"
#define NANOQL_FS_MAX_REMOTE_PATH 200
#define NANOQL_FS_FULL_PATH_SIZE \
    (sizeof(NANOQL_FS_ROOT) + NANOQL_FS_MAX_REMOTE_PATH + 1)
#define NANOQL_FS_CHUNK_SIZE 240

#define RX_RING_SIZE 2048
#define USB_CONFIG_SIZE (9 + CDC_ACM_DESCRIPTOR_LEN)

static TaskHandle_t link_task_handle;
static TaskHandle_t development_watch_task_handle;
static bool development_active;

extern TaskHandle_t com_task_handle;

static USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX uint8_t usb_read_buffer[512];
static USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX uint8_t usb_write_buffer[256];
static uint8_t rx_ring[RX_RING_SIZE];
static volatile uint16_t rx_head;
static volatile uint16_t rx_tail;
static volatile bool usb_ready;
static volatile bool usb_tx_busy;
static volatile bool usb_rx_reset_requested;
static bool fpga_upload_open;
static bool companion_suspended_for_upload;
static uint32_t fpga_upload_size;
static uint32_t fpga_upload_received;
static uint32_t fpga_upload_crc;
static uint32_t fpga_upload_expected_crc;
static bool return_to_companion_pending;
static bool microdrive_reset_pending;

enum nanoql_fs_session {
    NANOQL_FS_IDLE,
    NANOQL_FS_LISTING,
    NANOQL_FS_PUTTING,
    NANOQL_FS_GETTING
};

static enum nanoql_fs_session fs_session;
static FIL fs_file;
static DIR fs_directory;
static char fs_target_path[NANOQL_FS_FULL_PATH_SIZE];
static uint32_t fs_expected_size;
static uint32_t fs_expected_crc;
static uint32_t fs_received_size;
static uint32_t fs_received_crc;

static void fpga_upload_suspend_companion(void);
static void fpga_upload_resume_companion(void);

static const uint8_t device_descriptor[] = {
    USB_DEVICE_DESCRIPTOR_INIT(
        USB_2_0, 0xef, 0x02, 0x01,
        NANOQL_USB_VID, NANOQL_USB_PID, 0x0100, 0x01)
};

static const uint8_t config_descriptor[] = {
    USB_CONFIG_DESCRIPTOR_INIT(
        USB_CONFIG_SIZE, 0x02, 0x01, USB_CONFIG_BUS_POWERED, 100),
    CDC_ACM_DESCRIPTOR_INIT(
        0x00, CDC_INT_EP, CDC_OUT_EP, CDC_IN_EP, CDC_MAX_MPS, 0x02)
};

static const uint8_t device_qualifier_descriptor[] = {
    0x0a, USB_DESCRIPTOR_TYPE_DEVICE_QUALIFIER,
    0x00, 0x02, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00
};

static const char *string_descriptors[] = {
    (const char[]){0x09, 0x04},
    "NanoQL",
    "NanoQL Link",
    "NQL0001"
};

static const uint8_t *device_descriptor_callback(uint8_t speed)
{
    (void)speed;
    return device_descriptor;
}

static const uint8_t *config_descriptor_callback(uint8_t speed)
{
    (void)speed;
    return config_descriptor;
}

static const uint8_t *device_qualifier_descriptor_callback(uint8_t speed)
{
    (void)speed;
    return device_qualifier_descriptor;
}

static const char *string_descriptor_callback(uint8_t speed, uint8_t index)
{
    (void)speed;
    return index < 4 ? string_descriptors[index] : NULL;
}

static const struct usb_descriptor nanoql_descriptor = {
    .device_descriptor_callback = device_descriptor_callback,
    .config_descriptor_callback = config_descriptor_callback,
    .device_quality_descriptor_callback =
        device_qualifier_descriptor_callback,
    .string_descriptor_callback = string_descriptor_callback
};

bool nanoql_development_requested(void)
{
    bool fpga_ready = false;

    for (unsigned attempt = 0; attempt < 150; ++attempt) {
        if (sys_status_is_valid()) {
            fpga_ready = true;
            break;
        }
        bflb_mtimer_delay_ms(20);
    }

    if (!fpga_ready) {
        debugf("NanoQL: FPGA not ready, selecting autonomous USB mode");
        return false;
    }

    /* Live takeover is handled by development_watch_task. Sampling once
       keeps boot deterministic and lets a post-program reset return to the
       autonomous Companion immediately. */
    if (sys_get_buttons() & NANOQL_S1_MASK) {
        debugf("NanoQL: latched S1, selecting development CDC mode");
        return true;
    }

    debugf("NanoQL: no S1 request, selecting autonomous USB mode");
    return false;
}

bool nanoql_usb_is_active(void)
{
    return development_active;
}

static void prioritize_link_over_companion(void)
{
    TaskHandle_t task = com_task_handle;
    if (task == NULL || task == xTaskGetCurrentTaskHandle())
        return;

    /* mcu_hw_spi_begin/end serialize the shared FPGA SPI bus. Keep Companion
       alive for microSD and OSD service, below the CDC link priority. */
    vTaskPrioritySet(task, configMAX_PRIORITIES - 3);
    debugf("NanoQL: Companion retained below NanoQL Link priority");
}

extern void stop_hid(void);

static void development_watch_task(void *argument)
{
    (void)argument;

    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(50));
        if (!(sys_get_buttons() & NANOQL_S1_MASK))
            continue;

        debugf("NanoQL: S1 requested live USB development takeover");
        stop_hid();
        vTaskDelay(pdMS_TO_TICKS(500));
        usbh_deinitialize(USB_BUS_ID);
        vTaskDelay(pdMS_TO_TICKS(50));

        if (!nanoql_usb_start())
            debugf("NanoQL: unable to start development CDC mode");
        development_watch_task_handle = NULL;
        vTaskDelete(NULL);
    }
}

void nanoql_development_watch(void)
{
    if (development_active || development_watch_task_handle != NULL)
        return;

    xTaskCreate(development_watch_task, "NanoQL S1", 768, NULL,
                configMAX_PRIORITIES - 3, &development_watch_task_handle);
}

static void notify_link_task(void)
{
    if (link_task_handle == NULL)
        return;

    if (xPortIsInsideInterrupt()) {
        BaseType_t task_woken = pdFALSE;
        vTaskNotifyGiveFromISR(link_task_handle, &task_woken);
        portYIELD_FROM_ISR(task_woken);
    } else {
        xTaskNotifyGive(link_task_handle);
    }
}

static bool rx_push(uint8_t value)
{
    uintptr_t flags = bflb_irq_save();
    uint16_t next = (uint16_t)((rx_head + 1) % RX_RING_SIZE);
    bool stored = next != rx_tail;
    if (stored) {
        rx_ring[rx_head] = value;
        rx_head = next;
    }
    bflb_irq_restore(flags);
    return stored;
}

static bool rx_pop(uint8_t *value)
{
    uintptr_t flags = bflb_irq_save();
    bool available = rx_tail != rx_head;
    if (available) {
        *value = rx_ring[rx_tail];
        rx_tail = (uint16_t)((rx_tail + 1) % RX_RING_SIZE);
    }
    bflb_irq_restore(flags);
    return available;
}

static uint8_t crc8(const uint8_t *data, size_t length)
{
    uint8_t value = 0;
    for (size_t index = 0; index < length; ++index) {
        value ^= data[index];
        for (unsigned bit = 0; bit < 8; ++bit)
            value = (value & 0x80) ? (uint8_t)((value << 1) ^ 0x07)
                                   : (uint8_t)(value << 1);
    }
    return value;
}

static uint32_t read_be32(const uint8_t *data)
{
    return ((uint32_t)data[0] << 24) | ((uint32_t)data[1] << 16) |
           ((uint32_t)data[2] << 8) | data[3];
}

static uint32_t crc32_update(
    uint32_t value, const uint8_t *data, size_t length)
{
    while (length--) {
        value ^= *data++;
        for (unsigned bit = 0; bit < 8; ++bit)
            value = (value >> 1) ^
                    ((value & 1) ? UINT32_C(0xedb88320) : 0);
    }
    return value;
}

static void write_be32(uint8_t *data, uint32_t value)
{
    data[0] = (uint8_t)(value >> 24);
    data[1] = (uint8_t)(value >> 16);
    data[2] = (uint8_t)(value >> 8);
    data[3] = (uint8_t)value;
}

static uint8_t fs_error_from_result(FRESULT result)
{
    switch (result) {
    case FR_OK:
        return 0;
    case FR_NOT_READY:
    case FR_NO_FILESYSTEM:
    case FR_INVALID_DRIVE:
        return 20;
    case FR_INVALID_NAME:
        return 21;
    case FR_NO_FILE:
    case FR_NO_PATH:
        return 25;
    case FR_EXIST:
        return 26;
    case FR_WRITE_PROTECTED:
        return 28;
    case FR_DENIED:
        return 29;
    default:
        return (uint8_t)(0x40 | ((uint8_t)result & 0x1f));
    }
}

static bool fs_result_is_transient(FRESULT result)
{
    return result == FR_DISK_ERR || result == FR_INT_ERR;
}

static FRESULT fs_mkdir_retry_locked(const char *path)
{
    FRESULT result = FR_DISK_ERR;
    for (unsigned attempt = 0; attempt < 3; ++attempt) {
        result = f_mkdir(path);
        if (!fs_result_is_transient(result))
            break;
        bflb_mtimer_delay_ms(20);
    }
    return result;
}

static FRESULT fs_open_retry_locked(FIL *file, const char *path, BYTE mode)
{
    FRESULT result = FR_DISK_ERR;
    for (unsigned attempt = 0; attempt < 3; ++attempt) {
        result = f_open(file, path, mode);
        if (!fs_result_is_transient(result))
            break;
        bflb_mtimer_delay_ms(20);
    }
    return result;
}

static bool fs_make_path(
    const uint8_t *remote, uint8_t remote_length, char *full_path)
{
    if (remote_length > NANOQL_FS_MAX_REMOTE_PATH)
        return false;

    size_t root_length = strlen(NANOQL_FS_ROOT);
    memcpy(full_path, NANOQL_FS_ROOT, root_length);
    if (remote_length == 0) {
        full_path[root_length] = '\0';
        return true;
    }

    if (remote[0] == '/' || remote[remote_length - 1] == '/')
        return false;

    size_t component_start = 0;
    for (size_t index = 0; index <= remote_length; ++index) {
        if (index != remote_length && remote[index] != '/') {
            uint8_t character = remote[index];
            if (character < 0x20 || character > 0x7e ||
                character == '\\' || character == ':' || character == '*' ||
                character == '?' || character == '"' || character == '<' ||
                character == '>' || character == '|')
                return false;
            continue;
        }

        size_t component_length = index - component_start;
        if (component_length == 0 ||
            (component_length == 1 && remote[component_start] == '.') ||
            (component_length == 2 && remote[component_start] == '.' &&
             remote[component_start + 1] == '.'))
            return false;
        component_start = index + 1;
    }

    full_path[root_length] = '/';
    memcpy(&full_path[root_length + 1], remote, remote_length);
    full_path[root_length + 1 + remote_length] = '\0';
    return true;
}

static FRESULT fs_ensure_root_locked(void)
{
    FRESULT result = fs_mkdir_retry_locked(CARD_MOUNTPOINT "/NanoQL");
    if (result != FR_OK && result != FR_EXIST)
        return result;
    result = fs_mkdir_retry_locked(NANOQL_FS_ROOT);
    return result == FR_EXIST ? FR_OK : result;
}

static FRESULT fs_mkdir_tree_locked(char *path)
{
    FRESULT result = fs_ensure_root_locked();
    if (result != FR_OK || strcmp(path, NANOQL_FS_ROOT) == 0)
        return result;

    size_t root_length = strlen(NANOQL_FS_ROOT);
    for (char *separator = path + root_length + 1; ; ++separator) {
        if (*separator != '/' && *separator != '\0')
            continue;
        char saved = *separator;
        *separator = '\0';
        result = fs_mkdir_retry_locked(path);
        *separator = saved;
        if (result != FR_OK && result != FR_EXIST)
            return result;
        if (saved == '\0')
            return FR_OK;
    }
}

static FRESULT fs_ensure_parent_locked(const char *path)
{
    char parent[NANOQL_FS_FULL_PATH_SIZE];
    size_t length = strlen(path);
    if (length >= sizeof(parent))
        return FR_INVALID_NAME;
    memcpy(parent, path, length + 1);
    char *separator = strrchr(parent, '/');
    if (separator == NULL || separator <= parent + strlen(NANOQL_FS_ROOT))
        return fs_ensure_root_locked();
    *separator = '\0';
    return fs_mkdir_tree_locked(parent);
}

static void fs_close_locked(bool remove_partial_upload)
{
    if (fs_session == NANOQL_FS_LISTING)
        (void)f_closedir(&fs_directory);
    else if (fs_session == NANOQL_FS_PUTTING ||
             fs_session == NANOQL_FS_GETTING)
        (void)f_close(&fs_file);

    if (remove_partial_upload && fs_session == NANOQL_FS_PUTTING)
        (void)f_unlink(NANOQL_FS_TEMP);
    fs_session = NANOQL_FS_IDLE;
}

static void fs_abort_session(void)
{
    if (fs_session == NANOQL_FS_IDLE)
        return;
    if (!sdc_is_initialized()) {
        fs_session = NANOQL_FS_IDLE;
        return;
    }
    sdc_lock();
    fs_close_locked(true);
    sdc_unlock();
}

static uint8_t fs_command(
    const uint8_t *payload, uint8_t length,
    uint8_t *response, uint8_t *response_length)
{
    if (!sdc_is_initialized())
        return 20;

    char path[NANOQL_FS_FULL_PATH_SIZE];
    FRESULT result = FR_OK;
    *response_length = 0;

    switch (payload[0]) {
    case NANOQL_CMD_FS_INFO:
        if (length != 1)
            return 3;
        sdc_lock();
        result = fs_ensure_root_locked();
        sdc_unlock();
        if (result != FR_OK)
            return fs_error_from_result(result);
        memcpy(response, "NFS1", 4);
        response[4] = 1;    /* protocol version */
        response[5] = 0x3f; /* files plus automatic MDV1 synchronization */
        response[6] = NANOQL_FS_MAX_REMOTE_PATH;
        *response_length = 7;
        return 0;

    case NANOQL_CMD_FS_LIST_BEGIN:
        if (fs_session != NANOQL_FS_IDLE)
            return 22;
        if (!fs_make_path(&payload[1], (uint8_t)(length - 1), path))
            return 21;
        sdc_lock();
        result = fs_ensure_root_locked();
        if (result == FR_OK)
            result = f_opendir(&fs_directory, path);
        if (result == FR_OK)
            fs_session = NANOQL_FS_LISTING;
        sdc_unlock();
        if (result != FR_OK)
            return fs_error_from_result(result);
        response[0] = 0;
        *response_length = 1;
        return 0;

    case NANOQL_CMD_FS_LIST_NEXT: {
        if (length != 1 || fs_session != NANOQL_FS_LISTING)
            return 22;
        FILINFO information;
        sdc_lock();
        do {
            result = f_readdir(&fs_directory, &information);
        } while (result == FR_OK && information.fname[0] != '\0' &&
                 (information.fattrib & (AM_HID | AM_SYS)) != 0);
        if (result != FR_OK || information.fname[0] == '\0') {
            fs_close_locked(false);
            sdc_unlock();
            if (result != FR_OK)
                return fs_error_from_result(result);
            response[0] = 0;
            *response_length = 1;
            return 0;
        }
        size_t name_length = strlen(information.fname);
        if (name_length > NANOQL_FS_MAX_REMOTE_PATH) {
            sdc_unlock();
            return 27;
        }
        response[0] = (information.fattrib & AM_DIR) ? 2 : 1;
        uint32_t size = information.fsize > UINT32_MAX ?
                            UINT32_MAX : (uint32_t)information.fsize;
        write_be32(&response[1], size);
        response[5] = (uint8_t)name_length;
        memcpy(&response[6], information.fname, name_length);
        *response_length = (uint8_t)(6 + name_length);
        sdc_unlock();
        return 0;
    }

    case NANOQL_CMD_FS_PUT_BEGIN:
        if (length < 10 || fs_session != NANOQL_FS_IDLE)
            return length < 10 ? 3 : 22;
        if (!fs_make_path(&payload[9], (uint8_t)(length - 9), path))
            return 21;
        sdc_lock();
        result = fs_ensure_parent_locked(path);
        if (result == FR_OK) {
            FRESULT remove_result = f_unlink(NANOQL_FS_TEMP);
            if (remove_result != FR_OK && remove_result != FR_NO_FILE &&
                remove_result != FR_NO_PATH)
                result = remove_result;
        }
        if (result == FR_OK)
            result = fs_open_retry_locked(
                &fs_file, NANOQL_FS_TEMP,
                FA_CREATE_ALWAYS | FA_READ | FA_WRITE);
        if (result == FR_OK) {
            fs_session = NANOQL_FS_PUTTING;
            fs_expected_size = read_be32(&payload[1]);
            fs_expected_crc = read_be32(&payload[5]);
            fs_received_size = 0;
            fs_received_crc = UINT32_C(0xffffffff);
            memcpy(fs_target_path, path, strlen(path) + 1);
        }
        sdc_unlock();
        if (result != FR_OK)
            return fs_error_from_result(result);
        response[0] = 0;
        *response_length = 1;
        return 0;

    case NANOQL_CMD_FS_PUT_DATA: {
        if (length < 6 || fs_session != NANOQL_FS_PUTTING)
            return length < 6 ? 3 : 22;
        uint32_t offset = read_be32(&payload[1]);
        uint32_t data_length = (uint32_t)length - 5;
        if (data_length > NANOQL_FS_CHUNK_SIZE ||
            offset > fs_expected_size ||
            data_length > fs_expected_size - offset ||
            offset > fs_received_size ||
            (offset < fs_received_size &&
             data_length > fs_received_size - offset))
            return 3;
        bool extends_file = offset == fs_received_size;
        UINT written = 0;
        sdc_lock();
        result = f_lseek(&fs_file, offset);
        if (result == FR_OK)
            result = f_write(&fs_file, &payload[5], data_length, &written);
        sdc_unlock();
        if (result != FR_OK || written != data_length) {
            fs_abort_session();
            return result == FR_OK ? 23 : fs_error_from_result(result);
        }
        if (extends_file) {
            fs_received_crc = crc32_update(
                fs_received_crc, &payload[5], data_length);
            fs_received_size += data_length;
        }
        write_be32(response, offset + data_length);
        *response_length = 4;
        return 0;
    }

    case NANOQL_CMD_FS_PUT_COMMIT: {
        if (length != 1 || fs_session != NANOQL_FS_PUTTING)
            return length != 1 ? 3 : 22;
        uint32_t actual_crc = fs_received_crc ^ UINT32_C(0xffffffff);
        uint32_t actual_size = 0;
        sdc_lock();
        result = f_sync(&fs_file);
        if (result == FR_OK && f_size(&fs_file) <= UINT32_MAX)
            actual_size = (uint32_t)f_size(&fs_file);
        else if (result == FR_OK)
            result = FR_INVALID_OBJECT;
        (void)f_close(&fs_file);

        if (result == FR_OK &&
            (fs_received_size != fs_expected_size ||
             actual_size != fs_expected_size ||
             actual_crc != fs_expected_crc)) {
            (void)f_unlink(NANOQL_FS_TEMP);
            fs_session = NANOQL_FS_IDLE;
            sdc_unlock();
            return 24;
        }

        bool backup_created = false;
        if (result == FR_OK) {
            FILINFO existing;
            FRESULT exists = f_stat(fs_target_path, &existing);
            if (exists == FR_OK) {
                if (existing.fattrib & AM_DIR)
                    result = FR_DENIED;
                else {
                    (void)f_unlink(NANOQL_FS_BACKUP);
                    result = f_rename(fs_target_path, NANOQL_FS_BACKUP);
                    backup_created = result == FR_OK;
                }
            } else if (exists != FR_NO_FILE && exists != FR_NO_PATH) {
                result = exists;
            }
        }
        if (result == FR_OK)
            result = f_rename(NANOQL_FS_TEMP, fs_target_path);
        if (result != FR_OK && backup_created)
            (void)f_rename(NANOQL_FS_BACKUP, fs_target_path);
        else if (result == FR_OK && backup_created)
            (void)f_unlink(NANOQL_FS_BACKUP);
        fs_session = NANOQL_FS_IDLE;
        sdc_unlock();
        if (result != FR_OK)
            return fs_error_from_result(result);
        write_be32(response, actual_size);
        write_be32(&response[4], actual_crc);
        *response_length = 8;
        return 0;
    }

    case NANOQL_CMD_FS_GET_BEGIN:
        if (length < 2 || fs_session != NANOQL_FS_IDLE)
            return length < 2 ? 3 : 22;
        if (!fs_make_path(&payload[1], (uint8_t)(length - 1), path))
            return 21;
        sdc_lock();
        result = fs_open_retry_locked(&fs_file, path, FA_READ);
        if (result == FR_OK && f_size(&fs_file) > UINT32_MAX) {
            (void)f_close(&fs_file);
            result = FR_INVALID_OBJECT;
        }
        if (result == FR_OK) {
            fs_session = NANOQL_FS_GETTING;
            write_be32(response, (uint32_t)f_size(&fs_file));
            *response_length = 4;
        }
        sdc_unlock();
        return result == FR_OK ? 0 : fs_error_from_result(result);

    case NANOQL_CMD_FS_GET_DATA: {
        if (length != 6 || fs_session != NANOQL_FS_GETTING)
            return length != 6 ? 3 : 22;
        uint32_t offset = read_be32(&payload[1]);
        uint8_t requested = payload[5];
        if (requested == 0 || requested > NANOQL_FS_CHUNK_SIZE)
            return 3;
        UINT read = 0;
        sdc_lock();
        result = f_lseek(&fs_file, offset);
        if (result == FR_OK)
            result = f_read(&fs_file, &response[1], requested, &read);
        sdc_unlock();
        if (result != FR_OK) {
            fs_abort_session();
            return fs_error_from_result(result);
        }
        response[0] = (uint8_t)read;
        *response_length = (uint8_t)(read + 1);
        return 0;
    }

    case NANOQL_CMD_FS_GET_END:
        if (length != 1 || fs_session != NANOQL_FS_GETTING)
            return length != 1 ? 3 : 22;
        sdc_lock();
        fs_close_locked(false);
        sdc_unlock();
        response[0] = 0;
        *response_length = 1;
        return 0;

    case NANOQL_CMD_FS_DELETE:
        if (length < 2 || fs_session != NANOQL_FS_IDLE)
            return length < 2 ? 3 : 22;
        if (!fs_make_path(&payload[1], (uint8_t)(length - 1), path))
            return 21;
        sdc_lock();
        result = f_unlink(path);
        sdc_unlock();
        if (result != FR_OK)
            return fs_error_from_result(result);
        response[0] = 0;
        *response_length = 1;
        return 0;

    case NANOQL_CMD_FS_MKDIR:
        if (fs_session != NANOQL_FS_IDLE ||
            !fs_make_path(&payload[1], (uint8_t)(length - 1), path))
            return fs_session != NANOQL_FS_IDLE ? 22 : 21;
        sdc_lock();
        result = fs_mkdir_tree_locked(path);
        sdc_unlock();
        if (result != FR_OK)
            return fs_error_from_result(result);
        response[0] = 0;
        *response_length = 1;
        return 0;

    case NANOQL_CMD_FS_CANCEL:
        if (length != 1)
            return 3;
        fs_abort_session();
        response[0] = 0;
        *response_length = 1;
        return 0;

    case NANOQL_CMD_FS_MDV_CONTROL: {
        if (length != 2 || fs_session != NANOQL_FS_IDLE)
            return length != 2 ? 3 : 22;
        if (payload[1] == 0) {
            /* Release the old file before its atomic replacement. Keep the
               Companion and QL running so an interrupted desktop upload can
               never leave the board held in reset. */
            if (sdc_image_open(2, NULL) != 0)
                return 25;
        } else if (payload[1] == 1) {
            char image_name[] = "MDV1.mdv";
            sdc_set_cwd(2, NANOQL_FS_ROOT);
            if (sdc_image_open(2, image_name) != 0) {
                sys_set_val('R', 0);
                fpga_upload_resume_companion();
                return 25;
            }
            inifile_write("nanoql.ini");
            /* Pulse the QL reset only after process_frame() has acknowledged
               the command. Keep NanoQL Link active for the remote keyboard. */
            microdrive_reset_pending = true;
        } else if (payload[1] == 2) {
            /* Final desktop acknowledgement: release any stale reset left by
               an interrupted older synchronization before returning. */
            sys_set_val('R', 0);
        } else {
            return 3;
        }
        response[0] = 0;
        *response_length = 1;
        return 0;
    }

    default:
        return 3;
    }
}

static void fpga_upload_abort(void)
{
    if (!fpga_upload_open)
        return;
    gowin_stream_abort();
    fpga_upload_open = false;
    if (companion_suspended_for_upload) {
        vTaskResume(com_task_handle);
        companion_suspended_for_upload = false;
    }
}

static void fpga_upload_suspend_companion(void)
{
    TaskHandle_t task = com_task_handle;
    if (task == NULL || task == xTaskGetCurrentTaskHandle() ||
        companion_suspended_for_upload)
        return;

    /* Wait until the Companion owns neither shared resource before stopping
       it. During JTAG configuration the FPGA SPI endpoint disappears, and a
       concurrent Companion transaction can otherwise starve USB CDC. */
    sdc_lock();
    mcu_hw_spi_begin();
    vTaskSuspend(task);
    companion_suspended_for_upload = true;
    mcu_hw_spi_end();
    sdc_unlock();
}

static void fpga_upload_resume_companion(void)
{
    if (!companion_suspended_for_upload)
        return;
    vTaskResume(com_task_handle);
    companion_suspended_for_upload = false;
}

static uint8_t fpga_upload_command(
    const uint8_t *payload, uint8_t length, uint8_t *response)
{
    switch (payload[0]) {
    case NANOQL_CMD_FPGA_FLASH_BEGIN:
    case NANOQL_CMD_FPGA_FLASH_PROGRAM:
        return 13;

    case NANOQL_CMD_FPGA_BEGIN:
        if (length != 9)
            return 3;
        fpga_upload_abort();
        fpga_upload_size = read_be32(&payload[1]);
        fpga_upload_expected_crc = read_be32(&payload[5]);
        if (!fpga_upload_size || fpga_upload_size > NANOQL_FPGA_MAX_SIZE)
            return 4;
        fpga_upload_suspend_companion();
        if (!gowin_stream_begin()) {
            fpga_upload_resume_companion();
            return 5;
        }
        fpga_upload_open = true;
        fpga_upload_received = 0;
        fpga_upload_crc = UINT32_C(0xffffffff);
        response[0] = 0;
        return 0;

    case NANOQL_CMD_FPGA_DATA:
        if (!fpga_upload_open || length < 2 ||
            fpga_upload_received + length - 1 > fpga_upload_size)
            return 6;
        bool last = fpga_upload_received + length - 1 == fpga_upload_size;
        bool written = gowin_stream_data(&payload[1], length - 1, last);
        if (!written) {
            fpga_upload_abort();
            return 7;
        }
        fpga_upload_crc = crc32_update(
            fpga_upload_crc, &payload[1], length - 1);
        fpga_upload_received += length - 1;
        response[0] = 0;
        return 0;

    case NANOQL_CMD_FPGA_PROGRAM: {
        if (length != 1 || !fpga_upload_open)
            return 6;
        bool valid = fpga_upload_received == fpga_upload_size &&
                     (fpga_upload_crc ^ UINT32_C(0xffffffff)) ==
                         fpga_upload_expected_crc;
        if (!valid) {
            fpga_upload_abort();
            return 8;
        }

        debugf("NanoQL: finalizing %lu streamed FPGA bytes",
               (unsigned long)fpga_upload_size);
        bool programmed = gowin_stream_end();
        fpga_upload_open = false;
        if (!programmed) {
            fpga_upload_resume_companion();
            return 9;
        }
        return_to_companion_pending = true;
        response[0] = 0;
        return 0;
    }

    default:
        return 3;
    }
}

static bool remote_menu_event(uint8_t event)
{
    bool released = (event & 0x80) != 0;
    uint8_t usage = event & 0x7f;

    if (usage == 0x45) { /* F12 */
        menu_notify(released ? MENU_EVENT_KEY_RELEASE : MENU_EVENT_TOGGLE);
        return true;
    }
    if (!osd_is_visible())
        return false;
    if (released) {
        menu_notify(MENU_EVENT_KEY_RELEASE);
        return true;
    }

    switch (usage) {
    case 0x29: menu_notify(MENU_EVENT_BACK); break;   /* Escape */
    case 0x28: /* Enter */
    case 0x2c: menu_notify(MENU_EVENT_SELECT); break; /* Space */
    case 0x4b: menu_notify(MENU_EVENT_PGUP); break;
    case 0x4e: menu_notify(MENU_EVENT_PGDOWN); break;
    case 0x51: menu_notify(MENU_EVENT_DOWN); break;
    case 0x52: menu_notify(MENU_EVENT_UP); break;
    default: break;
    }
    return true;
}

static uint8_t spi_exchange(
    const uint8_t *payload, uint8_t length, uint8_t *response)
{
    if ((length == 2) && (payload[0] == NANOQL_CMD_KEY)) {
        if (remote_menu_event(payload[1])) {
            response[0] = 0;
            return 1;
        }
        mcu_hw_spi_begin();
        response[0] = mcu_hw_spi_tx_u08(SPI_TARGET_HID);
        response[1] = mcu_hw_spi_tx_u08(SPI_HID_KEYBOARD);
        response[2] = mcu_hw_spi_tx_u08(payload[1]);
        mcu_hw_spi_end();
        return 3;
    }

    mcu_hw_spi_begin();
    response[0] = mcu_hw_spi_tx_u08(NANOQL_SPI_TARGET);
    for (uint8_t index = 0; index < length; ++index)
        response[index + 1] = mcu_hw_spi_tx_u08(payload[index]);
    mcu_hw_spi_end();
    return (uint8_t)(length + 1);
}

static void usb_send(const uint8_t *data, uint8_t length)
{
    while (usb_ready && usb_tx_busy)
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(100));
    if (!usb_ready)
        return;

    memcpy(usb_write_buffer, data, length);
    usb_tx_busy = true;
    usbd_ep_start_write(USB_BUS_ID, CDC_IN_EP, usb_write_buffer, length);
}

static void send_error(uint8_t sequence, uint8_t code)
{
    uint8_t frame[] = {
        'Q', 'N', NANOQL_PROTOCOL_VERSION, sequence, 2, 0xff, code, 0
    };
    frame[7] = crc8(&frame[2], 5);
    usb_send(frame, sizeof(frame));
}

static void process_frame(
    uint8_t version, uint8_t sequence, uint8_t length,
    const uint8_t *payload, uint8_t received_crc)
{
    uint8_t crc_data[3 + NANOQL_MAX_PAYLOAD];
    crc_data[0] = version;
    crc_data[1] = sequence;
    crc_data[2] = length;
    memcpy(&crc_data[3], payload, length);

    if (version != NANOQL_PROTOCOL_VERSION) {
        send_error(sequence, 1);
        return;
    }
    if (crc8(crc_data, (size_t)(length + 3)) != received_crc) {
        send_error(sequence, 2);
        return;
    }

    uint8_t spi_response[NANOQL_MAX_PAYLOAD + 1];
    uint8_t response_length;
    if (payload[0] >= NANOQL_CMD_FPGA_BEGIN) {
        uint8_t error = fpga_upload_command(
            payload, length, spi_response);
        if (error) {
            send_error(sequence, error);
            return;
        }
        response_length = 1;
    } else if (payload[0] >= NANOQL_CMD_FS_INFO) {
        uint8_t error = fs_command(
            payload, length, spi_response, &response_length);
        if (error) {
            send_error(sequence, error);
            return;
        }
    } else {
        if (length > NANOQL_SPI_MAX_PAYLOAD) {
            send_error(sequence, 3);
            return;
        }
        response_length = spi_exchange(payload, length, spi_response);
    }
    uint8_t frame[6 + NANOQL_MAX_PAYLOAD + 1];
    frame[0] = 'Q';
    frame[1] = 'N';
    frame[2] = NANOQL_PROTOCOL_VERSION;
    frame[3] = sequence;
    frame[4] = response_length;
    memcpy(&frame[5], spi_response, response_length);
    frame[5 + response_length] =
        crc8(&frame[2], (size_t)(3 + response_length));
    usb_send(frame, (uint8_t)(6 + response_length));
}

static void link_task(void *argument)
{
    (void)argument;
    enum {
        WAIT_MAGIC_N,
        WAIT_MAGIC_Q,
        READ_VERSION,
        READ_SEQUENCE,
        READ_LENGTH,
        READ_PAYLOAD,
        READ_CRC
    } state = WAIT_MAGIC_N;
    uint8_t version = 0;
    uint8_t sequence = 0;
    uint8_t length = 0;
    uint8_t payload_index = 0;
    uint8_t payload[NANOQL_MAX_PAYLOAD];

    for (;;) {
        if (usb_rx_reset_requested) {
            fs_abort_session();
            fpga_upload_abort();
            fpga_upload_resume_companion();
            uintptr_t flags = bflb_irq_save();
            rx_tail = rx_head;
            usb_rx_reset_requested = false;
            bflb_irq_restore(flags);
            state = WAIT_MAGIC_N;
            payload_index = 0;
        }

        uint8_t value;
        if (!rx_pop(&value)) {
            ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
            continue;
        }

        switch (state) {
        case WAIT_MAGIC_N:
            if (value == 'N')
                state = WAIT_MAGIC_Q;
            break;
        case WAIT_MAGIC_Q:
            state = value == 'Q' ? READ_VERSION
                                 : (value == 'N' ? WAIT_MAGIC_Q : WAIT_MAGIC_N);
            break;
        case READ_VERSION:
            version = value;
            state = READ_SEQUENCE;
            break;
        case READ_SEQUENCE:
            sequence = value;
            state = READ_LENGTH;
            break;
        case READ_LENGTH:
            length = value;
            payload_index = 0;
            if (length == 0 || length > NANOQL_MAX_PAYLOAD) {
                send_error(sequence, 3);
                state = WAIT_MAGIC_N;
            } else {
                state = READ_PAYLOAD;
            }
            break;
        case READ_PAYLOAD:
            payload[payload_index++] = value;
            if (payload_index == length)
                state = READ_CRC;
            break;
        case READ_CRC:
            process_frame(version, sequence, length, payload, value);
            state = WAIT_MAGIC_N;
            if (return_to_companion_pending) {
                return_to_companion_pending = false;
                while (usb_ready && usb_tx_busy)
                    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(100));
                vTaskDelay(pdMS_TO_TICKS(50));
                debugf("NanoQL: FPGA programmed, returning to Companion");
                mcu_hw_reset();
            }
            if (microdrive_reset_pending) {
                uint8_t qdos_command = NANOQL_CMD_QDOS;
                uint8_t qdos_response[2];
                microdrive_reset_pending = false;
                while (usb_ready && usb_tx_busy)
                    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(100));
                debugf("NanoQL: MDV1 synchronized, resetting QL");
                /* Never assert the persistent Companion reset here. A task
                   interruption between R=1 and R=0 used to leave the startup
                   screen at BL616 IS HOLDING RESET. The host-link QDOS command
                   creates a bounded reset pulse entirely inside the FPGA. */
                sys_set_val('R', 0);
                vTaskDelay(pdMS_TO_TICKS(10));
                (void)spi_exchange(&qdos_command, 1, qdos_response);
                vTaskDelay(pdMS_TO_TICKS(50));
                sys_set_val('R', 0);
            }
            break;
        }
    }
}

static void usb_event_handler(uint8_t busid, uint8_t event)
{
    (void)busid;
    switch (event) {
    case USBD_EVENT_RESET:
    case USBD_EVENT_DISCONNECTED:
        usb_ready = false;
        usb_tx_busy = false;
        usb_rx_reset_requested = true;
        notify_link_task();
        break;
    case USBD_EVENT_SUSPEND:
        // Windows may suspend and immediately resume CDC while opening COM.
        // Preserve an otherwise valid NanoQL frame across that transition.
        usb_ready = false;
        usb_tx_busy = false;
        notify_link_task();
        break;
    case USBD_EVENT_CONFIGURED:
        usb_ready = true;
        usbd_ep_start_read(
            USB_BUS_ID, CDC_OUT_EP, usb_read_buffer, sizeof(usb_read_buffer));
        notify_link_task();
        break;
    case USBD_EVENT_RESUME:
        usb_ready = true;
        notify_link_task();
        break;
    default:
        break;
    }
}

static void usb_bulk_out(uint8_t busid, uint8_t endpoint, uint32_t length)
{
    (void)endpoint;
    for (uint32_t index = 0; index < length; ++index)
        (void)rx_push(usb_read_buffer[index]);
    usbd_ep_start_read(
        busid, CDC_OUT_EP, usb_read_buffer, sizeof(usb_read_buffer));
    notify_link_task();
}

static void usb_bulk_in(uint8_t busid, uint8_t endpoint, uint32_t length)
{
    (void)busid;
    (void)endpoint;
    (void)length;
    usb_tx_busy = false;
    notify_link_task();
}

static struct usbd_endpoint cdc_out_endpoint = {
    .ep_addr = CDC_OUT_EP,
    .ep_cb = usb_bulk_out
};

static struct usbd_endpoint cdc_in_endpoint = {
    .ep_addr = CDC_IN_EP,
    .ep_cb = usb_bulk_in
};

static struct usbd_interface cdc_control_interface;
static struct usbd_interface cdc_data_interface;

void usbd_cdc_acm_set_dtr(uint8_t busid, uint8_t interface, bool dtr)
{
    (void)busid;
    (void)interface;
    (void)dtr;
}

void usbd_cdc_acm_set_rts(uint8_t busid, uint8_t interface, bool rts)
{
    (void)busid;
    (void)interface;
    (void)rts;
}

void usbd_cdc_acm_set_line_coding(
    uint8_t busid, uint8_t interface, struct cdc_line_coding *coding)
{
    (void)busid;
    (void)interface;
    (void)coding;
}

void usbd_cdc_acm_get_line_coding(
    uint8_t busid, uint8_t interface, struct cdc_line_coding *coding)
{
    (void)busid;
    (void)interface;
    coding->dwDTERate = 115200;
    coding->bCharFormat = 0;
    coding->bParityType = 0;
    coding->bDataBits = 8;
}

bool nanoql_usb_start(void)
{
    if (development_active)
        return true;

    struct bflb_device_s *usb_device =
        bflb_device_get_by_name(BFLB_NAME_USB_V2);
    if (usb_device == NULL) {
        debugf("NanoQL: USB controller not found");
        development_active = false;
        return false;
    }

    prioritize_link_over_companion();

    xTaskCreate(link_task, "NanoQL Link", 1024, NULL,
                configMAX_PRIORITIES - 2, &link_task_handle);
    usbd_desc_register(USB_BUS_ID, &nanoql_descriptor);
    usbd_add_interface(
        USB_BUS_ID,
        usbd_cdc_acm_init_intf(USB_BUS_ID, &cdc_control_interface));
    usbd_add_interface(
        USB_BUS_ID,
        usbd_cdc_acm_init_intf(USB_BUS_ID, &cdc_data_interface));
    usbd_add_endpoint(USB_BUS_ID, &cdc_out_endpoint);
    usbd_add_endpoint(USB_BUS_ID, &cdc_in_endpoint);
    usbd_initialize(USB_BUS_ID, 0, usb_event_handler);
    development_active = true;
    return true;
}
