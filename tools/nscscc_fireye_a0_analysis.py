#!/usr/bin/env python3
"""
nscscc_perf/fireye_A0 性能瓶颈分析
- trace: /tmp/nscscc_fireye_A0/simu_trace.txt
- 区间: get_count 两次读取之间 (行104299~585708)
- 反汇编: /tmp/nscscc_fireye_A0/nscscc_fireye_A0.dis
"""
import re
from collections import Counter

# ---------- 解析反汇编 ----------
NO_WRITE = ("st.", "beq", "bne", "blt", "bge", "bltu", "bgeu", "dbar", "ibar",
            "cacop", "syscall", "break", "ertn", "idle", "tlb", "invtlb", "preld")
insn_info = {}
for line in open("/tmp/nscscc_fireye_A0/nscscc_fireye_A0.dis"):
    m = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]+)\s+([a-z0-9\.]+)(.*)", line)
    if not m: continue
    pc, enc, op, rest = m.group(1), m.group(2), m.group(3), m.group(4)
    regs = [int(x) for x in re.findall(r"\$r(\d+)", rest)]
    kind = "mul" if op in ("mul.w","mulh.w","mulh.wu") else (
           "div" if op.startswith(("div","mod")) else (
           "load" if op.startswith("ld.") or op in ("ll.w",) else (
           "store" if op.startswith("st.") or op in ("sc.w",) else (
           "branch" if op in ("jirl","bl") or op.startswith(("beq","bne","blt","bge","bltu","bgeu")) or op == "b" else (
           "alu")))))
    if op == "bl": dest, srcs = 1, set(regs)
    elif op == "jirl": dest, srcs = regs[0], set(regs[1:])
    elif op.startswith(NO_WRITE): dest, srcs = None, set(regs)
    elif op in ("sc.w",): dest, srcs = regs[0], set(regs[1:])
    else: dest, srcs = regs[0] if regs else None, set(regs[1:])
    insn_info[pc] = {"srcs": srcs, "dest": dest, "kind": kind, "op": op}

def info(pc, inst):
    if pc in insn_info: return insn_info[pc]
    v = int(inst, 16); hi = (v >> 26) & 0x3f
    if hi in (0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1a,0x1b):
        return {"srcs": set(), "dest": None, "kind": "branch", "op": "?"}
    if hi == 0x0A:
        return {"srcs": set(), "dest": 0, "kind": "load" if ((v>>24)&1)==0 else "store", "op": "?"}
    return {"srcs": set(), "dest": None, "kind": "alu", "op": "?"}

# ---------- 解析 trace (get_count 区间) ----------
START_LINE, END_LINE = 104299, 585708
def parse(path):
    groups = []
    cur_ns = None; cur = []
    with open(path) as f:
        for ln, line in enumerate(f, 1):
            if ln < START_LINE: continue
            if ln > END_LINE: break
            m = re.match(r"\[(\d+)ns\] mycpu : pc = ([0-9a-f]+), inst = ([0-9a-f]+)", line)
            if not m: continue
            ns, pc, inst = m.groups()
            if cur_ns is None: cur_ns = ns
            if ns != cur_ns:
                groups.append((cur_ns, cur)); cur_ns, cur = ns, []
            cur.append((pc, inst))
    if cur: groups.append((cur_ns, cur))
    return groups

groups = parse("/tmp/nscscc_fireye_A0/simu_trace.txt")
nss = [int(g[0]) for g in groups]
N = sum(len(g[1]) for g in groups)
C = len(groups)
total = (nss[-1]-nss[0])//2 + 1
dual = sum(1 for g in groups if len(g[1]) == 2)
print(f"nscscc fireye_A0 计算区间: N={N} 指令, 非空拍C={C}, 总周期={total}")
print(f"双提交拍 {dual} ({dual/C*100:.1f}%), 双提交指令比例 {2*dual/N*100:.1f}%")

def group_dests(g):
    d = {}
    for pc, inst in g[1]:
        i = info(pc, inst)
        if i["dest"] is not None: d[i["dest"]] = i["kind"]
    return d

def group_srcs(g):
    s = set()
    for pc, inst in g[1]:
        s |= info(pc, inst)["srcs"]
    return s

def group_kinds(g):
    return Counter(info(pc, inst)["kind"] for pc, inst in g[1])

# ---------- 归因 ----------
cat = Counter()
cat_cycle = Counter()
for i in range(1, len(groups)):
    gap = (nss[i]-nss[i-1])//2 - 1
    if gap == 0: continue
    pg, cg = groups[i-1], groups[i]
    pk = group_kinds(pg); ck = group_kinds(cg)
    pd = group_dests(pg); cs = group_srcs(cg)
    pg_last = info(pg[1][-1][0], pg[1][-1][1])["kind"]
    cg_first = info(cg[1][0][0], cg[1][0][1])["kind"]

    if gap >= 20:
        name = "Cache miss(≥20拍)"
    elif 5 <= gap <= 9:
        name = "停顿(5~9拍)"
    elif 2 <= gap <= 4:
        name = f"短停顿({gap}拍)"
    elif gap == 1:
        raw = [d for d in pd if d in cs]
        if "store" in pk and "load" in ck:
            name = "wr_buf(store→load)"
        elif raw:
            wt = Counter(pd[d] for d in raw)
            if wt.get("load"): name = "load-use"
            elif wt.get("mul") or wt.get("div"): name = "mul/div依赖"
            else: name = "ALU RAW"
        elif cg_first in ("mul","div") or pg_last in ("mul","div"):
            name = "mul/div延迟"
        else:
            name = "其他单拍"
    else:
        name = f"gap={gap}"
    cat[name] += 1
    cat_cycle[name] += gap

print(f"\n=== 空拍归因 (次数 / 空拍数 / 占总周期%) ===")
for name in sorted(cat_cycle, key=lambda k: -cat_cycle[k]):
    print(f"  {name:24s}: {cat[name]:6d} 次, {cat_cycle[name]:6d} 拍, {cat_cycle[name]/total*100:5.1f}%")

# 停顿(5~9拍)细分: 前组末类型
mid_detail = Counter()
for i in range(1, len(groups)):
    gap = (nss[i]-nss[i-1])//2 - 1
    if not (5 <= gap <= 9): continue
    pg = groups[i-1]
    pcs = [pc for pc,_ in pg[1]]
    kinds = set(info(pc,"0")["kind"] for pc in pcs)
    mid_detail[tuple(sorted(kinds))] += 1
print(f"\n=== 停顿(5~9拍) 前组类型 TOP ===")
for k, v in mid_detail.most_common(8):
    print(f"  {k}: {v}")

# 指令类型分布
it_dist = Counter()
for g in groups:
    for pc, inst in g[1]:
        it_dist[info(pc, inst)["kind"]] += 1
print(f"\n=== 指令类型分布 ===")
for k, v in it_dist.most_common():
    print(f"  {k:8s}: {v} ({v/N*100:.1f}%)")

# 长停顿细分
miss_detail = Counter()
for i in range(1, len(groups)):
    gap = (nss[i]-nss[i-1])//2 - 1
    if gap < 20: continue
    pg = groups[i-1]
    last = info(pg[1][-1][0], pg[1][-1][1])["kind"]
    nxt = int(groups[i][1][0][0], 16)
    prev = int(pg[1][-1][0], 16)
    seq = nxt == prev + 4
    miss_detail[(last, "顺序" if seq else "跳转")] += 1
print(f"\n=== 长停顿(≥20拍) 前组末类型 ===")
for (k, s), v in miss_detail.most_common():
    print(f"  {k:8s} {s}: {v}")
