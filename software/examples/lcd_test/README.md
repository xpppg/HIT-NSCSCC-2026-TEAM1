# LCD standalone test

This program is linked for execution at `0x80300000`. It is intended to be
downloaded as an ELF file through U-Boot/TFTP and started with `bootelf`.

## Build

```sh
cd software/examples/lcd_test
make uboot
```

The files used for board testing are:

- `obj/lcd_test_uboot.elf`: recommended U-Boot/TFTP image;
- `obj/lcd_test_uboot.bin`: raw binary, mainly for diagnostics;
- `obj/lcd_test_uboot.s`: linked disassembly.

## Run from U-Boot

Copy `obj/lcd_test_uboot.elf` to the TFTP server root, then run:

```text
setenv ipaddr <board-ip>
setenv serverip <tftp-server-ip>
ping ${serverip}
tftpboot 0xa3000000 lcd_test_uboot.elf
bootelf 0xa3000000
```

`0xa3000000` is only the temporary download buffer. `bootelf` reads the ELF
program headers, loads the executable sections at `0x80300000`, and jumps to
the `_start` entry point.

The test does not return to U-Boot. Reset the board to stop it.

The program uses the BSP's common U-Boot chain-load entry. Code and data use
U-Boot's uncached `0x8...` DMW window, no cache operation is executed, and
MMIO uses uncached `0x9...` aliases.

Immediately after U-Boot's `do_bootelf_exec...` text, the startup code emits
the breadcrumb characters `SDM`: uncached startup entered, data/BSS
initialization completed, and `main()` is about to run. A missing character
therefore identifies the startup stage that stopped.

## Expected result

The serial console first reports the AXI register self-test and LCD status.
The panel then cycles through red, green, blue, white, black, vertical color
bars, and a 16 x 32 ASCII font test page.

The default panel size is 480 x 864. During the build, `coe_to_c.awk` converts
`IP/LCD/rst_rom.coe` into `lcd_init_sequence.h`; the program replays the same
783 command/data words that were used by the reference hardware controller.
Bit 16 of each word selects command (`1`) or data (`0`), and bits 15:0 are sent
to the LCD data bus. A 120 ms delay is inserted after the Sleep Out command.

The build also converts `IP/LCD/font_rom.coe` into `lcd_font_16x32.h`. Its
65536 one-bit entries become 128 packed ASCII glyphs, each containing 32
16-bit rows. The software renderer writes foreground/background RGB565 pixels
through the existing LCD data register, so no hardware text-rendering IP is
required. The packed table occupies 8 KiB in the program image.
