# Linux I2S 播放快速步骤

本文假设：

- 开发板 IP：`169.254.89.144`
- TFTP 服务器 IP：`169.254.89.146`
- 最新 Buildroot 根文件系统已经嵌入 `vmlinux`
- MAX98357A 已连接 BCLK、LRCLK、DIN、电源和公共地

## 1. 主机准备文件

裁剪最新内核：

```sh
cd /home/xpg/chiplab-old/la32r-Linux

/home/xpg/chiplab-old/toolchains/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-strip \
  -o vmlinux.tftp vmlinux
```

将下面两个文件复制到你的 TFTP 根目录：

```text
/home/xpg/chiplab-old/la32r-Linux/vmlinux.tftp
/home/xpg/chiplab/software/examples/i2s_wav_uboot_test/haruhikage_30s_compressed_peak_minus12db.wav
```

例如 TFTP 根目录是 `/srv/tftp`：

```sh
sudo cp /home/xpg/chiplab-old/la32r-Linux/vmlinux.tftp /srv/tftp/
sudo cp /home/xpg/chiplab/software/examples/i2s_wav_uboot_test/haruhikage_30s_compressed_peak_minus12db.wav /srv/tftp/
```

## 2. U-Boot 启动 Linux

开发板上电进入 U-Boot 后执行：

```text
setenv ipaddr 169.254.89.144
setenv serverip 169.254.89.146
ping 169.254.89.146
tftpboot 0xa3000000 vmlinux
bootelf 0xa3000000 vmlinux console=tty0 console=ttyS0,115200 rdinit=/init
```

等待 Linux 启动完成，然后登录 `root`。

## 3. Linux 下载并播放

配置网络：

```sh
ip link set eth0 up
ip addr replace 169.254.89.144/16 dev eth0
ping -c 3 169.254.89.146
```

确认声卡存在：

```sh
cat /proc/asound/cards
aplay -l
```

下载歌曲：

```sh
tftp -g \
  -r haruhikage_30s.wav \
  -l /tmp/test.wav \
  169.254.89.146
```

播放：

```sh
aplay -D hw:0,0 /tmp/test.wav
```

如果 `aplay -l` 显示的声卡不是 card 0，把 `hw:0,0` 中第一个数字改成实际卡号。

## 4. 播放异常时只检查这三项

```sh
dmesg | grep -i -E 'i2s|asoc|max98357|underrun|error'
cat /proc/interrupts | grep -i -E 'i2s|media'
ls -l /tmp/test.wav
```

歌曲文件的正确大小是 `5292044` 字节。播放时不应出现 `I2S underrun` 或
`AXI error`。
