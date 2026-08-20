#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static const char *abs_name(unsigned int code)
{
	switch (code) {
	case ABS_X: return "X";
	case ABS_Y: return "Y";
	case ABS_MT_SLOT: return "MT_SLOT";
	case ABS_MT_POSITION_X: return "MT_X";
	case ABS_MT_POSITION_Y: return "MT_Y";
	case ABS_MT_TRACKING_ID: return "TRACKING_ID";
	case ABS_MT_TOUCH_MAJOR: return "TOUCH_MAJOR";
	case ABS_MT_WIDTH_MAJOR: return "WIDTH_MAJOR";
	default: return NULL;
	}
}

int main(int argc, char **argv)
{
	const char *device = argc > 1 ? argv[1] : "/dev/input/event0";
	struct input_event events[16];
	char name[128] = "unknown";
	ssize_t bytes;
	int fd;

	fd = open(device, O_RDONLY);
	if (fd < 0) {
		fprintf(stderr, "Cannot open %s: %s\n", device,
			strerror(errno));
		return 1;
	}

	if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0)
		strcpy(name, "unknown");
	printf("Listening on %s (%s); press Ctrl-C to stop\n", device, name);

	while ((bytes = read(fd, events, sizeof(events))) > 0) {
		unsigned int count = (unsigned int)bytes / sizeof(events[0]);
		unsigned int index;

		for (index = 0; index < count; ++index) {
			const struct input_event *event = &events[index];

			if (event->type == EV_SYN && event->code == SYN_REPORT) {
				printf("SYN\n");
			} else if (event->type == EV_ABS) {
				const char *name = abs_name(event->code);
				if (name)
					printf("%-12s %d\n", name, event->value);
			} else if (event->type == EV_KEY) {
				printf("KEY_%-8u %d\n", event->code, event->value);
			}
		}
		fflush(stdout);
	}

	if (bytes < 0)
		fprintf(stderr, "Read failed: %s\n", strerror(errno));
	close(fd);
	return bytes < 0 ? 1 : 0;
}
