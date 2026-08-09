# Loongson SoC LCD 扩展修改说明

## 1. 修改目标

本次修改在 `chip/soc_demo/loongson` SoC 上增加一个存储器映射的 16 位
Intel/8080 并口 LCD 控制器，并完成以下配套工作：

- 增加 LCD AXI 从设备及寄存器接口；
- 将 AXI 从设备互联由 5 路扩展为 6 路；
- 在 SoC 顶层实例化 LCD 控制器并引出板级信号；
- 将 LCD RTL 文件加入 Vivado 2019.2 和 2023.2 工程；
- 按参考约束增加 LCD 管脚和电平标准；
- 增加可通过 U-Boot/TFTP 下载运行的裸机 LCD 测试程序。

## 2. 修改文件

| 文件 | 修改内容 |
| --- | --- |
| `IP/LCD/lcd_axi_controller.v` | 新增 AXI3 到 16 位 8080 LCD 控制器和同步 FIFO |
| `IP/AMBA/axi_mux_syn.v` | AXI 从设备数由 5 增加到 6，新增 LCD 地址译码和 `s5` 通道 |
| `chip/soc_demo/loongson/soc_top.v` | 增加 LCD 顶层端口、AXI 连线和控制器实例 |
| `fpga/loongson/2019.2/system_run.xpr` | 将 LCD RTL 加入 Vivado 2019.2 工程 |
| `fpga/loongson/2023.2/system_run.xpr` | 将 LCD RTL 加入 Vivado 2023.2 工程 |
| `fpga/loongson/soc_up.xdc` | 增加 LCD 管脚和 `LVCMOS33` 约束 |
| `IP/LCD/rst_rom.coe` | 将 LCD 行窗口结束地址修正为 799（480 × 800） |
| `software/bsp/env/start_uboot.S` | 新增通用的非缓存 U-Boot 启动入口 |
| `software/bsp/env/uboot_uncached.lds` | 新增通用的 `0x80300000` U-Boot 链接布局 |
| `software/bsp/common.mk` | 新增 `make uboot` 并行构建目标 |
| `software/examples/lcd_test/main.c` | 新增裸机寄存器自检、LCD 初始化和显示测试 |
| `software/examples/lcd_test/Makefile` | 新增裸机程序构建配置 |
| `software/examples/lcd_test/README.md` | 增加编译和 U-Boot 启动说明 |

## 3. 地址映射

LCD 控制器占用一个 64 KiB 地址窗口：

| 类型 | 地址 | 用途 |
| --- | --- | --- |
| AXI 物理地址 | `0x1fa0_0000`～`0x1fa0_ffff` | 总线译码地址 |
| 上电直启裸机映射 | `0xbfa0_0000`～`0xbfa0_ffff` | 默认 BSP 启动代码重建 DMW 后使用 |
| U-Boot 非缓存映射 | `0x9fa0_0000`～`0x9fa0_ffff` | 本测试程序保留 U-Boot DMW 时使用 |

`axi_slave_mux` 中新增的 `s5` 对写地址和读地址分别判断
`addr[31:16] == 16'h1fa0`。原有从设备编号保持不变：

| AXI 从端口 | 设备 |
| --- | --- |
| `s0` | DDR3/默认地址空间 |
| `s1` | SPI/片内 SRAM 区域 |
| `s2` | APB 外设 |
| `s3` | CONFREG |
| `s4` | Ethernet MAC |
| `s5` | 新增 LCD 控制器 |

## 4. LCD 寄存器

所有寄存器均按 32 位对齐访问，控制器只使用地址低 16 位。

| 偏移 | 名称 | 访问 | 定义 |
| --- | --- | --- | --- |
| `0x00` | `CTRL` | 读写 | bit0：写 1 触发 FIFO/写引擎软复位；bit1：`lcd_rst_n`；bit2：背光使能 |
| `0x04` | `STATUS` | 只读 | bit0：FIFO 空；bit1：FIFO 满；bit2：控制器忙；bit3：复位输出状态；bit4：背光状态；bit16:8：FIFO 数据量 |
| `0x08` | `TIMING` | 读写 | bit7:0：数据建立周期；bit15:8：写低电平周期；bit23:16：数据保持周期 |
| `0x10` | `CMD` | 只写 | 将低 16 位作为 LCD 命令写入 FIFO，输出时 `lcd_rs=0` |
| `0x14` | `DATA` | 只写 | 将低 16 位作为 LCD 数据写入 FIFO，输出时 `lcd_rs=1` |

`TIMING` 的每个字段写入 0 时仍按 1 个时钟周期执行。复位默认值为
`0x0001_0101`，即建立、写脉冲和保持时间各为一个 AXI 时钟周期。

## 5. LCD 控制器实现

`lcd_axi_controller` 直接连接 SoC 的 AXI3 从接口，支持 32 位、FIXED 或
INCR 类型访问。控制器内部包含一个默认深度为 256、宽度为 17 位的同步
FIFO：16 位保存命令或数据，额外 1 位保存 `RS` 属性。

当 FIFO 满时，控制器通过 AXI `WREADY` 对 CPU 施加回压，因此裸机软件可以
连续写 `CMD` 或 `DATA` 寄存器，不需要在每次写入前轮询 FIFO。内部状态机按
以下顺序产生 8080 写时序：

1. 输出数据、`RS`，并拉低 `CS_N`；
2. 等待建立时间；
3. 拉低 `WR_N` 并保持设定周期；
4. 拉高 `WR_N` 并等待保持时间；
5. 释放 `CS_N` 和数据总线。

当前版本只实现 LCD 写操作，`lcd_rd_n` 固定为高电平，不支持读取 LCD ID、
GRAM 或状态寄存器。它也不包含帧缓冲和 DMA，像素数据由 CPU 通过 MMIO
写入。

对从 `DATA` 寄存器开始的 AXI burst 做了流式处理：后续每个 beat 仍被视为
LCD 数据，而不是因地址递增落到其他寄存器。这为以后增加 DMA 批量像素传输
保留了接口基础。

## 6. AXI 互联修改

`axi_mux_syn.v` 的从设备数量由 `SLV_MUX_5`/5 修改为 `SLV_MUX_6`/6，新增
完整的 `s5` AXI 写地址、写数据、写响应、读地址和读数据通道。

同时调整了以下逻辑：

- 响应仲裁第二组由两个有效端口扩展为 `s3`～`s5` 三个端口；
- 读写地址命中向量加入 `0x1fa0_xxxx`；
- 默认 DDR 命中条件排除 LCD 地址范围；
- 选择编号比较显式使用 3 位宽，避免扩展到 6 路后的位宽告警；
- AXI 默认响应值改用参数化位宽；
- 内部小 FIFO 的复位值改为按 `FIFO_WIDTH` 参数生成。

## 7. SoC 顶层修改

`soc_top.v` 新增如下外部端口：

```verilog
output        lcd_cs_n;
output        lcd_wr_n;
output        lcd_rd_n;
output        lcd_rs;
output        lcd_rst_n;
inout  [15:0] lcd_db;
output        lcd_bl_ctr;
```

顶层增加了一组 `lcd_s_*` AXI 信号，将 `axi_slave_mux` 的 `s5` 连接到
`lcd_axi_controller`。控制器与 SoC 外设总线共用 `aclk` 和 `aresetn`。

## 8. FPGA 管脚约束

LCD 接口统一设置为 `LVCMOS33`。当前约束来自提供的参考 XDC：

| 信号 | FPGA 管脚 | 信号 | FPGA 管脚 |
| --- | --- | --- | --- |
| `lcd_rst_n` | J25 | `lcd_db[0]` | H9 |
| `lcd_cs_n` | H18 | `lcd_db[1]` | K17 |
| `lcd_rs` | K16 | `lcd_db[2]` | J20 |
| `lcd_wr_n` | L8 | `lcd_db[3]` | M17 |
| `lcd_rd_n` | K8 | `lcd_db[4]` | L17 |
| `lcd_bl_ctr` | J15 | `lcd_db[5]` | L18 |
| `lcd_db[6]` | L15 | `lcd_db[7]` | M15 |
| `lcd_db[8]` | M16 | `lcd_db[9]` | L14 |
| `lcd_db[10]` | M14 | `lcd_db[11]` | F22 |
| `lcd_db[12]` | G22 | `lcd_db[13]` | G21 |
| `lcd_db[14]` | H24 | `lcd_db[15]` | J16 |

生成 bitstream 前应再次对照实际开发板原理图，确认这些管脚没有和现有外设
复用或冲突，并确认 LCD 模块的 IO 电压确实为 3.3 V。

## 9. 裸机测试程序

测试程序位于 `software/examples/lcd_test`，默认参数如下：

- LCD 非缓存基地址：`0x9fa0_0000`；
- 屏幕分辨率：480 × 800；
- 像素格式：RGB565；
- CPU 时钟：50 MHz；
- CONFREG 时钟：33 MHz；
- 串口地址：`0x9fe0_01e0`。

程序执行流程为：

1. 写入并读回 `TIMING` 和 `CTRL`，确认 LCD AXI 地址可访问；
2. 清空 FIFO、复位写引擎并控制外部 LCD 硬复位；
3. 用软件回放原 `rst_rom.coe` 中的厂商初始化序列；
4. 设置全屏显示窗口；
5. 循环显示红、绿、蓝、白、黑纯色、八色竖向彩条和 16 × 32 ASCII 字体页；
6. 将测试进度和错误信息输出到串口。

`Makefile` 调用 `coe_to_c.awk`，把 `IP/LCD/rst_rom.coe` 自动转换为
`lcd_init_sequence.h`。该 COE 共 783 个 17 位字，编码与原参考 LCD RTL 一致：
bit 16 为 1 表示命令、为 0 表示数据，bits 15:0 是 LCD 总线值。程序在回放完
第 763 项 `0x1100`（Sleep Out）之后等待写 FIFO 空闲并延时 120 ms，然后发送
剩余初始化项。COE 最后已包含 `0x2900`（Display On）和 `0x2c00`（Memory
Write）。

这块屏的列、行和显存写命令使用 16 位寄存器形式，而不是通用 8 位 DCS 形式。
例如列地址依次写 `0x2a00`、`0x2a01`、`0x2a02`、`0x2a03`，行地址使用
`0x2b00`～`0x2b03`，开始写像素使用 `0x2c00`。

`Makefile` 还通过 `font_coe_to_c.awk` 将 `IP/LCD/font_rom.coe` 转换为
`lcd_font_16x32.h`。原文件的 65536 个 1 bit 项对应 128 个 ASCII 字符，每个
字符为 16 × 32 点阵。转换时每行压缩成一个 `uint16_t`，因此软件字库在 ELF
中只占 8 KiB。`lcd_draw_char()` 设置单字符窗口并逐点写入前景色或背景色，
`lcd_draw_text()` 负责字符串换行和屏幕边界处理，不再需要 FPGA 字符 ROM 或
硬件文字渲染状态机。

逐行标记测试进一步确认了面板的有效高度是 800 行：向第 800～839 行写绿色、
第 840～853 行写粉色、第 854～863 行写黄色时，这三段颜色都回绕到了屏幕
顶部。因此原来的 480 × 864 配置会使最后 64 行覆盖最上面的 64 行，表现为
界面底部内容出现在顶部以及约半秒一次的闪烁。初始化序列的行结束地址现为
`0x031f`（十进制 799），逐行诊断程序仍保留 864 行输出，用于复现和定位
地址回绕问题。

## 10. 编译和 U-Boot 网络加载

编译命令：

```sh
cd software/examples/lcd_test
make uboot
```

该测试工程使用 BSP 的 `uboot_uncached.lds`：代码区位于 `0x8030_0000`，数据区
位于 `0x8038_0000`。二者都处于 U-Boot 配置的非缓存 `0x8...` DMW 窗口内。
不能使用默认的 `env/separate.lds`：后者把 ELF 链接到低地址 `0x1c00_0000`，
U-Boot 在装载第一个 LOAD 段时会触发 TLB Refill 异常。

LCD 工程通过 BSP 公共的 `start_uboot.S` 和 ELF 入口符号 `_start_uboot`
实现链式启动。该入口不执行任何 `cacop`，也不重建 DMW 或重新初始化 UART。
代码和数据使用 `0x8...` 非缓存窗口，LCD、UART 和 CONFREG 使用 `0x9...`
非缓存别名，整个测试程序不依赖 Cache。

为便于定位板上早期启动问题，链式启动路径在进入 `main()` 前直接通过 UART
输出 `SDM`：`S` 表示已进入非缓存启动代码，`D` 表示 `.data/.bss` 初始化完成，`M`
表示即将调用 `main()`。哪一个字符没有出现，就说明程序停在它之前的阶段。

生成文件：

- `obj/lcd_test_uboot.elf`：推荐通过 U-Boot `bootelf` 启动；
- `obj/lcd_test_uboot.bin`：裸二进制文件；
- `obj/lcd_test_uboot.s`：反汇编文件。

已编译生成的 ELF 为 32 位小端 LoongArch 可执行文件。为匹配 U-Boot 已建立
的非缓存直接映射，程序代码链接到 `0x8030_0000`，数据区链接到 `0x8038_0000`。
将 `lcd_test_uboot.elf` 放到 TFTP 根目录后，在 U-Boot 中执行：

```text
setenv ipaddr <开发板IP>
setenv serverip <TFTP服务器IP>
ping ${serverip}
tftpboot 0xa3000000 lcd_test_uboot.elf
bootelf 0xa3000000
```

`0xa300_0000` 只作为下载缓冲区；`bootelf` 按 ELF Program Header 将各段装载
到链接地址，并跳转到 `0x8030_0000`。程序不会返回 U-Boot，需要复位开发板
才能停止。

## 11. Linux fbdev 支持

Linux 使用 `/home/xpg/chiplab-old/la32r-Linux` 源码树。以下参数已统一为
480 × 800：

- `drivers/video/fbdev/loongson_lcd.c` 中的默认高度；
- `drivers/video/fbdev/loongson_lcd_init.h` 中的 LCD 行窗口结束地址；
- `arch/loongarch/boot/dts/loongson/loongson32_ls.dts` 中的 `height` 属性。

驱动内建到内核，设备树也以内建方式使用 `loongson32_ls`。启动新编译的
`vmlinux` 后，`fbset -fb /dev/fb0` 应报告 `geometry 480 800 480 800 16`，
此时一帧 RGB565 数据大小为 `480 * 800 * 2 = 768000` 字节。LVGL 测试程序
位于 `software/lvgl_test_linux`，通过 `/dev/fb0` 输出，不需要修改根文件系统
即可经 TFTP 下载运行。

## 12. 验证状态和后续工作

目前已经完成裸机程序的交叉编译和 ELF 结构检查。完整验证仍需以下步骤：

1. 使用 Vivado 对修改后的工程完成综合、实现并生成 bitstream；
2. 检查实现阶段是否存在管脚冲突、IO Bank 电压或时序问题；
3. 下载 bitstream 后先观察串口中的 AXI 寄存器自检结果；
4. 使用示波器或逻辑分析仪检查 `CS_N`、`WR_N`、`RS` 和数据总线时序；
5. 若屏幕仍无显示，核对 `rst_rom.coe` 所针对的 LCD 控制芯片型号，并检查
   8080 总线的 `CS_N`、`WR_N`、`RS` 和数据建立/保持时间；
6. 如需提高刷新速度，可进一步增加 DMA 或帧缓冲机制。
