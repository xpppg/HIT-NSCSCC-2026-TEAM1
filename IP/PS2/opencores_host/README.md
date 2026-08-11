# OpenCores PS/2 Host Controller

The files in this directory are derived from Piotr Foltyn's OpenCores
`ps2_host_controller`, licensed under LGPL-2.1-or-later.

- Upstream: https://opencores.org/projects/ps2_host_controller
- Mirror: https://github.com/freecores/ps2_host_controller
- Imported revision: `4707b69862d7760b360363c2f52b9fbc754946bd`

`ps2_host.v` keeps the upstream interface and protocol state machines, while
parameterizing the system clock and ensuring that both PS/2 pins are driven
open-drain.  The surrounding AXI registers and FIFOs are project-local code.
