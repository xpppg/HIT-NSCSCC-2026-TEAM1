# U-Boot WAV I2S test

This test parses a PCM WAV already placed in DDR and starts the multimedia
I2S DMA. The supported format is 44.1 kHz, stereo, signed 16-bit little
endian. The hardware loops the PCM data continuously.

The WAV must be loaded at `0xa4000004`: a normal 44-byte WAV header then puts
its PCM payload at the DMA-required 8-byte-aligned address `0xa4000030`.
This region also leaves enough space for WAV files up to 64 MiB without
overlapping the ELF staging area at `0xa3000000`.

Build both files with:

```sh
make wav
make uboot
```

To generate the frequency-isolation test instead:

```sh
make freq
make uboot
```

`obj/i2s_frequency_test.wav` contains 750 ms tones followed by 250 ms
silence at 60, 100, 200, 262, 330, 440, 523, 659, 1000, 2000, 4000 and
8000 Hz, all at approximately -12 dBFS.  The generator prints the exact
time-to-frequency map.  If the same interval crackles on every loop, that
frequency or its transition is the useful next target for signal-integrity
and amplifier testing.

Then copy `obj/i2s_test_melody.wav` and `obj/i2s_wav_uboot.elf` into the TFTP
root. On the board:

```text
setenv ipaddr 169.254.89.144
setenv serverip 169.254.89.146
tftpboot 0xa4000004 i2s_test_melody.wav
tftpboot 0xa3000000 i2s_wav_uboot.elf
bootelf 0xa3000000
```

Reset the board to stop playback and return to U-Boot.

## Full-song test

`haruhikage_44100_stereo_s16.wav` is converted from the supplied FLAC. It is
257.84 seconds long and 45,483,020 bytes. Copy it together with the rebuilt
player into the TFTP root, then run:

```text
tftpboot 0xa4000004 haruhikage_44100_stereo_s16.wav
tftpboot 0xa3000000 i2s_wav_uboot.elf
bootelf 0xa3000000
```

The WAV occupies physical DDR `0x04000004` through `0x06b6040f`; this does not
overlap the ELF staging address or the standalone program load segments.
