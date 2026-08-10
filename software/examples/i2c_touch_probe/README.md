# I2C touch probe

This standalone program verifies the OpenCores I2C controller at physical
address `0x1fa1_0000`.  It performs the Goodix reset/address-selection
sequence, probes addresses `0x5d` and `0x14`, and reads four product-ID bytes
from register `0x8140`.

Build and load it in the same way as the LCD standalone test:

```sh
cd software/examples/i2c_touch_probe
make uboot
```

Copy `obj/i2c_touch_probe_uboot.elf` to the TFTP directory, then execute:

```text
tftpboot 0xa3000000 i2c_touch_probe_uboot.elf
bootelf 0xa3000000
```

Expected output includes an ACK at `0x5d` or `0x14`, followed by a product ID
such as `9147` or `1151`.  If both addresses report no ACK, check the XDC pin
mapping, LCD module seating, 3.3 V I/O level, RESET/INT sequencing and the SDA/
SCL pull-ups.
