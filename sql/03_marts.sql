-- =============================================================================
-- 03_marts.sql
-- Star schema untuk analisis dan dashboard:
--
--   dim_tanggal ─┐
--   dim_wilayah ─┼── fact_harga_harian ──(agregasi)──> fact_harga_bulanan
--   dim_komoditas┤
--   dim_jenis_pasar
--
-- Semua tabel mart dibuat ulang dari schema staging setiap kali script dijalankan.
-- =============================================================================

DROP TABLE IF EXISTS
    mart.fact_harga_bulanan,
    mart.fact_harga_harian,
    mart.dim_tanggal,
    mart.dim_wilayah,
    mart.dim_komoditas,
    mart.dim_jenis_pasar
CASCADE;


-- -----------------------------------------------------------------------------
-- dim_jenis_pasar: urutan_rantai_pasok mengikuti alur barang
-- Produsen -> Pedagang Besar -> Pasar Tradisional -> Pasar Modern
-- -----------------------------------------------------------------------------
CREATE TABLE mart.dim_jenis_pasar AS
SELECT
    id   AS jenis_pasar_id,
    name AS nama_jenis_pasar,
    CASE id WHEN 4 THEN 1 WHEN 3 THEN 2 WHEN 1 THEN 3 WHEN 2 THEN 4 END AS urutan_rantai_pasok
FROM raw.pihps_ref_price_type;

ALTER TABLE mart.dim_jenis_pasar ADD PRIMARY KEY (jenis_pasar_id);


-- -----------------------------------------------------------------------------
-- dim_wilayah: provinsi + kelompok pulau
-- -----------------------------------------------------------------------------
CREATE TABLE mart.dim_wilayah AS
SELECT
    wilayah_id,
    nama_wilayah,
    CASE
        WHEN wilayah_id = 0 THEN 'Nasional'
        WHEN nama_wilayah IN ('Aceh', 'Sumatera Utara', 'Sumatera Barat', 'Riau', 'Kepulauan Riau',
                              'Jambi', 'Sumatera Selatan', 'Kepulauan Bangka Belitung',
                              'Bengkulu', 'Lampung') THEN 'Sumatera'
        WHEN nama_wilayah IN ('DKI Jakarta', 'Jawa Barat', 'Banten', 'Jawa Tengah',
                              'DI Yogyakarta', 'Jawa Timur') THEN 'Jawa'
        WHEN nama_wilayah IN ('Bali', 'Nusa Tenggara Barat', 'Nusa Tenggara Timur') THEN 'Bali & Nusa Tenggara'
        WHEN nama_wilayah LIKE 'Kalimantan%' THEN 'Kalimantan'
        WHEN nama_wilayah LIKE 'Sulawesi%' OR nama_wilayah = 'Gorontalo' THEN 'Sulawesi'
        WHEN nama_wilayah IN ('Maluku', 'Maluku Utara', 'Papua', 'Papua Barat') THEN 'Maluku & Papua'
    END AS pulau,
    wilayah_id = 0 AS is_nasional
FROM staging.stg_wilayah;

ALTER TABLE mart.dim_wilayah ADD PRIMARY KEY (wilayah_id);


-- -----------------------------------------------------------------------------
-- dim_komoditas
-- -----------------------------------------------------------------------------
CREATE TABLE mart.dim_komoditas AS
SELECT komoditas_id, nama_varian, kategori, satuan, urutan
FROM staging.stg_komoditas;

ALTER TABLE mart.dim_komoditas ADD PRIMARY KEY (komoditas_id);


-- -----------------------------------------------------------------------------
-- dim_tanggal: kalender lengkap 2018-2026 + penanda musiman.
-- hari_ke_idulfitri = selisih hari terhadap Idulfitri TERDEKAT
-- (negatif = sebelum Lebaran, mis. -7 = H-7). Memakai yang terdekat, bukan yang
-- setahun, supaya akhir Desember terhitung sebagai "menjelang Lebaran" tahun berikutnya
-- ketika Lebaran jatuh di bulan Maret.
-- -----------------------------------------------------------------------------
CREATE TABLE mart.dim_tanggal AS
WITH kalender AS (
    SELECT d::date AS tanggal
    FROM generate_series('2018-01-01'::date, '2026-12-31'::date, interval '1 day') AS d
),
idulfitri AS (
    SELECT tanggal, extract(year FROM tanggal) AS tahun
    FROM staging.stg_hari_besar WHERE nama_hari_besar = 'Idulfitri'
),
awal_ramadan AS (
    SELECT tanggal, extract(year FROM tanggal) AS tahun
    FROM staging.stg_hari_besar WHERE nama_hari_besar = 'Awal Ramadan'
)
SELECT
    k.tanggal,
    extract(year FROM k.tanggal)::int                     AS tahun,
    extract(quarter FROM k.tanggal)::int                  AS kuartal,
    extract(month FROM k.tanggal)::int                    AS bulan,
    (ARRAY['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli',
           'Agustus', 'September', 'Oktober', 'November', 'Desember'])
        [extract(month FROM k.tanggal)::int]              AS nama_bulan,
    date_trunc('month', k.tanggal)::date                  AS awal_bulan,
    extract(isodow FROM k.tanggal)::int                   AS hari_dalam_minggu,
    (ARRAY['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'])
        [extract(isodow FROM k.tanggal)::int]             AS nama_hari,
    extract(isodow FROM k.tanggal) <= 5                   AS is_hari_kerja,
    hb.nama_hari_besar,
    k.tanggal - f.tanggal                                 AS hari_ke_idulfitri,
    coalesce(k.tanggal >= r.tanggal AND k.tanggal < f_tahun.tanggal, false) AS is_ramadan
FROM kalender AS k
LEFT JOIN staging.stg_hari_besar AS hb ON hb.tanggal = k.tanggal
LEFT JOIN LATERAL (
    SELECT i.tanggal FROM idulfitri AS i ORDER BY abs(k.tanggal - i.tanggal) LIMIT 1
) AS f ON true
LEFT JOIN idulfitri AS f_tahun ON f_tahun.tahun = extract(year FROM k.tanggal)
LEFT JOIN awal_ramadan AS r ON r.tahun = extract(year FROM k.tanggal);

ALTER TABLE mart.dim_tanggal ADD PRIMARY KEY (tanggal);


-- -----------------------------------------------------------------------------
-- fact_harga_harian. Grain: tanggal x wilayah x varian x jenis pasar.
-- Hanya berisi hari yang ada datanya.
--   harga       = harga bersih (NULL kalau anomali), dipakai untuk analisis
--   harga_asli  = harga sesuai sumber, disimpan untuk audit
-- -----------------------------------------------------------------------------
CREATE TABLE mart.fact_harga_harian AS
SELECT
    tanggal,
    wilayah_id,
    komoditas_id,
    jenis_pasar_id,
    CASE WHEN is_anomali THEN NULL ELSE harga END AS harga,
    harga                                         AS harga_asli,
    is_anomali
FROM staging.stg_harga_harian;

ALTER TABLE mart.fact_harga_harian
    ADD PRIMARY KEY (tanggal, wilayah_id, komoditas_id, jenis_pasar_id),
    ADD FOREIGN KEY (tanggal)        REFERENCES mart.dim_tanggal,
    ADD FOREIGN KEY (wilayah_id)     REFERENCES mart.dim_wilayah,
    ADD FOREIGN KEY (komoditas_id)   REFERENCES mart.dim_komoditas,
    ADD FOREIGN KEY (jenis_pasar_id) REFERENCES mart.dim_jenis_pasar;

-- Pola query paling umum: satu komoditas, beberapa wilayah, rentang waktu
CREATE INDEX ON mart.fact_harga_harian (komoditas_id, wilayah_id, tanggal);


-- -----------------------------------------------------------------------------
-- fact_harga_bulanan: agregat bulanan untuk analisis tren dan dashboard Tableau.
--   koef_variasi = stddev / rata-rata harga harian dalam bulan (ukuran volatilitas)
--   kelengkapan  = hari berdata / hari kerja dalam bulan
-- -----------------------------------------------------------------------------
CREATE TABLE mart.fact_harga_bulanan AS
WITH hari_kerja AS (
    SELECT awal_bulan, count(*) AS n_hari_kerja
    FROM mart.dim_tanggal
    WHERE is_hari_kerja
    GROUP BY awal_bulan
)
SELECT
    d.awal_bulan                                                      AS bulan,
    f.wilayah_id,
    f.komoditas_id,
    f.jenis_pasar_id,
    round(avg(f.harga), 0)                                            AS harga_rata,
    min(f.harga)                                                      AS harga_min,
    max(f.harga)                                                      AS harga_max,
    round(stddev_samp(f.harga) / nullif(avg(f.harga), 0), 4)          AS koef_variasi,
    count(f.harga)                                                    AS hari_berdata,
    round(count(f.harga)::numeric / hk.n_hari_kerja, 3)               AS kelengkapan
FROM mart.fact_harga_harian AS f
JOIN mart.dim_tanggal AS d USING (tanggal)
JOIN hari_kerja AS hk ON hk.awal_bulan = d.awal_bulan
GROUP BY d.awal_bulan, f.wilayah_id, f.komoditas_id, f.jenis_pasar_id, hk.n_hari_kerja
HAVING count(f.harga) > 0;

ALTER TABLE mart.fact_harga_bulanan
    ADD PRIMARY KEY (bulan, wilayah_id, komoditas_id, jenis_pasar_id),
    ADD FOREIGN KEY (bulan)          REFERENCES mart.dim_tanggal,
    ADD FOREIGN KEY (wilayah_id)     REFERENCES mart.dim_wilayah,
    ADD FOREIGN KEY (komoditas_id)   REFERENCES mart.dim_komoditas,
    ADD FOREIGN KEY (jenis_pasar_id) REFERENCES mart.dim_jenis_pasar;
