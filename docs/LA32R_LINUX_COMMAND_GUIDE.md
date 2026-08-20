# LA32R SoC：U-Boot、Linux 与外设测试命令速查

适用于当前工程。默认参数：

| 项目 | 当前值 |
| --- | --- |
| 开发板 IP | `169.254.89.144/16` |
| TFTP 服务器 IP | `169.254.89.146` |
| U-Boot 下载地址 | `0xa3000000` |
| 串口 | `115200 8N1`、无流控 |
| 登录 | 用户 `root`，密码 `123` |
| LCD | `/dev/fb0`，480×800，RGB565，768000 字节 |
| VGA | `/dev/fb1`，640×480，RGB565，614400 字节 |
| I2S | ALSA `hw:0,0`，44.1 kHz、双声道、S16_LE |

命令中的 `<...>` 是需要替换的参数，不要原样输入尖括号。

## 1. U-Boot 引导 Linux

### 1.1 标准启动

```text
setenv ipaddr 169.254.89.144
setenv serverip 169.254.89.146
ping ${serverip}
tftpboot 0xa3000000 vmlinux
bootelf 0xa3000000 vmlinux console=tty0 console=ttyS0,115200 rdinit=/init
```

用户 `root`，密码 `123`。

### 1.2 把虚拟终端映射到指定显示器

LCD（`fb0`）：

```text
bootelf 0xa3000000 vmlinux console=tty0 console=ttyS0,115200 rdinit=/init fbcon=map:0
```

VGA（`fb1`）：

```text
bootelf 0xa3000000 vmlinux console=tty0 console=ttyS0,115200 rdinit=/init fbcon=map:1
```

串口控制台保留用于登录和诊断，LCD/VGA 显示 fbcon 虚拟终端。

### 1.3 U-Boot 裸机 ELF 测试格式

```text
tftpboot 0xa3000000 <测试程序.elf>
bootelf 0xa3000000
```

现有程序名包括：

```text
lcd_test_uboot.elf
vga_test_uboot.elf
ps2_test_uboot.elf
i2s_test_uboot.elf
i2c_touch_probe_uboot.elf
```

## 2. Linux 常用命令

| 用途 | 命令格式 |
| --- | --- |
| 查看当前目录 | `pwd` |
| 列出文件 | `ls -lh [目录]` |
| 切换目录 | `cd <目录>` |
| 查看文本 | `cat <文件>` |
| 复制文件 | `cp <源文件> <目标文件>` |
| 创建目录 | `mkdir -p <目录>` |
| 添加执行权限 | `chmod +x <程序>` |
| 查看进程 | `ps` |
| 结束进程 | `kill <PID>` 或 `killall <程序名>` |
| 后台运行 | `<命令> >/tmp/<名称>.log 2>&1 &` |
| 查看内核日志 | `dmesg | tail -n <行数>` |
| 查看系统信息 | `uname -a`、`uptime`、`free` |
| 查看文件系统 | `mount`、`df -h` |
| 读寄存器 | `devmem <物理地址> 32` |
| 写寄存器 | `devmem <物理地址> 32 <数值>` |
| 刷新文件缓存 | `sync` |
| 重启 | `reboot` |
| 查看 BusyBox 命令 | `busybox --list` |

后台任务控制示例：

```sh
<程序及参数> >/tmp/test.log 2>&1 &
ps
cat /tmp/test.log
killall <程序名>
```

## 3. 网口配置与 TFTP

### 3.1 配置网络

```sh
ip link set eth0 up
ip addr replace 169.254.89.144/16 dev eth0
ping -c 3 169.254.89.146
```

### 3.2 下载文件

通用格式：

```sh
tftp -g -r <服务器文件名> -l <板端文件名> <服务器IP>
```

示例：

```sh
tftp -g -r test.wav -l /tmp/test.wav 169.254.89.146
tftp -g -r lvgl_audio_player -l /tmp/lvgl_audio_player 169.254.89.146
chmod +x /tmp/lvgl_audio_player
```

## 4. 检查设备

```sh
dmesg | grep -i -E 'lcd|vga|i2s|max98357|ps2|serio|atkbd|goodix|i2c'
ls -l /dev/fb* /dev/input/event* /dev/i2c-* /dev/snd/*
cat /sys/class/graphics/fb0/name
cat /sys/class/graphics/fb1/name
fbset -fb /dev/fb0
fbset -fb /dev/fb1
cat /proc/bus/input/devices
cat /proc/asound/cards
aplay -l
cat /proc/interrupts
```

`eventX` 编号不是固定的。根据 `/proc/bus/input/devices` 中的名称和
`Handlers=... eventX` 确认：

- `AT Raw Set 2 keyboard`：PS/2 键盘；
- `Goodix Capacitive TouchScreen`：LCD 触摸屏。

## 5. LCD 与 VGA 测试

### 5.1 避免 fbcon 干扰 LCD 程序

```sh
echo 0 > /sys/class/graphics/fbcon/cursor_blink
printf '\033[?25l' > /dev/tty1
```

运行 LVGL、游戏或整屏 RAW 测试前，先停止正在占用 framebuffer 的程序：

```sh
killall lvgl_audio_player 2>/dev/null
killall lvgl_test 2>/dev/null
```

### 5.2 显示 RGB565 RAW 文件

LCD 格式：480×800、RGB565、小端、文件恰好 768000 字节。

```sh
dd if=<LCD图片.raw> of=/dev/fb0 bs=768000 count=1
```

VGA 格式：640×480、RGB565、小端、文件恰好 614400 字节。

```sh
dd if=<VGA图片.raw> of=/dev/fb1 bs=614400 count=1
```

清屏：

```sh
dd if=/dev/zero of=/dev/fb0 bs=768000 count=1
dd if=/dev/zero of=/dev/fb1 bs=614400 count=1
```

测试写入耗时：

```sh
time dd if=<图片.raw> of=<framebuffer> bs=<整帧字节数> count=1
```

### 5.3 VGA 色条程序

```sh
tftp -g -r vga_fb_test -l /tmp/vga_fb_test 169.254.89.146
chmod +x /tmp/vga_fb_test
/tmp/vga_fb_test /dev/fb1
```

### 5.4 最小 LVGL 显示测试

命令格式：

```sh
lvgl_test [framebuffer]
```

LCD 示例：

```sh
tftp -g -r lvgl_test -l /tmp/lvgl_test 169.254.89.146
chmod +x /tmp/lvgl_test
echo 0 > /sys/class/graphics/fbcon/cursor_blink
/tmp/lvgl_test /dev/fb0
```

VGA 示例：

```sh
/tmp/lvgl_test /dev/fb1
```

按串口 `Ctrl+C` 退出。

## 6. PS/2 键盘与触摸测试

先用第 4 节的方法确定键盘和触摸对应的 `eventX`。

### 6.1 PS/2 键盘

```sh
tftp -g -r ps2_event_test -l /tmp/ps2_event_test 169.254.89.146
chmod +x /tmp/ps2_event_test
/tmp/ps2_event_test /dev/input/<键盘eventX>
```

按键后应看到 `KEY_*` 和 `SYN`，按 `Ctrl+C` 退出。

### 6.2 LCD 触摸

```sh
tftp -g -r touch_event_test -l /tmp/touch_event_test 169.254.89.146
chmod +x /tmp/touch_event_test
/tmp/touch_event_test /dev/input/<触摸eventX>
```

触摸时应看到坐标，松开时应看到 `TRACKING_ID -1`。

### 6.3 I2C 触摸芯片探测

```sh
tftp -g -r i2c_touch_linux_probe -l /tmp/i2c_touch_linux_probe 169.254.89.146
chmod +x /tmp/i2c_touch_linux_probe
/tmp/i2c_touch_linux_probe /dev/i2c-0
```

## 7. I2S/ALSA 播放测试

当前硬件格式固定为 WAV PCM、44100 Hz、双声道、S16_LE。FLAC/MP3 需先在
主机上转换，不能直接交给当前播放器。

### 7.1 播放已有 WAV

```sh
tftp -g -r xp_startup.wav -l /tmp/xp_startup.wav 169.254.89.146
aplay -D hw:0,0 /tmp/xp_startup.wav
```

必须显式使用 `-D hw:0,0`，避免精简版 ALSA 查找不存在的默认插件。

后台播放与停止：

```sh
aplay -D hw:0,0 /tmp/xp_startup.wav >/tmp/aplay.log 2>&1 &
cat /tmp/aplay.log
killall aplay
```

### 7.2 生成并播放测试 WAV

```sh
tftp -g -r i2s_wav_test -l /tmp/i2s_wav_test 169.254.89.146
chmod +x /tmp/i2s_wav_test
/tmp/i2s_wav_test /tmp/test.wav
aplay -D hw:0,0 /tmp/test.wav
```

## 8. LVGL 音频播放器

命令格式：

```sh
lvgl_audio_player [framebuffer] \
  [--input /dev/input/eventX] \
  [--alsa hw:CARD,DEVICE] \
  [--music-dir <WAV目录>] \
  [--track <初始WAV>] \
  [--menu]
```

准备程序和歌曲：

```sh
tftp -g -r lvgl_audio_player -l /tmp/lvgl_audio_player 169.254.89.146
mkdir -p /tmp/music
tftp -g -r song01.wav -l /tmp/music/song01.wav 169.254.89.146
tftp -g -r song02.wav -l /tmp/music/song02.wav 169.254.89.146
chmod +x /tmp/lvgl_audio_player
```

LCD + Goodix 触摸 + I2S：

```sh
echo 0 > /sys/class/graphics/fbcon/cursor_blink
/tmp/lvgl_audio_player /dev/fb0 \
    --input /dev/input/<触摸eventX> \
    --alsa hw:0,0 \
    --music-dir /tmp/music
```

直接打开菜单：

```sh
/tmp/lvgl_audio_player /dev/fb0 \
    --input /dev/input/<触摸eventX> \
    --alsa hw:0,0 \
    --music-dir /tmp/music \
    --menu
```

指定首播歌曲：

```sh
/tmp/lvgl_audio_player /dev/fb0 \
    --input /dev/input/<触摸eventX> \
    --alsa hw:0,0 \
    --music-dir /tmp/music \
    --track /tmp/music/song02.wav
```

播放器会动态扫描目录中的有效 WAV，并读取真实歌曲时长。后台运行格式：

```sh
/tmp/lvgl_audio_player <参数> >/tmp/lvgl_audio_player.log 2>&1 &
```

## 9. openvt 虚拟终端与文字输出

普通文本不能直接重定向到 `/dev/fb0` 或 `/dev/fb1`；应输出到 fbcon 对应的
虚拟终端。启动参数用 `fbcon=map:0` 选择 LCD，或用 `fbcon=map:1` 选择 VGA。
系统启动后可用 `con2fbmap` 动态修改每个虚拟终端的显示设备。

### 9.1 打开可交互虚拟终端

```sh
openvt -c <VT编号> -s -f -- /bin/sh
```

例如打开并切换到 `tty1`：

```sh
openvt -c 1 -s -f -- /bin/sh
```

此时可用 PS/2 键盘操作；串口仍可用于诊断。切换虚拟终端：

```sh
chvt <VT编号>
```

### 9.2 动态切换 LCD/VGA 映射

查询 `tty1` 当前映射：

```sh
con2fbmap 1
```

把 `tty1` 映射到 LCD（`fb0`）并切换到该终端：

```sh
con2fbmap 1 0
chvt 1
```

把 `tty1` 动态改为 VGA（`fb1`）：

```sh
con2fbmap 1 1
chvt 1
```

也可以让两个虚拟终端分别使用两个显示器：

```sh
con2fbmap 1 0
con2fbmap 2 1
openvt -c 1 -f -- /bin/sh
openvt -c 2 -f -- /bin/sh
chvt 1
```

`con2fbmap` 的 VT 编号从 1 开始，framebuffer 编号从 0 开始。它只改变
fbcon 文本终端的映射，不会迁移直接打开 `/dev/fbX` 的 LVGL 或 RAW 显示程序。

### 9.3 在 LCD/VGA 上运行 neofetch

```sh
openvt -c 1 -s -f -- /bin/sh -c \
  'export TERM=linux; clear; neofetch --config none --off; exec /bin/sh'
```

只向 `tty1` 输出一次：

```sh
TERM=linux neofetch --config none --off > /dev/tty1 2>&1
chvt 1
```

清除虚拟终端：

```sh
printf '\033[2J\033[H' > /dev/tty1
```

## 10. LED 与数码管

LED 和数码管由 CONFREG 直接控制，Linux 下可使用 `devmem` 访问物理地址，
无需额外驱动。

| 设备 | 物理地址 | 有效位 | 说明 |
| --- | --- | --- | --- |
| 16 个单色 LED | `0x1fd0f000` | `[15:0]` | 每一位控制一个 LED |
| 双色 LED 0 | `0x1fd0f004` | `[1:0]` | 两位分别控制两种颜色 |
| 双色 LED 1 | `0x1fd0f008` | `[1:0]` | 两位分别控制两种颜色 |
| 八位数码管 | `0x1fd0f010` | `[31:0]` | 每 4 位显示一个十六进制数字 |

### 10.1 单色 LED

读取当前状态：

```sh
devmem 0x1fd0f000 32
```

全部点亮、全部熄灭和交替点亮：

```sh
devmem 0x1fd0f000 32 0x0000ffff
devmem 0x1fd0f000 32 0x00000000
devmem 0x1fd0f000 32 0x0000aaaa
devmem 0x1fd0f000 32 0x00005555
```

只点亮第 `n` 个 LED 时写入 `1 << n`，例如只点亮 LED 3：

```sh
devmem 0x1fd0f000 32 0x00000008
```

简单流水灯测试：

```sh
i=0
while [ "$i" -lt 16 ]; do
    devmem 0x1fd0f000 32 $((1 << i))
    sleep 1
    i=$((i + 1))
done
devmem 0x1fd0f000 32 0
```

### 10.2 双色 LED

数值 `0` 关闭，`1` 和 `2` 分别选择两个颜色通道，`3` 同时打开两个通道：

```sh
# 双色 LED 0
devmem 0x1fd0f004 32 0
devmem 0x1fd0f004 32 1
devmem 0x1fd0f004 32 2
devmem 0x1fd0f004 32 3

# 双色 LED 1
devmem 0x1fd0f008 32 1
```

具体红、绿通道与数值 `1`、`2` 的对应关系可通过上述命令直接确认。

### 10.3 八位数码管

数码管寄存器包含八个十六进制数码，每个 nibble 对应一位，支持 `0`～`F`：

```sh
# 显示 12345678
devmem 0x1fd0f010 32 0x12345678

# 显示 DEADBEEF
devmem 0x1fd0f010 32 0xdeadbeef

# 全部显示 0
devmem 0x1fd0f010 32 0x00000000
```

硬件会自动进行八位动态扫描，软件只需写一次显示数据。若观察方向与数值顺序
相反，这是数码管在开发板上的物理排列方向造成的，不需要调整扫描频率。

## 11. LCD 俄罗斯方块

命令格式：

```sh
lcd_tetris [framebuffer] [键盘event]
```

下载并运行：

```sh
tftp -g -r lcd_tetris -l /tmp/lcd_tetris 169.254.89.146
chmod +x /tmp/lcd_tetris
echo 0 > /sys/class/graphics/fbcon/cursor_blink
/tmp/lcd_tetris /dev/fb0 /dev/input/<键盘eventX>
```

按键：左右移动、上键旋转、下键加速、空格暂停、回车重开、Esc 退出。程序只
刷新变化的方块，不进行持续整屏刷新。

## 12. 快速故障检查

```sh
# 网络
ip addr show eth0
ip link show eth0
ping -c 3 169.254.89.146

# 显示
cat /sys/class/graphics/fb0/name
cat /sys/class/graphics/fb1/name
fbset -fb /dev/fb0
fbset -fb /dev/fb1

# 输入
cat /proc/bus/input/devices
cat /proc/interrupts

# 音频
cat /proc/asound/cards
aplay -l
dmesg | grep -i -E 'i2s|alsa|underrun|axi error'
```

若 LCD 周期性闪烁或系统被光标刷新拖慢：

```sh
echo 0 > /sys/class/graphics/fbcon/cursor_blink
```

若多个程序同时操作同一个 framebuffer 或 ALSA 设备，先停止旧程序后再测试。
