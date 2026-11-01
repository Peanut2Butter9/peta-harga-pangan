-- =============================================================================
-- 05_exports.sql
-- View di schema export: bentuk data untuk dashboard Tableau Public.
--
-- Tableau Public tidak bisa terhubung ke database, jadi setiap view di sini disalin
-- ke CSV oleh src/export_tableau.py. Tabel fakta hanya berisi ID dan angka supaya
-- file tetap kecil; nama-nama ada di tabel dimensi, dan Tableau menyambungkannya
-- lewat relationship (star schema yang sama dengan mart).
--
--   harga_mingguan  (fakta)  ─┐
--   harga_bulanan   (fakta)  ─┼── provinsi, komoditas, jenis_pasar  (dimensi)
--   rantai_pasok    (ringkasan siap pakai, untuk satu grafik)
--   sinyal_jawa     (ringkasan siap pakai, untuk peringatan dini)
--
-- Perubahan harga dihitung di sini dengan window function berbasis RANGE tanggal,
-- bukan LAG: kalau ada minggu atau bulan yang kosong, LAG akan membandingkan dengan
-- periode yang salah, sedangkan RANGE mengembalikan NULL.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS export;

DROP VIEW IF EXISTS
    export.sinyal_jawa,
    export.harga_mingguan,
    export.harga_bulanan,
    export.rantai_pasok,
    export.provinsi,
    export.komoditas,
    export.jenis_pasar;


-- -----------------------------------------------------------------------------
-- Dimensi
-- kelompok_wilayah memisahkan sentra Jawa (pemimpin harga di Q7) dari provinsi lain
-- -----------------------------------------------------------------------------
CREATE VIEW export.provinsi AS
SELECT
    wilayah_id,
    nama_wilayah AS wilayah,
    pulau,
    CASE
        WHEN is_nasional THEN 'Nasional'
        WHEN nama_wilayah IN ('Jawa Barat', 'Jawa Tengah', 'Jawa Timur') THEN 'Sentra Jawa'
        WHEN pulau = 'Jawa' THEN 'Jawa lainnya'
        ELSE 'Luar Jawa'
    END AS kelompok_wilayah,
    is_nasional
FROM mart.dim_wilayah;


-- kelompok mengikuti H5: komoditas segar vs pokok & kemasan
CREATE VIEW export.komoditas AS
SELECT
    komoditas_id,
    nama_varian AS varian,
    kategori,
    satuan,
    urutan AS urutan_varian,
    CASE
        WHEN kategori IN ('Beras', 'Minyak Goreng', 'Gula Pasir') THEN 'Pokok & kemasan'
        ELSE 'Segar'
    END AS kelompok
FROM mart.dim_komoditas;


CREATE VIEW export.jenis_pasar AS
SELECT
    jenis_pasar_id,
    nama_jenis_pasar AS jenis_pasar,
    urutan_rantai_pasok
FROM mart.dim_jenis_pasar;


-- -----------------------------------------------------------------------------
-- harga_mingguan. Grain: minggu x wilayah x varian x jenis pasar.
-- minggu = hari Jumat penutup minggu (Sabtu-Jumat), sama dengan analisis Q7.
-- perubahan_* = harga minggu ini / harga N minggu sebelumnya - 1
-- -----------------------------------------------------------------------------
CREATE VIEW export.harga_mingguan AS
WITH mingguan AS (
    SELECT
        tanggal + (5 - extract(isodow FROM tanggal)::int + 7) % 7 AS minggu,
        wilayah_id,
        komoditas_id,
        jenis_pasar_id,
        avg(harga)   AS harga,
        count(harga) AS hari_data
    FROM mart.fact_harga_harian
    GROUP BY 1, 2, 3, 4
    HAVING count(harga) > 0
)
SELECT
    minggu,
    wilayah_id,
    komoditas_id,
    jenis_pasar_id,
    round(harga, 0)                                          AS harga,
    round(harga / first_value(harga) OVER minggu_lalu - 1, 4) AS perubahan_1_minggu,
    round(harga / first_value(harga) OVER bulan_lalu - 1, 4)  AS perubahan_4_minggu,
    round(harga / first_value(harga) OVER tahun_lalu - 1, 4)  AS perubahan_52_minggu,
    hari_data
FROM mingguan
WINDOW
    seri        AS (PARTITION BY wilayah_id, komoditas_id, jenis_pasar_id ORDER BY minggu),
    minggu_lalu AS (seri RANGE BETWEEN interval '7 days' PRECEDING AND interval '7 days' PRECEDING),
    bulan_lalu  AS (seri RANGE BETWEEN interval '28 days' PRECEDING AND interval '28 days' PRECEDING),
    tahun_lalu  AS (seri RANGE BETWEEN interval '364 days' PRECEDING AND interval '364 days' PRECEDING);


-- -----------------------------------------------------------------------------
-- harga_bulanan. Grain: bulan x wilayah x varian x jenis pasar.
-- kelengkapan dipakai dashboard untuk menandai data yang tipis.
-- -----------------------------------------------------------------------------
CREATE VIEW export.harga_bulanan AS
SELECT
    bulan,
    wilayah_id,
    komoditas_id,
    jenis_pasar_id,
    harga_rata                                                          AS harga,
    round(harga_rata / first_value(harga_rata) OVER bulan_lalu - 1, 4)  AS perubahan_bulanan,
    round(harga_rata / first_value(harga_rata) OVER tahun_lalu - 1, 4)  AS perubahan_tahunan,
    koef_variasi,
    kelengkapan
FROM mart.fact_harga_bulanan
WINDOW
    seri       AS (PARTITION BY wilayah_id, komoditas_id, jenis_pasar_id ORDER BY bulan),
    bulan_lalu AS (seri RANGE BETWEEN interval '1 month' PRECEDING AND interval '1 month' PRECEDING),
    tahun_lalu AS (seri RANGE BETWEEN interval '12 months' PRECEDING AND interval '12 months' PRECEDING);


-- -----------------------------------------------------------------------------
-- rantai_pasok: harga tiap mata rantai dalam 12 bulan terakhir, per varian.
-- Dihitung per provinsi dulu lalu diambil mediannya, karena rata-rata nasional
-- tiap jenis pasar berasal dari kumpulan provinsi yang berbeda (lihat Q3 dan Q6).
--   harga_median_provinsi  = median rata-rata harga 12 bulan antarprovinsi
--   selisih_vs_tradisional = median antarprovinsi dari rata-rata (harga pasar ini /
--                            harga pasar tradisional - 1), hanya bulan yang ada keduanya
-- -----------------------------------------------------------------------------
CREATE VIEW export.rantai_pasok AS
WITH periode AS (
    SELECT (max(bulan) - interval '11 months')::date AS awal, max(bulan) AS akhir
    FROM mart.fact_harga_bulanan
),
per_provinsi AS (
    SELECT
        b.wilayah_id,
        b.komoditas_id,
        b.jenis_pasar_id,
        avg(b.harga_rata)                      AS harga,
        avg(b.harga_rata / t.harga_rata - 1)   AS selisih_vs_tradisional
    FROM mart.fact_harga_bulanan AS b
    CROSS JOIN periode AS p
    LEFT JOIN mart.fact_harga_bulanan AS t
      ON t.bulan = b.bulan AND t.wilayah_id = b.wilayah_id
     AND t.komoditas_id = b.komoditas_id AND t.jenis_pasar_id = 1
    WHERE b.bulan BETWEEN p.awal AND p.akhir
      AND b.wilayah_id <> 0
    GROUP BY b.wilayah_id, b.komoditas_id, b.jenis_pasar_id
)
SELECT
    pp.komoditas_id,
    pp.jenis_pasar_id,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY pp.harga)::numeric, 0)                  AS harga_median_provinsi,
    count(*)                                                                                   AS n_provinsi,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY pp.selisih_vs_tradisional)::numeric, 4)  AS selisih_vs_tradisional,
    count(pp.selisih_vs_tradisional)                                                           AS n_provinsi_berpasangan,
    p.awal                                                                                     AS periode_awal,
    p.akhir                                                                                    AS periode_akhir
FROM per_provinsi AS pp
CROSS JOIN periode AS p
GROUP BY pp.komoditas_id, pp.jenis_pasar_id, p.awal, p.akhir;


-- -----------------------------------------------------------------------------
-- sinyal_jawa: peringatan dini dari Q7. Grain: minggu x varian, pasar tradisional.
-- Harga di sentra Jawa (Jawa Barat, Jawa Tengah, Jawa Timur) bergerak 1-2 minggu lebih
-- dulu dari provinsi luar Jawa.
--   persentil_sentra_jawa = peringkat kenaikan minggu ini dibanding semua minggu
--                           2018-2026 untuk varian yang sama (0,9 = 10% kenaikan tertinggi).
--                           Dipakai sebagai ambang karena volatilitas tiap varian berbeda:
--                           naik 5% seminggu itu biasa untuk cabai, tapi ekstrem untuk beras.
--   perubahan_luar_jawa_minggu_depan = untuk menguji sinyal secara historis
-- -----------------------------------------------------------------------------
CREATE VIEW export.sinyal_jawa AS
WITH per_kelompok AS (
    SELECT
        h.minggu,
        h.komoditas_id,
        avg(h.perubahan_1_minggu) FILTER (WHERE p.kelompok_wilayah = 'Sentra Jawa') AS sentra_jawa,
        avg(h.perubahan_1_minggu) FILTER (WHERE p.kelompok_wilayah = 'Luar Jawa')   AS luar_jawa
    FROM export.harga_mingguan AS h
    JOIN export.provinsi AS p USING (wilayah_id)
    WHERE h.jenis_pasar_id = 1
    GROUP BY h.minggu, h.komoditas_id
)
SELECT
    minggu,
    komoditas_id,
    round(sentra_jawa, 4)                                       AS perubahan_sentra_jawa,
    round(luar_jawa, 4)                                         AS perubahan_luar_jawa,
    round(percent_rank() OVER (PARTITION BY komoditas_id ORDER BY sentra_jawa)::numeric, 3)
                                                                AS persentil_sentra_jawa,
    round(first_value(luar_jawa) OVER minggu_depan, 4)          AS perubahan_luar_jawa_minggu_depan
FROM per_kelompok
WHERE sentra_jawa IS NOT NULL AND luar_jawa IS NOT NULL
WINDOW minggu_depan AS (PARTITION BY komoditas_id ORDER BY minggu
                        RANGE BETWEEN interval '7 days' FOLLOWING AND interval '7 days' FOLLOWING);
