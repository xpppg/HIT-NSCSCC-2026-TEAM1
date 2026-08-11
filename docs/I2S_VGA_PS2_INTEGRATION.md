# LA32R SoC I2S、VGA、PS/2 集成与测试

本次改动在不改变 LCD、Goodix 触摸、网口、UART、原通用 DMA 和 LCD DMA 的
前提下，加入统一多媒体寄存器从设备，以及独立的 I2S/VGA DDR 读 DMA。
项目新增的 `IP/AVP` RTL 文件统一使用 `.v` 后缀，并按 Verilog 源文件加入工程。

## 地址、中断和引脚

| 设备 | 物理地址 | 裸机非缓存地址 | 子中断 |
| --- | --- | --- | --- |
| I2S | `0x1fa2_0000` | `0x9fa2_0000` | 0 |
| VGA | `0x1fa3_0000` | `0x9fa3_0000` | 2 |
| PS/2 | `0x1fa4_0000` | `0x9fa4_0000` | 1 |
| 中断控制 | `0x1fa4_f000` | `0x9fa4_f000` | CPU hwirq 9 |

CPU `intrpt[7]` 是多媒体级联中断。Linux 中 hwirq 9 与触摸使用的 hwirq 8
一样按高电平中断处理。

VGA 使用板载 VGA 口的 RGB444：R=`T4/T3/R2/U4`，G=`T2/R1/U2/R5`，
B=`P5/N1/P1/P3`，HSYNC/VSYNC=`U5/U6`。板载 PS/2 使用 `Y2/AD1`。
MAX98357A 使用 J13：BCLK=`R26`、LRCLK=`K26`、DIN=`N26`，模块必须与开发板
共地。全部为 LVCMOS33，约束已经写入 `fpga/loongson/soc_up.xdc`。

## Vivado 2023.2 手工操作

打开 `fpga/loongson/2023.2/system_run.xpr`，先在 Tcl Console 执行：

```tcl
source /home/xpg/chiplab/fpga/loongson/2023.2/add_multimedia_sources.tcl
```

不要编辑 `.xci` 文本。双击 `axi_interconnect_0`，把 Slave Interface 数量从
4 改成 6：

- S04_AXI：64 位、READ_ONLY、Async ACLK、Acceptance 2、FIFO 32、Register Slice。
- S05_AXI：64 位、READ_ONLY、Async ACLK、Acceptance 4、FIFO 32、Register Slice。
- S04/S05 ACLK 均接现有 33 MHz `aclk`，仲裁保持 Round-Robin。
- 原 S00～S03 不改。

新增两个 Clocking Wizard，模块名和端口必须与 `soc_top.v` 一致：

- `clk_wiz_vga`：100 MHz `clk_in1`，25.2 MHz `clk_out1`，启用高电平
  `reset` 和 `locked`。
- `clk_wiz_i2s`：100 MHz `clk_in1`，22.5792 MHz `clk_out1`，启用高电平
  `reset` 和 `locked`。

重新生成三个 IP 的 Output Products，再依次运行综合、实现、生成 bitstream。
实现完成后必须确认 DRC 无 Error，`report_timing_summary` 的 WNS 不小于 0。

## 寄存器

I2S 页：

| 偏移 | 名称 | 说明 |
| --- | --- | --- |
| `0x00` | CTRL | bit0 使能；写 bit1 同时清状态 |
| `0x04` | STATUS | bit0 周期、bit1 欠载、bit2 AXI 错误，W1C |
| `0x08` | BUF_ADDR | 8 字节对齐的物理地址 |
| `0x0c` | BUF_BYTES | 8 字节整数倍的循环缓冲区长度 |
| `0x10` | PERIOD_BYTES | 4 字节整数倍 |
| `0x14` | PLAY_POS | 真正送入 I2S 的字节位置 |
| `0x18` | CAPS | 固定 S16_LE、双声道、44.1 kHz |

VGA 页：CTRL/STATUS/FB_ADDR/STRIDE/MODE 分别位于 `0x00/04/08/0c/10`。
固定模式为 640×480 RGB565，stride=1280，总大小 614400 字节。STATUS bit0 为
FIFO 欠载，bit1 为 AXI 错误，均 W1C。

PS/2 页：DATA/STATUS/CTRL/CLOCK_HZ 位于 `0x00/04/08/0c`。STATUS bit0 为协议
错误，bit1 为发送忙，bits[12:8] 为 RX FIFO 字节数。读取 DATA 弹出一个字节，
写 DATA 发往键盘；硬件不把 Set-2 扫描码转换成 ASCII。

中断页：RAW_STATUS/ENABLE/ENABLE_SET/ENABLE_CLEAR 位于 `0xf000/f004/f008/f00c`。

## RTL 自检与裸机测试

运行时序仿真和全模块 lint：

```sh
cd /home/xpg/chiplab
sh IP/AVP/sim/run_verilator.sh
```

该命令覆盖 800×525 VGA 光栅与 RGB565→RGB444、VGA 欠载黑屏、PS/2 收发和
奇偶错误、I2S S16_LE 左右声道位序与周期/欠载事件，以及 AXI DMA 的 16-beat、
4 KiB 边界、循环和错误停止。

三个裸机程序使用原 BSP 的 U-Boot、无 Cache 链接方式：

```sh
cd /home/xpg/chiplab/software/examples/ps2_test && make uboot
cd /home/xpg/chiplab/software/examples/vga_test && make uboot
cd /home/xpg/chiplab/software/examples/i2s_test && make uboot
```

不要并行编译不同裸机目录，因为它们共用 BSP 临时目标文件。把相应 ELF 放进
TFTP 根目录后，开发板执行。产物分别位于
`software/examples/ps2_test/obj/ps2_test_uboot.elf`、
`software/examples/vga_test/obj/vga_test_uboot.elf` 和
`software/examples/i2s_test/obj/i2s_test_uboot.elf`：

```text
setenv ipaddr 169.254.89.144
setenv serverip 169.254.89.146
tftpboot 0xa3000000 ps2_test_uboot.elf
bootelf 0xa3000000
```

VGA/I2S 只需替换文件名。PS/2 应打印原始 `E0/F0` 扫描字节；VGA 应显示八色
色条和每 32 行一条白线；I2S 左右声道分别是 440/660 Hz 整数查表正弦波。

## Linux 和根文件系统构建

内核目录必须使用：

```sh
cd /home/xpg/chiplab-old/la32r-Linux
make ARCH=loongarch \
  CROSS_COMPILE=/home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf- \
  olddefconfig
make ARCH=loongarch \
  CROSS_COMPILE=/home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf- \
  vmlinux -j$(nproc)
```

保留调试版，用交叉 `strip` 另存 TFTP 版本：

```sh
/home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-strip \
  -o vmlinux.tftp vmlinux
```

Buildroot 已启用精简的 `alsa-lib` PCM 和 `alsa-utils/aplay`：

```sh
cd /home/xpg/chiplab-old/la32r-buildroot
make olddefconfig
make -j$(nproc)
```

该项目提供的旧版 LoongArch 外部工具链不包含 `liblto_plugin.so`，但 Buildroot
默认会把归档工具切换成 `gcc-ar/gcc-nm/gcc-ranlib`，从而在构建 `alsa-lib` 时
失败。`package/Makefile.in` 已针对 `BR2_loongisa` 保留普通的 `ar/nm/ranlib`；
当前配置未启用 LTO，因此不会丢失链接时优化功能。

若 Linux 使用内置 initramfs，Buildroot 输出更新后必须再构建一次内核。

## Linux 启动与验证

U-Boot：

```text
setenv ipaddr 169.254.89.144
setenv serverip 169.254.89.146
tftpboot 0xa3000000 vmlinux
bootelf 0xa3000000 vmlinux console=tty0 console=ttyS0,115200 rdinit=/init
```

登录后先确认枚举：

```sh
dmesg | grep -i -E 'media|vga|ps/2|serio|atkbd|i2s|asoc|max98357'
cat /sys/class/graphics/fb0/name
cat /sys/class/graphics/fb1/name
cat /proc/asound/cards
cat /proc/interrupts
```

预期 LCD 仍为 `fb0/la32r-lcd`，VGA 是 `fb1/la32r-vga`。三个 Linux 测试程序
位于 `software/examples/{vga_fb_linux_test,ps2_event_linux_test,i2s_wav_linux_test}`，
先在各目录 `make`，放入 TFTP 根目录。板端网络和测试命令：

```sh
ip link set eth0 up
ip addr replace 169.254.89.144/16 dev eth0

tftp -g -r vga_fb_test -l /tmp/vga_fb_test 169.254.89.146
tftp -g -r ps2_event_test -l /tmp/ps2_event_test 169.254.89.146
tftp -g -r i2s_wav_test -l /tmp/i2s_wav_test 169.254.89.146
chmod +x /tmp/vga_fb_test /tmp/ps2_event_test /tmp/i2s_wav_test

/tmp/vga_fb_test /dev/fb1
cat /proc/bus/input/devices
/tmp/ps2_event_test /dev/input/event1
/tmp/i2s_wav_test /tmp/test.wav
aplay -D hw:0,0 /tmp/test.wav
```

event 编号以 `/proc/bus/input/devices` 为准。持续压力测试可循环播放 WAV，同时
运行 LCD LVGL、`ping`、VGA 色条和键盘输入，并观察 `/proc/interrupts`、串口
overrun、I2S underrun 与 VGA underflow 是否持续增加。

## 来源和许可

- VGA 时序来自 Project F `display_controller`，MIT 许可证保存在
  `IP/VGA/projectf/LICENSE`。
- PS/2 主机移植自 OpenCores `ps2_host_controller` 的 FreeCores 镜像，固定修订
  和 LGPL-2.1-or-later 说明保存在 `IP/PS2/opencores_host/README.md` 及源文件头。
- 没有使用来源和 Xilinx 内部依赖不明确的 `stolen_audio_formatter.sv` 或
  `xil_audio_formatter.sv`。
