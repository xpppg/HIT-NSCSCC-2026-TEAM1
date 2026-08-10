# LA32R LVGL audio player UI preview

This example previews a 480 x 800 graphical audio player on `/dev/fb0`.
It provides a now-playing page with Pause, Next and Menu buttons and a separate
playlist page. Touch input and I2S playback are intentionally not connected yet.
The preview refreshes the progress bar every 100 ms and derives its position from
`CLOCK_MONOTONIC`, so rendering delays do not accumulate as playback-time error.
Real I2S sample consumption will replace this time source later.

The project reuses the LVGL 9.2.2 source already present in
`../lvgl_test_linux/vendor`.

Build on the Ubuntu host:

```sh
make -j$(nproc)
```

Run the player page on the target:

```sh
echo 0 > /sys/class/graphics/fbcon/cursor_blink
printf '\033[?25l' > /dev/tty1
chmod +x /tmp/lvgl_audio_player
/tmp/lvgl_audio_player /dev/fb0
```

Run the playlist preview instead:

```sh
/tmp/lvgl_audio_player /dev/fb0 --menu
```

Press `Ctrl+C` on the serial console to stop either view.
