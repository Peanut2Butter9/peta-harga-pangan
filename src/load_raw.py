"""Load snapshot JSON PIHPS dari data/raw/pihps ke schema `raw` di PostgreSQL.

Tabel raw dikosongkan lalu diisi ulang setiap kali script dijalankan, jadi hasilnya
selalu sama dengan isi folder data/raw.

Contoh:
    uv run python src/load_raw.py
"""
import json
import os
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw" / "pihps"
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://localhost/harga_pangan")
META_KEYS = {"no", "name", "level"}


def load_refs(cur):
    refs = {
        "raw.pihps_ref_price_type": ("ref_price_type.json", ["id", "name"]),
        "raw.pihps_ref_commodity": ("ref_commodity.json", ["id", "name", "cat_id", "denomination", "sort"]),
        "raw.pihps_ref_province": ("ref_province.json", ["id", "name"]),
    }
    for table, (filename, columns) in refs.items():
        rows = json.loads((RAW_DIR / filename).read_text())["data"]
        cur.execute(f"TRUNCATE {table}")
        cur.executemany(
            f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({', '.join(['%s'] * len(columns))})",
            [tuple(row.get(c) for c in columns) for row in rows],
        )


def load_harga(cur):
    cur.execute("TRUNCATE raw.pihps_harga")
    n_files = n_rows = 0
    columns = ("price_type_id, province_id, period_start, period_end, row_no, row_name, "
               "row_level, prices, source_file, fetched_at")
    with cur.copy(f"COPY raw.pihps_harga ({columns}) FROM STDIN") as copy:
        for path in sorted(RAW_DIR.glob("pt*/prov*/*.json")):
            payload = json.loads(path.read_text())
            params = payload["params"]
            for row in payload["data"]:
                prices = {k: v for k, v in row.items() if k not in META_KEYS}
                copy.write_row((
                    params["price_type_id"],
                    params["province_id"] or None,
                    params["start_date"],
                    params["end_date"],
                    row.get("no"),
                    row["name"],
                    row.get("level"),
                    json.dumps(prices, ensure_ascii=False),
                    str(path.relative_to(ROOT)),
                    payload["fetched_at"],
                ))
                n_rows += 1
            n_files += 1
    return n_files, n_rows


def main():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute((ROOT / "sql" / "01_schema.sql").read_text())
        load_refs(cur)
        n_files, n_rows = load_harga(cur)
    print(f"Selesai: {n_files} file, {n_rows} baris dimuat ke raw.pihps_harga")


if __name__ == "__main__":
    main()
