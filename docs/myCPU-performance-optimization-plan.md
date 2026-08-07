# myCPU 性能优化建议

> 背景：本文基于 `docs/myCPU-architecture-analysis.md`、当前 `IP/myCPU` RTL，以及围绕 NSCSCC 性能测试的讨论整理。这里假设功能正确性已经成立，重点只讨论对性能测试真正值得投入的优化方向。

## 1. 总体判断

当前 myCPU 是顺序双发射、顺序提交处理器。性能上限主要受以下因素限制：

- 副槽能力有限，实际双发射率容易下降；
- load/store、branch、CSR/TLB 等特殊指令共享主槽资源；
- D-cache/uncache stall 会冻结后端；
- 长延迟乘除会通过 waiting 信号阻塞 EXE；
- `turning` 槽位交换逻辑分散在旁路、提交、异常和 debug 路径中，后续扩展副槽时风险较高。

因此，真正值得做的优化应优先满足两个条件：

- 能明显提升性能测试中的平均 IPC 或减少 stall；
- 不明显拉长前端、IS、EXE 或提交关键路径。

## 2. 建议优先做的 5 项

### 2.1 将 `turning` 抽象为 older/younger

这是后续扩展副槽能力的基础工作。当前 `turning` 同时影响：

- 寄存器双写顺序；
- 异常时较新槽屏蔽；
- debug/difftest 提交顺序；
- 主/副槽旁路优先级；
- 分支、flush 与双提交控制。

建议在 MEM/commit 附近统一生成逻辑顺序视图：

```verilog
older_slot   = wb_turning ? sub_slot  : main_slot;
younger_slot = wb_turning ? main_slot : sub_slot;
```

后续提交、异常、debug、双写同寄存器处理都基于 `older_slot/younger_slot`，而不是到处直接判断 `wb_turning`。

收益：

- 降低副槽扩展时的正确性风险；
- 让顺序提交语义更清楚；
- 为副槽 BRU、更多双发射组合、异常屏蔽重构打基础。

注意：

- 这项本身不直接提高 IPC；
- 应分阶段做，先重构 MEM/commit 侧，再逐步整理 EXE/旁路侧。

### 2.2 副槽增加轻量 BRU 能力

当前副槽主要执行 `inst_normal`，分支只能进入主槽。大量循环尾部和控制密集代码会退化成单发射。

建议副槽优先支持：

- `b`
- `bl`
- `beq/bne`
- `blt/bge/bltu/bgeu`

暂时不建议副槽支持 LSU、CSR、TLB 或复杂特权操作。

收益：

- 提升 `ALU + branch`、`branch + independent ALU` 的配对机会；
- 对 `dhrystone`、排序类、字符串搜索、fireye 控制流测试有帮助；
- 比增加第二 LSU 风险低得多。

注意：

- 分支实际重定向、异常优先级和提交顺序仍必须服从 older/younger；
- 若副槽分支是较新指令，较老指令异常时必须屏蔽该分支效果；
- BPU 更新仍建议保持提交侧顺序更新。

### 2.3 D-cache 增加 dirty bit

当前 D-cache 替换时只要 victim line valid，就可能写回。没有 dirty bit 会导致只读 cache line 被替换时也产生 64B writeback。

建议为 64 组、2 路 D-cache 增加 dirty 状态：

- refill 后 dirty 置 0；
- store hit 后 dirty 置 1；
- store miss refill 并完成写入后 dirty 置 1；
- eviction 时仅 `valid && dirty` 才发起 writeback。

收益：

- 减少 clean victim 的无效 AXI 写流量；
- 缩短 D-cache miss 尾延迟；
- 对 `memcmp`、`lookup_table`、`crc32`、`stream_copy` 源数组、排序参考数组、SHA 输入等只读或读多写少场景有效。

注意：

- 这项属于访存侧优化，但成本很低；
- 状态位规模约 128 bit，硬件代价小；
- 要处理 reset、refill、store、writeback、cacop 或 flush 的状态一致性。

### 2.4 增加小型 store buffer

当前 store 在 MEM 阶段发出，后续 load 可能因为保守次序控制被阻塞。建议先做 1-entry 或 2-entry store buffer，不做复杂乱序内存系统。

保守方案：

- 只缓存 cached store；
- store 写入 buffer 后允许流水线继续；
- load 与 buffer 地址可能冲突时等待或前递；
- flush/exception 时按精确状态清理或提交；
- 暂时不做复杂 store 合并。

收益：

- 缓解 store 对后续 EXE/LSU 的阻塞；
- 对 `stream_copy`、`loop_induction`、排序类、fireye A0/D1 等 load/store 交替测试有帮助；
- 比第二 LSU 或 non-blocking cache 更容易落地。

注意：

- 必须保证精确异常；
- 必须处理 store 后同地址 load 的前递或阻塞；
- 不建议第一版支持 uncache store 合并。

### 2.5 乘法固定流水化，避免冻结 EXE

当前乘法通过 `mul_wating` 参与 `EXE_ready_go`，会冻结 EXE。相比完整 scoreboard，先把乘法做成固定延迟流水更划算。

建议：

- 乘法发射后进入固定延迟 pipeline；
- 普通 ALU 指令在无 RAW 相关时继续执行；
- 乘法消费者等待结果；
- 除法暂时保持阻塞，不急着改。

收益：

- 对 `inner_product`、CoreMark matrix、部分整数密集测试有帮助；
- 避免完整 scoreboard/ROB 的复杂度；
- 先解决更常见的短延迟长吞吐问题。

注意：

- 若允许 younger 指令越过未完成乘法执行，必须保证提交仍然顺序；
- 第一版可以只允许乘法 pipeline 和后续无关 ALU 在有限范围内并行；
- 不建议同时把除法也改成非阻塞，除法会明显增加状态管理复杂度。

## 3. 不建议优先做的优化

### 3.1 同拍 ALU0 到 ALU1 组合旁路

不建议。

原因：

- 关键路径会变成 `regfile -> ALU0 -> bypass mux -> ALU1 -> EXE reg`；
- 对 FPGA 频率非常不友好；
- 为少量同拍 RAW 双发射机会牺牲主频，不划算。

建议保持当前策略：同拍第二条读第一条目的寄存器时禁止双发射。

### 3.2 将分支判断前移到 ID/IS 后段

不建议优先做。

原因：

- IS 阶段已有寄存器读取、旁路 mux、RAW 判断；
- 再加入 branch compare 和 target 计算容易拉长时序；
- 前端重定向路径也会更紧。

若要优化分支，更建议先做副槽轻量 BRU，或在 EXE 侧做更早的 speculative redirect，但不要把大逻辑塞进 ID/IS。

### 3.3 完整 scoreboard

不建议当前阶段做完整 scoreboard。

原因：

- 一旦允许 younger ALU 越过 older div/mul 执行，就需要保存 younger 结果；
- 提交仍要顺序，就需要 completion queue 或小 ROB；
- 异常、flush、双提交、debug/difftest 都会明显复杂化。

建议替代路线：

1. 先做乘法固定流水化；
2. 除法继续阻塞；
3. 若后续确实需要，再设计 2-4 项 in-order completion queue。

### 3.4 第二 LSU

不建议当前阶段做。

原因：

- 需要 D-cache 双端口或仲裁；
- load/store 异常顺序、同地址冲突、store-load forwarding 都会复杂化；
- 当前主要瓶颈可以先通过 dirty bit、store buffer 和副槽 BRU 改善。

第二 LSU 收益可能大，但工程风险和验证成本也很高。

### 3.5 Fetch Buffer 激进用满 16 项

不建议优先做完整 16-entry 满容量方案。

原因：

- 用满 16 项后 `rd_ptr == wr_ptr`，需要依靠 count/valid 严格区分满空；
- 边界测试更复杂；
- 对性能提升通常不如副槽 BRU、dirty bit、store buffer 明显。

如果要试，可以先做低风险版本：

```verilog
assign full = count[3] & count[2]; // 大约 count >= 12 时反压
```

它能把有效深度从约 8/9 提到约 13，同时保持很简单的时序。

### 3.6 `$r0` 特判和少量无效比较优化

不建议优先做。

原因：

- `$r0` 不会写，已有逻辑中这类无效比较比例很低；
- 收益小，难以在性能测试中观察；
- 不应占用当前优化窗口。

若后续整理 RAW 判断，可以顺手清理，但不应作为独立优化项。

### 3.7 提交侧分支恢复

不建议把提交侧大逻辑直接拉到前端。

原因：

- 路径可能包含异常屏蔽、提交判断、flush、nextpc 选择；
- 对频率不利；
- 当前用户已经明确担心该路径影响主频，这个判断是合理的。

更稳妥的方向是：

- EXE 侧只做 speculative redirect；
- MEM/commit 保持精确提交和 BPU 更新；
- 异常、ERTN、TLB 重定向仍保持更高优先级。

## 4. 建议执行顺序

推荐按下面顺序推进：

1. `turning` 重构为 older/younger 抽象；
2. 副槽增加轻量 BRU；
3. D-cache dirty bit；
4. 1-entry 或 2-entry store buffer；
5. 乘法固定流水化。

如果目标是短期看性能测试分数变化：

1. 先做 D-cache dirty bit；
2. 再做副槽轻量 BRU；
3. 然后做 store buffer。

如果目标是降低后续架构演进风险：

1. 先做 older/younger；
2. 再扩副槽；
3. 最后处理访存和长延迟单元。

## 5. 结合 RTL 与实际测试的性能分析方法

性能分析不能只看 RTL，也不能只看一份完整 trace 的平均 IPC。比较可靠的做法是把静态结构、动态指令流和周期级停顿对应起来，再用反事实分析估算每项优化的收益上限。

下面的方法适用于双发射率、分支、Cache、长延迟运算和流水线停顿分析。

推荐固定采用以下流程：

```text
固定软硬件基线
    -> 静态还原 RTL 发射和停顿规则
    -> 确定 benchmark 有效计时区间
    -> 用匹配 ELF 映射动态指令
    -> 统计 IPC、双提交、指令类型和配对矩阵
    -> 重建当前双发并分类单发原因
    -> 分析空拍和长停顿
    -> 逐项放宽规则做反事实估算
    -> 用性能计数器和多负载验证
    -> 决定实现优先级
```

### 5.1 先区分要回答的问题

分析前应先明确目标属于哪一类：

1. **配对能力**：连续两条指令是否满足同拍发射条件；
2. **后端吞吐**：已经有指令时，两个执行槽能否同时工作；
3. **前端供给**：Fetch Buffer 是否经常为空，是否因为 I-Cache 或分支重定向断流；
4. **整体性能**：程序总周期、IPC 或测试分数为什么不高。

这几类问题不能混为一谈。例如，双提交比例较高但 IPC 很低，通常说明执行槽并不是主要瓶颈，而是大量周期根本没有指令进入后端。

如果 trace 时间戳以纳秒记录，还要先用实际时钟周期换算 `elapsed_cycles`。同拍双提交可以作为双发效果的代理指标，但不严格等价于发射级双发；不同执行延迟、流水线停顿和 flush 都可能让提交行为与最初发射行为产生差异。需要精确结论时，应增加 `issue_0/issue_1` 计数器。

建议同时记录以下指标：

```text
IPC                  = committed_instructions / elapsed_cycles
双提交指令比例        = 2 * dual_commit_cycles / committed_instructions
非空提交拍槽位利用率  = committed_instructions / (2 * nonempty_commit_cycles)
结构冲突比例          = structural_single_groups / reconstructed_issue_groups
```

### 5.2 固定分析基线

每次分析应记录：

- RTL 提交或版本号；
- 工作区是否有未提交修改；
- 软件 ELF、编译参数和循环次数；
- 仿真器、时钟周期和测试配置；
- trace 是否来自当前 RTL，而不是旧结果。

尤其要检查 `git status` 和相关文件的 `git diff`。Fetch Buffer 深度、Cache 状态机或编译优化等级的微小变化，都可能使两份 trace 不再可直接比较。

### 5.3 先静态还原当前机器规则

在看测试结果前，先从 RTL 列出每一级真正会造成停顿或禁止双发的条件，避免根据架构名称猜测实现。

当前核至少应检查：

- `IS_ready_go/IS_ready_go_2`：RAW、结构冲突和 PEU 串行化；
- `IS_to_EXE_inst`：主副槽交换规则；
- `inst_waiting`：两条特殊指令冲突；
- `is_raw_wating`：同拍两条指令间 RAW；
- `rf_we_wating/rf_we_wating_2`：相对 EXE 两槽的依赖；
- `EXE_ready_go`：乘除、D-Cache、MMU 和写缓冲停顿；
- `fetch_stall/pred_wating`：I-Cache 和预测读取停顿；
- flush 条件：分支纠错、异常、ERTN 和 TLB 重定向。

把规则整理成可以在软件中重放的形式。例如当前双发的核心规则可以近似表示为：

```text
if 两条都是特殊指令:
    只发较老指令
else if younger 读取 older 的目的寄存器:
    只发较老指令
else:
    两条同拍发射，必要时通过 turning 交换物理槽位
```

静态阶段还应确认每类指令的真实源、目的寄存器和功能单元。不能简单把指令编码中的 `rj/rk/rd` 字段都当作有效源操作数。

### 5.4 选择有效的动态统计区间

完整程序 trace 往往包含初始化、打印、串口轮询和退出代码。这些代码可能比正式测试区间长几个数量级，直接统计整份 trace 会得出错误结论。

推荐按以下优先级确定区间：

1. 软件已经提供的开始、结束计时函数；
2. benchmark 向性能计数寄存器写入的开始、结束标志；
3. ELF 中主循环入口、出口 PC；
4. 必要时在软件中增加明确的 marker。

切片后要做基本合理性检查：

- 区间内是否仍有 `printf/uart_putchar`；
- 热点 PC 是否属于 benchmark 主循环；
- 动态指令数是否与循环次数大致吻合；
- 开始、结束 PC 是否只出现预期次数。

本项目的 Dhrystone trace 就说明了这一步的重要性：完整 trace 主要由 UART 状态轮询组成，而真正计时区间只有很小一部分。整份 trace 的低双发率主要反映 I/O 等待，不代表 Dhrystone 核心循环。

### 5.5 使用与 trace 完全匹配的 ELF

动态 PC 必须使用生成该 trace 的同一份 ELF 反汇编。否则即使源码相同，编译选项、链接地址或库版本变化也会让 PC 与指令类型错位。

基本流程为：

```bash
loongarch32r-linux-gnusf-objdump -d <benchmark.elf> > <benchmark.dis>
```

然后建立：

```text
PC -> 指令字 -> 助记符 -> 指令类别 -> 源寄存器 -> 目的寄存器
```

建议至少划分：

- normal ALU/mul；
- branch/jirl；
- load；
- store；
- div；
- CSR/TLB/其他特权指令。

### 5.6 从动态指令流重建双发

只有提交 trace、没有发射级 trace 时，可以对动态提交顺序做贪心重建：

1. 从最老的未处理指令开始；
2. 取当前指令和下一条动态指令；
3. 按 RTL 的结构冲突、RAW 和功能单元规则判断能否配对；
4. 能配对则消耗两条，否则只消耗较老的一条；
5. 分别累计成功配对及单发原因。

需要同时保留两种 RAW 判断：

- **RTL 当前判断**：完全按现有编码字段比较，用于复现当前行为；
- **语义判断**：只比较指令真正使用的源寄存器，用于识别假 RAW。

两者之差就是“修正源寄存器有效位”可能带来的理论收益。这样可以避免仅凭静态概率高估假 RAW 的价值。

建议输出配对矩阵，例如：

```text
normal + normal
normal + branch
branch + normal
load/store + branch
load + load
store + store
```

配对矩阵比单一双发百分比更有用，因为它能直接指向缺少的资源。例如大量 `store + branch` 冲突说明副槽 BRU 可能有效；大量 `load + load` 则需要第二 LSU 或内存队列，工程成本完全不同。

### 5.7 用提交时间定位空拍和长停顿

把同一时间戳的两条提交记录合并为一个非空提交拍，再统计相邻非空提交拍之间的周期差：

```text
gap = current_commit_cycle - previous_commit_cycle
extra_empty_cycles = gap - 1
```

建议输出：

- gap 直方图；
- 大于某个阈值的所有长停顿；
- 每个长停顿前后的 PC、指令和反汇编；
- 长停顿总共占全部空拍的比例。

常见模式包括：

- 64 B 指令 Cache 行边界附近的长停顿；
- `bl/jirl` 前后的调用、返回停顿；
- 条件分支目标处的重定向气泡；
- load 后消费者造成的短停顿；
- `div` 前后的固定长延迟；
- uncache 访存或 UART 轮询造成的超长停顿。

仅靠提交 PC 得到的是归因线索，不应直接当成硬件定论。最终应结合 RTL 状态机或性能计数器区分 I-Cache miss、错误路径 refill、分支预测错误、D-Cache miss 和数据相关。

### 5.8 做反事实分析，而不只统计现状

确定主要冲突后，可以在动态序列重建器中一次只放宽一项规则：

```text
基线：当前 RTL 规则
方案 A：消除假 RAW
方案 B：允许 LSU + BRU
方案 C：允许两条访存
方案 D：消除乘法阻塞
```

每个方案重新计算：

- 可配对指令比例；
- 理论发射组数；
- 减少的单发组数；
- 仍然存在的下一大类冲突。

需要特别区分“发射组减少”和“程序总周期减少”。例如某方案少了 20 个发射组，但程序中还有数百拍 Cache miss，那么总周期收益上限可能只有百分之几。优化优先级应以总周期潜在收益为主，而不是只看局部双发率。

### 5.9 冷启动结果与稳态结果分开

单次短测试通常主要测到：

- 冷 I-Cache/D-Cache；
- 冷 BTB/PHT；
- 首次函数调用和返回；
- 初始化代码。

稳态性能应使用足够多的循环，并至少报告：

1. 第一轮冷启动结果；
2. 去掉第一轮后的稳态结果；
3. 包含全部软件开销的端到端结果。

三者可以分别回答硬件冷启动、核心循环吞吐和真实程序耗时问题，不能互相替代。

### 5.10 建议增加的硬件性能计数器

提交 trace 可以做近似分析，但最可靠的方法仍是在 RTL 中加入分类计数器。建议至少统计：

```text
cycle_total
commit_0 / commit_1 / dual_commit
issue_0 / issue_1 / dual_issue
fetch_buffer_empty
fetch_stall
cpu_stall
branch_mispredict
structural_special_special
same_pair_raw
exe_dependency_wait
mul_wait / div_wait
peu_wait
icache_miss / dcache_miss / uncache_wait
```

这些计数器最好只在 benchmark marker 打开的区间累计。分析时可以直接建立周期守恒关系：

```text
总周期 ≈ 有效发射周期
       + 前端断粮周期
       + 数据相关周期
       + 结构冲突周期
       + Cache/uncache 周期
       + 乘除和特权串行化周期
       + flush 恢复周期
```

各类停顿可能重叠，因此实现时应规定优先级，或者同时提供“独占原因”和“原始信号”两套计数。

### 5.11 跨测试验证与优化决策

一项优化至少应在三类负载上验证：

- 控制密集：Dhrystone、CoreMark、字符串处理；
- 访存密集：memcmp、lookup_table、stream/排序类；
- 计算密集：inner_product、乘除较多的测试。

最终建议用下面的表格记录每次分析结果：

| 项目 | 基线 | 优化后 | 变化 | 解释 |
| --- | ---: | ---: | ---: | --- |
| 总周期 |  |  |  |  |
| IPC |  |  |  |  |
| 双发指令比例 |  |  |  |  |
| 前端空拍 |  |  |  |  |
| 结构冲突 |  |  |  |  |
| RAW 等待 |  |  |  |  |
| I/D-Cache stall |  |  |  |  |
| 分支纠错 |  |  |  |  |

只有当动态热点、RTL 原因和反事实收益三者一致时，才应把某项优化提升为高优先级。若只满足其中一项，应先补计数器或扩大测试样本，而不是直接修改复杂数据通路。

## 6. 对可运行性能测试的观察建议

当前 `sims/verilator/run_prog/configure.sh` 直接支持的性能相关软件主要是：

- `coremark`
- `dhrystone`
- `fireye/A0`
- `fireye/B2`
- `fireye/C0`
- `fireye/D1`
- `fireye/I2`
- `c_prg/inner_product`
- `c_prg/lookup_table`
- `c_prg/loop_induction`
- `c_prg/memcmp`
- `c_prg/minmax_sequence`

其中 Fetch Buffer 深度实验可优先观察：

- `c_prg/minmax_sequence`
- `dhrystone`
- `c_prg/inner_product`
- `coremark`

访存侧 dirty bit/store buffer 可优先观察：

- `c_prg/memcmp`
- `c_prg/loop_induction`
- `c_prg/lookup_table`
- `fireye/A0`
- `fireye/D1`

副槽 BRU 可优先观察：

- `dhrystone`
- `fireye/C0`
- `fireye/I2`
- `coremark`
