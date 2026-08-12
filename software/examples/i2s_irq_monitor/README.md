# LA32R I2S IRQ monitor

This read-only Linux diagnostic samples the I2S interrupt count, I2S DMA
registers and multimedia interrupt controller registers. It never enables,
disables or clears an interrupt.

Build:

```sh
make
```

Run with a 100 ms interval until Ctrl-C:

```sh
./i2s_irq_monitor 100
```

The optional second argument limits the number of samples:

```sh
./i2s_irq_monitor 100 200
```

If Linux locks on the first I2S interrupt, this userspace process also stops.
In that case the last printed line distinguishes a first-interrupt deadlock
from an interrupt count that rises for some time before starvation.
