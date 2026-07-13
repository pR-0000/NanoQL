/* CherryUSB project configuration derived from the Apache-2.0 SDK example. */
#ifndef CHERRYUSB_CONFIG_H
#define CHERRYUSB_CONFIG_H

#include <stdio.h>

#define CONFIG_USB_PRINTF(...) printf(__VA_ARGS__)
#define CONFIG_USB_DBG_LEVEL USB_DBG_WARNING
#define CONFIG_USB_ALIGN_SIZE 4
#define USB_NOCACHE_RAM_SECTION __attribute__((section(".noncacheable")))

#define CONFIG_USBDEV_REQUEST_BUFFER_LEN 512
#define CONFIG_USBDEV_EP0_PRIO 4
#define CONFIG_USBDEV_EP0_STACKSIZE 2048
#define CONFIG_USBDEV_MAX_BUS 1
#define CONFIG_USBDEV_EP_NUM 8
#define CONFIG_USB_MUSB_EP_NUM 8
#define CONFIG_USB_HS

#define usb_phyaddr2ramaddr(address) (address)
#define usb_ramaddr2phyaddr(address) (address)

#endif
