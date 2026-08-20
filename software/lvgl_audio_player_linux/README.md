# LA32R LVGL audio player

This program draws a 480 x 800 player on `/dev/fb0`, reads the Goodix touch
screen from `/dev/input/event1`, and plays WAV files through ALSA device
`hw:0,0`.  Playback runs in a separate pthread, so blocking ALSA writes do not
block LVGL rendering or touch handling.

At startup the program scans a music directory, validates all `.wav` files and
builds the playlist in case-insensitive filename order.  The menu count and
each duration come from the files actually found; unsupported WAV files are
reported and skipped.  Up to 64 playable tracks are supported.

The Pause/Play and Next buttons control the real PCM stream.  Selecting a row
in Menu immediately switches the ALSA stream to that track.  The progress bar
is derived from the number of stereo frames accepted by ALSA rather than from
an independent UI timer, and its total length comes from the WAV data chunk.

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
the running target Linux system, create a directory and download every song
into it:

```sh
ip link set eth0 up
ip addr add 169.254.89.144/16 dev eth0

tftp -g -r lvgl_audio_player -l /tmp/lvgl_audio_player 169.254.89.146
mkdir -p /tmp/music
tftp -g -r song01.wav -l /tmp/music/song01.wav 169.254.89.146
tftp -g -r song02.wav -l /tmp/music/song02.wav 169.254.89.146
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
    --input /dev/input/event1 \
    --alsa hw:0,0 \
    --music-dir /tmp/music
```

Use `--track` to select the initial song.  It does not create a fixed playlist;
the other WAV files in `--music-dir` remain available:

```sh
/tmp/lvgl_audio_player /dev/fb0 --input /dev/input/event1 \
    --music-dir /tmp/music \
    --track /tmp/music/song02.wav
```

If `--track` is supplied without `--music-dir`, the program automatically
scans the selected file's parent directory.  Without either option it scans
`/tmp`.  Add `--menu` to open directly on the scrollable playlist.  Press
`Ctrl+C` on the serial console to stop.

Before testing Pause, Next, playlist switching, or `Ctrl+C` during playback,
program the FPGA with the updated `avp_stream_dma.v`.  That version drains an
outstanding AXI read burst before a stopped stream is restarted; an older
bitstream can report `I2S AXI error` after such a stop/restart sequence.
