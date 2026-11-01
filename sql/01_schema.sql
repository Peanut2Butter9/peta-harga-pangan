-- =============================================================================
-- 01_schema.sql
-- Membuat schema berlapis (raw -> staging -> mart) dan tabel raw.
-- Tabel raw menyimpan data persis seperti dari sumber; cleaning dilakukan di staging.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;

-- Satu baris = satu baris tabel PIHPS (kategori ATAU varian komoditas)
-- untuk satu wilayah, satu jenis pasar, dan satu bulan.
-- Harga harian masih berformat wide di kolom `prices`:
--   key   = tanggal 'dd/mm/yyyy'
--   value = harga sebagai teks dengan pemisah ribuan ('11,050') atau '-' kalau kosong
CREATE TABLE IF NOT EXISTS raw.pihps_harga (
    price_type_id  int          NOT NULL,  -- 1=Pasar Tradisional, 2=Pasar Modern, 3=Pedagang Besar, 4=Produsen
    province_id    int,                    -- NULL = rata-rata nasional
    period_start   date         NOT NULL,
    period_end     date         NOT NULL,
    row_no         text,                   -- 'I', 'II', ... untuk kategori; '1', '2', ... untuk varian
    row_name       text         NOT NULL,
    row_level      int,                    -- 1 = kategori, 2 = varian
    prices         jsonb        NOT NULL,
    source_file    text         NOT NULL,
    fetched_at     timestamptz  NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.pihps_ref_commodity (
    id            text,   -- 'cat_N' = kategori, 'com_N' = varian
    name          text,
    cat_id        text,   -- kategori induk untuk varian
    denomination  text,   -- satuan, mis. 'kg'
    sort          int
);

CREATE TABLE IF NOT EXISTS raw.pihps_ref_province (
    id    int,
    name  text
);

CREATE TABLE IF NOT EXISTS raw.pihps_ref_price_type (
    id    int,
    name  text
);
