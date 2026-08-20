// SPDX-License-Identifier: GPL-2.0-or-later
/* Minimal con2fbmap utility for the LA32R Buildroot system. */

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static void usage(const char *name)
{
    fprintf(stderr,
            "Usage:\n"
            "  %s <console>               Show the framebuffer mapping\n"
            "  %s <console> <framebuffer> Set the framebuffer mapping\n",
            name, name);
}

static int parse_u32(const char *text, unsigned int *value)
{
    char *end;
    unsigned long parsed;

    errno = 0;
    parsed = strtoul(text, &end, 0);
    if (errno || *text == '\0' || *end != '\0' || parsed > 0xffffffffUL)
        return -1;
    *value = (unsigned int)parsed;
    return 0;
}

int main(int argc, char **argv)
{
    struct fb_con2fbmap map;
    const char *fbdev = "/dev/fb0";
    int fd;
    int request;

    if (argc != 2 && argc != 3) {
        usage(argv[0]);
        return 2;
    }

    if (parse_u32(argv[1], &map.console) || map.console == 0) {
        fprintf(stderr, "Invalid console number: %s\n", argv[1]);
        return 2;
    }

    if (argc == 3) {
        if (parse_u32(argv[2], &map.framebuffer)) {
            fprintf(stderr, "Invalid framebuffer number: %s\n", argv[2]);
            return 2;
        }
        request = FBIOPUT_CON2FBMAP;
    } else {
        map.framebuffer = 0;
        request = FBIOGET_CON2FBMAP;
    }

    fd = open(fbdev, O_RDWR);
    if (fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", fbdev, strerror(errno));
        return 1;
    }

    if (ioctl(fd, request, &map) < 0) {
        fprintf(stderr, "%s console %u: %s\n",
                argc == 3 ? "Cannot map" : "Cannot query",
                map.console, strerror(errno));
        close(fd);
        return 1;
    }
    close(fd);

    printf("console %u is mapped to framebuffer %u\n",
           map.console, map.framebuffer);
    return 0;
}
