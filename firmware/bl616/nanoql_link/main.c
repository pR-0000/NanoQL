/*
 * NanoQL Link BL616 USB CDC to FPGA SPI bridge.
 *
 * USB setup is adapted from the CherryUSB CDC ACM example, copyright
 * (c) 2024 sakumisu, and BL616 SPI setup is adapted from FPGA Companion.
 * Both upstream sources are Apache-2.0 licensed. NanoQL modifications are
 * distributed under GPL-3.0-only with the rest of this repository.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "FreeRTOS.h"
#include "task.h"
#include "portmacro.h"

#include "board.h"
#include "bflb_gpio.h"
#include "bflb_irq.h"
#include "bflb_spi.h"
#include "usbd_core.h"
#include "usbd_cdc_acm.h"

#define USB_BUS_ID 0
#define CDC_IN_EP  0x83
#define CDC_OUT_EP 0x04
#define CDC_INT_EP 0x85
#define CDC_MAX_MPS 512

#define NANOQL_USB_VID 0xffff
#define NANOQL_USB_PID 0x4e51
#define NANOQL_PROTOCOL_VERSION 1
#define NANOQL_MAX_PAYLOAD 13
#define NANOQL_SPI_TARGET 4
#define NANOQL_SPI_FREQUENCY 20000000

#define RX_RING_SIZE 512
#define USB_CONFIG_SIZE (9 + CDC_ACM_DESCRIPTOR_LEN)

#if defined(TANG_NANO20K)
#define SPI_PIN_MISO GPIO_PIN_2
#define SPI_PIN_MOSI GPIO_PIN_3
#elif defined(TANG_NANO20K_V3923)
#define SPI_PIN_MISO GPIO_PIN_30
#define SPI_PIN_MOSI GPIO_PIN_27
#else
#error "Unsupported Tang Nano 20K revision"
#endif

#define SPI_PIN_CSN GPIO_PIN_0
#define SPI_PIN_SCK GPIO_PIN_1

static struct bflb_device_s *gpio;
static struct bflb_device_s *spi_device;
static TaskHandle_t link_task_handle;

static USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX uint8_t usb_read_buffer[512];
static USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX uint8_t usb_write_buffer[32];
static uint8_t rx_ring[RX_RING_SIZE];
static volatile uint16_t rx_head;
static volatile uint16_t rx_tail;
static volatile bool usb_ready;
static volatile bool usb_tx_busy;

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
    .device_quality_descriptor_callback = device_qualifier_descriptor_callback,
    .string_descriptor_callback = string_descriptor_callback
};

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

static void spi_init(void)
{
    gpio = bflb_device_get_by_name("gpio");
    bflb_gpio_init(gpio, SPI_PIN_MISO,
                   GPIO_FUNC_SPI0 | GPIO_ALTERNATE | GPIO_PULLUP |
                   GPIO_SMT_EN | GPIO_DRV_3);
    bflb_gpio_init(gpio, SPI_PIN_MOSI,
                   GPIO_FUNC_SPI0 | GPIO_ALTERNATE | GPIO_PULLUP |
                   GPIO_SMT_EN | GPIO_DRV_3);
    bflb_gpio_init(gpio, SPI_PIN_SCK,
                   GPIO_FUNC_SPI0 | GPIO_ALTERNATE | GPIO_PULLUP |
                   GPIO_SMT_EN | GPIO_DRV_3);
    bflb_gpio_init(gpio, SPI_PIN_CSN,
                   GPIO_OUTPUT | GPIO_PULLUP | GPIO_SMT_EN | GPIO_DRV_3);
    bflb_gpio_set(gpio, SPI_PIN_CSN);

    struct bflb_spi_config_s config = {
        .freq = NANOQL_SPI_FREQUENCY,
        .role = SPI_ROLE_MASTER,
        .mode = SPI_MODE1,
        .data_width = SPI_DATA_WIDTH_8BIT,
        .bit_order = SPI_BIT_MSB,
        .byte_order = SPI_BYTE_LSB,
        .tx_fifo_threshold = 0,
        .rx_fifo_threshold = 0,
    };

    spi_device = bflb_device_get_by_name("spi0");
    bflb_spi_init(spi_device, &config);
    bflb_spi_feature_control(
        spi_device, SPI_CMD_SET_DATA_WIDTH, SPI_DATA_WIDTH_8BIT);
}

static uint8_t spi_exchange(
    const uint8_t *payload, uint8_t length, uint8_t *response)
{
    bflb_gpio_reset(gpio, SPI_PIN_CSN);
    response[0] = bflb_spi_poll_send(spi_device, NANOQL_SPI_TARGET);
    for (uint8_t index = 0; index < length; ++index)
        response[index + 1] = bflb_spi_poll_send(spi_device, payload[index]);
    bflb_gpio_set(gpio, SPI_PIN_CSN);
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
    uint8_t response_length = spi_exchange(payload, length, spi_response);
    uint8_t frame[6 + NANOQL_MAX_PAYLOAD + 1];
    frame[0] = 'Q';
    frame[1] = 'N';
    frame[2] = NANOQL_PROTOCOL_VERSION;
    frame[3] = sequence;
    frame[4] = response_length;
    memcpy(&frame[5], spi_response, response_length);
    frame[5 + response_length] = crc8(&frame[2], (size_t)(3 + response_length));
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
    usbd_ep_start_read(busid, CDC_OUT_EP, usb_read_buffer, sizeof(usb_read_buffer));
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

static void usb_init(void)
{
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
}

void vApplicationMallocFailedHook(void)
{
    taskDISABLE_INTERRUPTS();
    for (;;) {}
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *name)
{
    (void)task;
    (void)name;
    taskDISABLE_INTERRUPTS();
    for (;;) {}
}

void vAssertCalled(void)
{
    taskDISABLE_INTERRUPTS();
    for (;;) {}
}

int main(void)
{
    board_init();
    spi_init();
#if defined(BOARD_USB_VIA_GPIO)
    board_usb_gpio_init();
#endif
    xTaskCreate(
        link_task, "nanoql_link", 1024, NULL,
        configMAX_PRIORITIES - 2, &link_task_handle);
    usb_init();
    vTaskStartScheduler();
    for (;;) {}
}
