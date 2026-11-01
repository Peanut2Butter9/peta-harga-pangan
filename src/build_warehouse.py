"""Bangun ulang schema staging dan mart dari schema raw, lalu jalankan quality checks.

Semua langkah berjalan dalam satu transaksi: kalau ada SQL yang error, database
kembali ke kondisi sebelum build.

Contoh:
    uv run python src/build_warehouse.py
"""
import os
import sys
import time
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql"
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://localhost/harga_pangan")
BUILD_STEPS = ["02_staging.sql", "03_marts.sql"]


def main():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        for name in BUILD_STEPS:
            start = time.perf_counter()
            cur.execute((SQL_DIR / name).read_text())
            print(f"{name} selesai ({time.perf_counter() - start:.1f} detik)")

        cur.execute((SQL_DIR / "04_quality_checks.sql").read_text())
        results = cur.fetchall()

    print("\nQuality checks:")
    for cek, nilai, lolos in results:
        print(f"  [{'LOLOS' if lolos else 'GAGAL'}] {cek}: {nilai}")

    if not all(lolos for _, _, lolos in results):
        sys.exit("\nAda quality check yang gagal.")


if __name__ == "__main__":
    main()
