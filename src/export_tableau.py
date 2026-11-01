"""Ekspor data ke CSV untuk dashboard Tableau Public.

Tableau Public tidak bisa terhubung ke PostgreSQL, jadi dashboard membaca CSV di
data/exports/. Bentuk datanya didefinisikan sebagai view di sql/05_exports.sql. Script ini:
  1. membuat ulang view tersebut,
  2. menyalin isinya ke CSV dengan COPY,
  3. melengkapi dimensi provinsi dengan koordinat peta dan hasil notebook (cluster, lead-lag),
  4. mengecek hasilnya: kunci unik, ID cocok dengan dimensi, dan data sampai tanggal terakhir,
  5. menggabungkan semua tabel ke satu file Excel (dashboard_pangan.xlsx) yang dibuka Tableau.

Jalankan setelah build_warehouse.py dan notebook 02-04, karena notebook menulis hasil
analisisnya sendiri ke data/exports/.

Contoh:
    uv run python src/export_tableau.py
"""
import os
import sys
from pathlib import Path

import pandas as pd
import psycopg
import xlsxwriter

ROOT = Path(__file__).resolve().parents[1]
SQL_FILE = ROOT / "sql" / "05_exports.sql"
EXPORT_DIR = ROOT / "data" / "exports"
EXCEL_FILE = EXPORT_DIR / "dashboard_pangan.xlsx"
KOORDINAT = ROOT / "data" / "reference" / "koordinat_provinsi.csv"
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://localhost/harga_pangan")

# view di schema export -> kolom kunci (grain)
VIEWS = {
    "harga_mingguan": ["minggu", "wilayah_id", "komoditas_id", "jenis_pasar_id"],
    "harga_bulanan": ["bulan", "wilayah_id", "komoditas_id", "jenis_pasar_id"],
    "rantai_pasok": ["komoditas_id", "jenis_pasar_id"],
    "sinyal_jawa": ["minggu", "komoditas_id"],
    "komoditas": ["komoditas_id"],
    "jenis_pasar": ["jenis_pasar_id"],
}
# file hasil notebook -> notebook yang menulisnya
HASIL_NOTEBOOK = {
    "risiko_hari_besar.csv": "notebooks/02_uji_hipotesis.ipynb",
    "lead_lag_provinsi.csv": "notebooks/03_lead_lag_provinsi.ipynb",
    "cluster_provinsi.csv": "notebooks/04_clustering_provinsi.ipynb",
}
# sheet di file Excel untuk Tableau: fakta dulu, lalu dimensi
SHEET_EXCEL = ["harga_mingguan", "harga_bulanan", "rantai_pasok", "sinyal_jawa", "risiko_hari_besar",
               "provinsi", "komoditas", "jenis_pasar"]
KOLOM_TANGGAL = ["minggu", "bulan", "periode_awal", "periode_akhir"]
BARIS_MAKS_EXCEL = 1_048_576


def salin_view(cur, view):
    with (EXPORT_DIR / f"{view}.csv").open("wb") as f, \
            cur.copy(f"COPY (SELECT * FROM export.{view}) TO STDOUT WITH (FORMAT csv, HEADER)") as copy:
        for blok in copy:
            f.write(blok)


def buat_provinsi(cur):
    """Dimensi provinsi + koordinat ibu kota + cluster (notebook 04) + lead-lag (notebook 03)."""
    cur.execute("SELECT * FROM export.provinsi ORDER BY wilayah_id")
    provinsi = pd.DataFrame(cur.fetchall(), columns=[c.name for c in cur.description])
    cluster = pd.read_csv(EXPORT_DIR / "cluster_provinsi.csv").drop(columns=["nama_wilayah", "pulau"])
    lead_lag = pd.read_csv(EXPORT_DIR / "lead_lag_provinsi.csv").drop(columns="nama_wilayah")
    provinsi = (provinsi
                .merge(pd.read_csv(KOORDINAT), on="wilayah_id", how="left")
                .merge(cluster, on="wilayah_id", how="left")
                .merge(lead_lag, on="wilayah_id", how="left"))
    provinsi.to_csv(EXPORT_DIR / "provinsi.csv", index=False, float_format="%.4f")
    return provinsi


def cek_hasil(tanggal_terakhir):
    gagal = []

    def periksa(nama, lolos, detail):
        print(f"  [{'LOLOS' if lolos else 'GAGAL'}] {nama}: {detail}")
        if not lolos:
            gagal.append(nama)

    baca = {f.stem: pd.read_csv(f) for f in sorted(EXPORT_DIR.glob("*.csv"))}
    dimensi = {"wilayah_id": baca["provinsi"], "komoditas_id": baca["komoditas"],
               "jenis_pasar_id": baca["jenis_pasar"]}

    for view, kunci in VIEWS.items():
        df = baca[view]
        periksa(f"{view}: kunci unik", not df.duplicated(kunci).any(), f"{len(df):,} baris")
    for nama in ["harga_mingguan", "harga_bulanan", "rantai_pasok", "sinyal_jawa", "risiko_hari_besar"]:
        df = baca[nama]
        yatim = {k: int((~df[k].isin(d[k])).sum()) for k, d in dimensi.items() if k in df}
        periksa(f"{nama}: semua ID ada di dimensi", not any(yatim.values()), f"ID tanpa pasangan {yatim}")
    for nama in ["harga_mingguan", "harga_bulanan"]:
        harga = baca[nama].harga
        periksa(f"{nama}: harga terisi dan > 0", bool(harga.notna().all() and (harga > 0).all()),
                f"min Rp {harga.min():,.0f}")

    minggu_terakhir = pd.Timestamp(baca["harga_mingguan"].minggu.max())
    periksa("harga_mingguan: sampai minggu terakhir", 0 <= (minggu_terakhir - tanggal_terakhir).days < 7,
            f"{minggu_terakhir:%d %b %Y} (data harian s.d. {tanggal_terakhir:%d %b %Y})")
    bulan_terakhir = pd.Timestamp(baca["harga_bulanan"].bulan.max())
    periksa("harga_bulanan: sampai bulan terakhir", bulan_terakhir == tanggal_terakhir.replace(day=1),
            f"{bulan_terakhir:%b %Y}")

    prov = baca["provinsi"][~baca["provinsi"].is_nasional]
    kosong = prov[["lat", "lon", "cluster", "skor_lead"]].isna().sum()
    periksa("provinsi: koordinat, cluster, dan skor lead lengkap", len(prov) == 34 and not kosong.any(),
            f"{len(prov)} provinsi, nilai kosong {kosong.to_dict()}")

    ukuran = {f.name: f.stat().st_size / 1e6 for f in sorted(EXPORT_DIR.glob("*.csv"))}
    print("\nFile:")
    for nama, mb in ukuran.items():
        print(f"  {nama:<24} {mb:6.1f} MB")
    return gagal


def tulis_excel():
    """Gabungkan semua CSV ke satu file Excel, satu sheet per tabel.

    Tableau membaca file ini, bukan CSV-nya. Di CSV, Tableau menebak pemisah kolom dan tanda
    desimal dari locale komputer. Dengan locale Indonesia (desimal = koma), "0.0123" terbaca
    sebagai teks, dan jenis_pasar.csv terpotong di "_" karena koma dikira tanda desimal.
    Sel Excel menyimpan tipenya sendiri (angka, tanggal, boolean), jadi hasilnya sama di
    komputer mana pun.
    """
    # constant_memory menulis baris demi baris, supaya 680 ribu baris tidak memenuhi RAM
    with xlsxwriter.Workbook(EXCEL_FILE, {"constant_memory": True}) as wb:
        format_tanggal = wb.add_format({"num_format": "yyyy-mm-dd"})
        for nama in SHEET_EXCEL:
            df = pd.read_csv(EXPORT_DIR / f"{nama}.csv")
            if len(df) >= BARIS_MAKS_EXCEL:
                sys.exit(f"{nama}: {len(df):,} baris, melebihi batas sheet Excel")
            for kolom in df.columns.intersection(KOLOM_TANGGAL):
                df[kolom] = pd.to_datetime(df[kolom])
            tanggal = {i for i, kolom in enumerate(df.columns) if kolom in KOLOM_TANGGAL}

            ws = wb.add_worksheet(nama)
            ws.write_row(0, 0, df.columns)
            for r, baris in enumerate(df.itertuples(index=False), start=1):
                for c, nilai in enumerate(baris):
                    if pd.isna(nilai):
                        continue  # sel kosong = NULL di Tableau
                    if c in tanggal:
                        ws.write_datetime(r, c, nilai.to_pydatetime(), format_tanggal)
                    else:
                        ws.write(r, c, nilai)
            print(f"  sheet {nama:<18} {len(df):>9,} baris")


def main():
    belum_ada = [nb for f, nb in HASIL_NOTEBOOK.items() if not (EXPORT_DIR / f).exists()]
    if belum_ada:
        sys.exit("Jalankan dulu notebook berikut (menulis hasil analisis ke data/exports/):\n  "
                 + "\n  ".join(belum_ada))

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute(SQL_FILE.read_text())
        for view in VIEWS:
            salin_view(cur, view)
            print(f"export.{view} -> data/exports/{view}.csv")
        buat_provinsi(cur)
        print("export.provinsi + koordinat + cluster + lead-lag -> data/exports/provinsi.csv")
        cur.execute("SELECT max(tanggal) FROM mart.fact_harga_harian")
        tanggal_terakhir = pd.Timestamp(cur.fetchone()[0])

    print("\nCek hasil ekspor:")
    if cek_hasil(tanggal_terakhir):
        sys.exit("\nAda cek ekspor yang gagal.")

    print(f"\nMenulis {EXCEL_FILE.relative_to(ROOT)}:")
    tulis_excel()
    print(f"  {EXCEL_FILE.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
