# myCPU fireye/C0 当前动态性能分析报告

> 分析对象：`IP/myCPU`，commit `07d308c`
> 分析方法：`docs/myCPU-performance-analysis-methodology.md`
> 分析输入：当前 RTL、实际编译源码、匹配 ELF、正式运行提交 trace
> 分析日期：2026-08-14
> 说明：本文使用当前 `nscscc_perf/fireye_C0` 产物，替代此前绑定旧 commit、旧 ELF 和旧 trace 的 C0 结论。

## 0. 结论先行

当前 fireye/C0 的整体性能第一瓶颈不是 Cache，也不是假 RAW，而是 **乘法执行停顿及紧随其后的乘法结果依赖**：

```text
总周期                         635488
动态指令                       456298
IPC                            0.7180
完全空拍                       252278（39.70%）

乘法提交前执行等待候选           85934（13.52% 总周期）
mul -> 立即消费者附加等待         40015（ 6.30% 总周期）
乘法相关合计候选                125949（19.82% 总周期）

load-use 候选                   44914（ 7.07% 总周期）
分支恢复候选                     68020（10.70% 总周期）
```

双发配对层面的第一限制是 **真 RAW**。贪心重建的 302040 个单发组中，真 RAW 为 197389（65.35%），结构冲突为 104650（34.65%）。假 RAW 在原始相邻流中出现 8 次，但在当前贪心对齐下没有成为实际基线阻塞；只消除假 RAW的发射组收益为 0。

优化优先级建议：

1. 乘法器固定流水化/解除全 EXE 冻结，并单独处理乘法结果旁路；
2. 改善分支预测或缩短误预测重定向路径；
3. load-use 旁路，尤其是热点 `ld.w -> beq`；
4. 若继续扩展双发资源，优先评估 LSU+BRU 同拍能力，而不是第二 LSU；
5. 当前 C0 上不应优先做假 RAW 或扩大 Cache。

上述百分比是候选空拍或发射组减少量占实测总周期的上限，不可直接相加为真实加速比。

## 1. 基线和正式计时边界

### 1.1 当前分析基线

```text
RTL commit:       07d308c
RTL dirty files:  无
配置 dirty file:  sims/verilator/run_prog/config-software.mak
benchmark:        nscscc_perf/fireye_C0
实际源码:         software/examples/nscscc_perf/bench/fireye_C0/shell13.c
ELF:              sims/verilator/run_prog/obj/nscscc_perf/fireye_C0_obj/obj/main.elf
trace:            sims/verilator/run_prog/tmp/simu_trace.txt
compiler:         loongarch32r-linux-gnusf-gcc 8.3.0
benchmark flags:  -O3 -funroll-all-loops -falign-jumps=16
                  -falign-functions=16 -fgcse-sm -fgcse-las
                  -finline-functions -finline-limit=1000 -msoft-float -G8 -DTIME -g
clock:            1 cycle = 2 ns
```

当前未提交修改只把运行目标从 CoreMark 切到 `nscscc_perf/fireye_C0`，同时配置 `TRACE_COMP=n`、`SIMU_TRACE=y`；没有未提交 RTL 修改。

产物指纹：

```text
ELF   mtime: 2026-08-14 00:41:40 -0700
ELF   sha256: 9c62a513acb0fcbf134c731f04049b1080d5c91214df5de056ded469dba9d732
trace mtime: 2026-08-14 00:42:33 -0700
trace sha256: efa5bfc8625315c3fe053668c7138c8e2bab9dda7cbf22b235e359f996b265b8
```

逐条对照正式区间的 trace PC、指令字和 ELF 反汇编：

```text
unknown PC = 0
instruction word mismatch = 0
```

因此本次 ELF 与 trace 匹配。不能使用仓库中另一个 `software/examples/fireye/C0/C0.c` 或旧 `obj/fireye/C0_obj` 产物代替当前输入。

### 1.2 正式计时边界

软件先后读取 SoC 计数器和 CPU `rdtimel.w`；结束处先读 CPU 计数器，再读 SoC 计数器。按方法论文档的推荐口径：排除第一次 CPU 计数器读取，包含第二次读取，总周期以两次 CPU 计数值之差为准。

```text
CPU timer instruction PC:  0x1c000438 (rdtimel.w)
start commit timestamp:     664004 ns
start value:                0x000508da
stop commit timestamp:      1934980 ns
stop value:                 0x000ebb3a

C = 0xebb3a - 0x508da = 635488 cycles
(1934980 - 664004) / 2 = 635488 cycles
```

计数器值与 trace 时间戳完全一致。SoC 计数器差为 635575，比 CPU 区间多 87 拍，原因是两类计数器读取顺序不对称；本文不混用该口径。

开始提示打印发生在第一次采样之前，结果和 PASS 打印发生在第二次采样之后，正式区间内没有 `printf`、UART 轮询或退出序列。第二次采样后 trace 读取到 `ans_C0=0x3e`，并走 `err==0` 成功分支，功能结果正确。

## 2. 负载结构和代表性

当前运行时 `SIMU_FLAG=0`，`LOOPTIMES_fireye_C0=4`；每次 `shell13_main` 内 `LOOP=2`。因此正式区间包含 4 次完整 C0，合计 8 次顶层 DFS：

```text
每次 shell13_main:
    构建两个 Trie：50 + 50 个长度为 2 的字符串
    LOOP=2:
        ans_C0 = 0
        dfs(1, 1)

dfs:
    读取两个 Trie 的 ch[last][i]
    任一为空则跳过
    两者均存在则更新 mpN/mpM 并递归到下一格
```

两个 `Trie.ch[100][26]` 共约 20.8 KiB，超过 8 KiB L1 D-Cache，但可放入当前 64 KiB L2 D-Cache。`-funroll-all-loops` 把 DFS 的 `i=0..25` 循环高度展开，形成重复的：

```text
ld.w -> mul.w -> add.w -> slli.w -> add.w -> ld.w -> beq
```

这解释了当前负载为何同时具有高乘法密度、密集真 RAW、load-use 和数据相关分支。

## 3. 基础指标

| 指标 | 数值 | 说明 |
| --- | ---: | --- |
| 周期 `C` | 635488 | CPU timer 直接事实 |
| 动态指令 `N` | 456298 | 正式区间 trace |
| **IPC** | **0.7180** | `N/C` |
| 非空提交拍 `G` | 383210 | trace 按周期聚合 |
| 双提交拍 `D` | 73088 | 双发的代理指标 |
| 双提交指令比例 | 32.04% | `2D/N` |
| 非空拍槽位利用率 | 59.54% | `N/(2G)` |
| 完全空拍 | 252278 | `C-G`，占 39.70% |

守恒关系全部通过：

```text
N = G + D = 383210 + 73088 = 456298
sum(gap - 1) = 252278 = C - G
gap 事件数 = 383210 = G（含开始计时器到第一提交组的锚点）
```

如果只消除全部完全空拍、保持现有提交组不变，IPC 上限也只有 `N/G=1.1907`。因此 C0 同时受空拍和单发依赖限制，不能只看双提交比例或只看 Cache。

## 4. 动态画像

报告分类将 mul 从普通 ALU 中单列，但双发结构模型仍严格按 RTL 把 mul 视为 `inst_normal`。

| 类型 | 动态数量 | 占比 |
| --- | ---: | ---: |
| normal（不含 mul） | 223540 | 48.99% |
| **mul** | **44856** | **9.83%** |
| load | 106450 | 23.33% |
| store | 19222 | 4.21% |
| branch | 62229 | 13.64% |
| privileged | 1 | <0.01% |

热点函数：

| 函数 | 动态指令 | 占比 |
| --- | ---: | ---: |
| **dfs** | **439872** | **96.40%** |
| shell13 | 16405 | 3.60% |
| timer helpers | 21 | <0.01% |

三个最主要的展开 DFS 片段中，以下各条指令分别执行 10752 次：

```text
0x1c0006d8 ld.w  -> 0x1c0006dc mul.w -> 0x1c0006e0 add.w
                                      -> slli.w -> add.w
                                      -> 0x1c0006ec ld.w -> 0x1c0006f0 beq

0x1c000754 ld.w  -> 0x1c00075c mul.w -> ... -> 0x1c00076c ld.w -> 0x1c000770 beq
0x1c0007d4 ld.w  -> 0x1c0007dc mul.w -> ... -> 0x1c0007ec ld.w -> 0x1c0007f0 beq
```

## 5. 双发重建

### 5.1 与实际提交校准

按当前 RTL 的 turning、`inst_normal` 和编码 RAW 条件进行顺序贪心重建：

```text
重建发射组          379169
重建配对组           77129
重建配对指令比例      33.81%
实际非空提交拍       383210
实际双提交指令比例     32.04%
```

重建比实际少 4041 组，相差实际 `G` 的 1.05%。差异来自提交 trace 无法表达的流水线状态、flush 和串行化等因素；因此反事实用于排序和上限估计，不冒充精确周期仿真。

### 5.2 当前单发原因

```text
总单发组       302040
true RAW       197389（65.35% 单发组；43.26% 动态指令）
structural     104650（34.65% 单发组；22.93% 动态指令）
false RAW           0（当前贪心基线阻塞）
tail                1
```

真 RAW 的主要指令链：

| 链 | 次数 |
| --- | ---: |
| add.w -> ld.w | 43504 |
| slli.w -> add.w | 43496 |
| add.w -> slli.w | 40000 |
| mul.w -> add.w | 38648 |
| ld.w -> mul.w | 12288 |

这类依赖构成地址计算和 Trie 索引链，不能靠增加副槽直接消除；若要同拍执行，必须提供同周期级联旁路，通常不现实且会恶化时序。

结构冲突主要由两条都需要当前主槽特殊资源造成：

| 方向 | 次数 |
| --- | ---: |
| load -> branch | 42561 |
| branch -> load | 40500 |
| load -> load | 13488 |
| store -> store | 5874 |
| branch -> branch | 1586 |
| store -> branch | 536 |

### 5.3 假 RAW

原始相邻指令流中共有 261998 次当前 RTL 编码 RAW，其中 261990 次是真 RAW，8 次是假 RAW；8 次均为 `mul.w -> ori`，由无效源字段碰巧相等产生。但在基线贪心对齐中，这 8 对没有成为最终阻塞点：

```text
编码 RAW 基线发射组       379169
只改成语义 RAW发射组      379169
收益                          0
```

这不否认 RTL 的假 RAW 缺陷，只说明 **当前 C0 不会从该修复获得可测的双发收益**。

## 6. 双发反事实

| 反事实 | 发射组 | 比基线减少 | 占实测总周期上限 |
| --- | ---: | ---: | ---: |
| baseline | 379169 | — | — |
| 只消除假 RAW | 379169 | 0 | 0.00% |
| **允许 LSU+BRU 同拍** | **338668** | **40501** | **6.37%** |
| 允许两条 memory 同拍 | 369228 | 9941 | 1.56% |
| LSU+BRU + 两条 memory | 330139 | 49030 | 7.72% |
| 取消全部结构限制、保留真 RAW | 329883 | 49286 | 7.76% |

“同时允许 LSU+BRU”和“两条 memory”不满足简单可加性，因为第一项改变后续贪心对齐。即使取消全部结构限制，仍被真 RAW 限制在 329883 个发射组，因此继续堆功能单元的收益很快饱和。

### 6.1 LSU+BRU 必须按方向判断

允许 LSU+BRU 的反事实贪心序列中：

| 方向 | 尝试 | 真 RAW | 成功配对 |
| --- | ---: | ---: | ---: |
| **load -> branch** | **42169** | **42169（100%）** | **0** |
| **branch -> load** | **40148** | **0** | **40148** |
| store -> branch | 536 | 0 | 536 |

原始相邻流同样有 42565 次 `load -> branch`，并且 42565 次全是真 RAW。热点形式就是：

```text
ld.w rX, ...
beq  rX, r0, ...
```

所以对当前 C0，LSU+BRU 的收益几乎全部来自 `branch -> load`，而不是 `load -> branch`。后者只有增加 load-to-branch 的同周期数据路径才可能配对。

若通过“副槽 BRU”实现 `branch -> load`，必须重新设计 turning、taken 分支对年轻主槽 load 的取消、访存请求抑制和异常精确性；不能只改 `inst_waiting`。

## 7. 提交空拍分析

### 7.1 gap 直方图

| gap | 事件数 | 空拍 `sum(gap-1)` | 占总周期 |
| --- | ---: | ---: | ---: |
| 1 | 237148 | 0 | 0.00% |
| 2 | 91525 | 91525 | 14.40% |
| **3** | **41121** | **82242** | **12.94%** |
| 6–8 | 13049 | 69959 | 11.01% |
| 9–10 | 3 | 26 | <0.01% |
| 11–20 | 234 | 2902 | 0.46% |
| 21–40 | 50 | 1773 | 0.28% |
| 41–80 | 80 | 3851 | 0.61% |
| >80 | 0 | 0 | 0.00% |
| **合计** | **383210** | **252278** | **39.70%** |

没有 gap=4 或 gap=5；所有 3–5 桶事件都精确为 gap=3。

### 7.2 第一瓶颈：乘法执行和结果依赖

`gap=3` 的 41121 个事件全部是“当前提交组含 mul”，贡献 82242 个空拍。另有 3692 个 `gap=2` 事件的当前组含 mul，贡献 3692 个空拍。因此乘法提交前的执行等待候选为：

```text
82242 + 3692 = 85934 empty cycles = 13.52% C
```

此外，`gap=2` 中 40015 次是前组 `mul.w` 的目的寄存器被当前组立即读取：

```text
mul.w -> add.w/addi.w immediate consumer
40015 empty cycles = 6.30% C
```

两类事件互斥，合计 125949 空拍，占总周期 19.82%。典型热点每轮同时出现：

```text
ld.w@6d8
mul.w@6dc       # 到该提交组 gap=3，2 个空拍
add.w@6e0       # 立即使用乘法结果，gap=2，再 1 个空拍
```

RTL 证据与该模式一致：

- `alu.v` 的 `mul_wating` 在 `mul_complete` 前持续拉高；
- `mycpu_core.v` 将 `mul_wating/sub_mul_wating` 放入整个 `EXE_ready_go`，会冻结 EXE 前进；
- `forward_ok` 只覆盖单周期 ALU，不覆盖乘法结果，因此立即消费者还会被 `rf_we_wating` 阻塞。

应把两个优化拆开评估：

1. **流水化乘法器并解除全 EXE 冻结**，主要针对 85934 拍候选；
2. **乘法完成旁路或编译调度**，主要针对随后的 40015 拍候选。

只做“可每拍接收一条乘法”不等于自动消除 `mul -> consumer` 延迟。

### 7.3 第二瓶颈：分支恢复

`gap=6..8` 共 13049 个事件、69959 个空拍，其中：

```text
前一提交组含 branch：12772 events（97.88%）
对应空拍：           68020（97.23% of this bin，10.70% C）
```

候选热点包括 `beq@0x1c0007f0/770/6f0` 和展开循环回跳 `bne@0x1c000858`。RTL 中 BRU 在 EXE 比较实际结果，但全局 `br_taken` 重定向由 MEM 寄存后的 `wb_br_taken` 产生，因此误预测恢复路径较长。

按事件数粗略除以动态分支数，候选恢复事件约为 20.5%；这不是硬件 mispredict counter，不能作为精确预测失败率。另有 231 个 gap=13/14 事件发生在 branch 后并紧接 load，可能是分支恢复与存储层次停顿叠加，本文没有把它们强行计入 68020 拍。

### 7.4 第三瓶颈：load-use

`gap=2` 中有 44914 次前一提交组的 load 目的寄存器被当前组真实读取，占总周期 7.07%。其中绝大多数是展开 DFS 中的：

```text
ld.w@6ec -> beq@6f0
ld.w@76c -> beq@770
ld.w@7ec -> beq@7f0
```

当前 `rf_we_wating` 对 EXE 中不能单周期前递的生产者阻塞，load 不满足 `ex_dest_from[0] & EXE_forward_ok`，所以这是真实 load-use 延迟，不是假 RAW。

### 7.5 Cache 和前端长停顿不是当前第一优先级

所有 `gap>10` 合计只有 8526 个空拍，占 1.34%：

| 启发式特征 | 事件 | 空拍 | 占总周期 |
| --- | ---: | ---: | ---: |
| 当前组从 load 开始 | 99 | 4266 | 0.67% |
| 前组含 branch | 251 | 3804 | 0.60% |
| 顺序跨 64B 指令边界 | 12 | 362 | 0.06% |
| 其他 | 2 | 94 | 0.01% |

“当前组从 load 开始”只是 D-Cache miss 候选，不是 miss 计数器。当前硬件已经是 8 KiB、2-way、64B line 的 L1 D-Cache，加 64 KiB L2 D-Cache；C0 的约 20.8 KiB Trie 工作集虽然超过 L1，但能进入 L2。该结构与旧 C0 报告只按 8 KiB D-Cache 推断的基线不同，也与本轮长停顿较少相符。

## 8. 瓶颈排序和优化收益上限

### 8.1 整体周期瓶颈

| 排名 | 优化对象 | 候选周期/发射组 | 占 `C` | 若全部消除的理想加速比 |
| --- | --- | ---: | ---: | ---: |
| 1 | 乘法执行等待 + 立即消费者 | 125949 cycles | 19.82% | 24.72% |
| 2 | 分支恢复（gap 6–8 高可信候选） | 68020 cycles | 10.70% | 11.99% |
| 3 | load-use | 44914 cycles | 7.07% | 7.61% |
| 4 | LSU+BRU 结构扩展 | 40501 groups | 6.37% 上限 | 不可直接等同周期 |
| 5 | 双 memory 结构扩展 | 9941 groups | 1.56% 上限 | 不可直接等同周期 |
| 6 | 长 gap 中 load 开始候选 | 4266 cycles | 0.67% | 0.68% |
| 7 | 假 RAW | 0 groups | 0.00% | 0.00% |

“理想加速比”按 `C/(C-saved)-1` 计算，只用于上限直觉。各类事件会重叠、重新对齐，并可能受新关键路径和频率下降抵消，不能把表中加速比相加。

### 8.2 推荐实现顺序

#### P0：先处理乘法流水和旁路

当前 mul 占动态指令 9.83%，并形成规则、重复的三拍提交间隔。建议先做两个可独立验证的版本：

1. 固定延迟流水乘法，允许无依赖指令继续推进，不让 `mul_wating` 全局冻结 EXE；
2. `mul_complete` 时提供受 valid/flush 保护的结果旁路，或让编译器在 mul 与消费者之间调度独立指令。

验证时必须检查双槽同时 mul、flush、异常、结果顺序和 Fmax。若新旁路拉长 IS/EXE 关键路径，应比较“周期减少 × 频率”的净收益。

#### P1：分支预测和恢复路径

优先给 `beq@6f0/770/7f0`、`bne@858` 增加按 PC 的预测/恢复计数。确认后再选择：改善 PHT/BTB，或将错误重定向从 MEM 前移。前移恢复必须同步处理副槽年轻指令取消。

#### P2：load-use

`ld.w -> beq` 贡献明确。可评估 D-Cache hit 数据到 BRU/IS 的专用旁路，但路径很可能跨 Cache 数据输出、比较器和控制逻辑，时序风险高。先增加 `load_use_wait` 按消费者类型计数，再决定是否值得做通用旁路。

#### P3：LSU+BRU 同拍

反事实上限 6.37%，明显高于第二 LSU 的 1.56%。但有效方向是 `branch -> load`，这要求 branch 在较老槽、load 在较年轻槽时，taken/mispredict 能可靠取消年轻 load 的请求和异常；实现复杂度高于单改译码结构谓词。

#### 暂缓：假 RAW和扩大 Cache

假 RAW 是应修的通用正确性/性能建模缺陷，但本 C0 trace 的收益为 0；可以低成本修复，却不能把它列为 C0 性能主项。当前长 gap 中 load 候选只占 0.67%，在没有 `dcache_miss/L2_hit` 计数器前，不建议为 C0 优先扩大 Cache。

## 9. 证据强度、局限和建议计数器

### 9.1 证据强度

- **直接事实**：计时器差值、IPC、提交组、双提交、指令类型、热点 PC、gap 直方图、RTL 布尔条件；
- **高可信重建**：当前双发贪心、真/假 RAW 拆分、各结构反事实；
- **高可信候选**：所有 gap=3 当前组含 mul、热点 `mul -> consumer`、gap 6–8 前组 97.88% 含 branch；
- **启发式推断**：长 gap 的 D-Cache/L2/I-Cache 具体归因、由提交 gap 推算的预测失败比例。

### 9.2 局限

- trace 是提交视角，没有逐周期 `mul_wating/rf_we_wating/cpu_stall/br_taken`；
- 双发贪心不含完整流水线状态，和实际提交组仍差 1.05%；
- `SIMU_FLAG=0` 下重复 4 次，包含第一次 Trie/Cache/预测器冷启动，也包含后续热态，本文未再拆迭代；
- 反事实只给理论发射组或候选空拍上限，没有重新仿真，也没有综合 Fmax；
- load、branch、Cache stall 可能在同一长 gap 中叠加，未做强行唯一归因。

### 9.3 最值得增加的硬件计数器

```text
mul_wait_cycle                         验证 85934 拍乘法执行候选
mul_result_dependency_wait_cycle       验证 40015 拍 mul->consumer 候选
load_use_wait_cycle（按消费者类型）      验证 ld->beq 占比
branch_mispredict（按 PC）              验证 beq/bne 恢复热点
branch_recovery_cycle                  分离预测失败率和恢复延迟
dcache_l1_miss / dcache_l2_hit/miss    分离 L1、L2 和主存延迟
icache_miss                            校验顺序 64B 边界候选
dual_issue + single_issue_reason       校准贪心模型与实际发射
```

## 10. 方法论检查清单

- [x] 记录当前 commit、dirty 配置、编译参数、ELF 和 trace 指纹
- [x] 确认实际编译源码，而非同名旧目录源码
- [x] 用两次 CPU 计数器实际采样定义正式边界
- [x] CPU 计数器差与 trace 时间戳交叉验证一致
- [x] 排除正式区间外的打印和 test-finish 轮询
- [x] ELF PC/指令字逐条匹配，unknown/mismatch 均为 0
- [x] `N=G+D` 和 `sum(gap-1)=C-G` 守恒
- [x] mul 在性能画像中单列、在结构模型中仍按 RTL 属 normal
- [x] 基线用编码 RAW，语义 RAW只用于拆分和反事实
- [x] 区分真 RAW、假 RAW和结构冲突
- [x] LSU+BRU 按 load/branch 方向统计
- [x] 反事实一次只放宽一条结构规则
- [x] 区分发射组上限和真实周期收益
- [x] 将直接事实、重建和启发式推断分级
- [x] 列出需要硬件计数器确认的归因
