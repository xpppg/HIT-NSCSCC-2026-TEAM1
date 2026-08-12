// SPDX-License-Identifier: MIT
/* Read-only LA32R I2S/IRQ monitor for Linux. */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define I2S_BASE       0x1fa20000UL
#define MEDIA_BASE     0x1fa4f000UL
#define I2S_CTRL       0x00
#define I2S_STATUS     0x04
#define I2S_BUF_BYTES  0x0c
#define I2S_PERIOD     0x10
#define I2S_PLAY_POS   0x14
#define MEDIA_RAW      0x00
#define MEDIA_ENABLE   0x04

static volatile sig_atomic_t stop_requested;

static void stop_handler(int signo)
{
	(void)signo;
	stop_requested = 1;
}

static uint64_t monotonic_ms(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
		return 0;
	return (uint64_t)ts.tv_sec * 1000U + (uint64_t)ts.tv_nsec / 1000000U;
}

static unsigned long long read_i2s_irq_count(void)
{
	char line[512];
	FILE *fp = fopen("/proc/interrupts", "r");

	if (!fp)
		return ~0ULL;
	while (fgets(line, sizeof(line), fp)) {
		char *colon;
		char *end;
		unsigned long long value;

		if (!strstr(line, "1fa20000.i2s"))
			continue;
		colon = strchr(line, ':');
		if (!colon)
			break;
		errno = 0;
		value = strtoull(colon + 1, &end, 10);
		if (!errno && end != colon + 1) {
			fclose(fp);
			return value;
		}
		break;
	}
	fclose(fp);
	return ~0ULL;
}

static volatile uint32_t *map_regs(int fd, unsigned long address,
				   long page_size, void **mapping)
{
	unsigned long page = address & ~((unsigned long)page_size - 1UL);
	unsigned long offset = address - page;

	*mapping = mmap(NULL, (size_t)page_size, PROT_READ, MAP_SHARED, fd,
			(off_t)page);
	if (*mapping == MAP_FAILED)
		return NULL;
	return (volatile uint32_t *)((char *)*mapping + offset);
}

int main(int argc, char **argv)
{
	unsigned long interval_ms = 100;
	unsigned long max_samples = 0;
	unsigned long sample = 0;
	unsigned long long previous_irq = ~0ULL;
	volatile uint32_t *i2s;
	volatile uint32_t *media;
	void *i2s_mapping;
	void *media_mapping;
	long page_size;
	int mem_fd;

	if (argc > 1)
		interval_ms = strtoul(argv[1], NULL, 0);
	if (argc > 2)
		max_samples = strtoul(argv[2], NULL, 0);
	if (!interval_ms) {
		fprintf(stderr, "interval_ms must be non-zero\n");
		return 2;
	}

	page_size = sysconf(_SC_PAGESIZE);
	if (page_size <= 0) {
		perror("sysconf(_SC_PAGESIZE)");
		return 1;
	}
	mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (mem_fd < 0) {
		perror("open /dev/mem");
		return 1;
	}
	i2s = map_regs(mem_fd, I2S_BASE, page_size, &i2s_mapping);
	media = map_regs(mem_fd, MEDIA_BASE, page_size, &media_mapping);
	if (!i2s || !media) {
		perror("mmap /dev/mem");
		return 1;
	}

	signal(SIGINT, stop_handler);
	signal(SIGTERM, stop_handler);
	setvbuf(stdout, NULL, _IOLBF, 0);
	printf("LA32R I2S IRQ monitor: interval=%lu ms; Ctrl-C to stop\n",
	       interval_ms);
	printf("time_ms sample irq_total irq_delta ctrl status play_pos "
	       "buf_bytes period_bytes raw enable\n");

	while (!stop_requested && (!max_samples || sample < max_samples)) {
		unsigned long long irq_count = read_i2s_irq_count();
		unsigned long long delta = 0;

		if (irq_count != ~0ULL && previous_irq != ~0ULL)
			delta = irq_count - previous_irq;
		printf("%llu %lu ", (unsigned long long)monotonic_ms(), sample);
		if (irq_count == ~0ULL)
			printf("NA NA ");
		else
			printf("%llu %llu ", irq_count, delta);
		printf("0x%08x 0x%08x 0x%08x 0x%08x 0x%08x "
		       "0x%08x 0x%08x\n",
		       i2s[I2S_CTRL / 4], i2s[I2S_STATUS / 4],
		       i2s[I2S_PLAY_POS / 4], i2s[I2S_BUF_BYTES / 4],
		       i2s[I2S_PERIOD / 4], media[MEDIA_RAW / 4],
		       media[MEDIA_ENABLE / 4]);
		if (irq_count != ~0ULL)
			previous_irq = irq_count;
		sample++;
		usleep(interval_ms * 1000U);
	}

	munmap(i2s_mapping, (size_t)page_size);
	munmap(media_mapping, (size_t)page_size);
	close(mem_fd);
	return 0;
}
