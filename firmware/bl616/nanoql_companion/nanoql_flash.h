#ifndef NANOQL_FLASH_H
#define NANOQL_FLASH_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint8_t stage;
    uint8_t status;
    uint8_t expected;
    uint8_t actual;
    uint32_t address;
} nanoql_flash_diagnostic_t;

bool nanoql_flash_probe(uint32_t *jedec_id, uint8_t *status);
bool nanoql_flash_begin(uint32_t length, uint32_t *jedec_id, uint8_t *status);
bool nanoql_flash_write(const uint8_t *data, uint16_t length);
bool nanoql_flash_finish(void);
void nanoql_flash_abort(void);
void nanoql_flash_get_diagnostic(nanoql_flash_diagnostic_t *diagnostic);

#endif
