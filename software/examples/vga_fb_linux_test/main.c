#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "/dev/fb1";
    static const uint16_t colors[8] = {
        0xffff, 0xffe0, 0x07ff, 0x07e0,
        0xf81f, 0xf800, 0x001f, 0x0000
    };
    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
    uint16_t *pixels;
    size_t size;
    unsigned int x, y;
    int fd = open(path, O_RDWR);

    if (fd < 0) {
        fprintf(stderr, "open %s: %s\n", path, strerror(errno));
        return 1;
    }
    if (ioctl(fd, FBIOGET_VSCREENINFO, &var) ||
        ioctl(fd, FBIOGET_FSCREENINFO, &fix)) {
        perror("FBIOGET_*SCREENINFO");
        return 1;
    }
    if (var.xres != 640 || var.yres != 480 || var.bits_per_pixel != 16) {
        fprintf(stderr, "unexpected mode %ux%u-%u\n",
                var.xres, var.yres, var.bits_per_pixel);
        return 1;
    }
    size = (size_t)fix.line_length * var.yres;
    pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) {
        perror("mmap");
        return 1;
    }

    for (y = 0; y < var.yres; ++y) {
        uint16_t *row = (uint16_t *)((unsigned char *)pixels +
                                     (size_t)y * fix.line_length);
        for (x = 0; x < var.xres; ++x)
            row[x] = (y % 32 == 0) ? 0xffff : colors[(x * 8) / var.xres];
    }
    msync(pixels, size, MS_SYNC);
    printf("%s: stable RGB565 bars written (%zu bytes)\n", path, size);
    munmap(pixels, size);
    close(fd);
    return 0;
}
