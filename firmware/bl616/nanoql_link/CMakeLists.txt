cmake_minimum_required(VERSION 3.15)

set(CONFIG_FREERTOS 1)
set(CONFIG_CHERRYUSB_OSAL "freertos")
set(CONFIG_CHERRYUSB 1)
set(CONFIG_CHERRYUSB_DEVICE 1)
set(CONFIG_CHERRYUSB_DEVICE_CDC_ACM 1)
set(CONFIG_BFLOG 0)

if(TANG_BOARD STREQUAL "nano20k")
    add_definitions(-DTANG_NANO20K)
elseif(TANG_BOARD STREQUAL "nano20k_v3923")
    add_definitions(-DTANG_NANO20K_V3923)
else()
    message(FATAL_ERROR "TANG_BOARD must be nano20k or nano20k_v3923")
endif()

find_package(bouffalo_sdk REQUIRED HINTS $ENV{BL_SDK_BASE})

sdk_add_include_directories(.)
sdk_set_main_file(main.c)

project(nanoql_link)
