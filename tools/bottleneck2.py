#!/usr/bin/env python3
"""
寄存器级精确依赖分析：对每个提交间隔(gap)归因到具体 stall 源
- load-use: 前组某 load 的 dest 被当前组某指令读取
- mul 依赖: 前组 mul 的 dest 被当前组读 / 当前组首条是 mul(EXE 2拍)
- wr_buf: 前组含 store 且当前组含 load
- branch 恢复: 前组含 branch 且 gap>=5
- 其余: 归 front-end 或其他
"""
import re
from collections import Counter

# ---------- 解析反汇编: pc -> (srcs, dest, kind) ----------
NO_WRITE = ("st.", "beq", "bne", "blt", "bge", "bltu", "bgeu", "dbar", "ibar",
            "cacop", "syscall", "break", "ertn", "idle", "tlb", "invtlb", "preld")
insn_info = {}  # pc -> dict(srcs:set, dest:str|None, kind:str)
for line in open("/tmp/coremark.dis"):
    m = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]+)\s+([a-z0-9\.]+)(.*)", line)
    if not m: continue
    pc, enc, op, rest = m.group(1), m.group(2), m.group(3), m.group(4)
    regs = [int(x) for x in re.findall(r"\$r(\d+)", rest)]
    kind = "mul" if op in ("mul.w","mulh.w","mulh.wu") else (
           "div" if op.startswith(("div","mod")) else (
           "load" if op.startswith("ld.") or op in ("ll.w",) else (
           "store" if op.startswith("st.") or op in ("sc.w",) else (
           "branch" if op in ("beq","bne","blt","bge","bltu","bgeu","b") or op.startswith(("beq","bne","blt","bge","bltu","bgeu")) or op in ("jirl","bl") else (
           "alu")))))
    if op == "bl":
        dest, srcs = 1, set(regs)
    elif op == "jirl":
        dest, srcs = regs[0], set(regs[1:])
    elif op.startswith(NO_WRITE):
        dest, srcs = None, set(regs)
    elif op in ("sc.w",):
        dest, srcs = regs[0], set(regs[1:])
    else:
        # LoongArch: dest = 第一个寄存器
        dest, srcs = regs[0] if regs else None, set(regs[1:])
    insn_info[pc] = {"srcs": srcs, "dest": dest, "kind": kind, "op": op}

def info(pc, inst):
    """合并: 反汇编优先, 缺失时用编码粗判"""
    if pc in insn_info:
        return insn_info[pc]
    v = int(inst, 16)
    hi = (v >> 26) & 0x3f
    if hi in (0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1a,0x1b):
        return {"srcs": set(), "dest": None, "kind": "branch", "op": "?"}
    if hi == 0x0A:
        ld = ((v >> 24) & 1) == 0
        return {"srcs": set(), "dest": 0, "kind": "load" if ld else "store", "op": "?"}
    return {"srcs": set(), "dest": None, "kind": "alu", "op": "?"}

# ---------- 解析 trace ----------
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
N = sum(len(g[1]) for g in groups)
total = (nss[-1]-nss[0])//2 + 1

def group_dests(g):
    d = {}
    for pc, inst in g[1]:
        i = info(pc, inst)
        if i["dest"] is not None:
            d[i["dest"]] = i["kind"]
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
detail = Counter()
for i in range(1, len(groups)):
    gap = (nss[i]-nss[i-1])//2 - 1
    if gap == 0: continue
    pg, cg = groups[i-1], groups[i]
    pk = group_kinds(pg)
    ck = group_kinds(cg)
    pd = group_dests(pg)
    cs = group_srcs(cg)
    pg_last = info(pg[1][-1][0], pg[1][-1][1])["kind"]
    cg_first = info(cg[1][0][0], cg[1][0][1])["kind"]

    if gap >= 20:
        name = "D/I-Cache miss(≥20拍)"
    elif 5 <= gap <= 9:
        name = "分支误预测恢复(5~9拍)"
    elif gap == 1:
        # 单拍: 细分
        raw = [d for d in pd if d in cs]
        if "store" in pk and "load" in ck:
            name = "wr_buf_wating(store→load)"
        elif raw:
            # 找写者类型
            wt = Counter(pd[d] for d in raw)
            if wt.get("load"):
                name = "load-use(load→读)"
            elif wt.get("mul") or wt.get("div"):
                name = "mul/div 依赖"
            else:
                name = "ALU→ALU RAW"
        elif cg_first in ("mul", "div") or (pg_last in ("mul","div")):
            name = "mul/div 延迟"
        else:
            name = "其他单拍"
    elif 2 <= gap <= 4:
        name = f"中等停顿({gap}拍)"
    else:
        name = f"gap={gap}"
    cat[name] += 1
    cat_cycle[name] += gap
    detail[(name, pg_last, cg_first)] += 1

print(f"正式区间: N={N} 指令, 总周期={total}")
print(f"\n=== 空拍归因 (次数 / 空拍数 / 占总周期%) ===")
for name in sorted(cat_cycle, key=lambda k: -cat_cycle[k]):
    print(f"  {name:32s}: {cat[name]:6d} 次, {cat_cycle[name]:6d} 拍, {cat_cycle[name]/total*100:5.1f}%")

print(f"\n=== 单拍细分 (前组末→当前组首) ===")
for (name, pl, cl), v in sorted(detail.items(), key=lambda x: -x[1]):
    if "单拍" in name or "RAW" in name or "依赖" in name:
        print(f"  {name:28s} {pl:6s}→{cl:6s}: {v}")

# 单拍气泡最末归类: 每类单拍的前组末/当前组首分布
print(f"\n=== 各类单拍的(前组末,当前组首)TOP ===")
sub = Counter()
for i in range(1, len(groups)):
    gap = (nss[i]-nss[i-1])//2 - 1
    if gap != 1: continue
    pg, cg = groups[i-1], groups[i]
    pk = group_kinds(pg); ck = group_kinds(cg)
    pd = group_dests(pg); cs = group_srcs(cg)
    pg_last = info(pg[1][-1][0], pg[1][-1][1])["kind"]
    cg_first = info(cg[1][0][0], cg[1][0][1])["kind"]
    raw = [d for d in pd if d in cs]
    if "store" in pk and "load" in ck: key = "wr_buf"
    elif raw:
        wt = Counter(pd[d] for d in raw)
        key = "load-use" if wt.get("load") else ("mul-dep" if (wt.get("mul") or wt.get("div")) else "alu-raw")
    elif cg_first in ("mul","div") or pg_last in ("mul","div"): key = "mul-lat"
    else: key = "other"
    sub[(key, pg_last, cg_first)] += 1
for (k, pl, cl), v in sub.most_common(20):
    print(f"  {k:9s} {pl:6s}→{cl:6s}: {v}")
