#ifndef NANOQL_DRIVE_H
#define NANOQL_DRIVE_H

#define NANOQL_MDV_FOLDER_INDEX 7
#define NANOQL_MDV_SOURCE_ROOT "/sd/NanoQL/Microdrives"

enum nanoql_drive_result {
    NANOQL_DRIVE_OK = 0,
    NANOQL_DRIVE_IO,
    NANOQL_DRIVE_MEMORY,
    NANOQL_DRIVE_TOO_MANY_FILES,
    NANOQL_DRIVE_INVALID_NAME,
    NANOQL_DRIVE_DUPLICATE_NAME,
    NANOQL_DRIVE_FULL,
    NANOQL_DRIVE_MOUNT_FAILED
};

int nanoql_drive_prepare_root(void);
int nanoql_drive_build_folder(const char *source);
const char *nanoql_drive_result_text(int result);

#endif
