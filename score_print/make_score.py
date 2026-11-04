# -*- coding: utf-8 -*-
"""小星星曲谱排版：两页 120x95mm（可拼成 260x95mm 长条，中间虚线裁开）"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Ellipse, FancyBboxPatch
from matplotlib import font_manager as fm

OUT = os.path.dirname(os.path.abspath(__file__))
MM = 1 / 25.4  # mm -> inch

f_zh = fm.FontProperties(fname=r"C:\Windows\Fonts\msyh.ttc")
f_zhb = fm.FontProperties(fname=r"C:\Windows\Fonts\msyhbd.ttc")
f_sh = fm.FontProperties(fname=r"C:\Windows\Fonts\simhei.ttf")
f_sym = fm.FontProperties(fname=r"C:\Windows\Fonts\seguisym.ttf")

# ---------------- 乐谱数据 ----------------
# 音高 -> 五线谱纵向位置（单位：线距，底=E4 在第 1 线）
PITCH_Y = {"C4": -1, "D4": -0.5, "E4": 0, "F4": 0.5, "G4": 1.0,
           "A4": 1.5, "B4": 2.0, "C5": 2.5}
JIANPU = {"C4": "1", "D4": "2", "E4": "3", "F4": "4", "G4": "5", "A4": "6", "B4": "7"}

SONG = [
    ("一闪一闪亮晶晶", [("C4", 1), ("C4", 1), ("G4", 1), ("G4", 1), ("A4", 1), ("A4", 1), ("G4", 2)]),
    ("满天都是小星星", [("F4", 1), ("F4", 1), ("E4", 1), ("E4", 1), ("D4", 1), ("D4", 1), ("C4", 2)]),
    ("挂在天上放光明", [("G4", 1), ("G4", 1), ("F4", 1), ("F4", 1), ("E4", 1), ("E4", 1), ("D4", 2)]),
    ("好像许多小眼睛", [("G4", 1), ("G4", 1), ("F4", 1), ("F4", 1), ("E4", 1), ("E4", 1), ("D4", 2)]),
    ("一闪一闪亮晶晶", [("C4", 1), ("C4", 1), ("G4", 1), ("G4", 1), ("A4", 1), ("A4", 1), ("G4", 2)]),
    ("满天都是小星星", [("F4", 1), ("F4", 1), ("E4", 1), ("E4", 1), ("D4", 1), ("D4", 1), ("C4", 2)]),
]

# ---------------- 绘制一块面板 ----------------
def draw_panel(ax, ox, lines, page_label):
    """ox: 面板左下角在画布中的 x 偏移(mm)；lines: 3 行乐句"""
    S = 2.4                     # 五线谱线距 mm
    FR_X, FR_Y, FR_W, FR_H = 3, 3, 114, 89   # 边框

    # 边框
    ax.add_patch(FancyBboxPatch((ox + FR_X, FR_Y), FR_W, FR_H,
                                boxstyle="round,pad=0,rounding_size=2.5",
                                fc="white", ec="#999999", lw=1.1, mutation_aspect=1))

    # 标题
    cx = ox + FR_X + FR_W / 2
    ax.text(cx, 85.5, "★ 小星星 ★", ha="center", va="center",
            fontsize=21, fontproperties=f_sh, color="#111111")
    ax.text(cx, 80.2, "Twinkle, Twinkle, Little Star   ·   1 = C   ·   4/4   ·   \u2669 = 96",
            ha="center", va="center", fontsize=8.5, fontproperties=f_sym, color="#444444")

    sys_bottoms = [66.0, 41.0, 16.0]        # 每行五线谱最下面一条线的 y
    x0, dx = 25, 12.5                        # 第一个音符 x、音符间距
    bar_x = x0 + 3 * dx + dx / 2             # 小节线
    end_x = x0 + 6 * dx + 6.0                # 终止线

    for row, sysb in enumerate(sys_bottoms):
        lyric, notes = lines[row]
        top = sysb + 4 * S

        # 五线
        for i in range(5):
            ax.plot([ox + x0 - 14, ox + end_x + 2], [sysb + i * S] * 2,
                    color="#111111", lw=1.0, solid_capstyle="butt")

        # 高音谱号
        ax.text(ox + 9.5, sysb + S, "\U0001D11E", fontsize=52,
                fontproperties=f_sym, ha="center", va="center", color="#111111")

        # 拍号 4/4
        ax.text(ox + 17.5, sysb + 1.5 * S, "4", fontsize=13, fontweight="bold",
                fontproperties=f_sym, ha="center", va="center", color="#111111")
        ax.text(ox + 17.5, sysb + 0.5 * S, "4", fontsize=13, fontweight="bold",
                fontproperties=f_sym, ha="center", va="center", color="#111111")

        # 音符
        for i, (pitch, dur) in enumerate(notes):
            nx = ox + x0 + i * dx
            cy = sysb + PITCH_Y[pitch] * S
            if dur == 2:   # 二分音符（空心）
                ax.add_patch(Ellipse((nx, cy), 3.7, 2.75, angle=20,
                                     fc="white", ec="#111111", lw=1.5))
            else:          # 四分音符（实心）
                ax.add_patch(Ellipse((nx, cy), 3.7, 2.75, angle=20,
                                     fc="#111111", ec="#111111", lw=0.8))
            if pitch == "C4":   # 下加一线
                ax.plot([nx - 2.7, nx + 2.7], [cy, cy], color="#111111",
                        lw=1.0, solid_capstyle="butt")
            # 符干（向上）
            ax.plot([nx + 1.65, nx + 1.65], [cy + 0.2, cy + 9.2],
                    color="#111111", lw=1.3, solid_capstyle="butt")
            # 歌词（C4 符头最低到 sysb-3.8，字顶须低于 sysb-4.6 留出空隙）
            ax.text(nx, sysb - 6.4, lyric[i], ha="center", va="center",
                    fontsize=10, fontproperties=f_zh, color="#111111")
            # 简谱数字（灰色），二分音符后加延音线
            ax.text(nx, sysb - 10.2, JIANPU[pitch], ha="center", va="center",
                    fontsize=8.5, fontproperties=f_zh, color="#777777")
            if dur == 2:
                ax.plot([nx + 1.7, nx + 4.4], [sysb - 10.2, sysb - 10.2],
                        color="#777777", lw=1.0, solid_capstyle="butt")

        # 小节线
        ax.plot([ox + bar_x] * 2, [sysb, top], color="#111111", lw=1.3,
                solid_capstyle="butt")
        # 终止线：最后乐句用 细+粗 双线，其余单细线
        if row == 2:
            ax.plot([ox + end_x] * 2, [sysb, top], color="#111111", lw=1.2,
                    solid_capstyle="butt")
            ax.plot([ox + end_x + 1.5] * 2, [sysb, top], color="#111111", lw=3.0,
                    solid_capstyle="butt")
        else:
            ax.plot([ox + end_x] * 2, [sysb, top], color="#111111", lw=1.3,
                    solid_capstyle="butt")

    # 页脚
    ax.text(cx, 1.3, page_label, ha="center", va="center",
            fontsize=7, fontproperties=f_zh, color="#999999")


def make_fig(w_mm, h_mm):
    fig = plt.figure(figsize=(w_mm * MM, h_mm * MM))
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, w_mm)
    ax.set_ylim(0, h_mm)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.patch.set_facecolor("white")
    return fig, ax


def export(fig, name):
    fig.savefig(os.path.join(OUT, name + ".pdf"))
    fig.savefig(os.path.join(OUT, name + ".png"), dpi=300)
    plt.close(fig)


# ---- 单页（120 x 95）----
for idx, rng in [(1, range(0, 3)), (2, range(3, 6))]:
    fig, ax = make_fig(120, 95)
    draw_panel(ax, 0, [SONG[i] for i in rng], f"第 {idx} 页 · 共 2 页")
    export(fig, f"小星星_第{idx}页_120x95mm")

# ---- 拼版长条（260 x 95，中间裁开）----
fig, ax = make_fig(260, 95)
draw_panel(ax, 8, [SONG[i] for i in range(0, 3)], "第 1 页 · 共 2 页")
draw_panel(ax, 132, [SONG[i] for i in range(3, 6)], "第 2 页 · 共 2 页")
ax.plot([130, 130], [2, 92.5], color="#bbbbbb", lw=0.9,
        linestyle=(0, (4, 3)), dashes=(4, 3))
ax.text(122.5, 1.3, "\u2702", ha="center", va="center",
        fontsize=8, fontproperties=f_sym, color="#aaaaaa")
ax.text(130.8, 1.3, "沿虚线裁开", ha="center", va="center",
        fontsize=7, fontproperties=f_zh, color="#aaaaaa")
export(fig, "小星星_拼版_260x95mm")

print("done:", *[f for f in sorted(os.listdir(OUT)) if not f.endswith(".py")], sep="\n  ")
