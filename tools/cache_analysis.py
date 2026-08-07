#!/usr/bin/env python3
"""长停顿(≥20拍)的前组末PC分布，判断 icache vs dcache"""
import re
from collections import Counter

insn_info = {}
for line in open("/tmp/coremark.dis"):
    m = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]+)\s+([a-z0-9\.]+)(.*)", line)
    if not m: continue
    pc, enc, op = m.group(1), m.group(2), m.group(3)
    kind = "mul" if op in ("mul.w","mulh.w","mulh.wu") else (
           "div" if op.startswith(("div","mod")) else (
           "load" if op.startswith("ld.") or op in ("ll.w",) else (
           "store" if op.startswith("st.") or op in ("sc.w",) else (
           "branch" if op in ("jirl","bl") or op.startswith(("beq","bne","blt","bge","bltu","bgeu")) or op == "b" else "alu"))))
    insn_info[pc] = (op, kind)

def parse(path):
    groups = []
    cur_ns = None; cur = []
    with open(path) as f:
        for ln, line in enumerate(f, 1):
            if ln < 18804: continue
            if ln > 294132: break
            m = re.match(r"\[(\d+)ns\] mycpu : pc = ([0-9a-f]+), inst = ([0-9a-f]+)", line)
            if not m: continue
            ns, pc, inst = m.groups()
            if cur_ns is None: cur_ns = ns
            if ns != cur_ns:
                groups.append((cur_ns, cur)); cur_ns, cur = ns, []
            cur.append((pc, inst))
    if cur: groups.append((cur_ns, cur))
    return groups

groups = parse("/tmp/coremark_log_now/simu_trace.txt")
nss = [int(g[0]) for g in groups]

long_stall = Counter()
long_stall_detail = Counter()
for i in range(1, len(groups)):
    gap = (nss[i]-nss[i-1])//2 - 1
    if gap < 20: continue
    pg = groups[i-1]
    last_pc = pg[1][-1][0]
    op, kind = insn_info.get(last_pc, ("?", "?"))
    nxt = groups[i][1][0][0]
    # 判断: 下一组 PC 是否紧邻前组末PC (顺序取指) → 若是则非分支重定向
    seq = int(nxt, 16) == int(last_pc, 16) + 4
    if kind == "branch":
        cls = "分支后"
    elif kind == "load":
        cls = "load后(dcache?)"
    elif kind == "store":
        cls = "store后"
    else:
        cls = "alu后"
    long_stall[cls] += 1
    long_stall_detail[(cls, last_pc, op)] += 1

print("=== 长停顿(≥20拍) 337次 细分 ===")
for k, v in long_stall.most_common():
    print(f"  {k}: {v} 次")
print("\n=== 具体 PC TOP ===")
for (cls, pc, op), v in long_stall_detail.most_common(15):
    print(f"  {cls:16s} {pc} {op:10s}: {v}")

# 平均停顿长度
import statistics
lens = []
for i in range(1, len(groups)):
    gap = (nss[i]-nss[i-1])//2 - 1
    if gap >= 20: lens.append(gap)
print(f"\n长停顿平均 {sum(lens)/len(lens):.1f} 拍, 中位数 {sorted(lens)[len(lens)//2]}, 最大 {max(lens)}")
