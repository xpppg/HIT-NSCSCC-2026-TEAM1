# LA32R SoC：U-Boot 网络启动 Linux 快速手册

本文适用于当前工程的 Loongson LA32R SoC，使用 U-Boot 从 TFTP 服务器下载
`vmlinux`，随后启动内置 initramfs 的 Linux。当前使用的网络参数为：

| 项目 | 地址 |
| --- | --- |
| 开发板 U-Boot/Linux | `169.254.89.144` |
| TFTP 服务器 | `169.254.89.146` |
| ELF 临时下载地址 | `0xa3000000` |
| 串口 | `115200 8N1`，无流控 |

## 1. 主机端准备内核

内核源码目录：

```sh
cd /home/xpg/chiplab-old/la32r-Linux
```

完整编译命令：

```sh
make ARCH=loongarch \
  CROSS_COMPILE=/home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf- \
  vmlinux -j$(nproc)
```

该内核启用了 `CONFIG_DEBUG_INFO`，刚链接完成的 `vmlinux` 可能超过 200 MB，
不能直接下载到当前 128 MB DDR。使用 LoongArch 交叉工具链生成单独的 TFTP
版本，保留原始调试版：

```sh
/home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-strip \
  -o vmlinux.tftp vmlinux
```

检查文件：

```sh
ls -lh vmlinux vmlinux.tftp
readelf -h vmlinux.tftp | sed -n '1,24p'
readelf -l vmlinux.tftp
```

正确文件应为 32 位、小端、LoongArch ELF 可执行文件，入口地址在
`0xa0xxxxxx` 范围。当前裁剪后的文件约为 19 MB。

将 `vmlinux.tftp` 复制到所使用的 TFTP 服务器根目录，并改名为
`vmlinux`。例如 TFTP 根目录为 `/srv/tftp` 时：

```sh
sudo cp vmlinux.tftp /srv/tftp/vmlinux
sudo chmod 644 /srv/tftp/vmlinux
```

如果 TFTP 服务运行在 Windows，则把 `vmlinux.tftp` 复制到 TFTP 软件配置的
根目录并命名为 `vmlinux`。

不要使用主机自带的 x86 `strip`；必须使用上面的
`loongarch32r-linux-gnusf-strip`。

## 2. U-Boot 下载并启动 Linux

开发板上电，在串口出现以下提示符后输入命令：

```text
u-boot@LoongsonSoC#
```

完整命令如下，可逐行复制：

```text
setenv ipaddr 169.254.89.144
setenv serverip 169.254.89.146
ping ${serverip}
tftpboot 0xa3000000 vmlinux
bootelf 0xa3000000 vmlinux console=tty0 console=ttyS0,115200 rdinit=/init
```

说明：

- `0xa3000000` 只是 ELF 下载缓冲区，不是 Linux 的入口地址。
- `bootelf` 会读取 ELF 信息，把内核装载到其链接地址并跳转到 ELF 入口。
- `vmlinux` 是传给内核的 `argv[0]` 占位参数。
- `console=tty0` 启用虚拟终端，使 fbcon 把内核记录输出到 LCD。
- `console=ttyS0,115200` 同时保留串口控制台；把它放在最后，使串口继续作为
  `/dev/console` 的首选控制台。
- `rdinit=/init` 启动内核中内置的 Buildroot initramfs。
- 不要把 `bootcmd` 环境变量当作内核参数；`bootelf ... bootcmd` 只会传递
  字面字符串 `bootcmd`，不会自动展开其环境变量内容。

TFTP 成功时会看到 `Bytes transferred`，随后 `bootelf` 应输出类似：

```text
## Starting application at 0xa0......
do_bootelf_exec...
```

之后等待 Linux 启动并出现：

```text
Welcome to Linux
linux login:
```

登录用户为 `root`，密码为123

## 3. Linux 启动后检查 LCD 和触摸

登录后执行：

```sh
dmesg | grep -i -E 'lcd|dma|i2c|goodix'
cat /sys/class/graphics/fb0/name
fbset -fb /dev/fb0
ls -l /dev/fb0 /dev/i2c-0 /dev/input/event0
```

预期 LCD 信息包括：

```text
la32r-lcd
geometry 480 800 480 800 16
```

为了避免 fbcon 光标周期性触发 LCD 刷新：

```sh
echo 0 > /sys/class/graphics/fbcon/cursor_blink
```

## 4. Linux 中配置网络

```sh
ip link set eth0 up
ip addr replace 169.254.89.144/16 dev eth0
ping -c 3 169.254.89.146
```

网卡可能在 `ip link set eth0 up` 后经过几秒才打印 `Link OK`。如果
`ip addr replace` 不受当前 BusyBox 支持，可以改用：

```sh
ip addr add 169.254.89.144/16 dev eth0
```

若提示 `RTNETLINK answers: File exists`，说明地址已经存在，不需要重复添加。

## 5. 下载并运行 LVGL 音频播放器

先把以下文件放入 TFTP 根目录：

```text
/home/xpg/chiplab/software/lvgl_audio_player_linux/lvgl_audio_player
```

开发板执行：

```sh
tftp -g -r lvgl_audio_player \
     -l /tmp/lvgl_audio_player \
     169.254.89.146

chmod +x /tmp/lvgl_audio_player
echo 0 > /sys/class/graphics/fbcon/cursor_blink
/tmp/lvgl_audio_player /dev/fb0 --input /dev/input/event0
```

放到后台运行：

```sh
/tmp/lvgl_audio_player /dev/fb0 --input /dev/input/event0 \
    >/tmp/lvgl_audio_player.log 2>&1 &
```

查看日志或停止程序：

```sh
cat /tmp/lvgl_audio_player.log
killall lvgl_audio_player
```

## 6. 下载并显示 RGB565 RAW 图片

主机端测速图片位置：

```text
/home/xpg/chiplab/software/lvgl_audio_player_linux/lcd_speed_test_480x800_rgb565.raw
```

把它放到 TFTP 根目录后，在开发板执行：

```sh
tftp -g -r lcd_speed_test_480x800_rgb565.raw \
     -l /tmp/lcd_speed_test.raw \
     169.254.89.146

killall lvgl_audio_player 2>/dev/null
dd if=/tmp/lcd_speed_test.raw of=/dev/fb0 bs=768000 count=1
```

480 × 800 RGB565 的正确文件大小必须是：

```text
480 * 800 * 2 = 768000 字节
```

## 7. 常见问题

### TFTP 超时

检查服务器 IP、网线、TFTP 根目录、防火墙，以及 `ping ${serverip}` 是否成功。

### `No elf image at address 0xa3000000`

说明下载失败、文件不完整，或者 TFTP 根目录中的文件并非 ELF 格式的
`vmlinux`。重新下载并检查 `Bytes transferred`。

### `CPU Trigger exception`

确认使用的是 LoongArch 交叉工具链裁剪的 ELF，而不是 `vmlinux.bin`、主机
`strip` 处理的文件或其他架构的文件。下载地址必须使用 `0xa3000000`，不要把
文件直接下载到 ELF 的链接地址。

### Linux 启动后没有串口输出

确认使用了完整启动命令：

```text
bootelf 0xa3000000 vmlinux console=tty0 console=ttyS0,115200 rdinit=/init
```

同时确认串口为 115200、8 数据位、无校验、1 停止位、无硬件流控。

### `/dev/fb0` 存在但界面周期性闪烁或系统变卡

关闭 fbcon 光标闪烁：

```sh
echo 0 > /sys/class/graphics/fbcon/cursor_blink
```
bootelf 0xa3000000 vmlinux console=tty0 console=ttyS0,115200 rdinit=/init initcall_blacklist=la32r_vga_driver_init,la32r_ps2_driver_init

ip link set eth0 up
ip addr replace 169.254.89.144/16 dev eth0
ping -c 3 169.254.89.146

tftp -g \
    -r lvgl_audio_player \
    -l /tmp/lvgl_audio_player \
    169.254.89.146

tftp -g \
    -r haruhikage.wav \
    -l /tmp/original.wav \
    169.254.89.146

chmod +x /tmp/lvgl_audio_player

echo 0 > /sys/class/graphics/fbcon/cursor_blink
printf '\033[?25l' > /dev/tty1

/tmp/lvgl_audio_player /dev/fb0 \
    --input /dev/input/event1 \
    --alsa hw:0,0 \
    --track /tmp/xp_startup.wav



tftp -g \
    -r xp_startup.wav \
    -l /tmp/music/xp_startup.wav \
    169.254.89.146

/tmp/lvgl_audio_player /dev/fb0 \
    --input /dev/input/event1 \
    --alsa hw:0,0 \
    --music-dir /tmp/music

openvt -c 1 -s -f -- /bin/sh