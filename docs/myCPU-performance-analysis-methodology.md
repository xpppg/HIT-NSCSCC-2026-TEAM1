# myCPU 性能分析方法论与 LLM 执行手册

> 目标：给出一套可重复、可审计、可由其他 LLM 直接执行的 CPU 性能分析流程。分析必须同时结合 RTL、benchmark 软件、匹配的 ELF、动态提交 trace 和周期信息，最终输出有数据依据的瓶颈排序与优化收益上限。

## 1. 文档用途

本手册用于回答以下问题：

- 当前 CPU 的 IPC 为什么不高；
- 双发射率受什么限制；
- 前端、后端、Cache、分支和长延迟单元各损失多少周期；
- 某项 RTL 优化在当前动态负载中是否真的有收益；
- 优化收益是局部双发率提升，还是能转化为总周期下降；
- 哪些结论是 trace 直接证明的，哪些只是基于 PC 模式的推断。

本手册不要求分析者预先相信优化文档中的结论。优化优先级必须由当前 RTL 和当前测试重新推导。

## 2. 核心原则

### 2.1 静态结构和动态热点必须同时成立

一项优化值得做，至少要同时满足：

1. RTL 中确实存在对应限制；
2. benchmark 正式计时区间频繁触发该限制；
3. 放宽该限制后，理论发射组数或空拍数明显下降；
4. 收益没有被更大的前端或 Cache 停顿完全淹没。

只有 RTL 限制、没有动态热点，说明它不是当前优先项。只有动态现象、没有找到 RTL 原因，说明归因还不完整。

### 2.2 必须区分四类问题

分析前先明确正在回答哪一层问题：

| 层次 | 问题 | 典型指标 |
| --- | --- | --- |
| 配对能力 | 连续两条指令能否同拍发射 | 理论配对率、结构冲突、同拍 RAW |
| 后端吞吐 | 有指令时两个执行槽是否持续工作 | 双提交比例、非空拍槽位利用率 |
| 前端供给 | 后端是否经常拿不到指令 | Fetch Buffer empty、I-Cache stall、分支恢复 |
| 整体性能 | 程序为什么耗费这些周期 | IPC、总周期、各类空拍和 stall |

“双发率低”和“IPC 低”不等价。双提交比例很高但 IPC 很低，通常表示存在大量完全没有提交的空拍；此时继续扩大执行宽度未必有效。

### 2.3 先证明统计区间有效

禁止直接对整份 trace 计算 IPC 或双发率，除非已经证明整份 trace 就是 benchmark 正式区间。

初始化、打印、UART 轮询、异常处理和退出代码可能比正式测试长几个数量级。错误区间会让后续所有精确计算都失去意义。

### 2.4 区分事实、重建和推断

输出结论时使用三档证据强度：

- **直接事实**：来自计时器读数、RTL 布尔条件、性能计数器或 trace 精确计数；
- **高可信重建**：按当前 RTL 规则在动态指令流上重放得到；
- **启发式推断**：根据提交间隔、前后 PC 和指令类型推测 stall 原因。

提交 trace 中某次长间隔出现在分支之后，只能说明与控制流高度相关。若没有 `icache_miss` 或 `branch_mispredict` 计数器，不能武断地把全部周期归为某一个硬件信号。

### 2.5 一次只改变一个假设

反事实分析必须逐项放宽规则。例如分别计算：

- 只消除假 RAW；
- 只允许 LSU+BRU；
- 再允许双访存；
- 只消除乘法阻塞。

不要同时假设“完美预测、零 Cache miss、无限功能单元”，然后把结果当作某项具体优化的收益。

## 3. 输入、工具和输出

### 3.1 必需输入

最少需要以下材料：

```text
当前 RTL 源码
benchmark 源码和编译参数
产生本次 trace 的 ELF
正式运行输出
提交 trace
时钟周期或周期计数器读数
当前 git 状态
```

如果 ELF、trace 和 RTL 不是同一轮构建产物，必须停止定量分析或明确降低结论可信度。

### 3.2 推荐工具

```text
rg / rg --files                 搜索 RTL、软件和日志
git status / git diff           确认分析基线
objdump -d                      建立 PC 到指令的映射
nm -n                           建立 PC 到函数的映射
awk / Perl / Python             流式处理大型 trace
RTL 性能计数器                  最终确认 stall 原因
```

大型 trace 应采用流式处理，避免一次性读入全部文本。只需保存正式区间的指令记录或按提交拍聚合后的结果。

### 3.3 最终输出必须包含

一份合格的分析至少包含：

1. 分析基线和有效计时边界；
2. 总周期、动态指令数和 IPC；
3. 双提交比例和非空拍槽位利用率；
4. 动态指令类型与热点函数；
5. 当前规则下的双发重建；
6. 结构冲突、真 RAW、假 RAW 的独立计数；
7. 空拍直方图和主要 stall 归因；
8. 至少两项反事实方案；
9. 总周期收益上限，而不仅是局部百分比；
10. 结论的可信度、局限和下一步计数器需求。

## 4. 总体执行流程

其他 LLM 应严格按以下顺序执行：

```text
阶段 0：固定软硬件基线
    ↓
阶段 1：静态还原 RTL 发射、旁路和 stall 规则
    ↓
阶段 2：确定 benchmark 的精确计时区间
    ↓
阶段 3：使用匹配 ELF 建立动态指令语义
    ↓
阶段 4：计算基础性能指标和热点分布
    ↓
阶段 5：按 RTL 规则重建双发
    ↓
阶段 6：分析提交空拍和长停顿
    ↓
阶段 7：逐项做反事实分析
    ↓
阶段 8：形成瓶颈排序和优化建议
    ↓
阶段 9：用硬件计数器、稳态迭代和其他负载复核
```

不得因为已经看到某个可疑 RTL 条件，就跳过测试区间和动态频率验证。

## 5. 阶段 0：固定分析基线

### 5.1 记录版本状态

执行：

```bash
git status --short
git diff -- <相关 RTL 和配置文件>
```

记录：

- RTL commit；
- 未提交修改；
- benchmark 配置；
- trace 生成时间；
- ELF 生成时间；
- 仿真配置；
- trace 是否开启双提交记录。

工作区中的修改属于分析基线的一部分，不能因为未提交就忽略。例如 Fetch Buffer 深度改变后，旧 trace 不能代表当前 RTL。

### 5.2 记录软件配置

必须确认：

- 优化等级；
- 编译器版本；
- benchmark 迭代次数；
- 数据集大小；
- 是否开启性能模式；
- 内存放置方式；
- 是否在计时区间内打印。

CoreMark、Dhrystone 等测试为了缩短仿真时间，经常只配置一次迭代。这种结果可用于结构和动态指令分析，但冷 Cache、冷预测器占比会高于稳态运行。

### 5.3 基线清单模板

```text
RTL commit:
RTL dirty files:
benchmark:
ELF path:
trace path:
compiler:
compiler flags:
iterations:
data size:
clock period:
timer source:
trace coverage:
```

## 6. 阶段 1：静态还原 RTL 规则

### 6.1 先画出有效流水线

从 valid、ready、allowin 和流水寄存器还原实际流水级，而不是只看文件名。

当前 myCPU 应重点追踪：

```text
pre-IF -> IF1 -> IF2 -> Fetch Buffer/ID -> IS -> EXE -> MEM/commit
```

记录每一级：

- valid 如何产生和清除；
- ready_go 的全部条件；
- allowin 如何向前传播；
- flush 会清除哪些级；
- 哪一级完成分支恢复、访存和提交。

### 6.2 提取全部 stall 条件

当前项目至少检查：

```text
IS_ready_go
IS_ready_go_2
EXE_ready_go
MEM_ready_go
fetch_stall
cpu_stall
rf_we_wating
rf_we_wating_2
inst_waiting
is_raw_wating
peu_wating*
mul_wating
div_wating
wr_buf_wating
mmu_wating
pred_wating
```

把每个信号转换为自然语言，例如：

```text
wr_buf_wating:
MEM 阶段存在访存，同时 EXE 阶段是年轻 load 时，阻止 EXE 前进。

mul_wating:
乘法结果尚未有效时，冻结整个 EXE 级。
```

### 6.3 建立功能单元与槽位能力表

不能笼统地写“顺序双发”。必须列出每类指令可以进入哪个槽：

| 指令类型 | 主槽 | 副槽 | 是否可交换 | 共享资源 |
| --- | --- | --- | --- | --- |
| 普通 ALU | 是 | 是 | 是 | 两套 ALU |
| mul | 是 | 是 | 是 | 各槽乘法路径及全局等待 |
| branch | 是 | 否 | 可把普通指令转到副槽 | BRU |
| load/store | 是 | 否 | 可把普通指令转到副槽 | LSU/D-Cache |
| div | 是 | 否 | 受长延迟等待 | divider |
| CSR/TLB | 是 | 否 | 通常串行化 | PEU/CSR |

表格必须来自当前译码和执行连接，不能沿用旧文档。

这里的类别必须严格服务于 RTL 发射谓词，不能用报告中的性能分类替代。例如当前 `mul` 虽然需要单独统计执行等待，但在结构冲突判定中仍属于可进副槽的 `normal`；若把它擅自改成 special，会直接改变整条贪心配对序列。实现模型前应把 `inst_normal` 等 RTL 信号逐项抄成布尔表达式并用代表指令做单元测试。

### 6.4 正确理解 turning

当前 myCPU 可以通过 `turning` 把物理主副槽和程序顺序解耦。因此：

```text
normal + branch  可以双发
branch + normal  也可以双发
normal + load    可以双发
load + normal    也可以双发
```

只有“两条都需要主槽特殊资源”时才出现当前结构冲突。分析副槽 BRU 时，不能错误声称它主要增加 `ALU+branch`；其主要机会是 `LSU+branch`。

### 6.5 建立真实寄存器语义

每条指令必须得到：

```text
dest
dest_valid
src1
src1_used
src2
src2_used
memory_read
memory_write
branch
normal/special
```

LoongArch 指令中的 `rj/rk/rd` 编码字段并不总是寄存器源：

- 立即数指令的某些字段属于立即数；
- `pcaddu12i` 使用 PC 而不是 `rj`；
- `b/bl` 的编码位不是两个寄存器源；
- store 和条件分支可能使用 `rd` 作为源；
- `bl` 的目的寄存器是 `$r1`；
- 写 `$r0` 不形成有效目的寄存器。

必须分别实现：

```text
rtl_encoded_raw(a, b)    完全模拟当前 RTL 字段比较
semantic_true_raw(a, b)  只比较 b 真正使用的源寄存器
```

两者之差才是假 RAW。

基线重建必须调用 `rtl_encoded_raw`，`semantic_true_raw` 只能用于把已发生的编码 RAW 拆成真/假两类，或构造“消除假 RAW”的反事实。不能因为数据通路上的 `r1_sel/r2_sel` 选择了立即数或 PC，就推断当前发射 RAW 判断也使用了这些选择信号；必须沿 RTL 组合逻辑确认。若本例基线算出 `false_raw == 0`，先视为模型实现异常，不得直接据此下结论。

### 6.6 建立当前发射判定器

用伪代码描述当前规则：

```text
function can_dual_issue(older, younger):
    if both_need_special_main_slot(older, younger):
        return false, "structural"

    if rtl_encoded_raw(older, younger):
        if semantic_true_raw(older, younger):
            return false, "true_raw"
        else:
            return false, "false_raw"

    if csr_or_privileged_serialization(older, younger, pipeline_state):
        return false, "serialization"

    return true, "pair"
```

如果只有提交 trace，没有逐周期流水线状态，CSR 和相对 EXE 依赖无法完全重建，应明确标为近似。

## 7. 阶段 2：确定精确计时区间

### 7.1 边界优先级

按以下顺序寻找：

1. 计时器或硬件计数器的两次实际采样指令；
2. `start_time/stop_time` 或 `get_count` 函数；
3. benchmark marker；
4. 主循环入口和出口；
5. 人工增加 marker。

函数调用 PC 不是最精确边界。若 `start_time()` 内部又调用 `get_clock_count()`，真正的开始时间是计数器 load 完成的时刻，而不是调用 `start_time` 的 `bl`。

### 7.2 用计数器读数交叉验证

找到两次计数器采样后，必须验证：

```text
counter_end - counter_start == benchmark 输出的 total ticks
```

如果 trace 时间戳能够换算为周期，还应验证：

```text
(timestamp_end - timestamp_start) / clock_period == total ticks
```

两者完全一致时，计时区间可信度最高。

### 7.3 定义包含关系

推荐口径：

- 排除第一次计数器读取本身；
- 包含第一次读取之后提交的指令；
- 包含第二次计数器读取，因为停止采样之前的调用和读取延迟属于软件测得周期；
- 总周期以硬件计数器差值为准。

如果采用其他包含关系，必须在报告中说明。

### 7.4 检查区间污染

切片后统计热点 PC。若前三个热点形成类似：

```text
ld.bu status
andi ready_bit
beq retry
```

通常说明 UART 或设备轮询仍在区间内。

还应检查：

- `printf`、`uart_putchar` 是否进入区间；
- 中断或异常处理是否占据大量指令；
- benchmark 主函数是否覆盖主要动态指令；
- 动态循环次数是否和软件配置一致。

## 8. 阶段 3：使用匹配 ELF 建立语义

### 8.1 生成反汇编和符号表

```bash
loongarch32r-linux-gnusf-objdump -d <benchmark.elf> > /tmp/benchmark.dis
loongarch32r-linux-gnusf-nm -n --defined-only <benchmark.elf> > /tmp/benchmark.nm
```

不要使用另一次编译产生的 ELF。

### 8.2 建立两个映射

```text
PC -> 指令字、助记符、操作数
PC -> 所属函数
```

函数映射可以使用“地址不大于 PC 的最近 text symbol”。应忽略数据符号，只使用 `T/t` 类型。

### 8.3 语义解析最低要求

解析器至少支持：

```text
b, bl, beq, bne, blt, bge, bltu, bgeu, jirl
ld.*, ll.*
st.*, sc.*
add/sub/logic/shift/immediate
mul.*
div.*, mod.*
CSR/TLB/ERTN
```

对于伪指令，例如 `move`，应按反汇编操作数识别真实目的和源。

### 8.4 映射自检

至少检查：

- trace 指令字是否和 ELF 同一 PC 指令字一致；
- 未识别 PC 的比例是否为零或极低；
- 热点函数是否符合 benchmark 组成；
- 指令类别之和是否等于动态指令总数。

若映射大量失败，不得继续给出精确 RAW 或配对结论。

## 9. 阶段 4：基础性能指标

### 9.1 按提交拍分组

本项目 trace 中，同一时间戳最多可能有两条提交。将同一时间戳记录合并成一个提交组：

```text
group = {timestamp, committed_instruction_0, committed_instruction_1?}
```

### 9.2 计算公式

```text
N                         = 正式区间动态提交指令数
C                         = 计数器得到的正式区间周期数
G                         = 非空提交拍数
D                         = 含两条提交的拍数

IPC                       = N / C
双提交指令比例             = 2D / N
非空拍槽位利用率           = N / (2G)
完全空拍                   = C - G
空拍比例                   = (C - G) / C
```

如果没有硬件计数器：

```text
C = (last_timestamp - first_timestamp) / clock_period + 1
```

必须确认时间戳单位和时钟周期。不能默认相邻 2ns 就一定代表目标 FPGA 主频，只能代表该仿真的周期换算。

### 9.3 双提交不是精确双发

双提交可作为双发效果的代理，但不严格等于发射级事件：

- 两槽执行延迟可能不同；
- stall 可能让发射和提交重新对齐；
- flush 会取消年轻指令；
- 长延迟指令会改变提交间隔。

若 RTL 中能增加计数器，应以 `dual_issue` 为主、`dual_commit` 为交叉验证。

## 10. 阶段 5：动态画像

### 10.1 指令类型分布

输出：

| 类型 | 数量 | 占比 |
| --- | ---: | ---: |
| normal |  |  |
| load |  |  |
| store |  |  |
| branch |  |  |
| mul |  |  |
| div/mod |  |  |
| privileged |  |  |

注意：`mul` 可以同时属于 `normal` 槽位类别和“长延迟执行类型”。报告中要说明分类是互斥还是重叠。

### 10.2 热点函数和热点 PC

输出前 10～20 个函数：

```text
function -> dynamic instructions -> percentage
```

再输出热点 PC 和反汇编，用于发现：

- 循环尾分支；
- 链表遍历；
- load-use；
- CRC 小函数调用；
- 设备轮询；
- 异常路径。

### 10.3 判断负载代表性

一个 benchmark 是否有普适性，应从动态覆盖判断，而不是只看名称。例如 CoreMark 正式区间应覆盖 list、state、matrix 和 CRC；如果 90% 指令都落在打印函数中，则该次运行仍不具有代表性。

## 11. 阶段 6：重建双发

### 11.1 基线贪心算法

```text
i = 0
groups = 0

while i < instruction_count:
    groups += 1

    if i is last instruction:
        count("tail")
        break

    older = inst[i]
    younger = inst[i + 1]

    result = current_rtl_pair_rule(older, younger)

    if result == pair:
        count_pair(type(older), type(younger))
        i += 2
    else:
        count_single_reason(result)
        i += 1
```

贪心重建的意义是估算当前保序双发规则在同一动态顺序上的配对能力。它不是完整周期级仿真。

贪心循环结束后必须通过以下守恒检查，否则停止分析并修正模型：

```text
instruction_count == 2 * pairs + singles
groups             == pairs + singles
singles            == structural + true_raw + false_raw + serialization + tail
```

其中各原因必须互斥；不能让一个失败配对同时计入 structural 和 RAW。对同一 trace、同一边界和同一 RTL 基线，结果还必须通过第 16 节校准，未通过时不得继续比较优化方案。

### 11.2 必须输出三类单发原因

```text
structural
true_raw
false_raw
```

可再细分：

```text
branch+load
load+branch
store+branch
load+load
store+load
branch+branch
CSR serialization
```

### 11.3 配对方向不能合并

以下组合具有不同语义：

```text
load -> branch
branch -> load
store -> branch
branch -> store
```

例如 CoreMark 中，`load -> branch` 经常存在真 RAW，而其他三个方向几乎没有寄存器 RAW。若简单合并成“LSU+branch RAW 率”，会掩盖真正风险。

### 11.4 LSU+BRU 的 RAW 分析模板

对每个方向输出：

| 方向 | 尝试配对 | 真 RAW | 假 RAW | 可成功配对 |
| --- | ---: | ---: | ---: | ---: |
| branch→load |  |  |  |  |
| branch→store |  |  |  |  |
| load→branch |  |  |  |  |
| store→branch |  |  |  |  |

“尝试配对”必须来自**开放 LSU+BRU 规则后重新运行的贪心序列**。扫描原始动态指令流得到的全部相邻 `LSU↔branch` 只能称为“相邻转移”，可用于描述程序局部性，但不能作为方案实际尝试数或收益分母；此前一次配对是否成功会改变后续候选的对齐。

还要说明非 RAW 正确性风险：

- branch 较老、store 较年轻时，错误预测后不得产生年轻 store 的架构副作用；
- store 较老、branch 较年轻时，store 异常必须屏蔽年轻 branch 重定向；
- load 较老、branch 较年轻且有 RAW 时，应保持互锁，不建议建立同拍 load→branch 长组合旁路；
- BPU 更新、异常和提交必须遵守 older/younger 顺序。

## 12. 阶段 7：提交空拍和 stall 归因

### 12.1 构造 gap

对相邻非空提交组：

```text
gap_cycles = current.timestamp_cycle - previous.timestamp_cycle
extra_empty_cycles = gap_cycles - 1
```

输出精确直方图，例如：

```text
gap=1
gap=2
gap=3..5
gap=6..10
gap=11..20
gap=21..40
gap=41..80
gap>80
```

每个区间必须同时输出两个量：

```text
event_count
extra_cycles = sum(gap_cycles - 1)
```

事件数不是损失周期数。例如 343 个长 gap 事件完全可能贡献一万多个空拍；禁止把 `event_count` 直接写成 cycles 或拿它除以总周期。

检查：

```text
sum(extra_empty_cycles) == C - G
```

如果不相等，说明边界、时间换算或分组有错误。

### 12.2 短气泡分析

对 `gap=2` 等单拍气泡，统计：

- 当前提交组是否含 mul；
- 前一提交组是否含 load/store；
- 前一 load 目的寄存器是否被当前组读取；
- 前一提交组是否含访存，当前组是否含 load；
- RTL 是否存在对应的 `mul_wating`、load-use 或 `wr_buf_wating`。

可以建立互斥启发式分类：

```text
if current_group_contains_mul:
    mul_wait_candidate
else if previous_group_contains_memory and current_group_contains_load:
    memory_to_load_serialization_candidate
else if previous_load_dest_used_by_current_group:
    load_use_candidate
else:
    other_short_bubble
```

这是启发式分类。最终应由硬件计数器确认。

注意因果相位：当前 RTL 的 `mul_wating` 延迟的是**当前将要提交的组**，因此这里检查 `current_group_contains_mul`，不能改成检查 previous group。组内任一槽含 mul 都算，不能只看首条或尾条。若校准样例中 `other_short_bubble` 占比异常偏高，应先怀疑相位、组内检查或分类优先级错误。

### 12.3 分支恢复分析

若某个 gap 高度固定，例如大量集中在 6～8 拍，检查前一提交组是否含 branch。

输出：

```text
branch_count
recovery_event_count
recovery_event_rate
extra_cycles
average_penalty
```

再按以下维度细分：

- 助记符：`beq/bne/jirl/bl/...`；
- 函数；
- PC；
- taken/not-taken，如果 trace 或计数器可用。

如果 99% 以上固定 gap 的前一组含 branch，可以高可信地称为“分支恢复候选”，但仍建议用 `branch_mispredict` 计数器确认。

### 12.4 长停顿分析

对超过阈值的 gap，保存：

```text
gap cycles
previous group PCs
current group PCs
previous instruction types
current first instruction type
是否顺序 PC
是否跨 64B I-Cache 行
是否位于 branch 之后
是否为 load 首次提交
所属函数
```

推荐互斥分类顺序：

```text
1. 顺序执行且 current_pc 为 64B 行首 -> sequential_icache_boundary
2. 前一提交组包含 branch           -> after_branch/control_frontend
3. 当前第一条是 load               -> dcache_or_uncache_candidate
4. 其他                             -> unknown
```

分类顺序应写入报告，因为这些条件可能重叠。

### 12.5 结合 RTL 判断长停顿

例如当前 I-Cache：

```text
cache_stall = miss | cache_state_not_idle
```

这表示 Cache refill 期间即使新地址命中，也可能无法继续供给。分支后的长停顿可能来自：

- 分支目标 miss；
- 错误路径已经发起 refill；
- refill 阻塞了目标地址访问；
- Fetch Buffer 在等待期间耗空。

仅凭提交 PC 无法区分这些情况，应请求或增加：

```text
icache_miss
icache_refill_busy
redirect_while_refill
fetch_buffer_empty
```

## 13. 阶段 8：反事实分析

### 13.1 双发反事实

至少计算：

```text
baseline_current_rtl
semantic_raw_only
allow_lsu_plus_bru
allow_two_memory
unlimited_fu_keep_true_raw
```

所有方案必须从同一个已校验的 `baseline_current_rtl` 出发，一次只替换一个明确谓词。不得把使用编码 RAW 的基线与使用另一套指令分类、边界或贪心对齐方式的变体直接相减。

每个方案输出：

```text
reconstructed_issue_groups
pairs
paired_instruction_ratio
structural_singles
raw_singles
group_reduction_vs_baseline
```

### 13.2 总周期收益上限

```text
issue_cycle_upper_bound = baseline_groups - variant_groups
total_cycle_upper_bound_ratio = issue_cycle_upper_bound / measured_total_cycles
```

必须称为“上限”或“理想估算”。原因包括：

- 新配对可能改变后续 RAW 和功能单元占用；
- 前端可能供不上两条指令；
- Cache 和分支空拍仍然存在；
- 新硬件可能降低主频；
- 提交和异常约束可能增加新的 stall。

### 13.3 stall 反事实

空拍优化可以用对应候选周期作为上限：

```text
perfect_branch_prediction_upper_bound = branch_recovery_empty_cycles
perfect_load_use_upper_bound           = load_use_candidate_cycles
perfect_store_buffer_upper_bound       = store_to_load_candidate_cycles
perfect_mul_pipeline_upper_bound       = mul_wait_candidate_cycles
```

这些值不能直接相加，因为多个条件可能重叠，优化后动态对齐也会改变。

### 13.4 工程成本必须进入排序

同样是 5% 理论收益：

- 加一个 used bit 可能成本很低；
- 第二 LSU 需要多端口 Cache、内存顺序和异常处理；
- non-blocking Cache 需要 MSHR 和请求重放；
- 同拍 ALU0→ALU1 旁路可能显著降低频率。

最终排序建议同时给出：

| 优化 | 动态上限 | 工程成本 | 时序风险 | 正确性风险 | 推荐等级 |
| --- | ---: | --- | --- | --- | --- |

## 14. 阶段 9：稳态和跨负载验证

### 14.1 冷启动和稳态分开

至少报告：

1. 第一轮；
2. 去掉第一轮后的稳态；
3. 全程序端到端。

单轮测试可能放大：

- 冷 I-Cache；
- 冷 D-Cache；
- 冷 BTB/PHT；
- 首次函数调用；
- 初始化和计时函数开销。

### 14.2 跨负载验证

建议覆盖：

```text
控制密集：CoreMark state/list、Dhrystone、字符串处理
访存密集：memcmp、lookup_table、stream、排序
计算密集：inner_product、matrix、乘法密集循环
系统行为：uncache、异常、TLB、Linux
```

CoreMark 更均衡，但不能替代所有访存容量和系统负载测试。例如 CoreMark 2KB 数据集可能无法暴露 D-Cache 容量 miss 或 dirty eviction 问题。

### 14.3 比较优化前后必须保持的条件

```text
同一 ELF 或明确说明重新编译
同一数据集
同一迭代次数
同一随机种子
同一仿真配置
同一计时边界
同一时钟假设
功能结果和 CRC 均正确
```

若优化降低最大频率，应同时报告：

```text
cycles improvement
frequency change
time improvement = cycles / frequency
```

## 15. 推荐硬件性能计数器

### 15.1 基础计数器

```text
cycle_total
commit_0
commit_1
dual_commit
issue_0
issue_1
dual_issue
```

### 15.2 发射和相关

```text
fetch_buffer_empty
structural_special_special
structural_branch_memory
structural_memory_memory
same_pair_true_raw
same_pair_false_raw
exe_dependency_wait
load_use_wait
peu_wait
```

### 15.3 执行和访存

```text
mul_wait
div_wait
wr_buf_wait
cpu_stall
dcache_miss
dcache_writeback
uncache_wait
```

### 15.4 前端和分支

```text
fetch_stall
icache_miss
icache_refill_cycles
redirect_while_refill
branch_count
branch_mispredict
return_count
return_mispredict
flush_recovery_cycles
```

### 15.5 计数器设计要求

计数器应支持 benchmark marker，仅在正式区间累计。

由于多个 stall 信号可能同拍拉高，建议同时提供：

1. 原始信号计数：允许重叠；
2. 独占原因计数：按固定优先级每拍只归入一类。

独占原因优先级必须写在 RTL 注释和分析报告中。

## 16. CoreMark 校准示例

本节只用于帮助其他 LLM 检查实现是否得到相近数量级，不应把这些数字硬编码为未来结论。

### 16.1 有效区间

当前示例中，两次 `get_clock_count()` 最终都通过 PC `0x1c0058a8` 读取计数器：

```text
start = 0x00007574
end   = 0x0004b722
cycles = 278958
```

正式区间约 275329 条动态指令，IPC 约 0.987。

完整 trace 后部主要是 UART 轮询，所以整份 trace 的 IPC 和双发率不能代表 CoreMark。

### 16.2 动态组成

```text
normal 约 48.9%
load   约 23.4%
branch 约 20.2%
store  约 7.5%
```

热点函数覆盖 list、state、matrix 和 CRC，说明正式区间具有基本代表性。

### 16.3 双发重建校准

在第 16.1 节这份示例 trace、边界和当时 RTL 均未变化时，编码 RAW 基线应得到：

```text
groups       = 187482
pairs        = 87847
paired inst  = 63.812%
structural   = 77010
true RAW     = 22049
false RAW    = 575
tail         = 1
```

只消除假 RAW 后应为 187067 groups、88262 pairs；允许 LSU+BRU 后应为 165181 groups、110148 pairs，paired inst 约 80.01%。这些数值是回归校验点，不是要强行套用到新 RTL：若输入工件未变而数字不符，先检查 structural 分类、编码 RAW、计时边界和贪心对齐；若工件已变，则记录差异原因并重新建立校准。允许 LSU+BRU 的变化明显，而消除假 RAW 只产生很小变化。

### 16.4 LSU+BRU 方向性校准

CoreMark 中应观察到：

```text
branch -> load/store：寄存器真 RAW 很少
store  -> branch：没有由 store 产生的寄存器 RAW
load   -> branch：RAW 很高，因为 branch 常立即测试 load 结果
```

开放 LSU+BRU 后，整体真 RAW 阻塞约占尝试配对的两成，但高度集中在 `load→branch`。因此应保留该方向互锁，同时允许其他独立组合。

本例开放后的贪心尝试数约为 30778，其中真 RAW 5979（约 19.43%）；不要用原始流中约 46546 个相邻转移代替该分母。

### 16.5 空拍校准

示例中空拍主要分为：

```text
单拍气泡
约 6～8 拍的分支恢复气泡
约 20 拍以上的 I-Cache/控制流长停顿
```

单拍气泡可进一步与 load-use、store→load 串行化和 mul waiting 对应。若未来 RTL 改变，比例也应随之变化。

本例的额外周期校准为：`gap=2` 贡献 38348 cycles，其中互斥分类约为 load-use 16850、前一访存到当前 load 10667、当前组 mul 9395、other 1436；`gap=6..8` 贡献 30717 cycles；`gap>20` 共 343 个事件，但贡献 13879 cycles。最后一组数字专门用于检查是否混淆事件数和空拍周期数。

## 17. 常见错误与禁止事项

### 17.1 直接统计整份 trace

错误原因：初始化和 UART 轮询可能占据绝大多数指令。

正确做法：找到两次实际计数器采样，验证差值后切片。

### 17.2 使用不匹配的 ELF

错误原因：同一源码不同编译选项会改变 PC、寄存器分配和控制流。

正确做法：检查 ELF 时间、配置和 trace 指令字。

### 17.3 把所有编码字段当作源寄存器

错误原因：立即数、PC 源和无条件分支会产生假 RAW。

正确做法：同时实现 RTL 字段判断和语义 used 判断。

### 17.4 把双提交等同于双发射

错误原因：流水延迟和 stall 会改变提交对齐。

正确做法：双提交作代理，发射计数器作最终依据。

### 17.5 只报告百分比，不报告分母

错误示例：“RAW 占 20%。”

必须说明：

```text
是全部动态指令的 20%
还是所有相邻组合的 20%
还是开放某方案后实际尝试配对的 20%
```

### 17.6 合并方向不同的组合

错误示例：只报告“LSU+branch RAW 率”。

正确做法：分别报告 `load→branch`、`branch→load`、`store→branch` 和 `branch→store`。

### 17.7 把局部发射收益当作总加速比

错误原因：前端和 Cache 空拍仍然存在。

正确做法：同时报告发射组减少比例和相对实测总周期的上限。

### 17.8 从一次长 gap 武断认定 Cache miss

错误原因：分支恢复、错误路径 refill、uncache 和数据相关都可能产生类似间隔。

正确做法：统计模式相关性，并明确需要哪些计数器确认。

### 17.9 忽略正确性和频率

副槽 BRU、第二 LSU 和同拍旁路都可能改变：

- 精确异常；
- flush 屏蔽；
- store 副作用；
- BPU 更新顺序；
- regfile 双写顺序；
- FPGA 关键路径。

性能分析输出必须指出这些工程风险。

## 18. LLM 输出模板

其他 LLM 完成分析后，建议按以下结构输出。

### 18.1 结论摘要

```text
整体 IPC 的第一瓶颈：
双发配对的第一瓶颈：
最不值得优先做的优化：
数据可信度和主要限制：
```

### 18.2 测试和边界

```text
benchmark:
iterations:
ELF:
trace:
start sampling PC/value/time:
end sampling PC/value/time:
measured cycles:
interval contamination check:
```

### 18.3 基础指标

| 指标 | 数值 |
| --- | ---: |
| 动态指令 |  |
| 周期 |  |
| IPC |  |
| 非空提交拍 |  |
| 双提交拍 |  |
| 双提交指令比例 |  |
| 槽位利用率 |  |
| 空拍 |  |

### 18.4 动态画像

```text
指令类型表
热点函数表
热点 PC 表
```

### 18.5 双发瓶颈

```text
当前理论配对率
结构冲突矩阵
真 RAW
假 RAW
方向敏感的 LSU+branch 分析
```

### 18.6 空拍归因

```text
gap 直方图
单拍气泡分类
分支恢复事件
长停顿分类
无法确认的部分
```

### 18.7 反事实与优先级

| 优化 | 理论减少周期/发射组 | 相对总周期上限 | 成本 | 风险 | 推荐 |
| --- | ---: | ---: | --- | --- | --- |

### 18.8 下一步验证

```text
需要新增的计数器
需要增加的迭代
需要补充的负载
需要检查的时序和正确性
```

## 19. 最终检查清单

分析结束前逐项确认：

- [ ] 已记录 RTL、ELF、trace 和编译基线；
- [ ] 已证明计时边界与软件输出一致；
- [ ] 已排除 UART、打印和初始化污染；
- [ ] ELF 指令字与 trace 匹配；
- [ ] 指令分类总数等于动态指令数；
- [ ] 周期、非空提交拍和空拍满足守恒关系；
- [ ] 双提交只作为双发代理；
- [ ] 结构冲突谓词逐项对应当前 RTL，且没有把 mul 等报告类别误作 special；
- [ ] 基线使用编码 RAW，语义 RAW 只用于拆分或反事实；
- [ ] 双发重建通过 `N=2*pairs+singles` 等守恒检查和校准点；
- [ ] 已区分结构冲突、真 RAW 和假 RAW；
- [ ] 已区分 `load→branch` 等方向；
- [ ] 已区分原始相邻转移与开放方案后的贪心尝试；
- [ ] gap 同时报告事件数和 `sum(gap-1)`，没有把事件数当周期；
- [ ] 反事实一次只放宽一项规则；
- [ ] 已把局部收益换算为总周期上限；
- [ ] 已标明直接事实、重建和启发式推断；
- [ ] 已说明冷启动和单次迭代限制；
- [ ] 已列出需要性能计数器确认的结论；
- [ ] 优化建议包含频率、异常、flush 和 store 副作用风险。

完成以上检查后，其他 LLM 才应输出最终瓶颈排序或建议修改 RTL。
