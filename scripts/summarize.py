#!/usr/bin/env python3
"""summarize.py <runs_dir> <baseline.json> <save 0|1>. Median of runs, one line per scenario."""
import json, sys, glob, os, statistics as st
runs, base_p, save = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
by = {}
for f in sorted(glob.glob(f"{runs}/*.[0-9]*.json")):
    by.setdefault(os.path.basename(f).split(".")[0], []).append(json.load(open(f)))
base = json.load(open(base_p)) if os.path.exists(base_p) else {}
cur, bad = {}, 0
for sid, rs in by.items():
    m = lambda k: round(st.median(r["frame"][k] for r in rs), 1)
    scopes = {}
    for r in rs:
        for k, v in r["scopes"].items(): scopes.setdefault(k, []).append(v["total"] / max(r["frame"]["frames"], 1))
    top = sorted(((round(st.median(v), 2), k) for k, v in scopes.items()), reverse=True)[:3]
    mem = round(st.median(r["memMB"][-1] - r["memMB"][0] for r in rs), 1)
    cur[sid] = {"fps": m("fps"), "p95": m("p95"), "p99": m("p99"), "max": m("max"), "hitch": m("hitches"), "memΔ": mem,
                "top": {k: v for v, k in top}}
    c, b = cur[sid], base.get(sid)
    line = f"{sid:<14} fps {c['fps']:>5} p95 {c['p95']:>5} p99 {c['p99']:>5} max {c['max']:>6} hitch {c['hitch']:>4} memΔ {mem:>6}"
    if b:
        d = (c["p95"] - b["p95"]) / max(b["p95"], 0.1) * 100
        line += f" | p95 {d:+.0f}% fps {c['fps'] - b['fps']:+.1f} hitch {c['hitch'] - b['hitch']:+.0f}"
        if d > 10: line += " REGRESS"; bad = 1
    if top: line += " | " + " ".join(f"{k}={v}ms/f" for v, k in top)
    print(line)
json.dump(cur, open(os.path.join(runs, "summary.json"), "w"), indent=1)
if save: json.dump(cur, open(base_p, "w"), indent=1, sort_keys=True); print(f"baseline saved {base_p}")
sys.exit(bad)
