# OpenCores I2C integration

The files in `opencores/` are an unmodified copy of Richard Herveille's
OpenCores I2C Master Core, imported from the following repository and branch:

- repository: `https://github.com/fabriziotappero/ip-cores.git`
- branch: `communication_controller_i2c_controller_core`
- commit: `afaacbc8fdd191cc435c482b783aa750e5b7c7f6`

The original copyright and redistribution notice is retained at the top of
each RTL file.  `axi_i2c_ocores.v` is the project-specific AXI3 wrapper.

## SoC mapping

The controller is mapped at physical address `0x1fa1_0000`.  OpenCores byte
registers use a four-byte CPU stride:

| Offset | OpenCores register |
| --- | --- |
| `0x00` | prescaler low |
| `0x04` | prescaler high |
| `0x08` | control |
| `0x0c` | transmit/receive |
| `0x10` | command/status |

The wrapper adds two registers outside the Linux `i2c-ocores` resource:

| Offset | Description |
| --- | --- |
| `0x20` | touch control: bit 0 `RESET_N`, bit 1 drives `INT` low |
| `0x24` | line status: bit 0 `INT`, bit 1 `SCL`, bit 2 `SDA`, bit 3 `RESET_N` |

After an AXI reset, `TOUCH_CTRL` defaults to `0x01`: RESET_N is released and
INT remains high-impedance.  With the module's INT pull-up this selects the
verified Goodix address `0x14`, allowing Linux to probe the device without a
separate GPIO controller.

The OpenCores prescaler equation is
`prescale = input_clock / (5 * I2C_clock) - 1`.  With the SoC's 33 MHz
peripheral clock, `0x0041` gives approximately 100 kHz.

For Linux, configure `i2c-ocores` with `reg-io-width = <4>`,
`reg-shift = <2>`, an input clock of 33 MHz and a bus clock of 100 kHz.
The controller IRQ is connected to `core_top.intrpt[5]`.  The active-low
Goodix touch-event interrupt is inverted and connected to `intrpt[6]`.
