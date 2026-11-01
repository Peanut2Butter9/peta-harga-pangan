"""Gaya grafik bersama untuk semua notebook.

Warna kategori dipakai berurutan dan tidak diulang; warna selalu mengikuti entitasnya,
bukan peringkatnya. Garis tipis, grid hairline, teks memakai warna teks (bukan warna seri).
"""
from pathlib import Path

import matplotlib as mpl
import matplotlib.dates as mdates
import numpy as np
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.ticker import FuncFormatter
from matplotlib.transforms import Bbox

FIG_DIR = Path(__file__).resolve().parents[1] / "reports" / "figures"

SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"

# urutan slot kategori (lolos validasi buta warna untuk pasangan bersebelahan)
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
# untuk scatter / peta (semua pasangan saling bersebelahan) hanya 3 slot pertama yang aman
SERIES_ALL_PAIRS = SERIES[:3]

# divergen biru <-> merah dengan titik tengah abu-abu
DIVERGING = ["#184f95", "#3987e5", "#9ec5f4", "#f0efec", "#f4b1b0", "#e66767", "#b02a2a"]
# sekuensial satu warna (biru), terang -> gelap
SEQUENTIAL = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]
CMAP_SEQ = LinearSegmentedColormap.from_list("sekuensial", SEQUENTIAL)
CMAP_DIV = LinearSegmentedColormap.from_list("divergen", DIVERGING)   # rendah = biru, tinggi = merah

BULAN = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]


def nama_bulan(t):
    """Timestamp -> 'Okt 2026'."""
    return f"{BULAN[t.month - 1]} {t.year}"


def sumbu_tanggal(ax, dengan_hari=True):
    """Label tanggal sumbu-x dalam bahasa Indonesia: '31 Jul' atau 'Jul 20'."""
    def fmt(x, _):
        d = mdates.num2date(x)
        return f"{d.day} {BULAN[d.month - 1]}" if dengan_hari else f"{BULAN[d.month - 1]} {d:%y}"
    ax.xaxis.set_major_formatter(FuncFormatter(fmt))


def warna_label(posisi_di_skala):
    """Warna teks di dalam sel heatmap: putih di atas warna gelap, hitam di atas warna terang."""
    return "#ffffff" if posisi_di_skala > 0.45 else INK


def set_style():
    mpl.rcParams.update({
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "savefig.facecolor": SURFACE,
        "figure.dpi": 110,
        "savefig.dpi": 160,
        "savefig.bbox": "tight",
        "font.family": "sans-serif",
        "font.sans-serif": ["Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"],
        "font.size": 10,
        "text.color": INK,
        "axes.labelcolor": INK_2,
        "axes.titlesize": 12,
        "axes.titleweight": "bold",
        "axes.titlelocation": "left",
        "axes.titlepad": 10,
        "axes.edgecolor": AXIS,
        "axes.linewidth": 1,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "axes.axisbelow": True,
        "axes.prop_cycle": mpl.cycler(color=SERIES),
        "grid.color": GRID,
        "grid.linewidth": 1,
        "grid.linestyle": "-",
        "xtick.color": MUTED,
        "ytick.color": MUTED,
        "xtick.labelcolor": INK_2,
        "ytick.labelcolor": INK_2,
        "xtick.major.size": 0,
        "ytick.major.size": 0,
        "lines.linewidth": 2,
        "lines.solid_capstyle": "round",
        "lines.solid_joinstyle": "round",
        "legend.frameon": False,
        "legend.labelcolor": INK_2,
        "legend.fontsize": 9,
    })


def label_titik(ax, xs, ys, labels, fontsize=7):
    """Label titik scatter tanpa saling menimpa.

    Untuk setiap titik, beberapa posisi label dicoba; yang dipakai adalah posisi pertama yang
    tidak menimpa label atau titik lain dan tetap di dalam area grafik. Kalau semua posisi
    bertabrakan, dipakai posisi dengan tabrakan paling sedikit.
    """
    fig = ax.figure
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    titik = ax.transData.transform(np.column_stack([xs, ys]))
    terpakai = [Bbox.from_extents(px - 5, py - 5, px + 5, py + 5) for px, py in titik]
    area = ax.get_window_extent(renderer)
    kandidat = [(5, 2, "left"), (-5, 2, "right"), (5, -11, "left"), (-5, -11, "right"),
                (0, 7, "center"), (0, -15, "center"), (5, 9, "left"), (-5, 9, "right"),
                (5, -18, "left"), (-5, -18, "right")]

    def tabrakan(kotak):
        di_luar = not (area.x0 <= kotak.x0 and kotak.x1 <= area.x1 and area.y0 <= kotak.y0 and kotak.y1 <= area.y1)
        return 10 * di_luar + sum(kotak.overlaps(b) for b in terpakai)

    # titik paling kanan diberi label lebih dulu, supaya label default (di kanan titik) tidak
    # menutupi tetangga yang belum diberi label
    for x, y, teks_label in sorted(zip(xs, ys, labels), key=lambda r: -r[0]):
        terbaik = None
        for dx, dy, ha in kandidat:
            teks = ax.annotate(teks_label, (x, y), xytext=(dx, dy), textcoords="offset points",
                               fontsize=fontsize, color=INK_2, ha=ha, va="bottom")
            kotak = teks.get_window_extent(renderer).expanded(1.02, 1.05)
            skor = tabrakan(kotak)
            if terbaik is None or skor < terbaik[0]:
                if terbaik is not None:
                    terbaik[1].remove()
                terbaik = (skor, teks, kotak)
            else:
                teks.remove()
            if skor == 0:
                break
        terpakai.append(terbaik[2])


def subtitle(ax, text):
    """Subjudul abu-abu tepat di bawah judul grafik."""
    ax.text(0, 1.01, text, transform=ax.transAxes, color=INK_2, fontsize=9, va="bottom")


def save(fig, name):
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    fig.savefig(FIG_DIR / f"{name}.png")
