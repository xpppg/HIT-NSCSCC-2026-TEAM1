# Linux I2C touch probe

This program validates the first Linux integration stage without requiring
`i2c-tools`.  It uses `/dev/i2c-0` and the `I2C_RDWR` ioctl to read the four
Goodix product-ID bytes at register `0x8140` from address `0x14`.

Build it with:

```sh
cd software/examples/i2c_touch_linux_probe
make
```

Transfer `i2c_touch_linux_probe` to the target with TFTP, then run:

```sh
chmod +x /tmp/i2c_touch_linux_probe
/tmp/i2c_touch_linux_probe
```

Pass a different adapter path as the first argument if the controller is not
assigned bus zero.
