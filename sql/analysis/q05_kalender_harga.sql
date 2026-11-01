-- =============================================================================
-- Q5. Bulan apa harga termurah dan termahal untuk tiap komoditas?
-- Keputusan terkait: kalender pembelian / waktu terbaik menambah stok.
--
-- Data: harga bulanan nasional, pasar tradisional, Jan 2018 - Okt 2026.
-- Metode ratio-to-moving-average (dekomposisi musiman klasik):
--   1. tren          = rata-rata bergerak 2x12 bulan terpusat (centered moving average)
--   2. rasio         = harga bulan itu / tren  (menghilangkan efek kenaikan jangka panjang)
--   3. indeks musim  = rata-rata rasio untuk setiap bulan kalender (Jan..Des) dari semua tahun
--   4. bulan termurah/termahal = indeks terendah/tertinggi
-- Catatan: Lebaran maju ~11 hari setiap tahun, jadi efeknya tersebar ke beberapa bulan
-- dan tidak terlihat tajam di analisis per bulan kalender (lihat Q4 untuk efek Lebaran).
--
-- INSIGHT (Jan 2018 - Okt 2026):
--   1. September-Oktober adalah bulan termurah untuk hampir semua komoditas segar
--      (cabai, bawang, ayam, telur) sekaligus gula dan minyak goreng.
--   2. Pola musim terkuat ada di bawang merah (termurah Okt -17,7% vs tren, termahal Jun
--      +16,3%, selisih 41%) dan cabai rawit merah (termurah Sep -16,0%, termahal Mar +18,0%,
--      selisih 40%).
--   3. Cabai paling mahal di awal tahun (Jan-Mar, musim hujan); bawang putih di Mei,
--      bawang merah di Juni.
--   4. Beras dan daging sapi praktis tidak punya pola musiman (selisih < 2,5%), jadi
--      waktu pembelian tidak banyak berpengaruh.
--   Rekomendasi: kalender pembelian. Tambah stok komoditas yang tahan disimpan (bawang
--   merah/putih, gula, minyak goreng) di Sep-Okt. Untuk cabai yang cepat busuk, siapkan
--   kontrak harga atau alternatif cabai beku/kering untuk Jan-Mar.
-- =============================================================================

WITH bulanan AS (
    SELECT k.kategori, k.nama_varian, k.urutan, b.bulan, b.harga_rata
    FROM mart.fact_harga_bulanan AS b
    JOIN mart.dim_komoditas AS k USING (komoditas_id)
    WHERE b.wilayah_id = 0 AND b.jenis_pasar_id = 1
),
tren AS (
    SELECT
        *,
        -- 2x12 MA: rata-rata dari dua rata-rata 12 bulan yang bergeser satu bulan
        (  avg(harga_rata) OVER (PARTITION BY nama_varian ORDER BY bulan
                                 ROWS BETWEEN 6 PRECEDING AND 5 FOLLOWING)
         + avg(harga_rata) OVER (PARTITION BY nama_varian ORDER BY bulan
                                 ROWS BETWEEN 5 PRECEDING AND 6 FOLLOWING)) / 2 AS ma_2x12,
        count(*) OVER (PARTITION BY nama_varian ORDER BY bulan
                       ROWS BETWEEN 6 PRECEDING AND 6 FOLLOWING)            AS n_jendela
    FROM bulanan
),
indeks AS (
    SELECT
        kategori,
        nama_varian,
        urutan,
        extract(month FROM bulan)::int AS bln,
        avg(harga_rata / ma_2x12)      AS indeks_musim
    FROM tren
    WHERE n_jendela = 13            -- hanya bulan dengan jendela lengkap
    GROUP BY kategori, nama_varian, urutan, extract(month FROM bulan)
),
nama_bulan AS (
    SELECT ARRAY['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
                 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'] AS nama
)
SELECT
    i.kategori,
    i.nama_varian,
    n.nama[(array_agg(i.bln ORDER BY i.indeks_musim))[1]]            AS bulan_termurah,
    round(100 * (min(i.indeks_musim) - 1), 1)                        AS termurah_vs_tren_pct,
    n.nama[(array_agg(i.bln ORDER BY i.indeks_musim DESC))[1]]       AS bulan_termahal,
    round(100 * (max(i.indeks_musim) - 1), 1)                        AS termahal_vs_tren_pct,
    round(100 * (max(i.indeks_musim) / min(i.indeks_musim) - 1), 1)  AS selisih_mahal_vs_murah_pct
FROM indeks AS i
CROSS JOIN nama_bulan AS n
GROUP BY i.kategori, i.nama_varian, i.urutan, n.nama
ORDER BY selisih_mahal_vs_murah_pct DESC;
