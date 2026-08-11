#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "/dev/input/event1";
    struct input_event events[16];
    char name[128] = "unknown";
    ssize_t bytes;
    int fd = open(path, O_RDONLY);

    if (fd < 0) {
        fprintf(stderr, "open %s: %s\n", path, strerror(errno));
        return 1;
    }
    if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0)
        strcpy(name, "unknown");
    printf("Listening on %s (%s); press Ctrl-C to stop\n", path, name);

    while ((bytes = read(fd, events, sizeof(events))) > 0) {
        unsigned int count = (unsigned int)bytes / sizeof(events[0]);
        unsigned int i;

        for (i = 0; i < count; ++i) {
            if (events[i].type == EV_KEY)
                printf("KEY code=%u value=%d (%s)\n", events[i].code,
                       events[i].value,
                       events[i].value == 0 ? "release" :
                       events[i].value == 1 ? "press" : "repeat");
        }
        fflush(stdout);
    }
    if (bytes < 0)
        fprintf(stderr, "read: %s\n", strerror(errno));
    close(fd);
    return bytes < 0;
}
