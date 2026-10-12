"""Builds the figures used in paper.tex from the CSV tables in results/.
Run from the project folder:  python3 paper/make_figures.py
"""
import csv, os, statistics as st
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = lambda *p: os.path.join(ROOT, "results", "tables", *p)
OUT = os.path.join(ROOT, "paper", "figures")
os.makedirs(OUT, exist_ok=True)

plt.rcParams.update({"font.family": "serif", "font.size": 9, "axes.spines.top": False,
                     "axes.spines.right": False, "axes.unicode_minus": True,
                     "savefig.dpi": 300, "savefig.bbox": "tight"})
INK, MUTED, ACCENT, ACCENT2 = "#1f2933", "#7b8794", "#2f6db5", "#c2553a"
CAT_COL = {"HVHA": "#c2553a", "HVLA": "#d9a23a", "LVHA": "#7a4fa3", "LVLA": "#2f6db5", "N": "#7b8794"}
CAT_NAME = {"HVHA": "happy, energetic", "HVLA": "pleasant, calm", "LVHA": "tense, energetic",
            "LVLA": "sad, calm", "N": "neutral"}

def read(path, delim=","):
    with open(path, newline="") as f:
        return list(csv.DictReader(f, delimiter=delim))

# 1. Song map ---------------------------------------------------------------
r = read(T("ratings", "ratings_with_consensus_deviation.tsv"), "\t")
songs = defaultdict(lambda: {"v": [], "a": [], "cat": None})
for x in r:
    s = songs[x["song_id"]]; s["v"].append(float(x["Valence"])); s["a"].append(float(x["Arousal"]))
    s["cat"] = x["Song Catergory"]
fig, ax = plt.subplots(figsize=(5.2, 3.4))
for cat in CAT_COL:
    pts = [(st.mean(s["v"]), st.mean(s["a"])) for s in songs.values() if s["cat"] == cat]
    ax.scatter(*zip(*pts), s=42, color=CAT_COL[cat], label=f"{cat} ({CAT_NAME[cat]})",
               edgecolor="white", linewidth=0.6, zorder=3)
ax.axvline(5, color=MUTED, lw=0.6, ls=":"); ax.axhline(5, color=MUTED, lw=0.6, ls=":")
ax.set_xlim(1, 9); ax.set_ylim(1, 9)
ax.set_xlabel("Mean valence (1 unpleasant, 9 pleasant)"); ax.set_ylabel("Mean arousal (1 calm, 9 excited)")
ax.legend(frameon=False, fontsize=7, loc="lower left", title="Intended category", title_fontsize=7)
ax.text(1.2, 8.6, "no song averaged\nbelow 3.1 on valence", fontsize=7, color=MUTED, va="top")
fig.savefig(os.path.join(OUT, "fig1_song_map.png")); plt.close(fig)

# 2. Alpha by region (sanity check) ----------------------------------------
qc = {(x["participant_id"], x["song_id"]): x["included"] == "TRUE" for x in read(T("features", "qc_table.csv"))}
bp = read(T("features", "bandpower_roi.csv"))
per = defaultdict(list)
for x in bp:
    if x["band"] == "alpha" and x["amp_thresh_uv"] == "100" and qc.get((x["participant_id"], x["song_id"])):
        per[(x["roi"], x["participant_id"])].append(float(x["log10_power"]))
rois = ["posterior", "central", "left_temporal", "right_temporal", "left_frontal", "right_frontal", "frontal_midline"]
labels = ["Posterior", "Central", "Left\ntemporal", "Right\ntemporal", "Left\nfrontal", "Right\nfrontal", "Frontal\nmidline"]
fig, ax = plt.subplots(figsize=(5.6, 2.8))
for i, roi in enumerate(rois):
    vals = [st.mean(v) for (rr, p), v in per.items() if rr == roi]
    jitter = np.random.default_rng(i).uniform(-0.15, 0.15, len(vals))
    ax.scatter(i + jitter, vals, s=9, color=MUTED, alpha=0.6, zorder=2)
    ax.plot([i - 0.28, i + 0.28], [st.mean(vals)] * 2, color=ACCENT if roi == "posterior" else INK, lw=2.4, zorder=3)
ax.set_xticks(range(len(rois))); ax.set_xticklabels(labels, fontsize=7.5)
ax.set_ylabel("Alpha power (log10 µV²)")
fig.savefig(os.path.join(OUT, "fig2_alpha_by_region.png")); plt.close(fig)

# 3. Pooling demo ------------------------------------------------------------
pd_ = read(T("statistics", "step17_pooling_demo.csv"))
names = {"(a)": "Naive pooling\n(395 trials, invalid)", "(b)": "Two stage within person\n(20 people)",
         "(c)": "Between person means\n(20 people)"}
fig, axes = plt.subplots(1, 2, figsize=(6.2, 2.4), sharey=True)
for ax, key, title in zip(axes, ["H1", "H2"], ["H1: posterior alpha and arousal", "H2: FAA and valence"]):
    rows = [x for x in pd_ if x["analysis"].startswith(key)]
    for j, x in enumerate(rows):
        y = 2 - j; col = ACCENT2 if "(a)" in x["method"] else INK
        ax.errorbar(float(x["r"]), y, xerr=[[float(x["r"]) - float(x["ci_low"])], [float(x["ci_high"]) - float(x["r"])]],
                    fmt="o", color=col, ms=4, capsize=3, lw=1.2)
    ax.axvline(0, color=MUTED, ls="--", lw=0.8)
    ax.set_title(title, fontsize=8.5); ax.set_xlabel("Spearman r with 95% CI"); ax.set_xlim(-0.7, 0.55)
axes[0].set_yticks([2, 1, 0]); axes[0].set_yticklabels([names[k] for k in ["(a)", "(b)", "(c)"]], fontsize=7.5)
fig.savefig(os.path.join(OUT, "fig3_pooling.png")); plt.close(fig)

# 4. Confirmatory and sensitivity forest ------------------------------------
conf = read(T("statistics", "step18_confirmatory_H1_H2.csv")); dev = read(T("statistics", "step19_consensus_deviation.csv"))
sens = read(T("statistics", "step22_sensitivity.csv"))
def row(x): return float(x["std_estimate"]), float(x["std_ci_low"]), float(x["std_ci_high"])
items = []
for h, lab in [("H1", "Arousal and posterior alpha (H1)"), ("H2", "Valence and FAA (H2)")]:
    items.append((lab, None, "head"))
    c = [x for x in conf if x["hypothesis"].startswith(h + ":")][0]
    items.append(("Confirmatory model", row(c), "main"))
    d = [x for x in dev if x["hypothesis"].startswith(h + " person")][0]
    items.append(("Person specific deviation", row(d), "main"))
    for x in sens:
        if x["hypothesis"] == h and x["model"] != "primary":
            nm = {"both ratings": "Both ratings in one model", "+ liking & familiarity": "Adding liking and familiarity",
                  "relative power": "Relative power", "75 uV amplitude threshold": "Stricter 75 µV threshold"}[x["model"]]
            items.append((nm, row(x), "sens"))
fig, ax = plt.subplots(figsize=(5.6, 3.9))
y = len(items); ticks, tl = [], []
for lab, v, kind in items:
    y -= 1
    if kind == "head":
        ax.text(-0.315, y, lab, fontsize=8.5, fontweight="bold", va="center", ha="left"); continue
    col = INK if kind == "main" else MUTED
    ax.errorbar(v[0], y, xerr=[[v[0] - v[1]], [v[2] - v[0]]], fmt="o" if kind == "main" else "s",
                color=col, ms=4 if kind == "main" else 3, capsize=2.5, lw=1.2)
    ticks.append(y); tl.append(lab)
ax.axvline(0, color=MUTED, ls="--", lw=0.8)
ax.set_yticks(ticks); ax.set_yticklabels(tl, fontsize=7.5); ax.set_xlim(-0.32, 0.25); ax.set_ylim(-1.3, len(items) - 0.3)
ax.set_xlabel("Standardized within person effect with 95% CI")
fig.savefig(os.path.join(OUT, "fig4_confirmatory.png")); plt.close(fig)

# 5. Raw per person slopes (H3 story) ----------------------------------------
tr = read(T("statistics", "analysis_trials.csv"))
by = defaultdict(list)
for x in tr:
    if x["post_alpha"] not in ("", "NA"): by[x["participant_id"]].append((float(x["Arousal"]), float(x["post_alpha"])))
sl = []
for p, v in sorted(by.items()):
    a = np.array(v); xw = a[:, 0] - a[:, 0].mean(); yw = a[:, 1] - a[:, 1].mean()
    b = (xw @ yw) / (xw @ xw); res = yw - b * xw; se = np.sqrt((res @ res) / (len(a) - 2) / (xw @ xw))
    sl.append((p, b, se))
sl.sort(key=lambda t: t[1])
fig, ax = plt.subplots(figsize=(5.6, 3.0))
for i, (p, b, se) in enumerate(sl):
    ax.errorbar(i, b, yerr=1.96 * se, fmt="o", color=INK, ms=3.5, capsize=2, lw=1)
fixed = float([x for x in conf if x["hypothesis"].startswith("H1:")][0]["estimate"])
ax.axhline(fixed, color=ACCENT, lw=1.6, label="Group slope (all 20 people shrink to this line)")
ax.axhline(0, color=MUTED, ls="--", lw=0.8)
ax.set_xticks(range(len(sl))); ax.set_xticklabels([p.replace("sub", "S").replace("S-", "S") for p, _, _ in sl], rotation=90, fontsize=6.5)
ax.set_ylabel("Raw slope: alpha per\narousal point (log10 units)"); ax.set_xlabel("Listener (sorted by slope)")
ax.legend(frameon=False, fontsize=7, loc="upper left")
fig.savefig(os.path.join(OUT, "fig5_person_slopes.png")); plt.close(fig)

# 6. Exploratory grid ----------------------------------------------------------
ex = read(T("statistics", "step21_exploratory_grid.csv"))
bands = ["delta", "theta", "alpha", "beta", "gamma"]; preds = ["Valence", "Arousal", "Liking"]
fig, axes = plt.subplots(1, 3, figsize=(6.4, 2.6), sharey=True)
for ax, pr in zip(axes, preds):
    M = np.full((len(rois), len(bands)), np.nan); P = np.ones_like(M)
    for x in ex:
        if x["predictor"] == {"Liking": "Likeability"}.get(pr, pr):
            M[rois.index(x["roi"]), bands.index(x["band"])] = float(x["t"]); P[rois.index(x["roi"]), bands.index(x["band"])] = float(x["p"])
    im = ax.imshow(M, cmap="RdBu_r", vmin=-3, vmax=3, aspect="auto")
    for i in range(len(rois)):
        for j in range(len(bands)):
            if P[i, j] < 0.05: ax.text(j, i, "•", ha="center", va="center", fontsize=9, color=INK)
    ax.set_xticks(range(5)); ax.set_xticklabels(["δ", "θ", "α", "β", "γ"]); ax.set_title(pr, fontsize=8.5)
    for s in ax.spines.values(): s.set_visible(False)
axes[0].set_yticks(range(len(rois))); axes[0].set_yticklabels([l.replace("\n", " ") for l in labels], fontsize=7)
cb = fig.colorbar(im, ax=axes, shrink=0.85, pad=0.02); cb.set_label("t value", fontsize=8)
fig.savefig(os.path.join(OUT, "fig6_exploratory.png")); plt.close(fig)
print("figures written to", OUT)
