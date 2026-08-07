#!/usr/bin/env python3
"""
nscscc_perf/dhrystone 前端供给分析
- 区间: get_count start(行384359)~stop(行415576), 总周期33861
- 分析是否有前端供给不足 (fetch 跟不上执行)
"""
import re
from collections import Counter

# 反汇编
insn_info = {}
funcs = {}
cur_fn = None
for line in open("/tmp/dhrystone/dhrystone.dis"):
    m = re.match(r"\s*([0-9a-f]+) <([^>]+)>:", line)
    if m: cur_fn = m.group(2)
    m2 = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]+)\s+([a-z0-9\.]+)(.*)", line)
    if m2:
        pc = m2.group(1)
        op = m2.group(3)
        kind = ("load" if op.startswith("ld.") or op in ("ll.w",) else
                "store" if op.startswith("st.") or op in ("sc.w",) else
                "branch" if op in ("jirl","bl") or op.startswith(("beq","bne","blt","bge","bltu","bgeu")) or op=="b" else
                "alu")
        insn_info[pc] = (op, kind)
        if cur_fn: funcs[pc] = cur_fn

def parse():
    groups = []
    cur_ns = None; cur = []
    with open("/tmp/dhrystone/simu_trace.txt") as f:
        for ln, line in enumerate(f, 1):
            if ln < 384359: continue
            if ln > 415576: break
            m = re.match(r"\[(\d+)ns\] mycpu : pc = ([0-9a-f]+), inst = ([0-9a-f]+)", line)
            if not m: continue
            ns, pc, inst = m.groups()
            if cur_ns is None: cur_ns = ns
            if ns != cur_ns:
                groups.append((cur_ns, cur)); cur_ns, cur = ns, []
            cur.append((pc, inst))
    if cur: groups.append((cur_ns, cur))
    return groups

groups = parse()
nss = [int(g[0]) for g in groups]
N = sum(len(g[1]) for g in groups)
C = len(groups)
total = (nss[-1]-nss[0])//2 + 1
dual = sum(1 for g in groups if len(g[1]) == 2)
print(f"dhrystone 计时区间: N={N} 指令, C={C}, 总周期={total}")
print(f"双提交拍 {dual} ({dual/C*100:.1f}%), 双提交指令比例 {2*dual/N*100:.1f}%")

# ============ 前端供给分析 ============
# 前端供给不足的表现: 空拍 (gap>=1)
# 分类: 1) 分支相关 2) icache 3) 后端 stall (load-use等) 4) 其他
gaps = [(nss[i]-nss[i-1])//2 - 1 for i in range(1, len(groups))]
gapc = Counter(g for g in gaps if g > 0)
print(f"\n=== gap 分布 ===")
for g in sorted(gapc):
    print(f"  gap={g}: {gapc[g]}次, {gapc[g]*g}拍")

# 空拍归因 (简化版)
cat = Counter()
cat_cyc = Counter()
for i in range(1, len(groups)):
    gap = gaps[i-1]
    if gap == 0: continue
    pg = groups[i-1]
    pg_pcs = [pc for pc,_ in pg[1]]
    # 前组末指令类型
    last_pc = pg_pcs[-1]
    last_op, last_kind = insn_info.get(last_pc, ("?","?"))
    # 分支?
    if last_kind == "branch":
        if gap >= 5:
            cat["分支恢复(5拍+)"] += 1; cat_cyc["分支恢复(5拍+)"] += gap
        else:
            cat["分支后短停"] += 1; cat_cyc["分支后短停"] += gap
    elif gap >= 20:
        cat["Cache/长停顿(20拍+)"] += 1; cat_cyc["Cache/长停顿(20拍+)"] += gap
    elif gap >= 5:
        cat["中等停顿(5~19)"] += 1; cat_cyc["中等停顿(5~19)"] += gap
    else:
        cat["单拍停顿"] += 1; cat_cyc["单拍停顿"] += gap

print(f"\n=== 空拍归因 ===")
for k in sorted(cat_cyc, key=lambda x: -cat_cyc[x]):
    print(f"  {k}: {cat[k]}次, {cat_cyc[k]}拍 ({cat_cyc[k]/total*100:.1f}%)")

# 函数分布
func_cnt = Counter()
for g in groups:
    for pc, inst in g[1]:
        func_cnt[funcs.get(pc, "?")] += 1
print(f"\n=== 函数分布 ===")
for k, v in func_cnt.most_common(10):
    print(f"  {k:20s}: {v} ({v/N*100:.1f}%)")

# 指令类型
it = Counter()
for g in groups:
    for pc, inst in g[1]:
        it[insn_info.get(pc, ("?","?"))[1]] += 1
print(f"\n=== 指令类型 ===")
for k, v in it.most_common():
    print(f"  {k:8s}: {v} ({v/N*100:.1f}%)")
