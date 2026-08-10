#include <errno.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <linux/i2c.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define GOODIX_ADDR        0x14
#define GOODIX_PRODUCT_ID  0x8140

static int goodix_read(int fd, uint16_t reg, uint8_t *data, uint16_t length)
{
	uint8_t address[2] = {(uint8_t)(reg >> 8), (uint8_t)reg};
	struct i2c_msg messages[2] = {
		{
			.addr = GOODIX_ADDR,
			.flags = 0,
			.len = sizeof(address),
			.buf = address,
		},
		{
			.addr = GOODIX_ADDR,
			.flags = I2C_M_RD,
			.len = length,
			.buf = data,
		},
	};
	struct i2c_rdwr_ioctl_data transfer = {
		.msgs = messages,
		.nmsgs = 2,
	};

	return ioctl(fd, I2C_RDWR, &transfer);
}

int main(int argc, char **argv)
{
	const char *device = argc > 1 ? argv[1] : "/dev/i2c-0";
	uint8_t product_id[4];
	int fd;

	fd = open(device, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "Cannot open %s: %s\n", device,
			strerror(errno));
		return 1;
	}

	if (goodix_read(fd, GOODIX_PRODUCT_ID, product_id,
			sizeof(product_id)) < 0) {
		fprintf(stderr, "I2C_RDWR to 0x%02x failed: %s\n",
			GOODIX_ADDR, strerror(errno));
		close(fd);
		return 1;
	}

	close(fd);
	printf("Goodix address: 0x%02x\n", GOODIX_ADDR);
	printf("Product ID: %c%c%c%c\n", product_id[0], product_id[1],
		product_id[2], product_id[3]);
	printf("Raw ID: %02x %02x %02x %02x\n", product_id[0],
		product_id[1], product_id[2], product_id[3]);

	return memcmp(product_id, "1158", sizeof(product_id)) == 0 ? 0 : 2;
}
