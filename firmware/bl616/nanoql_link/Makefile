SDK_DEMO_PATH ?= $(abspath .)
BL_SDK_BASE ?= $(abspath ../../../../private/bl616-link-build/bouffalo_sdk)

CHIP ?= bl616
BOARD ?= bl616dk
TANG_BOARD ?= nano20k_v3923
CROSS_COMPILE ?= riscv64-unknown-elf-
cmake_definition += -DTANG_BOARD=$(TANG_BOARD)

include $(BL_SDK_BASE)/project.build
