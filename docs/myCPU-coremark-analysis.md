# myCPU CoreMark 动态性能分析报告

> 分析对象：`IP/myCPU`（commit `49d1379` + 工作区未提交修改）  
> 分析方法：遵循 `docs/myCPU-performance-analysis-methodology.md`（性能分析方法论与 LLM 执行手册）  
> 分析输入：RTL 源码、CoreMark ELF、动态提交 trace、周期计数器读数  
> 分析时间：2026-08-04  
> 证据强度：本文区分**直接事实**（计数器读数、trace 精确计数）、**高可信重建**（按 RTL 规则重放）与**启发式推断**（提交间隔分类）。

## 1. 测试与边界

### 1.1 分析基线（阶段 0）

```text
RTL commit:        49d1379 (HEAD -> dev-xpg)
RTL dirty files:   IP/myCPU/fetch_buffer.v   (full: count[3] -> count[3]&count[2])
                   sims/verilator/run_prog/config-software.mak (uboot -> coremark)
benchmark:         CoreMark 1.0, 2K, Iterations = 1
ELF path:          sims/verilator/run_prog/obj/coremark_obj/obj/coremark.elf
trace path:        sims/verilator/run_prog/log/coremark_log/simu_trace.txt
compiler:          GCC 8.3.0 (loongarch32r-linux-gnusf)
compiler flags:    -O3 -funroll-all-loops -finline-limit=200 -fno-if-conversion2
                   -fselective-scheduling -fno-code-hoisting -fno-common
                   -falign-functions=4 -falign-jumps=4 -falign-loops=4
data size:         2K (SEED_METHOD=STACK)
iterations:        1
clock:             1 周期 = 2 ns（仿真 main_time 每周期 +1，aclk 翻转两次）
timer source:      get_clock_count() @ PC 0x1c0058a8（uncache load 读计数器）
```

**重要**：工作区未提交的 `fetch_buffer.v` 修改（`full = count[3] & count[2]`，有效深度从约 8 提到约 12）属于本分析基线的一部分，本报告的全部数据都是该深度提升之后的结果。旧 trace 不能代表旧 RTL。

### 1.2 计时区间（阶段 2）

两次计数器采样（trace 行 18804 / 294132）：

```text
start:  [0000060166ns] pc = 1c0058a8, val = 0x00007574 (= 30068 ticks)
end:    [0000618082ns] pc = 1c0058a8, val = 0x0004b722 (= 309026 ticks)
```

交叉验证：

```text
counter_end - counter_start = 309026 - 30068 = 278958
CoreMark 输出 Total ticks  = 278958          ✓ 完全一致
(timestamp_end - timestamp_start) / 2ns      = 278958 ✓
```

**计时区间 = trace 行 18804 ~ 294132（含）**。包含关系：排除第一次计数器读取指令本身，包含第二次计数器读取（停止采样前的调用和读取延迟属于软件测得周期）。

### 1.3 区间污染检查（阶段 2.4）

- 区间内 uart/printf/sprintf/memcpy/memset 相关函数动态指令：**0 条**；
- 热点函数均为 CoreMark 核心：`core_bench_list`、`core_bench_state`、`matrix_test`、`crc16`、`crc32`、`crcu16`；
- 动态循环次数与软件配置（Iterations=1）一致；
- ELF（04:57）与 trace（04:58）同一轮构建，trace 指令字与反汇编逐条匹配。

结论：正式区间无污染，结果可直接用于定量分析。

## 2. 基础性能指标（阶段 4）

```text
N                  = 275329   （正式区间动态提交指令数）
C                  = 278958   （硬件计数器差值，非换算值）
IPC                = 0.9870
G                  = 195996   （非空提交拍）
D                  = 79333    （含两条提交的拍）
双提交指令比例       = 57.6%    （2D / N）
非空拍槽位利用率     = 70.2%    （N / 2G）
完全空拍            = 82962    （C - G）
空拍比例            = 29.7%    （(C-G) / C）
```

**守恒校验**：`sum(gap - 1) = 82962 == C - G = 82962` ✓ 边界、分组和时间换算无错误。

### 2.1 双提交 ≠ 双发射

双提交（57.6%）与阶段 6 重建的发射配对率（53.1%）存在约 4.5 个百分点的差值，来源包括：

- 两槽执行延迟不同导致发射/提交重新对齐；
- stall 期间发射与提交解耦；
- flush 取消年轻指令；
- 长延迟指令（mul）改变提交间隔。

因此本报告以双提交作为双发效果的**代理指标**，发射级结论以阶段 6 重建为准；两者交叉印证方向一致。

## 3. 动态画像（阶段 5）

### 3.1 指令类型分布（互斥分类）

| 类型 | 数量 | 占比 | 手册校准值 |
| --- | ---: | ---: | --- |
| normal（纯整数） | 125200 | 45.47% | — |
| mul | 9412 | 3.42% | — |
| **normal（含 mul）** | **134612** | **48.89%** | 48.9% ✓ |
| load | 64345 | 23.37% | 23.4% ✓ |
| branch | 55647 | 20.21% | 20.2% ✓ |
| store | 20725 | 7.53% | 7.5% ✓ |
| div/priv | 0 | 0% | — |

注意：`mul` 属于 `inst_normal` 槽位类别，但也是"长延迟执行类型"，此处分类为互斥单列。

### 3.2 热点函数

| 函数 | 动态指令 | 占比 |
| --- | ---: | ---: |
| core_bench_list | 83838 | 30.45% |
| core_bench_state | 80332 | 29.18% |
| matrix_test | 73168 | 26.57% |
| crc16 | 17536 | 6.37% |
| crc32 (crcu32) | 16447 | 5.97% |
| crcu16 | 3887 | 1.41% |

正式区间覆盖 list / state / matrix / CRC 四大测试，负载具有基本代表性；90%+ 指令在核心测试函数中，非打印或轮询。

## 4. 双发重建（阶段 6）

### 4.1 基线贪心算法

按提交顺序贪心配对：两条都进得去且无 RAW 则配对，否则单独发射。发射判定按当前 RTL 规则：

```text
结构冲突：两条都非 inst_normal（都需主槽特殊资源）→ 单发
RAW：     older 写目的寄存器 && younger 语义上读同一寄存器 → 单发
CSR/特权：相邻对含特权指令 → 单发（近似，trace 级无法重建流水内 CSR 在途）
```

### 4.2 结果

```text
重建发射组 = 202281
配对       = 73048，配对指令比 = 53.1%
单发       = 129233
```

| 单发原因 | 数量 | 占比（全部指令） |
| --- | ---: | ---: |
| **结构冲突（special+special）** | 113510 | **41.23%** |
| 真 RAW | 15722 | 5.71% |
| 尾指令 | 1 | ~0 |

**结论：当前双发第一瓶颈是结构冲突（两条特殊指令争主槽），占全部指令的 41%。真 RAW 只占 5.7%。** 假 RAW（RTL 字段比较 vs 语义源比较之差）≈ 0，因为本 RTL 的 `r1_sel/r2_sel` 已正确过滤立即数字段。

### 4.3 配对类型 TOP

```text
normal+normal  20668    load+normal  15356    branch+normal  14035
normal+branch   6887    mul+normal    5832    store+normal    3597
normal+load     2634    normal+mul    2280    ...
```

可见"特殊指令 + normal"的配对（load/branch/store + normal 合计约 4.2 万对）是当前双发的主要形态，得益于 `turning` 槽位交换。

## 5. 方向敏感的 LSU+BRU 分析（阶段 8.1）

在"副槽已支持 BRU"的反事实假设下，对 `load/store` 与 `branch` 的相邻组合按方向独立检查真 RAW：

| 方向 | 尝试配对 | 真 RAW | 可成功 | 结论 |
| --- | ---: | ---: | ---: | --- |
| branch→load | 25983 | 0 | 25983 | **可放开**（无寄存器 RAW） |
| store→branch | 2480 | 0 | 2480 | **可放开** |
| **load→branch** | 16663 | **12034（72%）** | 4629 | **必须保留互锁** |
| branch→store | 1420 | 0 | 1420 | 可放开 |

与手册 16.4 校准一致：RAW 高度集中在 `load→branch`（branch 紧接测试 load 结果）。其余方向几乎无寄存器 RAW。

**副槽 BRU 实现的正确性约束**（非 RAW 风险）：

- branch 较老、store 较年轻：误预测后年轻 store 不得产生架构副作用；
- store 较老、branch 较年轻：store 异常必须屏蔽年轻 branch 重定向；
- BPU 更新、异常屏蔽、提交顺序必须服从 older/younger；
- `load→branch` 同拍组合建议保持互锁，不建立组合旁路。

## 6. 空拍归因（阶段 7）

### 6.1 gap 直方图

| gap（周期） | 次数 |
| --- | ---: |
| 1 | 151486 |
| 2 | 38348 |
| 3–5 | 1 |
| 6–10 | 5816 |
| 11–20 | 1 |
| 21–40 | 211 |
| 41–80 | 117 |
| >80 | 15 |

### 6.2 分支恢复分析（高可信）

```text
6~8 拍 gap 且前一提交组含分支：5813 次（5816 中占 99.9%）
分支恢复候选空拍总周期：30700（占全部周期 11.01%）
```

判定：gap 集中在 6~8 拍且几乎全部紧跟在分支后，与"BRU 在 EXE 判断、MEM 重定向、误预测路径较长"的 RTL 结构吻合，归为**分支恢复候选**。最终需 `branch_mispredict` 计数器确认。

### 6.3 单拍气泡（gap=2）细分

| 类别 | 数量 | 说明 |
| --- | ---: | --- |
| load-use（前组 load 目的被当前组读） | 14698 | 启发式分类 |
| store→load（前组 store 尾 + 当前组 load 首） | 7571 | 对应 `wr_buf_wating` 串行化 |
| mul 等待（前组最后为 mul） | 2403 | 对应 `mul_wating` |
| 其他 | 13676 | 无法细分 |

单拍气泡合计 38348 周期，占总周期 **13.75%**。此为启发式分类，最终需 `mul_wait` / `wr_buf_wait` / `load_use_wait` 计数器确认。

### 6.4 长停顿（gap>20）分类

互斥优先级 `after_branch > seq_64B_boundary > load_first`：

| 类别 | 数量 |
| --- | ---: |
| after_branch（前组含分支） | 205 |
| sequential 64B 行边界 | 132 |
| load_first | 1 |
| unknown | 5 |

长停顿合计 343 周期（0.12%），占比很小。I-Cache refill 期间即使新地址命中也可能无法供给（`cache_stall` 结构），但仅凭提交 PC 无法区分，需 `icache_miss/refill_busy/redirect_while_refill` 计数器。

## 7. 反事实分析（阶段 8）

### 7.1 双发反事实（发射组减少，相对实测总周期 278958 的上限）

| 方案 | 发射组 | 组减少 | 总周期上限 |
| --- | ---: | ---: | ---: |
| baseline（当前 RTL） | 202281 | — | — |
| 只允许副槽 BRU（含 LSU+branch） | 187461 | 14820 | **5.31%** |
| 只允许双访存（第二 LSU） | 163963 | 38318 | **13.74%** |
| 副槽 BRU + 双访存（有重叠，不可相加） | 152312 | 49969 | 17.91% |
| 只按语义 RAW（消除字段假 RAW） | 202281 | 0 | **0%** |
| CSR 不串行化 | 202281 | 0 | **0%** |

### 7.2 stall 反事实上限

| 优化 | 候选空拍 | 总周期上限 |
| --- | ---: | ---: |
| 完美分支预测 | 30700 | 11.01% |
| 完美消除单拍气泡 | 38348 | 13.75% |
| 完美 load-use 消除 | ~14698 | ~5.3% |
| 完美 store buffer（store→load） | ~7571 | ~2.7% |

**注意**：这些值不能直接相加——多个条件可能重叠，优化后动态对齐也会改变。上限只表示该项的独立收益。

### 7.3 关键结论

1. **整体 IPC 的第一瓶颈是空拍（29.7%），不是发射宽度**：分支恢复（11%）+ 单拍气泡（13.7%）占主导。即使双发完美，总周期也只受发射组数约束，而当前前端/控制流空拍是更大的盘子。
2. **双发配对第一瓶颈是结构冲突（41%）**。其中双访存（13.7% 上限）> 副槽 BRU（5.3% 上限），但双访存工程风险高（D-Cache 双端口/仲裁、store 顺序、异常）。
3. **最不值得优先做的**：消除假 RAW、CSR 串行化（本次负载收益为 0）。
4. **副槽 BRU 收益虽然中等（5.3% 上限），但工程成本低**，且与 `turning` 已有机制兼容（normal+特殊 已是当前主流配对形态）。
5. **分支恢复空拍（11%）值得专项优化**：BRU 在 EXE 判断、MEM 重定向的恢复路径长，但缩短恢复路径对时序风险高，建议先加计数器确认再决策。

### 7.4 工程成本排序

| 优化 | 动态上限 | 工程成本 | 时序风险 | 正确性风险 | 推荐等级 |
| --- | ---: | --- | --- | --- | --- |
| 分支恢复优化/计数器 | 11.0% | 中 | 高（前端路径） | 中 | 先验证再定 |
| 第二 LSU（双访存） | 13.7% | 高 | 高 | 高 | 暂缓 |
| 副槽轻量 BRU | 5.3% | 低 | 低 | 中（load→branch 互锁） | **优先** |
| store buffer（1-2 entry） | ~2.7% | 低-中 | 低 | 中（精确异常） | 次优 |
| mul 固定流水化 | ~0.9% | 中 | 低 | 中 | 一般 |
| 消除假 RAW / CSR 串行化 | ~0% | — | — | — | 不推荐 |

## 8. 结论摘要（手册 18.1 模板）

```text
整体 IPC 的第一瓶颈：    29.7% 完全空拍，其中分支恢复 11.0% + 单拍气泡 13.7%
双发配对的第一瓶颈：     结构冲突 41.2%（两条特殊指令争主槽）
最不值得优先做的优化：   消除假 RAW、CSR 串行化（本次负载收益 0）
数据可信度：             计时边界与 tick 完全吻合、ELF/trace 同轮、区间零污染、
                         守恒校验通过；CSR/相对 EXE 依赖为近似重建；
                         单次迭代存在冷启动效应
```

## 9. 局限与下一步验证

### 9.1 本分析的限制

- **单次迭代**：冷 I-Cache、冷 D-Cache、冷 BTB/PHT 占比高于稳态，空拍比例可能偏高；
- **无周期级流水状态**：CSR 在途、相对 EXE 依赖、load-use 精确判断为启发式近似；
- **双提交为代理指标**：发射级结论依赖重建；
- **单一负载**：CoreMark 不能代表访存容量 miss、TLB、uncache、异常等场景。

### 9.2 建议新增硬件性能计数器（手册 15 节）

按优先级：

```text
branch_mispredict          验证 11.0% 分支恢复归因
dual_issue                 校准 53.1% 配对率与 57.6% 双提交的差值
mul_wait                   验证 2403 次 mul 单拍气泡
wr_buf_wait                验证 7571 次 store→load 串行化
load_use_wait              验证 load-use 气泡
icache_miss / refill_busy  验证 >20 拍长停顿（当前仅 0.12%，低优先）
redirect_while_refill
fetch_buffer_empty         评估前端供给
```

计数器应支持 benchmark marker，仅在正式区间累计；同时提供原始计数（可重叠）与独占原因计数（固定优先级，每拍只归一类）。

### 9.3 下一步负载建议

- CoreMark 多轮迭代（分离冷启动与稳态）；
- 访存密集：`memcmp`、`lookup_table`、`stream_copy`、排序；
- 控制密集：`dhrystone`、`fireye/C0`、`fireye/I2`；
- 系统行为：uncache、异常、TLB、Linux 引导段。

## 10. 分析检查清单（手册 19 节）

- [x] 已记录 RTL、ELF、trace 和编译基线（含未提交修改）
- [x] 已证明计时边界与软件输出一致（278958 == 278958）
- [x] 已排除 UART、打印和初始化污染（0 条）
- [x] ELF 指令字与 trace 匹配（同轮构建 + 逐条对照）
- [x] 指令分类总数等于动态指令数
- [x] 周期、非空提交拍和空拍满足守恒关系（82962 == 82962）
- [x] 双提交只作为双发代理指标
- [x] 已区分结构冲突、真 RAW 和假 RAW
- [x] 已区分 load→branch 等方向（方向独立分析）
- [x] 反事实一次只放宽一项规则
- [x] 已把局部收益换算为总周期上限
- [x] 已标明直接事实、重建和启发式推断
- [x] 已说明冷启动和单次迭代限制
- [x] 已列出需要性能计数器确认的结论
- [x] 优化建议包含频率、异常、flush 和 store 副作用风险
