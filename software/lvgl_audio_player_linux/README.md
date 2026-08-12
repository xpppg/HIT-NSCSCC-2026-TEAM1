# LA32R LVGL audio player

This program draws a 480 x 800 player on `/dev/fb0`, reads the Goodix touch
screen from `/dev/input/event0`, and plays WAV files through ALSA device
`hw:0,0`.  Playback runs in a separate pthread, so blocking ALSA writes do not
block LVGL rendering or touch handling.

The Pause/Play and Next buttons control the real PCM stream.  Selecting a row
in Menu immediately switches the ALSA stream to that track.  The progress bar
is derived from the number of stereo frames accepted by ALSA rather than from
an independent UI timer.

Only the hardware format supported by the first LA32R I2S implementation is
accepted:

- RIFF/WAVE PCM (not FLAC or MP3)
- 44.1 kHz
- two channels
- signed 16-bit little-endian samples

## Build

The Makefile uses the existing standalone LA32R toolchain and the `alsa-lib`
headers/shared library from the existing Buildroot staging directory:

```sh
cd /home/xpg/chiplab/software/lvgl_audio_player_linux
make -j$(nproc)
```

The output is `lvgl_audio_player`.  `make check` prints its target ELF header
and dynamic dependencies.

## Prepare and download audio

If necessary, convert a source file on the host:

```sh
ffmpeg -i input.flac -ar 44100 -ac 2 -c:a pcm_s16le test.wav
```

Place `lvgl_audio_player` and the WAV files in the TFTP server directory.  On
the running target Linux system:

```sh
ip link set eth0 up
ip addr add 169.254.89.144/16 dev eth0

tftp -g -r lvgl_audio_player -l /tmp/lvgl_audio_player 169.254.89.146
tftp -g -r test.wav -l /tmp/test.wav 169.254.89.146
chmod +x /tmp/lvgl_audio_player
```

If the address already exists, the second `ip addr add` returning `File exists`
is harmless.

## Run

Disable the fbcon cursor before starting, otherwise its periodic writes compete
with LVGL for `/dev/fb0`:

```sh
echo 0 > /sys/class/graphics/fbcon/cursor_blink
printf '\033[?25l' > /dev/tty1
/tmp/lvgl_audio_player /dev/fb0 \
    --input /dev/input/event0 \
    --alsa hw:0,0 \
    --track /tmp/test.wav
```

The first `--track` replaces playlist item 1, the second replaces item 2, and
so on, up to five files.  For example:

```sh
/tmp/lvgl_audio_player /dev/fb0 --input /dev/input/event0 \
    --track /tmp/song01.wav \
    --track /tmp/song02.wav \
    --track /tmp/song03.wav
```

Without arguments the defaults are `/tmp/test.wav` and
`/tmp/track02.wav` through `/tmp/track05.wav`.  Add `--menu` to open directly
on the playlist.  Press `Ctrl+C` on the serial console to stop.

Before testing Pause, Next, playlist switching, or `Ctrl+C` during playback,
program the FPGA with the updated `avp_stream_dma.v`.  That version drains an
outstanding AXI read burst before a stopped stream is restarted; an older
bitstream can report `I2S AXI error` after such a stop/restart sequence.
