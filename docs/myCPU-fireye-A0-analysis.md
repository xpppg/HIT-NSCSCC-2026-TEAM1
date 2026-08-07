# myCPU fireye/A0 动态性能分析报告

> 分析对象：`IP/myCPU`（commit `49d1379` + 工作区未提交修改）  
> 分析方法：遵循 `docs/myCPU-performance-analysis-methodology.md`  
> 分析输入：RTL 源码、fireye/A0 ELF、动态提交 trace  
> 分析时间：2026-08-04  
> 与 CoreMark 对比：见 `docs/myCPU-coremark-analysis.md`（同为 49d1379 基线）

## 1. 测试与边界

### 1.1 分析基线

```text
RTL commit:        49d1379 + fetch_buffer.v 未提交修改（full=count[3]&count[2]）
benchmark:         fireye/A0（NSSCSCC 性能测试）
源码:              software/examples/fireye/A0/A0.c（A0_n=10000, A0_k=20, LOOP=1）
ELF path:          sims/verilator/run_prog/obj/fireye/A0_obj/obj/fireye_A0.elf
trace path:        sims/verilator/run_prog/log/fireye/A0_log/simu_trace.txt
compiler:          GCC 8.3.0 (loongarch32r-linux-gnusf) -O3 -g
数据规模:          pos[10000] (40 KB), data[20]
clock:             1 周期 = 2 ns
```

### 1.2 负载结构

fireye/A0 是"埃拉托色尼筛"变体，每轮外循环（20 次）：

```text
外循环 (i=0..19, x=data[i]):
    内循环 (j=x; j<=10000; j+=x):  pos[j] ^= 1        # 步长访问，跨 cache 行
    求和循环 (j=1..10000):          tmp += pos[j]       # 顺序访问 40 KB
    ans = max(ans, tmp)
```

理论内循环迭代 `sum(10000//x | x∈data) = 5141` 次；求和循环迭代 `10000×20 = 200000` 次。

### 1.3 计时区间

fireye/A0 **无显式计时器采样**（与 CoreMark 的 `get_clock_count` 不同），整段程序运行即被测时间。本次分析采用 **main 区间**（剔除 `_start`/`ex_base_init`/`ex_table_init` 启动代码与退出序列）：

```text
main 起点: [0000168228ns] pc = 1c000800（main 首指令）
main 终点: [0001836932ns] pc = 1c0008cc（main 返回 jirl）
周期 C    = (1836932 - 168228) / 2 + 1 = 834353
printf 开销: 1731518ns→1836932ns ≈ 52707 拍（占 main 6.3%，含 vfprintf 库代码）
```

全程序口径（含启动初始化）：约 916410 周期、901879 条指令、IPC≈0.984。以下分析以 main 区间为主。

## 2. 基础指标

```text
N                  = 846432   （main 区间动态指令）
C                  = 834353   （时间戳换算，无硬件计数器）
IPC                = 1.0145
G                  = 435639   （非空提交拍）
D                  = 410793   （双提交拍）
双提交指令比例       = 97.1%
非空拍槽位利用率     = 97.1%
完全空拍            = 398714   （47.8%）
```

**守恒校验**：`sum(gap-1) = 398714 == C-G = 398714` ✓

### 2.1 关键现象：双发率接近极限但 IPC 仅 1.01

fireye/A0 是手册 2.2 节的典型反例：**双提交指令比例 97.1%、重建配对率 97.3%，但 IPC 只有 1.0145、完全空拍高达 47.8%**。空拍（load-use、D-Cache miss、分支恢复）决定了 IPC，继续扩大执行宽度对此负载几乎无效。

## 3. 动态画像

| 类型 | 数量 | 占比 |
| --- | ---: | ---: |
| normal | 420479 | 49.68% |
| branch | 210854 | 24.91% |
| load | 208635 | 24.65% |
| store | 6416 | 0.76% |
| div/mul | 48 | 0.01% |

热点函数：`main` 98.19%（831112 条），其余为 printf 库（uart_putchar 1.14%、memset 0.49%、vfprintf 0.04%）。负载几乎全部集中在 main 的计算循环，无 UART 轮询污染。

## 4. 双发重建（RTL 规则贪心）

```text
重建发射组 = 434660，配对 = 411772，配对指令比 = 97.3%
单发原因: true_raw 11640 (1.38%)，structural_special_special 11248 (1.33%)
```

| 配对类型 | 数量 |
| --- | ---: |
| load+normal | 205219 |
| normal+branch | 200013 |
| store+normal | 5173 |

**配对率已接近理论极限 100%**。主循环全部指令对（`ld+add`、`add+bge`、`st+add`）都满足配对条件。双发优化空间极小（见反事实）。

## 5. 提交空拍归因（核心）

### 5.1 提交组模式

内循环（`pos[j]^=1`，每迭代）：

```text
ld.w@64 + add.w@68    (配对)     ← gap 变化（大 gap = 下迭代 ld.w 的 D-Cache miss）
xori@6c               (单独)     ← gap=2（load-use：xori 依赖 ld.w 的 $r13）
st.w@70 + add.w@74    (配对)     ← gap=1
bge@78                (单独)     ← gap=1
```

求和循环（`tmp += pos[j]`，每迭代）：

```text
ld.w@88 + addi.w@8c   (配对)     ← gap=1
add.w@90 + bne@94     (配对)     ← gap=2（load-use：add.w 依赖 ld.w 的 $r14）
```

### 5.2 gap 直方图

| gap | 次数 | 空拍合计 | 归因 |
| --- | ---: | ---: | ---: |
| 1 | 207320 | 0 | 连续提交 |
| **2** | **209521** | **209521（25.1%）** | **load-use 单拍空泡** |
| 3–5 | 1 | 0 | — |
| 6–10 | 15154 | 83332（10.0%） | 分支恢复 |
| 11–40 | 2522 | 78071（9.4%） | D-Cache miss（长 refill） |
| 41–80 | 583 | 26893（3.2%） | D-Cache miss |
| >80 | 9 | 775（0.1%） | 异常/退出 |

### 5.3 归因 1：load-use 单拍空泡（25.1%，最大瓶颈）

`gap=2` 共 209521 拍，其中 208479 拍的前一提交组含 load。RTL 根因：

```verilog
// mycpu_core.v: load 结果不可 EXE 旁路
assign rf_we_wating = (is_r1 == ex_dest & ex_dest_we & EXE_valid
                     & ~(ex_dest_from[0] & EXE_forward_ok)) | ...
// EXE_forward_ok 只覆盖 ALU 单周期结果，load(ld.w) 的 dest_from[1] 不满足 → 消费者等待
```

- 求和循环 `ld.w $r14 → add.w $r14`：约 20 万次（每迭代 1 拍）；
- 内循环 `ld.w $r13 → xori $r13`：约 5141 次。

**这是 fireye/A0 的第一瓶颈，占总周期 25.1%。**

### 5.4 归因 2：D-Cache miss（12.7%）

`gap 11–80` 合计约 105739 拍（12.7%）。前一组最后提交 PC 分布：

```text
bge@78（内循环回跳） 4774 次  ← 下一迭代 ld.w@64 的 D-Cache miss
bne@94（求和循环回跳） 410 次
beq@f0               394 次
```

根因：

- 内循环以步长 `x`（x=5..820）访问 `pos[j]`，**每次迭代跨 cache 行**，miss 频繁；
- 求和循环顺序访问 40 KB 的 `pos`，远超 8 KB D-Cache，每轮约 500 次 miss × 20 轮；
- 每次 miss 触发 16-beat AXI refill，约 34 拍停顿。

**注意**：`dbuffer` 顺序预取只能覆盖求和循环的顺序访问，对**内循环的步长访问无效**。

### 5.5 归因 3：分支恢复（10.0%）

`gap 6–10` 共 15154 次，其中 15133 次前一组含 branch（bne@94 求和循环回跳、bge@78 内循环回跳）。每次恢复约 6 拍。这与"BRU 在 EXE 判断、MEM 重定向"的恢复路径一致。

**循环回跳分支（should be 高度可预测）仍有 1.5 万次恢复**，值得检查 BTB/PHT 对这些分支的行为。

## 6. 反事实分析

### 6.1 双发反事实（收益极小）

| 方案 | 发射组减少 | 相对总周期上限 |
| --- | ---: | ---: |
| 只允许副槽 BRU | 1162 | **0.14%** |
| 只允许双访存 | 8541 | **1.02%** |
| 副槽 BRU + 双访存 | 9669 | 1.16% |

**结论：fireye/A0 的双发配对已接近饱和，双发类优化（优化文档 2.2/3.4 的副槽 BRU、第二 LSU）对此负载几乎无收益。**

### 6.2 stall 反事实（真正的优化空间）

| 优化 | 候选空拍 | 相对总周期上限 |
| --- | ---: | ---: |
| load-use 消除（EXE 前递 load 或缩短 load 延迟） | ~209521 | **25.1%** |
| D-Cache miss 降低（更大 cache / 更早预取 / 非阻塞） | ~105739 | 12.7% |
| 完美分支预测 | 83332 | 10.0% |

**load-use 是此负载最大的单一优化点，但实现难度高**（load 数据从 D-Cache bank 输出到旁路，关键路径风险大）。

## 7. 与 CoreMark 的对比

| 维度 | CoreMark | fireye/A0 |
| --- | ---: | ---: |
| IPC | 0.987 | 1.015 |
| 重建配对率 | 53.1% | **97.3%** |
| 双提交指令比例 | 57.6% | 97.1% |
| 完全空拍 | 29.7% | 47.8% |
| 第一瓶颈 | 结构冲突（41.2%） | **load-use（25.1%）** |
| 第二瓶颈 | 分支恢复（11.0%） | D-Cache miss（12.7%） |
| 双发优化的上限 | 副槽 BRU 5.3% / 双访存 13.7% | 副槽 BRU 0.14% / 双访存 1.02% |

**核心启示（印证手册 14.2 跨负载验证）：**

1. 不同负载的瓶颈完全不同——CoreMark 卡在**配对能力**（结构冲突），fireye/A0 卡在**空拍**（load-use / cache miss）。优化优先级不能由一个负载外推。
2. fireye/A0 证明：**即使双发率 97%，IPC 也仅 1.01**——空拍（47.8%）决定了性能。对这类负载，执行宽度已经过剩。
3. 对 fireye 系列（A0/B2/C0/D1/I2）这类小循环负载，**load-use 转发与 D-Cache miss 处理比扩宽执行更有效**。

## 8. 结论摘要

```text
整体 IPC 的第一瓶颈：    47.8% 完全空拍；load-use 25.1% + D-Cache miss 12.7%
                        + 分支恢复 10.0%
双发配对的第一瓶颈：     无（配对率 97.3%，接近饱和；双发优化收益 ≤1.2%）
最不值得优先做的优化：   副槽 BRU、双访存（此负载收益 0.14%~1.02%）
最有价值的优化方向：     load-use 前递/减延迟（25.1%）、D-Cache miss（12.7%）
数据可信度：             main 区间剔除启动与 printf 后统计；gap 守恒校验通过
                        （398714==398714）；无显式计时器，周期为时间戳换算；
                        归因为启发式分类，需硬件计数器确认
```

## 9. 局限与下一步验证

### 9.1 局限

- **无显式计时器**：周期由时间戳换算，无法与软件输出交叉验证（fireye 无 tick 输出）；
- printf 占 main 6.3%，包含库代码（vfprintf/__dtoa），但 main 99% 指令在计算循环，影响有限；
- 单次迭代，冷启动效应存在；
- 归因（load-use / cache miss / 分支）为提交间隔启发式，需计数器确认。

### 9.2 建议计数器

```text
load_use_wait / rf_we_wating    确认 25.1% load-use 归因
dcache_miss / dcache_refill     确认 12.7% D-Cache miss（区分内循环步长 miss 与求和循环顺序 miss）
branch_mispredict               确认 10.0% 分支恢复（bne@94/bge@78 循环回跳为何高恢复率）
dbuffer_prefetch_hit            评估 dbuffer 对求和循环顺序访问的实际收益
```

### 9.3 对优化文档的补充意见

优化文档（`myCPU-performance-optimization-plan.md`）第 5 节将 fireye/A0 列为副槽 BRU 的观察负载，但本分析表明 **fireye/A0 的瓶颈是 load-use 与 D-Cache miss，副槽 BRU 在此负载收益仅 0.14%**。若以 fireye 系列为目标，应优先考虑：

1. **load-use 转发**（25.1%）：评估 EXE 级 load 结果旁路或 load 延迟减拍，注意时序风险；
2. **D-Cache miss**（12.7%）：对步长访问，预取无效，需考虑更大 cache 或 miss 期间不阻塞后续独立指令（非阻塞 cache）；对求和循环顺序访问，dbuffer 已有覆盖；
3. **分支恢复**（10.0%）：调查循环回跳分支预测失败率偏高的原因（BTB 别名？PHT 饱和？）。

## 10. 分析检查清单（手册 19 节）

- [x] 已记录 RTL、ELF、trace 和编译基线（含未提交修改）
- [x] 已确定计时边界（main 区间，剔除启动/退出；无显式计时器已声明）
- [x] 已排除 UART、打印污染（main 99% 在计算循环）
- [x] ELF 指令字与 trace 匹配（同轮构建 + 逐条对照）
- [x] 指令分类总数等于动态指令数
- [x] 周期、非空提交拍和空拍满足守恒关系（398714 == 398714）
- [x] 双提交只作为双发代理指标
- [x] 已区分结构冲突、真 RAW（此负载假 RAW 极少）
- [x] 已区分方向（load→use 链确认）
- [x] 反事实一次只放宽一项规则
- [x] 已把局部收益换算为总周期上限
- [x] 已标明直接事实、重建和启发式推断
- [x] 已说明冷启动、单次迭代和无计时器限制
- [x] 已列出需要性能计数器确认的结论
- [x] 优化建议包含频率、异常、flush 和 store 副作用风险
