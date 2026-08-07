# myCPU CPU 架构详细分析

> 分析对象：`IP/myCPU` 目录下的 RTL 源码  
> 分析基线：提交 `49d1379`（工作区中 `myCPU` 源码无未提交修改）  
> 分析方式：静态阅读 RTL、模块层次和已有 Verilator 编译日志；本文不把尚未接通的模块视为有效功能，也不以仿真可编译代替功能正确性证明。

## 1. 总体结论

`myCPU` 是一个面向 LoongArch32 Reduced（LA32R）的 32 位、顺序执行、双发射、双提交处理器核。核心采用较深的顺序流水线，在前端每拍最多获取两条指令，通过取指缓冲解耦 I-Cache 和后端；后端最多并行执行两条普通运算指令，但分支、访存、CSR/特权指令等共享单套功能单元，因此会限制双发射。

从 RTL 可以确认的主要能力如下：

| 项目 | 实现情况 |
| --- | --- |
| ISA | 32 位 LA32R 子集，包含整数、乘除、分支、访存、CSR、TLB、LL/SC 等 |
| 执行模型 | 顺序发射、顺序执行、顺序提交；不是乱序执行 |
| 取指/提交宽度 | 每拍最多 2 条 |
| 流水级 | `pre-IF → IF1 → IF2 → ID/取指队列 → IS → EXE → MEM/提交` |
| 整数执行 | 两套 ALU，第二槽主要执行 `inst_normal` 类指令 |
| 分支预测 | 双读口、2 路 BTB + BHT/PHT 混合方向预测 |
| 寄存器堆 | 32×32 位，4 读 2 写，带 EXE/MEM 旁路 |
| I-Cache | 8 KiB，2 路，64 组，64 B 行，双字读取 |
| D-Cache | 8 KiB，2 路，64 组，64 B 行，写回、写分配 |
| 地址翻译 | 16 项全相联 TLB，双搜索口，支持 4 KiB/4 MiB 页和 DMW |
| 外部总线 | 32 位 AXI，Cache 行以 16 个 32 位 beat 传输 |
| 特权支持 | CSR、异常/中断、TLB 指令、定时器、LL/SC |
| 验证接口 | 最多双指令提交的 Difftest、寄存器和 CSR 状态导出 |

架构可以概括为：

```text
                         +--------------------------+
 next PC ──> BPU ───────>│ pre-IF / IF1 / IF2      │
    ^                    │ 每拍取 2 条，I-TLB/I$    │
    │                    +------------+-------------+
    │                                 │
    │                    +------------v-------------+
    │                    │ 16-entry Fetch Buffer    │
    │                    +------------+-------------+
    │                                 │ 最多 2 条
    │                    +------------v-------------+
    │                    │ 双译码 / IS / 相关检测    │
    │                    │ 4R2W Regfile + Forwarding│
    │                    +------+-------------+-----+
    │                           │             │
    │                    +------v------+ +----v-----+
    │                    │ ALU0        │ │ ALU1     │
    │                    │ BRU/LSU/PEU │ │ 普通整数 │
    │                    +------+------+ +----+-----+
    │                           │             │
    │                    +------v-------------v-----+
    +── mispredict/excp ─│ MEM / 顺序双提交 / CSR   │
                         +-------------+------------+
                                       │
                              D-TLB → D$/Uncache
                                       │
                              AXI arbiter/controller
```

## 2. RTL 组织与模块层次

### 2.1 顶层层次

对外顶层是 `mycpu_top.v` 中的 `core_top`，内部主要包含：

```text
core_top
├── mycpu_core          流水线、译码、执行、CSR、MMU、提交
│   ├── pre_IF
│   ├── BPU
│   │   ├── BTB
│   │   └── PHT
│   ├── IF
│   ├── fetch_buffer
│   ├── ID × 2
│   ├── regfile
│   ├── alu × 2
│   ├── bru
│   ├── lsu
│   ├── peu
│   ├── CSR0
│   └── MMU
│       └── tlb
├── icache
├── vcache              已实例化但未接通有效数据路径
├── dcache
├── dbuffer             实际作用是 D-Cache 行预取缓冲
├── uncache
└── axi_control
```

`mycpu_core` 使用类 SRAM 接口访问指令和数据；`core_top` 把它们连接到 Cache、非缓存通路和 AXI 控制器。这样将流水线与外部存储协议隔离，但当前接口没有标准 `addr_ok/data_ok` 握手，而是依赖 `fetch_stall/cpu_stall` 冻结请求。

### 2.2 文件职责

| 文件 | 主要职责 |
| --- | --- |
| `mycpu_top.v` | CPU 对外 AXI 顶层、Cache/Uncache/AXI 集成、请求保持 |
| `mycpu_core.v` | 流水线控制、双发射、旁路、异常、提交、模块集成 |
| `pre_IF.v`、`IF.v` | PC 生成、预测等待、取指流水寄存和双指令获取 |
| `fetch_buffer.v` | 取指队列，保存 PC、指令、预测和取指异常信息 |
| `ID.v` | 指令译码、立即数、功能单元控制和译码级异常 |
| `regfile.v` | 4 读 2 写通用寄存器堆 |
| `alu.v`、`div.v` | 两套整数 ALU、乘法和迭代除法 |
| `bru.v` | 分支条件、实际目标和预测错误检测 |
| `lsu.v` | 访存地址/掩码/数据格式、对齐异常、LL/SC 请求 |
| `peu.v` | CSR、计数器、TLB 和 ERTN 等特权操作执行 |
| `CSR.v` | 特权寄存器、异常入口/返回、定时器和 LLBit |
| `MMU.v`、`tlb.v` | 地址模式选择、TLB 查询/维护、页异常 |
| `BPU.v`、`bram.v` | BTB、BHT/PHT 和对应推断 RAM |
| `icache*.v` | I-Cache 标签、状态机和数据阵列 |
| `dcache*.v` | D-Cache 标签、替换、写回和数据阵列 |
| `dbuffer.v` | 两行顺序预取缓冲 |
| `uncache.v` | 非缓存单次访问状态机 |
| `axi_control.v` | AXI 读写仲裁、Cache 行 burst 拼装/拆分 |
| `victim_cache.v` | 32 行全相联 victim cache 草案，目前未形成有效路径 |
| `CPU_WB_STAGE.v` | 旧的单端口调试提交序列化模块，目前未被实例化 |
| `salu` | `alu.v` 内的备用简单 ALU，目前未被实例化 |

## 3. 顶层接口与时钟复位

### 3.1 外部接口

`core_top` 对外提供：

- 单时钟 `aclk` 和低有效复位 `aresetn`；
- 8 位硬件中断输入 `intrpt`；
- 32 位 AXI 读、写地址、写数据和响应通道；
- 两组写回调试口，对应两个提交槽；
- 比赛模板要求的 `break_point/infor_flag/reg_num/ws_valid/rf_rdata` 调试口。

模板调试口目前被直接置零，只有两组 `debug*_wb_*` 能反映实际提交。AXI 的 `arlen/awlen` 在外部顶层声明为 8 位，而 `axi_control` 内部是 4 位，当前通过连接时的隐式扩展工作，应统一宽度。

### 3.2 复位行为

内部先把 `~resetn` 寄存为 `clk_rst`，再形成同步高有效 `reset`。PHT 初始化期间还会拉起 `pht_rst`，并被并入全核复位：

```text
reset = delayed(~resetn) OR pht_rst
```

PHT 有 2048 个条目，复位状态机逐项写零，因此上电后大约需要 2048 拍完成预测表清零。这样适合 BRAM 推断，但意味着核的可执行复位时间远长于普通流水线复位。

初始 PC 设为 `0x1bff_fffc`，顺序 next PC 在复位后成为 `0x1c00_0000`，即软件启动地址。

## 4. 流水线组织

### 4.1 逻辑流水级

虽然代码未用统一总线定义每一级，但可从 valid、allowin 和流水寄存器还原出以下阶段：

| 阶段 | 作用 |
| --- | --- |
| pre-IF | 根据异常、ERTN、分支纠错和预测结果选择 next PC |
| IF1 | 发起 I-TLB 查询、物理地址生成和 I-Cache 请求 |
| IF2 | 接收一行中的相邻两条指令，绑定预测和取指异常 |
| ID | 16 项 Fetch Buffer 队首的双译码 |
| IS | 读取 4 端口寄存器堆、旁路、检查相关和功能单元冲突 |
| EXE | 两套 ALU；槽 0 还连接 BRU、LSU、PEU 和 MMU |
| MEM | 获取 load 数据，提交寄存器/CSR/异常/分支结果 |

代码中没有真正实例化独立 WB 阶段，`MEM` 实际承担了提交/写回职责，`WB_allowin` 被固定为 1。因此称其为 7 个逻辑阶段比“固定 8 级流水”更准确；`CPU_WB_STAGE.v` 是未使用的旧实现。

### 4.2 valid/allowin 控制

各级采用 ready/allowin 风格：

```text
allowin = (ready_go AND next_allowin) OR NOT valid
```

主要停顿源为：

- I-Cache miss：`fetch_stall`；
- D-Cache 或非缓存访问：`cpu_stall`；
- BPU 同步 RAM 返回等待：`pred_wating`；
- I-TLB/D-TLB 查询等待：`fetch_wating/mmu_wating`；
- load-use、乘除和 CSR 相关；
- D-Cache 写回与新 load 的次序冲突。

异常、ERTN、TLB 重定向和分支预测错误会清除前端及在途 valid。当前 `tlb_remake` 固定为 0，对应的 `tlb_entry` 也未驱动，属于保留但未启用的重定向通路。

### 4.3 全局冻结与请求保持

`core_top` 对指令/数据 SRAM-like 请求增加一级保持寄存器。当 Cache 拉高 stall 后，请求地址、写掩码和写数据保持不变，直到 stall 解除。这弥补了接口缺少显式请求握手的问题，但跨层依赖较强：任何 Cache 状态机修改都必须保持 stall 与请求采样时序一致。

## 5. 双取指、Fetch Buffer 与双发射

### 5.1 每拍双取指

正常情况下 PC 每拍前进 8 字节，同时 I-Cache 返回 `PC` 和 `PC+4` 两条指令。若第一条位于 64 B Cache 行最后一个字，`sub_inst_valid` 置零，PC 只前进 4 字节，避免第二条跨行读取。

若第一条预测为跳转，第二条会被取消；若第二条预测为跳转，则两条均可进入队列，下一次取指从第二条的预测目标继续。

### 5.2 Fetch Buffer

`fetch_buffer` 物理上定义了 16 项数组，保存：

- PC；
- 指令字；
- 预测 taken、target、PHT 旧状态；
- 取指阶段异常信息。

写端和读端均支持每拍 1 或 2 项。`full = count[3]`，因此计数达到 8～15 时即禁止继续写入，源码注释称“real max_depth = 9”。这意味着阵列虽有 16 项，但有效可用深度大约只有 8～9 项，不能按 16 项满容量理解。

### 5.3 双发射规则

两条指令都经过独立 `ID` 译码，但第二执行槽只承接 `inst_normal` 类指令。该类包括：

- 普通整数算术、逻辑和移位；
- `mul.w/mulh.w/mulh.wu`；
- `cpucfg/cacop/dbar/ibar` 在译码上也被标为 normal。

分支、load/store、除法、CSR、TLB、ERTN、LL/SC 等不属于第二槽可自由并行的普通类。发射规则可概括为：

1. 两条都是普通指令：分别送 ALU0、ALU1；
2. 一条普通、一条特殊：特殊指令送主槽，普通指令可转向副槽；
3. 两条都是特殊指令：发生结构冲突，只发射较老指令；
4. 第二条读取第一条目的寄存器：禁止同拍双发射；
5. CSR 写及相关特权操作与流水线中已有 CSR 操作串行化。

这是静态、保序的双发射机制，没有 rename、ROB、保留站或动态调度。

### 5.4 槽位交换 `turning`

当第一条普通、第二条特殊时，第二条会进入主执行槽，第一条转入副 ALU，物理槽位与程序次序发生交换。`ex_turning/wb_turning/rf_we_turning` 用于恢复逻辑提交顺序，并解决两写口写同一寄存器时“较新指令最终生效”的语义。

这一设计节省了复制 BRU/LSU/PEU 的资源，但显著增加了旁路、异常屏蔽、调试提交和双写冲突逻辑的复杂度。

## 6. 数据相关、旁路和寄存器堆

### 6.1 寄存器堆

寄存器堆为 32×32 位：

- 4 个组合读口，分别服务两条指令的两个源操作数；
- 2 个同步写口；
- 读地址为 0 时固定返回 0；
- 两写口命中同一目的寄存器时，依靠 `turning` 控制赋值次序。

RTL 没有复位整个寄存器数组。除 `$r0` 外的初值依赖软件在读取前写入，或依赖仿真器未初始化策略；这是常见的 FPGA 面积选择，但随机复位验证必须特别关注未初始化读取。

### 6.2 旁路网络

四个源操作数均具有：

- EXE 主槽结果旁路；
- EXE 副槽结果旁路；
- MEM/提交主写口旁路；
- MEM/提交副写口旁路。

只有 ALU 的单周期算术、逻辑、移位和 LUI 类结果声明 `forward_ok`。乘法、除法、load 和 PEU 结果不可在 EXE 直接旁路，因此消费者必须等待。

### 6.3 冒险检测

主要 RAW 检测包括：

- IS 中两条指令之间的同拍 RAW；
- IS 相对 EXE 两槽目的寄存器的相关；
- CSR 指令相对 IS/EXE/MEM 中 CSR 写的相关。

设计没有 WAR/WAW 动态冒险，因为整体保序；但双写同一寄存器通过写口次序显式处理。

## 7. 执行单元

### 7.1 两套 ALU

两套 `alu` 功能相同，支持：

- `add/sub`；
- 有符号/无符号比较；
- `and/or/nor/xor`；
- 逻辑/算术移位；
- LUI/立即数传递；
- `mul.w/mulh.w/mulh.wu`；
- `div.w/mod.w/div.wu/mod.wu`。

由于发射规则限制，第二套 ALU 主要提高普通整数和乘法指令吞吐率。

### 7.2 乘法器

乘法器把两个 32 位操作数拆成 4 个 16×16 乘法，使用 `use_dsp48` 属性引导 FPGA DSP 推断，再组合为 64 位结果。输入在一个时钟沿采样，下一拍 `result_valid` 有效，因此从流水线观察是一个需要停顿的短延迟运算。

有符号控制只在 `mulh.w` 打开；`mul.w` 取低 32 位，符号与否低位相同，逻辑成立。

### 7.3 除法器

`div` 是逐位恢复除法器，源码注明执行约 34 周期。EXE 在 `div_wating` 期间冻结。两套 ALU 各自实例化了一套除法器，但译码没有把除法标为可进入第二普通槽，因此副除法器通常不会获得有效除法指令，属于资源与发射规则不完全匹配。

### 7.4 BRU

BRU 支持条件分支、`b/bl/jirl`，在 EXE 计算实际 taken 和 target，并比较取指时携带的预测信息。以下任一情况触发 `br_taken` 重定向：

- 实际跳转、预测不跳；
- 实际不跳、预测跳转；
- 都预测跳转，但目标地址错误。

虽然 BRU 在 EXE 得出结果，纠错信号被寄存到 MEM 后才反馈 pre-IF，因此误预测恢复路径较长。

### 7.5 LSU

LSU 支持字节、半字、字的 load/store，以及 LL/SC：

- 地址为 `rj + imm`；
- store 根据地址低位生成 4 位字节写掩码；
- load 在返回阶段进行符号/零扩展；
- 半字/字未对齐产生 ALE（ecode `0x09`）；
- SC 在 LLBit 为 0 时取消内存写，并返回失败；成功时清除 LLBit。

当前只有一套 LSU，因此每拍最多发射一条访存指令。

### 7.6 PEU

PEU 是特权执行单元，负责：

- `csrrd/csrwr/csrxchg`；
- `rdcnt*`；
- `tlbsrch/tlbrd/tlbwr/tlbfill/invtlb`；
- `ertn`；
- LLBit 更新和 SC 返回值。

PEU 与 CSR/MMU 之间通过控制向量和组合数据通路连接。CSR 指令采用保守串行化，降低了旁路复杂度。

## 8. 分支预测器

### 8.1 总体结构

BPU 有两个并行读端，可同时预测 `PC` 和 `PC+4`。预测 taken 条件为：

```text
BTB tag hit AND direction predictor taken
```

分支在提交附近更新 BTB 和 PHT，异常或 ERTN 会清空 BTB，并重新初始化方向表。

### 8.2 BTB

BTB 结构为：

- 1024 组；
- 2 路；
- 每路保存 32 位目标；
- 每路保存 8 位 tag；
- 双读口通过复制 RAM 实现；
- 满组时使用 1 位周期翻转信号作伪随机替换。

索引使用 `PC[11:2]`，tag 只使用 `PC[19:12]`。因此 BTB 实际只比较 PC 的低 20 位，`PC[31:20]` 没有进入 tag。相差 1 MiB 整数倍且低 20 位相同的分支会发生假命中，这是一个明确的别名风险，尤其在内核高地址映射和多个地址空间中值得重点验证。

BTB 只在实际 taken 时写入；not-taken 分支依赖方向预测器阻止使用旧 BTB 项。

### 8.3 BHT/PHT

方向预测由两级信息组合：

- 1024 项、每项 2 位的局部历史表 BHT；
- 2048 项、每项 2 位的饱和计数器 PHT；
- 基础索引为 `PC[11:2] XOR PC[21:12]`；
- BHT 的低位与基础索引拼成 11 位 PHT 索引。

BHT 值为 `00` 时强制预测不跳，`11` 时强制预测跳，其他状态使用 PHT 计数器高位。PHT 用分支携带回来的旧状态做饱和更新。

代码定义了 32 项 RAS，但 BPU 中实例化被注释，因此当前没有有效的返回地址栈预测。

## 9. I-Cache

### 9.1 组织参数

I-Cache 参数由地址拆分可得：

| 属性 | 数值 |
| --- | --- |
| 容量 | 8 KiB |
| 相联度 | 2 路 |
| 组数 | 64 |
| Cache line | 64 B / 16 words |
| 索引 | 地址 `[11:6]` |
| tag | 地址 `[31:12]` |
| 替换 | 每组 1 位近似 LRU |
| 读宽 | 同时返回当前字和下一字 |

数据阵列由每路 16 个 64×32 RAM bank 组成。同步 RAM 读导致 I-Cache 数据相对请求延迟一拍，与 IF/BPU 的等待和保持逻辑配合。

### 9.2 miss 流程

I-Cache 状态机为：

```text
IDLE → SEND(AR) → REC(接收整行) → IDLE
```

miss 时锁存 64 B 对齐地址，AXI 返回完整 512 位 Cache 行后更新选中 way 的数据和 tag。整个 miss 期间 `cache_stall` 拉高，前端冻结；没有 hit-under-miss 或多未决 miss。

### 9.3 一致性与维护限制

当前 I-Cache 没有接入 `cacop` 失效/写回操作，也没有观察 D-Cache 写入，因此不支持硬件 I/D 一致性。加载代码、修改代码或执行自修改代码后，需要的软件维护动作在此 RTL 中并未完整落地。

## 10. D-Cache 与数据预取

### 10.1 D-Cache 组织

D-Cache 与 I-Cache 同为 8 KiB、2 路、64 组、64 B 行。每行 tag RAM 使用 21 位：最高位充当有效位，其余 20 位为 tag。

它采用写回、写分配策略：

- store hit 直接按字节使能修改 Cache bank；
- miss 选择 LRU way；
- 若被替换 way 有效，先把整行写回 AXI；
- 同时从 AXI 读取新行，完成替换后重试原请求。

实现中没有独立 dirty 位，任何有效 victim line 都会写回，即使该行从未被修改。功能上保守但会增加 AXI 写流量和 miss 延迟。

### 10.2 D-Cache miss 状态机

读入新行和写回旧行使用两套相互配合的状态机：

```text
read:  IDLE → SEND → REC → DONE
write: IDLE → SEND → REC → DONE
```

读 miss 可以发起新行读取；若 victim 有效，旧行写回同时推进。D-Cache 直到读入和必要写回均结束才回到 IDLE，因此仍是 blocking cache。

### 10.3 `dbuffer` 的真实作用

`dbuffer` 名称容易被理解为 store buffer，但源码实现的是一个两行顺序预取缓冲：

1. 记录最近两次 D-Cache 读 miss 行地址；
2. 检测当前访问是否为之前地址的下一条 64 B Cache 行；
3. 空闲时预取再下一行；
4. 预取命中时直接把整行送给 D-Cache refill；
5. D-Cache 写回同地址时使预取项失效，避免旧数据覆盖。

它能改善顺序数据流，但只有一个未决预取，并会与 demand read、I-Cache 和 uncache 共享 AXI 读通道。

### 10.4 Victim Cache 状态

`victim_cache.v` 实际定义了 32 个全相联 64 B 项，尽管文件注释仍写“八个条目”。顶层虽实例化 `u_ivcache`，但：

- I-Cache 没有输出 eviction line/address；
- `icache_write_back/icache_waddr/icache_cacheline_old` 未驱动；
- `vcache_en` 未连接；
- victim 命中返回路径被注释。

因此当前 victim cache 不属于有效微架构，应视为未完成实验代码。

## 11. 非缓存访问与 AXI

### 11.1 Uncache

MMU 根据 CRMD、DMW 或 TLB MAT 属性产生 `dcache_v`。不可缓存请求进入 `uncache` 状态机，一次只处理一个字节、半字或字访问，并在 AXI 响应完成前冻结 CPU。

### 11.2 AXI 读仲裁

AXI 读侧支持四类请求，优先级大致为：

```text
Uncache load > D-Cache demand miss/预取协调 > I-Cache miss > 独立 D-buffer 预取
```

Cache 行读取固定：

- `ARLEN = 15`，即 16 beat；
- `ARSIZE = 2`，每 beat 4 字节；
- `ARBURST = INCR`；
- 总计 64 B。

控制器一次只允许一个读 burst 在途，并将 16 个 beat 拼成 512 位 Cache line。不同来源用 AXI ID 0/1/2 区分，但内部状态机仍按单未决事务工作。

### 11.3 AXI 写侧

写侧在 uncache store 和 D-Cache writeback 之间仲裁：

- uncache store 为单 beat，并根据 `wstrb` 推导 `AWSIZE`；
- D-Cache 写回固定 16 beat；
- `bready` 恒为 1；
- 一次只允许一个写事务。

读写状态机可并行工作，因此理论上 Cache refill 与旧行 writeback 可以重叠；但控制器没有队列、乱序响应跟踪和 AXI 错误处理，`rresp/bresp` 也未用于生成异常。

## 12. MMU 与 TLB

### 12.1 地址模式

MMU 支持三种路径：

1. 直接地址模式：虚拟地址直接作为物理地址；
2. DMW0/DMW1：按虚地址高 3 位匹配并替换物理高 3 位；
3. 页表映射模式：通过 TLB 得到 PPN。

取指和数据各有一个 TLB 搜索端口。由于大规模组合匹配和后续选择的时序压力，MMU 又用 `tlb_l2_ready*` 将结果锁存一拍，因此 TLB 模式访问会产生显式等待。

### 12.2 TLB 组织

TLB 为 16 项全相联，每项包含：

- `E`：项有效；
- `VPPN`、`ASID`、`G`；
- 页大小，当前只编码 4 KiB 或 4 MiB；
- 偶/奇两个页的 `PPN/PLV/MAT/D/V`。

提供两个组合搜索端口、一个索引读端口、一个写端口和 INVTLB 批量失效逻辑。`tlbfill` 使用自由运行的 4 位计数器选择替换项，不是随机或 LRU。

### 12.3 TLB 指令

已实现：

- `TLBSRCH`：搜索结果写回 TLBIDX；
- `TLBRD`：按索引读取并写回多个 TLB CSR；
- `TLBWR`：按 TLBIDX 写入；
- `TLBFILL`：按循环计数索引写入；
- `INVTLB op=0..6`：按 global、ASID、VPPN 条件失效。

### 12.4 页异常

取指侧可产生：

- TLBR（`0x3f`）；
- PPI（`0x07`）；
- PIF（`0x03`）。

数据侧可产生：

- TLBR（`0x3f`）；
- PPI（`0x07`）；
- PIL（`0x01`）；
- PIS（`0x02`）；
- PME（`0x04`）。

需重点复核取指页有效条件：`inst_addr_sel2` 当前要求 `~s0_d`。LoongArch TLB 的 D 位通常表示页是否可写，对取指不应要求为 0；这里可能把 D 位错误地纳入了取指有效判断。应结合 LA32R 手册和 Linux 页表属性做定向测试后决定是否修正。

## 13. CSR、异常、中断与 LL/SC

### 13.1 CSR 范围

实现的主要 CSR 包括：

- CRMD、PRMD、ECFG、ESTAT、ERA、BADV、EENTRY；
- SAVE0～SAVE3；
- TID、TCFG、TVAL、TICLR；
- TLBIDX、TLBEHI、TLBELO0/1、ASID、TLBRENTRY；
- DMW0/1、PGDL、PGDH、PGD；
- LLBCTL；
- 内部映射的 `RDCNTVL/RDCNTVH/RDCNTID/LLBit`。

CSR 有两个组合读口，以支持双译码观察；实际 CSR 写入仍按顺序串行完成。

### 13.2 异常来源与优先级

异常信息以 `{esubcode, ecode, valid}` 16 位向量随流水线传播。主要来源为：

- IF：PC 未对齐、I-TLB 异常；
- ID：中断、syscall、break、非法指令；
- EXE/LSU：数据未对齐；
- EXE/MMU：D-TLB 页异常；
- PEU：非法 INVTLB 操作码。

进入 MEM 时的选择优先级为：

```text
前级已有异常 > LSU 对齐异常 > MMU 异常 > PEU 异常
```

异常提交时写 ERA、ESTAT 和必要的 BADV/TLBEHI，并把 PC 重定向到：

- 普通异常：EENTRY；
- TLB refill：TLBRENTRY。

ERTN 从 ERA 返回并恢复 CRMD 的 PLV/IE。分支纠错、异常和 ERTN 都会冲刷流水线与 Fetch Buffer。

### 13.3 中断

8 位外部中断映射到 ESTAT `[9:2]`，定时器中断使用 ESTAT bit 11。`has_int` 为挂起中断、ECFG 屏蔽和 CRMD.IE 的组合结果。中断在 ID 译码时附着到当前有效指令，并最终在 MEM 精确提交。

需要注意，两条同拍译码都接收同一个 `has_int`。虽然提交和异常屏蔽逻辑试图保持较老指令优先，但这是双发射精确中断的敏感区域，应加入“中断恰好落在双发射对之间”的定向验证。

### 13.4 LL/SC

LLBit 存放在 LLBCTL bit 0：

- LL 完成时写 1；
- SC 且 LLBit=1 时执行 store、返回 1 并清零；
- SC 且 LLBit=0 时取消 store并返回 0；
- ERTN 根据 KLO 位决定是否保留 LLBit。

当前实现只有一个布尔 LLBit，没有监控 LL 地址，也未观察外部 master、DMA 或总线 snoop。因此它实现的是单核简化语义，不足以保证多核或 DMA 并发下的完整原子性。

## 14. 提交与 Difftest

### 14.1 顺序双提交

MEM 可同时产生两个寄存器写回。`sel_sub_pipe` 和 `wb_turning` 恢复程序次序，使 Difftest 的 index 0 始终表示较老提交，index 1 表示较新提交。

如果较老指令发生异常，较新槽的提交会被抑制；分支误预测也会取消其后的错误路径指令。整体目标是精确异常和保序架构状态。

### 14.2 Difftest 输出

在 `DIFFTEST_EN` 下导出：

- 两路指令提交；
- 异常/ERTN 事件；
- load/store 地址与数据；
- 主要 CSR；
- 32 个 GPR；
- TLB fill 索引和计数器指令信息。

Difftest 接口定义偏向 64 位参考框架，而本核信号为 32 位，因此编译日志中会出现大量 32→64 位扩展告警。这些多为适配噪声，但应显式零扩展以避免真正的位宽错误被淹没。

## 15. 指令覆盖

从 `ID.v` 可确认译码覆盖如下：

| 类别 | 指令 |
| --- | --- |
| 算术比较 | `add.w/sub.w/addi.w/slt/sltu/slti/sltui` |
| 逻辑 | `and/or/nor/xor/andi/ori/xori` |
| 移位 | `sll/srl/sra` 的寄存器和立即数形式 |
| 构造地址 | `lu12i.w/pcaddu12i` |
| 乘除 | `mul.w/mulh.w/mulh.wu/div.w/mod.w/div.wu/mod.wu` |
| 分支跳转 | `beq/bne/blt/bge/bltu/bgeu/b/bl/jirl` |
| 访存 | `ld.b/ld.bu/ld.h/ld.hu/ld.w/st.b/st.h/st.w` |
| 原子 | `ll.w/sc.w` |
| CSR/计数器 | `csrrd/csrwr/csrxchg/rdcntid/rdcntvl/rdcntvh` |
| TLB | `tlbsrch/tlbrd/tlbwr/tlbfill/invtlb` |
| 异常与系统 | `syscall/break/ertn/idle/cpucfg/cacop/dbar/ibar` |

其中“能译码”不等于“语义完整”：`cpucfg` 当前返回常数 0；`cacop/dbar/ibar/idle` 没有看到完整的 Cache 维护、屏障或低功耗状态机，应视为兼容性占位实现。

## 16. 已确认的工程风险

以下问题直接来自当前 RTL 或已有 Verilator 日志，按建议优先级排列。

### P0/P1：正确性风险

1. **`dest_from` 存在组合反馈告警**  
   `ID.v` 用 `dest_from[0] = ~dest_from[2] & ~dest_from[1]`，同时分位驱动同一向量。Verilator 报两个 `UNOPTFLAT`。应改为独立 wire 或一次性赋值，消除工具依赖和组合环判断。

2. **多个关键控制信号为隐式 wire**  
   包括 `sub_div_wating`、`rf_we_turning`、MMU 的 `we`、BRU 的 `rj_eq_rd`、顶层 `dcache_awready` 等。没有 ``default_nettype none`` 时拼写错误会静默生成 1 位线网，应全部显式声明。

3. **BTB tag 未覆盖完整 PC 高位**  
   只比较 `PC[19:12]`，存在 1 MiB 周期的地址别名假命中。即便误命中最终能由 BRU 纠正，也会造成性能下降；若目标和方向信息在特殊控制流中配合不当，也会增加验证难度。

4. **取指 TLB 路径使用 `~s0_d`**  
   疑似错误使用页 dirty 位。需要用 D=0/D=1 的可执行页分别做定向测试。

5. **精确异常依赖复杂的槽位交换逻辑**  
   `turning` 同时影响寄存器写口、较新槽屏蔽、提交顺序和异常时保留结果。应覆盖“较老/较新槽分别发生异常、分支误预测、CSR 和长延迟指令”的交叉测试。

6. **AXI 响应错误被忽略**  
   `rresp/bresp` 没有转换为机器异常，外部总线错误会被当作成功响应。

### P1/P2：功能完整性风险

7. **无有效 Cache 维护路径**  
   `cacop` 可译码但 I/D Cache 未接入相应维护信号，Linux 中涉及 DMA、代码加载或 I/D 一致性的场景需额外确认。

8. **LL/SC 未绑定地址，也不监听外部写**  
   仅适合单核、无外部竞争的简化环境。

9. **D-Cache 无 dirty 位**  
   所有有效 victim 都写回，浪费总线带宽并拉长 miss 尾延迟。

10. **阻塞式 Cache 和单未决 AXI**  
    miss 时整核或前端冻结，没有 MSHR、hit-under-miss 或多事务并行；性能上限高度依赖命中率和 DDR 延迟。

11. **分支恢复点较晚**  
    BRU 在 EXE 判断，重定向在 MEM 发出，误预测代价偏高。

12. **未完成模块混在有效源码中**  
    victim cache、旧 WB、RAS、salu 等会增加维护和 lint 噪声，应删除、隔离到 experimental 目录或真正接通。

### P2：RTL 质量与可维护性

13. **位宽告警较多**  
    包括 PHT RAM 2/32 位、Difftest 32/64 位、AXI LEN 4/8 位、debug write enable 1/4 位等。部分是无害扩展，部分可能掩盖 bug。

14. **端口缺失、空接和未驱动信号较多**  
    尤其集中在未完成 victim cache、AXI debug 口和 Difftest 辅助事件。

15. **手工展开逻辑规模大**  
    TLB 16 项匹配、D-Cache tag reset、Cache bank 实例大量复制，容易产生不一致修改。建议用 generate/数组化组合重构。

16. **命名与注释存在偏差**  
    `dbuffer` 实际是预取缓冲，victim cache 注释称 8 项但实现 32 项，部分中文注释有编码损坏。

## 17. 性能特征判断

不依赖综合报告，仅从结构可以得到以下定性判断：

### 有利因素

- 双取指、双普通整数发射和双提交可提高顺序代码 IPC；
- 4R2W 寄存器堆和 EXE/MEM 旁路减少普通 ALU 相关停顿；
- 2 路 I/D Cache 和 64 B 行适合常见局部性；
- 数据顺序预取缓冲可改善流式访问；
- BTB/PHT 使用 BRAM，避免大型分布式表拖累面积；
- 乘法使用 DSP 友好的 16×16 分块。

### 主要瓶颈

- 第二槽只适合普通整数类，实际双发射率受代码组合限制；
- 分支、访存、CSR/PEU 均为单功能单元；
- load-use 不能 EXE 前递，Cache 同步读进一步增加延迟；
- 除法约 34 拍并冻结 EXE；
- 所有 Cache miss 为 blocking；
- D-Cache clean eviction 也写回；
- 分支误预测到 MEM 才重定向；
- TLB 模式显式增加一拍等待；
- PHT 初始化使复位时间约增加 2048 拍。

从提交历史可以看到曾以 100 MHz 左右时序为优化目标，但本文未读取 Vivado 时序报告，因此不能把提交信息当成当前 bitstream 已收敛的频率结论。

## 18. 建议的验证矩阵

### 18.1 双发射与提交

- 两条普通 ALU，无相关；
- 第一条写、第二条读同寄存器；
- 两条写同寄存器；
- 普通+分支、分支+普通；
- 普通+load/store、load/store+普通；
- 两条特殊指令结构冲突；
- 槽位交换后主/副槽分别异常；
- 双提交同时遇到中断。

### 18.2 BPU

- taken/not-taken 饱和转换；
- BTB 两路填满后的替换；
- 第一条和第二条分别预测跳转；
- Cache 行末第二条无效；
- 高 12 位不同、低 20 位相同的 PC 别名；
- JIRL 目标变化和函数返回密集负载。

### 18.3 Cache/AXI

- 两路冲突和 LRU 替换；
- clean/dirty victim 的 AXI 写流量；
- refill 与 writeback 并行；
- 预取命中、被 demand store 失效；
- I/D 同地址一致性；
- AXI backpressure、任意 beat 间隙；
- 非 OKAY `rresp/bresp`；
- uncached byte/half/word 访问。

### 18.4 MMU/异常

- DA、DMW0、DMW1、TLB 四种地址路径；
- 4 KiB/4 MiB 页；
- ASID/global 匹配；
- D=0/D=1 可执行页；
- PIL/PIS/PIF/PPI/PME/TLBR；
- TLBFILL 环回覆盖；
- INVTLB op 0～6；
- 异常、ERTN 与 Cache miss/长除法同时发生。

### 18.5 LL/SC

- LL→SC 成功；
- 无 LL 的 SC 失败；
- 两次 SC；
- LL 后异常/ERTN；
- LL 地址与 SC 地址不同；
- LL 后 DMA/外部 master 写同一地址。

## 19. 推荐改进顺序

1. 加入 ``default_nettype none``，补齐全部隐式信号声明；修正 `dest_from` 组合反馈。
2. 建立双发射精确异常、BTB 高位别名和 D 位取指定向测试，先确认正确性疑点。
3. 将 PHT、Difftest、AXI LEN 和 debug 接口位宽显式统一，降低 lint 噪声。
4. 为 I/D Cache 接入真正的维护操作，补齐 `cacop/dbar/ibar` 语义。
5. 给 D-Cache 增加 dirty 位，只写回脏行。
6. 将 `dbuffer` 重命名为 prefetch buffer，并增加性能计数器验证预取收益。
7. 删除或隔离未使用的 WB、RAS、victim cache 和 salu；若保留 victim cache，则完成 eviction/lookup/refill 全链路。
8. 缩短分支恢复路径，评估从 EXE 直接重定向前端。
9. 在基本正确性稳定后，再评估非阻塞 Cache、多个 AXI outstanding 或更强的第二槽能力。

## 20. 最终评价

该 CPU 已不是教学意义上的简单单发射五级流水核，而是一颗面向 FPGA 性能竞赛、能够承载 U-Boot/Linux 的顺序双发射实现。其设计重点很明确：用双取指、双 ALU、较大的 BTB/PHT、独立 I/D Cache 和数据预取，在不引入乱序执行复杂度的前提下提高 IPC。

当前架构的优势是功能覆盖广、验证接口完整、软硬件链路已经延伸到系统软件；主要风险则集中在双槽交换带来的控制复杂度、Cache/MMU 的边界语义、未完成模块和较高的 lint 技术债务。下一阶段最有价值的工作不是继续堆叠结构，而是先以定向测试和差分回归收紧精确异常、地址翻译、Cache 一致性与双发射提交边界，再基于可靠性能计数决定后续优化方向。
