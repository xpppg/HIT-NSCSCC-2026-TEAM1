# myCPU fireye/C0 动态性能分析报告（修正版）

> 分析对象：`IP/myCPU`（commit `49d1379` + 工作区未提交修改）  
> 分析方法：遵循 `docs/myCPU-performance-analysis-methodology.md`（2026-08-04 更新版）  
> **本版修正**：使用双向 turning 配对模型（结构冲突 = 两条都不能进副槽）、编码 RAW 基线、mul 属 normal；gap 每段同时报告事件数与空拍；双口径（计算主体 / main 端到端）；守恒逐表校验。  
> 旧版（未过校准，`myCPU-fireye-C0-analysis-old-baseline-err.md`）结论作废，以本版为准。

## 1. 测试与边界

### 1.1 分析基线

```text
RTL commit:        49d1379 + fetch_buffer.v 未提交修改（full=count[3]&count[2]）
benchmark:         fireye/C0（NSSCSCC 性能测试）
源码:              software/examples/fireye/C0/C0.c（LOOP=2, A=B=50）
ELF path:          sims/verilator/run_prog/obj/fireye/C0_obj/obj/fireye_C0.elf
trace path:        sims/verilator/run_prog/log/fireye/C0_log/simu_trace.txt
compiler:          GCC 8.3.0 (loongarch32r-linux-gnusf) -O3
输出:              "62"（ans==62 校验通过）
clock:             1 周期 = 2 ns
```

### 1.2 负载结构

Trie 构建 + DFS 深度优先搜索（双 Trie 同步匹配计数）：

```text
main:
    run():
        insert(t[0], C0_data0[i]) × 50     # 构建 Trie 0
        insert(t[1], C0_data1[i]) × 50     # 构建 Trie 1
        LOOP=2 次: ans=0; dfs(1,1)
    printf("%d\n", ans)                    # main 末尾，460176ns

dfs(x, y):                                  # 递归，depth=4
    if x==3: ++ans; return
    for i in 0..25:
        nx = t[0].ch[lastN][i]; ny = t[1].ch[lastM][i]
        if (nx && ny): mpN[x][y]=nx; mpM[x][y]=ny; dfs(下一格)
```

数据规模：两个 Trie 各 10.4KB，合计 20.8KB >> 8KB D-Cache；DFS 随机跳跃访问（按数据驱动字符分支）。

### 1.3 计时边界

```text
main 起点:  76144ns（1c000800）
run() 调用: 76418ns（1c000830 bl run）→ 计算主体起点
printf:     460176ns（1c000840 bl printf）→ 计算主体终点（计算主体 = 76144..460174）
main 返回:  531450ns（1c00085c）→ main 端到端终点
```

**双口径**：
- **计算主体**（76144..460174）：不含 printf，即纯 DFS 计算；
- **main 端到端**（76144..531450）：含 printf 库（vfprintf 等，约 71300 拍）。

## 2. 基础指标

| 指标 | 计算主体 | main 端到端 |
| --- | ---: | ---: |
| N（动态指令） | 194777 | 205907 |
| C（周期） | 192016 | 227654 |
| **IPC** | **1.0144** | 0.9045 |
| G（非空提交拍） | 138041 | 148845 |
| D（双提交拍） | 56736 | 57062 |
| 双提交指令比例 | 58.3% | 55.4% |
| 槽位利用率 | 70.6% | 69.2% |
| 完全空拍 | 28.1% | 34.6% |

**守恒校验（逐表）**：

```text
计算主体: sum(gap-1)=53975 == C-G=53975 ✓；事件数之和=138040 == G-1=138040 ✓
main端到端: sum(gap-1)=78809 == C-G=78809 ✓；事件数之和=148844 == G-1=148844 ✓
```

## 3. 动态画像（计算主体）

| 类型 | 数量 | 占比 |
| --- | ---: | ---: |
| normal | 131234 | 67.4% |
| load | 24385 | 12.5% |
| branch | 21012 | 10.8% |
| **mul** | 11206 | **5.8%** |
| store | 6940 | 3.6% |

热点函数：dfs 约 96%（计算主体几乎全部为 dfs 递归）。Trie 索引计算链 `ld.w@f8 → add.w@fc → slli.w@00 → mul.w@04 → ...` 是 dfs 主路径。

## 4. 双发重建（修正模型，计算主体）

基线（编码 RAW）：

```text
发射组 = 136581
守恒: N = 2*pairs + singles = 194777 ✓
```

| 单发原因 | 数量 | 占比 |
| --- | ---: | ---: |
| **真 RAW** | **47553** | **24.4%** |
| 结构冲突 | 30431 | 15.6% |
| 假 RAW | 0 | 0% |
| tail | 1 | ~0 |

**C0 的第一配对瓶颈是真 RAW（24.4%），不是结构冲突**——dfs 索引链 `load→mul→add` 之间 RAW 依赖密集。这与 CoreMark（结构冲突 41%）完全不同。

## 5. 反事实分析（计算主体口径）

| 方案 | 发射组 | 减少 | 相对总周期上限 |
| --- | ---: | ---: | ---: |
| baseline（编码 RAW） | 136581 | — | — |
| 只按语义 RAW（消除假 RAW） | 136381 | 200 | 0.10% |
| **副槽 BRU**（允许 branch 进副槽） | 133473 | 3108 | **1.62%** |
| **第二 LSU**（仅 memory 进副槽） | 130782 | 5799 | **3.02%** |
| 副槽 BRU + 第二 LSU | 130582 | 5999 | 3.12% |

**关键修正结果**：第二 LSU 收益（3.02%）> 副槽 BRU（1.62%）。C0 的 dfs 主路径含 `st.w` 相邻（`st.w@5c → st.w@60`）与 `ld.w` 链，双访存能配对部分 memory+memory 组合。

**注意**：此结论与 A0（副槽 BRU >> 第二 LSU）**相反**——不同负载的双发优化收益方向不同，必须逐负载分析，不能外推。

## 6. 方向敏感 LSU+BRU（allow_bru 贪心序列）

| 方向 | 贪心尝试 | 真 RAW | 可成功 |
| --- | ---: | ---: | ---: |
| branch→load | 10897 | 0 | 10897 |
| branch→store | 0 | 0 | 0 |
| load→branch | 200 | 0 | 200 |
| store→branch | 586 | 0 | 586 |

对照：原始流相邻转移 branch→load 10901 / load→branch 10641 / store→branch 586。

**C0 与 CoreMark 相反：load→branch 的真 RAW 几乎为 0**（dfs 的 `ld.w→beq` 判空时，目的寄存器经 mul/add 链后才被分支使用；贪心对齐后 load→branch 相邻对也很少）。branch→load 是主要形态（10897 次可成功，无 RAW 障碍）。

**结论：副槽 BRU 在 C0 上主要收益来自 branch→load 配对。**

## 7. 空拍归因（计算主体）

### 7.1 gap 直方图（事件数 + 空拍）

| gap | 事件数 | 空拍 | 归因 |
| --- | ---: | ---: | ---: |
| 1 | 110161 | 0 | 连续提交 |
| 2 | 22831 | 22831（11.9%） | load-use / mul 等待 |
| 3–5 | 1552 | 3104（1.6%） | mul/load 延迟 |
| 6–10 | 3274 | 19198（10.0%） | 分支恢复 |
| 11–20 | 0 | 0 | — |
| 21–40 | 125 | 4393（2.3%） | D-Cache miss |
| 41–80 | 97 | 4449（2.3%） | D-Cache miss |
| >80 | 0 | 0 | — |

### 7.2 归因 1：load-use + mul 等待（13.5%）

`gap=2`（22831 拍）互斥分类：

```text
load-use（前组 load dest 被当前组读）  11026
当前组含 mul（mul_wating）            9628
其他                                1712
前组访存→当前 load                    465
```

**C0 的 load-use 与 mul_wating 几乎平分单拍气泡**——`ld.w→mul.w→add.w` 链使两者交替出现。这是 A0（纯 load-use）与 CoreMark（mul 少）的中间态。

### 7.3 归因 2：分支恢复（10.0%）

`gap 6–10` 共 3274 次，3269 次（99.8%）前组含 branch，空拍 19173 拍。来源：dfs 的 `beq@34/54`（Trie 节点判空）、`bge@64`（行末）、`beq@90`（循环条件）、递归调用返回。DFS 分支模式数据驱动，误预测率高是结构性的。

### 7.4 归因 3：D-Cache miss（4.6%）

`gap>20` 合计 8842 拍（4.6%），前组最后 PC 均为 dfs 内紧跟 load 的 `add.w@4c/2c/00`、`beq@34` 等。Trie 20.8KB 随机访问远超 8KB D-Cache，miss 触发 16-beat refill。

**C0 的 D-Cache miss 占比（4.6%）远低于 A0（12.7%）**——dfs 深度仅 4，递归路径局部性尚可。

### 7.5 递归开销

dfs 自递归 `bl@970` 共 434 次（含 LOOP=2），每次保存/恢复 9 个寄存器（`st.w/ld.w` ×9）。递归框架开销占计算主体比例小（dfs 主路径 96%）。

## 8. 结论摘要

```text
整体 IPC 的第一瓶颈：    28.1% 空拍（计算主体）；load-use+mul 13.5% + 分支恢复 10.0%
                        + D-Cache miss 4.6%
双发配对的第一瓶颈：     真 RAW 24.4%（dfs 索引链 load→mul→add 依赖密集）；
                        结构冲突 15.6% 其次
反事实：                 第二 LSU 3.02% > 副槽 BRU 1.62%（与 A0 相反，勿外推）
副槽 BRU 细节：          主要收益来自 branch→load（10897 次，无 RAW 障碍）
最有价值的优化方向：     load-use/mul 延迟（13.5%，与 A0 同根因）；
                        分支恢复（10.0%，跨负载共性）
数据可信度：             双口径守恒逐表通过；基线模型为修正版（编码 RAW、双向 turning）；
                        无显式计时器；归因为启发式，需计数器确认
```

## 9. 局限与下一步验证

### 9.1 局限

- 无显式计时器，周期为时间戳换算；
- 计算主体边界以 `bl printf`（460176ns）为界；
- 单次配置（LOOP=2），DFS 分支模式可能随数据变化；
- 归因为提交间隔启发式，`load→mul` 链的精确停顿级数需周期级确认。

### 9.2 建议计数器

```text
branch_mispredict（按 PC）     确认 10.0% 分支恢复（beq@34/54 节点判空 vs beq@90 循环）
load_use_wait                  确认 load-use（11026 次候选）
mul_wait                       确认 mul 等待（9628 次候选）
dcache_miss                    确认 4.6% 长停顿（Trie 随机 miss）
dual_issue                     校准 58.3% 双提交与重建配对率的差值
```

### 9.3 对优化文档的补充意见

1. **load→mul 链级联延迟**：`ld.w→mul.w` 使 load-use 与 mul_wating 交替出现（合计 13.5%）。实现"乘法固定流水化"（优化文档 2.5）时需同时考虑其与 load-use 的级联；
2. **第二 LSU 在 C0 有 3.02% 上限**（store+store / load+store 配对），在 A0 几乎为零（0.013%）——双访存收益完全依赖负载形态；
3. **副槽 BRU 在 C0 主要受益 branch→load**（与 CoreMark 的 load→branch 高 RAW 不同）——方向敏感分析必须逐负载做，不能套用 CoreMark 结论。

## 10. 分析检查清单（手册 19 节）

- [x] 已记录 RTL、ELF、trace 和编译基线（含未提交修改）
- [x] 已确定计时边界（双口径：计算主体 / main 端到端）
- [x] 已排除 UART/printf 污染（计算主体不含 printf）
- [x] ELF 指令字与 trace 匹配（同轮构建）
- [x] 指令分类总数等于动态指令数
- [x] 周期、非空提交拍和空拍守恒（53975==53975，78809==78809）
- [x] 双提交只作为双发代理指标
- [x] 结构冲突谓词 = 两条都不能进副槽（双向 turning），mul 属 normal
- [x] 基线使用编码 RAW，语义 RAW 只用于拆分/反事实
- [x] 双发重建通过 N=2*pairs+singles 守恒
- [x] 已区分结构冲突、真 RAW、假 RAW（0）
- [x] 已区分方向（C0 为 branch→load 主导，无 load→branch RAW）
- [x] 已区分贪心尝试与相邻转移（10897 vs 10901）
- [x] gap 同时报告事件数和 sum(gap-1)
- [x] 反事实一次只放宽一项规则
- [x] 已把局部收益换算为总周期上限
- [x] 已标明直接事实、重建和启发式推断
- [x] 已说明冷启动、单次配置和无计时器限制
- [x] 已列出需要性能计数器确认的结论
- [x] 优化建议包含频率、异常、flush 风险
