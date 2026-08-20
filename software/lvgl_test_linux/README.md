# LA32R Linux LVGL framebuffer test

This is a minimal LVGL 9.2.2 application for the LA32R Linux target. It uses
`/dev/fb0` directly, renders in RGB565, and does not enable LVGL floating-point
features.

Build it on the Ubuntu host with:

```sh
make -j$(nproc)
```

On the target, stop framebuffer-console cursor updates and run:

```sh
echo 0 > /sys/class/graphics/fbcon/cursor_blink
printf '\033[?25l' > /dev/tty1
chmod +x /tmp/lvgl_test
/tmp/lvgl_test /dev/fb0
```

Press `Ctrl+C` on the serial console to stop it.
