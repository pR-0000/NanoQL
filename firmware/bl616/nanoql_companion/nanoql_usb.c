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
#include "../mcu_hw.h"
#include "../menu.h"
#include "../osd.h"
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
#define NANOQL_SPI_MAX_PAYLOAD 13
#define NANOQL_SPI_TARGET 4
#define NANOQL_S1_MASK 0x01
#define NANOQL_CMD_KEY 0x05
#define NANOQL_CMD_FPGA_BEGIN 0xf0
#define NANOQL_CMD_FPGA_DATA 0xf1
#define NANOQL_CMD_FPGA_PROGRAM 0xf2
#define NANOQL_CMD_FPGA_FLASH_BEGIN 0xf3
#define NANOQL_CMD_FPGA_FLASH_PROGRAM 0xf4
#define NANOQL_FPGA_MAX_SIZE (2u * 1024u * 1024u)

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
static bool fpga_upload_open;
static uint32_t fpga_upload_size;
static uint32_t fpga_upload_received;
static uint32_t fpga_upload_crc;
static uint32_t fpga_upload_expected_crc;
static bool return_to_companion_pending;

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

static void stop_companion_task(void)
{
    TaskHandle_t task = com_task_handle;
    if (task == NULL || task == xTaskGetCurrentTaskHandle())
        return;

    com_task_handle = NULL;
    vTaskDelete(task);
    debugf("NanoQL: autonomous Companion task stopped");
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

static void fpga_upload_abort(void)
{
    if (!fpga_upload_open)
        return;
    gowin_stream_abort();
    fpga_upload_open = false;
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
        if (!gowin_stream_begin()) {
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
        if (!programmed)
            return 9;
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
    case USBD_EVENT_SUSPEND:
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

    /* Companion and NanoQL Link must never drive the FPGA SPI bus together. */
    stop_companion_task();

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
