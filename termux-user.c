#define _GNU_SOURCE
#include <pwd.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#undef getpwuid

static struct passwd orig_pwd;
static char username[256];
static int initialized = 0;

static void init() {
    if (initialized) return;
    initialized = 1;

    const char *home = getenv("HOME");
    if (!home) return;
    char path[512];
    snprintf(path, sizeof(path), "%s/.local/share/plasma-hw.conf", home);

    FILE *f = fopen(path, "r");
    if (!f) return;

    char line[512];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "TERMUX_USER=", 12) == 0) {
            char *val = line + 12;
            val[strcspn(val, "\r\n")] = 0;
            if (strlen(val) > 0) {
                strncpy(username, val, sizeof(username) - 1);
            }
            break;
        }
    }
    fclose(f);
}

struct passwd *getpwuid(uid_t uid) {
    init();

    typedef struct passwd *(*getpwuid_fn)(uid_t);
    getpwuid_fn orig = (getpwuid_fn)dlsym(RTLD_NEXT, "getpwuid");
    struct passwd *pw = orig(uid);

    if (pw && username[0]) {
        orig_pwd = *pw;
        orig_pwd.pw_name = username;
        return &orig_pwd;
    }
    return pw;
}
