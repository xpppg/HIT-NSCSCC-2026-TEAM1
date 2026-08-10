# LA32R LVGL audio player UI preview

This example provides a 480 x 800 graphical audio player on `/dev/fb0` and
reads the Goodix touchscreen from `/dev/input/event0`.  The Pause/Play, Next
and Menu buttons are interactive.  Playlist rows select a song and the Back
button returns to the player.  I2S playback remains intentionally unconnected.
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
/tmp/lvgl_audio_player /dev/fb0 --input /dev/input/event0
```

Run the playlist preview instead:

```sh
/tmp/lvgl_audio_player /dev/fb0 --input /dev/input/event0 --menu
```

The startup log prints the framebuffer resolution and the absolute coordinate
range reported by evdev.  Press `Ctrl+C` on the serial console to stop.

The evdev adapter consumes input up to one `SYN_REPORT` at a time.  This keeps
fast press/release transitions distinct even when framebuffer rendering has
temporarily allowed several reports to accumulate in the kernel queue.
