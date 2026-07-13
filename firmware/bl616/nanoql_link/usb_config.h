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

/* The shared BL616 USB v2 driver includes host-side structure definitions. */
#define CONFIG_USBHOST_MAX_RHPORTS 1
#define CONFIG_USBHOST_MAX_EXTHUBS 2
#define CONFIG_USBHOST_MAX_EHPORTS 4
#define CONFIG_USBHOST_MAX_INTERFACES 8
#define CONFIG_USBHOST_MAX_INTF_ALTSETTINGS 2
#define CONFIG_USBHOST_MAX_ENDPOINTS 8
#define CONFIG_USBHOST_DEV_NAMELEN 16
#define CONFIG_USBHOST_MAX_BUS 1
#define CONFIG_USBHOST_PIPE_NUM 10
#define CONFIG_USB_EHCI_HCCR_OFFSET 0
#define CONFIG_USB_EHCI_FRAME_LIST_SIZE 1024
#define CONFIG_USB_EHCI_QH_NUM 10
#define CONFIG_USB_EHCI_QTD_NUM (CONFIG_USB_EHCI_QH_NUM * 3)
#define CONFIG_USB_EHCI_ITD_NUM 20
#define CONFIG_USB_EHCI_HCOR_RESERVED_DISABLE
#define CONFIG_USB_HS

#define usb_phyaddr2ramaddr(address) (address)
#define usb_ramaddr2phyaddr(address) (address)

#endif
