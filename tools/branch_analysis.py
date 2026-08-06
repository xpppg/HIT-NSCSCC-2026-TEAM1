#!/usr/bin/env python3
"""深入分析: 1)分支误预测类型 2)cache miss 类型"""
import re
from collections import Counter

# ---------- 解析反汇编 ----------
NO_WRITE = ("st.", "beq", "bne", "blt", "bge", "bltu", "bgeu", "dbar", "ibar",
            "cacop", "syscall", "break", "ertn", "idle", "tlb", "invtlb", "preld")
insn_info = {}
for line in open("/tmp/coremark.dis"):
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
    # branch 目标与是否无条件
    target = None
    uncond = False
    if kind == "branch":
        m2 = re.search(r"([0-9a-f]+)\s*<", rest)
        target = int(m2.group(1), 16) if m2 else None
        if op in ("b", "bl", "jirl"): uncond = True
    if op == "bl": dest, srcs = 1, set(regs)
    elif op == "jirl": dest, srcs = regs[0], set(regs[1:])
    elif op.startswith(NO_WRITE): dest, srcs = None, set(regs)
    elif op in ("sc.w",): dest, srcs = regs[0], set(regs[1:])
    else: dest, srcs = regs[0] if regs else None, set(regs[1:])
    insn_info[pc] = {"srcs": srcs, "dest": dest, "kind": kind, "op": op,
                     "target": target, "uncond": uncond}

def info(pc, inst):
    if pc in insn_info: return insn_info[pc]
    v = int(inst, 16); hi = (v >> 26) & 0x3f
    if hi in (0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1a,0x1b):
        return {"srcs": set(), "dest": None, "kind": "branch", "op": "?", "target": None, "uncond": hi==0x14}
    if hi == 0x0A:
        return {"srcs": set(), "dest": 0, "kind": "load" if ((v>>24)&1)==0 else "store", "op": "?", "target": None, "uncond": False}
    return {"srcs": set(), "dest": None, "kind": "alu", "op": "?", "target": None, "uncond": False}

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

# ========== 1. 分支误预测分类 ==========
# 误预测恢复(gap 5~9)后，下一组第一条 PC 如果是分支 target → taken 分支被误预测为 not-taken
# 下一组第一条 PC 如果是 seq(分支后一条) → not-taken 被误预测为 taken
misp_after = Counter()
misp_by_pc = Counter()
for i in range(1, len(groups)):
    gap = (nss[i]-nss[i-1])//2 - 1
    if not (5 <= gap <= 9): continue
    pg = groups[i-1]
    # 找前组最后一条分支
    brs = [(pc, inst) for pc, inst in pg[1] if info(pc, inst)["kind"] == "branch"]
    if not brs: continue
    br_pc, br_inst = brs[-1]
    bi = info(br_pc, br_inst)
    next_pc = groups[i][1][0][0]
    if bi["uncond"]:
        cls = "无条件(b/bl/jirl)误预测"
    else:
        if bi["target"] is not None and int(next_pc, 16) == bi["target"]:
            cls = "条件taken误预测为not-taken"
        elif bi["target"] is not None and int(next_pc, 16) == (int(br_pc, 16) + 4):
            cls = "条件not-taken误预测为taken"
        else:
            cls = f"目标异常(next={next_pc}, tgt={bi['target']:x})" if bi["target"] else "目标未知"
    misp_after[cls] += 1
    misp_by_pc[br_pc] += 1

print("=== 分支误预测分类 (gap 5~9, 6523次) ===")
for k, v in misp_after.most_common():
    print(f"  {k}: {v} ({v/sum(misp_after.values())*100:.1f}%)")

print("\n=== 误预测分支 TOP PC (含目标) ===")
for pc, v in misp_by_pc.most_common(12):
    bi = info(pc, "0")
    print(f"  {pc} {bi['op']:8s} → {bi['target'] and hex(bi['target'])} : {v} 次")

# ========== 2. 分支总执行次数与预测准确率 ==========
tot_branch = 0
for g in groups:
    for pc, inst in g[1]:
        if info(pc, inst)["kind"] == "branch": tot_branch += 1
print(f"\n总分支指令: {tot_branch}, 误预测恢复次数(5~9拍): {sum(misp_after.values())}")
print(f"分支预测准确率 ≈ {100 - sum(misp_after.values())/tot_branch*100:.1f}%")

# ========== 3. cache miss 类型 (gap>=20) ==========
miss_after = Counter()
for i in range(1, len(groups)):
    gap = (nss[i]-nss[i-1])//2 - 1
    if gap < 20: continue
    pg = groups[i-1]
    last = info(pg[1][-1][0], pg[1][-1][1])
    nxt_pc = int(groups[i][1][0][0], 16)
    prev_pc = int(pg[1][-1][0], 16)
    if last["kind"] == "branch":
        cls = "分支后(icache refill/redirect)"
    elif last["kind"] == "load":
        cls = "load后(dcache miss)"
    elif last["kind"] == "store":
        cls = "store后"
    else:
        cls = "alu后"
    miss_after[cls] += 1
print("\n=== 长停顿(≥20拍) 337次 的前组末类型 ===")
for k, v in miss_after.most_common():
    print(f"  {k}: {v}")
