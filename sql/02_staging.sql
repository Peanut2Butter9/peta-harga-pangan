-- =============================================================================
-- 02_staging.sql
-- Membersihkan data raw:
--   1. unpivot harga harian dari format wide (jsonb) ke format long
--   2. konversi teks ke tipe data yang benar ('11,050' -> 11050, '-' -> NULL)
--   3. membuang baris kategori agar harga tidak terhitung ganda
--   4. menandai lonjakan harga yang tidak wajar (anomali)
-- Semua tabel staging dibuat ulang dari schema raw setiap kali script dijalankan.
-- =============================================================================

DROP TABLE IF EXISTS
    staging.stg_harga_harian,
    staging.stg_komoditas,
    staging.stg_wilayah,
    staging.stg_hari_besar
CASCADE;


-- -----------------------------------------------------------------------------
-- Wilayah: 34 provinsi PIHPS + 'Nasional'.
-- Di raw, rata-rata nasional disimpan dengan province_id NULL; di sini diberi id 0
-- supaya bisa jadi key yang tidak NULL.
-- -----------------------------------------------------------------------------
CREATE TABLE staging.stg_wilayah AS
SELECT 0 AS wilayah_id, 'Nasional' AS nama_wilayah
UNION ALL
SELECT id, trim(name)
FROM raw.pihps_ref_province;

ALTER TABLE staging.stg_wilayah ADD PRIMARY KEY (wilayah_id);


-- -----------------------------------------------------------------------------
-- Komoditas: hanya level varian ('com_N'). Kategori ('cat_N') menjadi atribut.
-- -----------------------------------------------------------------------------
CREATE TABLE staging.stg_komoditas AS
SELECT
    replace(v.id, 'com_', '')::int                AS komoditas_id,
    trim(v.name)                                  AS nama_varian,
    trim(k.name)                                  AS kategori,
    v.denomination                                AS satuan,
    row_number() OVER (ORDER BY k.sort, v.sort)   AS urutan
FROM raw.pihps_ref_commodity v
JOIN raw.pihps_ref_commodity k ON k.id = v.cat_id
WHERE v.id LIKE 'com\_%';

ALTER TABLE staging.stg_komoditas ADD PRIMARY KEY (komoditas_id);


-- -----------------------------------------------------------------------------
-- Hari besar yang biasanya memengaruhi harga pangan.
-- Tanggal Islam memakai versi pemerintah (sidang isbat Kemenag).
-- Tahun 2026 sudah dicek dari pengumuman sidang isbat; tahun lain perlu dicocokkan
-- ulang dengan SKB libur nasional sebelum dipakai untuk analisis final.
-- -----------------------------------------------------------------------------
CREATE TABLE staging.stg_hari_besar (
    tanggal          date PRIMARY KEY,
    nama_hari_besar  text NOT NULL
);

INSERT INTO staging.stg_hari_besar (tanggal, nama_hari_besar) VALUES
    ('2018-05-17', 'Awal Ramadan'), ('2018-06-15', 'Idulfitri'), ('2018-08-22', 'Iduladha'),
    ('2019-05-06', 'Awal Ramadan'), ('2019-06-05', 'Idulfitri'), ('2019-08-11', 'Iduladha'),
    ('2020-04-24', 'Awal Ramadan'), ('2020-05-24', 'Idulfitri'), ('2020-07-31', 'Iduladha'),
    ('2021-04-13', 'Awal Ramadan'), ('2021-05-13', 'Idulfitri'), ('2021-07-20', 'Iduladha'),
    ('2022-04-03', 'Awal Ramadan'), ('2022-05-02', 'Idulfitri'), ('2022-07-10', 'Iduladha'),
    ('2023-03-23', 'Awal Ramadan'), ('2023-04-22', 'Idulfitri'), ('2023-06-29', 'Iduladha'),
    ('2024-03-12', 'Awal Ramadan'), ('2024-04-10', 'Idulfitri'), ('2024-06-17', 'Iduladha'),
    ('2025-03-01', 'Awal Ramadan'), ('2025-03-31', 'Idulfitri'), ('2025-06-06', 'Iduladha'),
    ('2026-02-19', 'Awal Ramadan'), ('2026-03-21', 'Idulfitri'), ('2026-05-27', 'Iduladha');

INSERT INTO staging.stg_hari_besar (tanggal, nama_hari_besar)
SELECT make_date(tahun, 12, 25), 'Natal' FROM generate_series(2018, 2026) AS tahun
UNION ALL
SELECT make_date(tahun, 1, 1), 'Tahun Baru' FROM generate_series(2018, 2026) AS tahun;


-- -----------------------------------------------------------------------------
-- Harga harian (format long). Grain: jenis pasar x wilayah x varian x tanggal.
--
-- Aturan anomali ("lonjakan yang balik lagi"):
--   harga dianggap anomali kalau menyimpang > 25% dari rata-rata 5 data SEBELUM
--   dan juga > 25% dari rata-rata 5 data SESUDAH, ke arah yang sama.
--   Kenaikan harga yang bertahan (tren) tidak ikut tertandai, karena data sesudahnya
--   ikut naik. Ambang 25% dipilih setelah membandingkan 20/25/30/40%: pada 25% ada
--   ~0,04% sel tertandai, termasuk kasus yang jelas salah seperti telur nasional
--   Rp53.250 pada Iduladha 31 Juli 2020 (hari sebelum & sesudahnya ~Rp26.300).
-- Anomali tidak dihapus, hanya ditandai, supaya keputusan cleaning bisa ditelusuri.
-- -----------------------------------------------------------------------------
CREATE TABLE staging.stg_harga_harian AS
WITH unpivot AS (
    SELECT
        h.price_type_id                                       AS jenis_pasar_id,
        coalesce(h.province_id, 0)                            AS wilayah_id,
        k.komoditas_id,
        to_date(kv.key, 'DD/MM/YYYY')                         AS tanggal,
        nullif(replace(kv.value, ',', ''), '-')::numeric(12, 2) AS harga
    FROM raw.pihps_harga AS h
    JOIN staging.stg_komoditas AS k ON k.nama_varian = trim(h.row_name)
    CROSS JOIN LATERAL jsonb_each_text(h.prices) AS kv(key, value)
    WHERE h.row_level = 2          -- buang baris kategori (level 1)
),
terisi AS (
    SELECT * FROM unpivot WHERE harga IS NOT NULL
),
dengan_konteks AS (
    SELECT
        t.*,
        avg(harga) OVER sebelum AS rata_5_sebelum,
        avg(harga) OVER sesudah AS rata_5_sesudah
    FROM terisi AS t
    WINDOW
        sebelum AS (PARTITION BY jenis_pasar_id, wilayah_id, komoditas_id
                    ORDER BY tanggal ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING),
        sesudah AS (PARTITION BY jenis_pasar_id, wilayah_id, komoditas_id
                    ORDER BY tanggal ROWS BETWEEN 1 FOLLOWING AND 5 FOLLOWING)
)
SELECT
    jenis_pasar_id,
    wilayah_id,
    komoditas_id,
    tanggal,
    harga,
    coalesce(
        (harga > 1.25 * rata_5_sebelum AND harga > 1.25 * rata_5_sesudah)
        OR (harga < 0.75 * rata_5_sebelum AND harga < 0.75 * rata_5_sesudah),
        false
    ) AS is_anomali
FROM dengan_konteks;

-- Primary key sekaligus memastikan tidak ada duplikat pada grain di atas.
ALTER TABLE staging.stg_harga_harian
    ADD PRIMARY KEY (jenis_pasar_id, wilayah_id, komoditas_id, tanggal);
