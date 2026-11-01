"""Ambil data harga harian PIHPS Nasional (Bank Indonesia) dan simpan sebagai snapshot JSON mentah.

Data diambil per provinsi per bulan, karena request satu bulan jauh lebih cepat
(~0,6 detik) dibanding rentang panjang (~45 detik untuk satu tahun).
File yang sudah ada dilewati, jadi script aman dijalankan ulang kalau terhenti.

Contoh:
    uv run python src/fetch_pihps.py --start 2018-01 --end 2026-10 --price-types 1
"""
import argparse
import json
import time
from datetime import date, datetime, timedelta
from pathlib import Path

import requests

BASE_URL = "https://www.bi.go.id/hargapangan/WebSite/TabelHarga"
RAW_DIR = Path(__file__).resolve().parents[1] / "data" / "raw" / "pihps"
NATIONAL = 0  # province_id kosong di API = rata-rata nasional

session = requests.Session()
session.headers.update({"User-Agent": "peta-harga-pangan/0.1 (portfolio data project)"})


def get_json(endpoint, params=None, retries=3):
    for attempt in range(1, retries + 1):
        try:
            resp = session.get(f"{BASE_URL}/{endpoint}", params=params, timeout=90)
            resp.raise_for_status()
            return resp.json()
        except (requests.RequestException, ValueError) as exc:
            if attempt == retries:
                raise
            wait = 10 * attempt
            print(f"  gagal ({exc}), coba lagi dalam {wait} detik", flush=True)
            time.sleep(wait)


def parse_month(text):
    year, month = text.split("-")
    return int(year), int(month)


def month_range(start, end):
    year, month = start
    while (year, month) <= end:
        yield year, month
        year, month = (year + 1, 1) if month == 12 else (year, month + 1)


def month_bounds(year, month):
    first = date(year, month, 1)
    next_first = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
    return first, next_first - timedelta(days=1)


def save_refs():
    refs = {
        "ref_price_type": "GetRefPriceType",
        "ref_commodity": "GetRefCommodityAndCategory",
        "ref_province": "GetRefProvince",
    }
    for name, endpoint in refs.items():
        data = get_json(endpoint)
        (RAW_DIR / f"{name}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1))
    return json.loads((RAW_DIR / "ref_province.json").read_text())["data"]


def fetch_month(price_type, province_id, year, month, refresh):
    """Simpan satu bulan data; return True kalau ada request ke server."""
    path = RAW_DIR / f"pt{price_type}" / f"prov{province_id:02d}" / f"{year}-{month:02d}.json"
    first, last = month_bounds(year, month)
    # Bulan yang baru berakhir < 7 hari lalu (atau belum selesai) selalu diambil ulang,
    # karena input data dari enumerator bisa terlambat.
    is_final = last < date.today() - timedelta(days=7)
    if path.exists() and is_final and not refresh:
        return False

    params = {
        "price_type_id": price_type,
        "comcat_id": "",
        "province_id": province_id or "",
        "regency_id": "",
        "market_id": "",
        "tipe_laporan": 1,  # 1 = laporan harian
        "start_date": first.isoformat(),
        "end_date": last.isoformat(),
    }
    data = get_json("GetGridDataDaerah", params)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "params": params,
        "fetched_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "data": data["data"],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False))
    return True


def main():
    parser = argparse.ArgumentParser(description="Ambil data harga harian PIHPS per provinsi per bulan.")
    parser.add_argument("--start", default="2018-01", help="bulan awal, format YYYY-MM")
    parser.add_argument("--end", default=date.today().strftime("%Y-%m"), help="bulan akhir, format YYYY-MM")
    parser.add_argument("--price-types", type=int, nargs="+", default=[1],
                        help="1=Pasar Tradisional, 2=Pasar Modern, 3=Pedagang Besar, 4=Produsen")
    parser.add_argument("--provinces", type=int, nargs="+",
                        help="ID provinsi PIHPS (default: nasional + semua provinsi)")
    parser.add_argument("--delay", type=float, default=0.7, help="jeda antar request, dalam detik")
    parser.add_argument("--refresh", action="store_true", help="ambil ulang walau file sudah ada")
    args = parser.parse_args()

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    provinces = save_refs()
    province_ids = args.provinces or [NATIONAL] + sorted(p["id"] for p in provinces)
    months = list(month_range(parse_month(args.start), parse_month(args.end)))

    total = len(args.price_types) * len(province_ids) * len(months)
    print(f"{total} bulan-provinsi akan dicek ({len(province_ids)} wilayah x {len(months)} bulan "
          f"x {len(args.price_types)} jenis pasar)", flush=True)
    failed = []
    done = 0
    for price_type in args.price_types:
        for province_id in province_ids:
            for year, month in months:
                done += 1
                try:
                    if fetch_month(price_type, province_id, year, month, args.refresh):
                        time.sleep(args.delay)
                except (requests.RequestException, ValueError) as exc:
                    failed.append((price_type, province_id, f"{year}-{month:02d}"))
                    print(f"  GAGAL pt={price_type} prov={province_id} {year}-{month:02d}: {exc}", flush=True)
                if done % 100 == 0 or done == total:
                    print(f"{done}/{total} (pt={price_type}, prov={province_id}, {year}-{month:02d})", flush=True)

    if failed:
        print(f"\n{len(failed)} request gagal. Jalankan ulang script untuk mengambil yang tersisa:")
        for item in failed:
            print("  ", item)
    else:
        print("\nSelesai tanpa error.")


if __name__ == "__main__":
    main()
