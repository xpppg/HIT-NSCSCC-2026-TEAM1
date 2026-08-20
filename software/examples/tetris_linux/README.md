# LCD Tetris

面向当前 LA32R Linux 系统的轻量俄罗斯方块测试程序：

- LCD：默认 `/dev/fb0`，480×800、RGB565。
- 键盘：默认 `/dev/input/event0`，使用 Linux `EV_KEY`。
- 操作：左右移动、上键旋转、下键加速下降、空格暂停、回车重新开始、Esc 退出。
- 启动后使用 `EVIOCGRAB` 独占键盘，并将当前 VT 临时切换到
  `KD_GRAPHICS`，退出时自动恢复。

程序只在初始化时清屏。游戏运行时比较新旧棋盘，只向 framebuffer
写入发生变化的方块范围。当前 LCD 内核驱动按脏行 DMA，因此最终传输范围
是这些方块所覆盖的少量 LCD 行，而不是每次传输完整的 480×800 帧。

## 编译

```bash
cd /home/xpg/chiplab/software/examples/tetris_linux
make
```

生成文件为 `lcd_tetris`。

## 运行

```bash
lcd_tetris [framebuffer] [input-event]
```

例如：

```bash
/tmp/lcd_tetris /dev/fb0 /dev/input/event0
```

建议从串口 shell 启动。这样串口保留诊断输出，LCD 只显示游戏画面。
