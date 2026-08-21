#ifndef NANOQL_USB_H
#define NANOQL_USB_H

#include <stdbool.h>

bool nanoql_development_requested(void);
void nanoql_development_watch(void);
bool nanoql_usb_is_active(void);
bool nanoql_usb_is_recovery(void);
bool nanoql_usb_start(void);

#endif
