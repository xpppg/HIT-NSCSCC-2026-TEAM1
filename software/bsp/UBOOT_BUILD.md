# BSP U-Boot ELF 构建模式

使用 `common.mk` 的示例现在有两种互不替代的构建方式：

```sh
make
```

生成原有的 `0x1c000000` 直接启动程序。

```sh
make uboot
```

生成 `obj/<target>_uboot.elf`，代码入口为 `0x80300000`，数据区位于
`0x80380000`。代码、数据和栈都通过 U-Boot 的 `0x8...` 非缓存 DMW 窗口
访问，生成的 ELF 不包含 `cacop`。

该模式的 ELF 让每个带文件内容的 LOAD 段满足 `VirtAddr == PhysAddr`。本项目
U-Boot 按 `VirtAddr` 装载数据，因此不能沿用直接启动镜像中“数据 VMA 位于
DSRAM、LMA 紧跟代码”的布局。

应用在 `BOOT_FROM_UBOOT` 宏有效时，应使用 `0x9...` 非缓存外设别名。例如：

```c
#ifdef BOOT_FROM_UBOOT
unsigned long UART_BASE = 0x9fe001e0;
#else
unsigned long UART_BASE = 0xbfe001e0;
#endif
```

U-Boot 加载命令：

```text
tftpboot 0xa3000000 <target>_uboot.elf
bootelf 0xa3000000
```

启动入口会输出阶段字符：`S` 表示进入入口，`D` 表示数据和 BSS 初始化完成，
`M` 表示即将进入 `main()`，`R` 表示 `main()` 已返回，`E` 表示发生异常。
