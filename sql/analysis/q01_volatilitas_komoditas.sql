-- =============================================================================
-- Q1. Komoditas mana yang paling volatil, dan bagaimana tren harganya 2018–2025?
-- Keputusan terkait: komoditas mana yang perlu diprioritaskan untuk kontrak harga tetap.
--
-- Data: harga nasional, pasar tradisional.
-- Metode:
--   volatilitas_harian_pct = rata-rata koefisien variasi harga harian dalam satu bulan
--   ayunan_tahunan_pct     = rata-rata per tahun dari (bulan termahal / bulan termurah - 1)
--   kenaikan_pct, cagr_pct = perubahan rata-rata harga tahunan 2018 -> 2025
--                            (2025 = tahun penuh terakhir)
--
-- INSIGHT (data s.d. 30 Okt 2026):
--   1. Cabai dan bawang merah adalah risiko utama. Harga cabai rawit merah rata-rata
--      berayun 102% dalam setahun (bulan termahal ~2x bulan termurah), cabai merah
--      keriting 83%, cabai merah besar 79%, bawang merah 64%. -> H1 diterima.
--   2. Beras dan daging sapi paling stabil (ayunan tahunan < 7%), tapi beras naik
--      30-37% dalam 2018-2025 (CAGR ~4%/tahun). Risikonya kenaikan struktural, bukan fluktuasi.
--   3. Kenaikan terbesar 2018->2025 justru pada minyak goreng curah (+60%) dan
--      bawang merah (+57%). Daging ayam hampir tidak naik (+6%, CAGR 0,9%).
--   Rekomendasi: kontrak harga tetap/forward buying untuk cabai & bawang merah;
--   untuk beras & minyak goreng, cukup anggarkan kenaikan tahunan ~4-7%.
-- =============================================================================

WITH bulanan AS (
    SELECT k.kategori, k.nama_varian, d.tahun, b.harga_rata, b.koef_variasi
    FROM mart.fact_harga_bulanan AS b
    JOIN mart.dim_komoditas AS k USING (komoditas_id)
    JOIN mart.dim_tanggal AS d ON d.tanggal = b.bulan
    WHERE b.wilayah_id = 0          -- nasional
      AND b.jenis_pasar_id = 1      -- pasar tradisional
),
per_tahun AS (
    SELECT
        nama_varian,
        tahun,
        avg(harga_rata)                         AS harga_tahunan,
        max(harga_rata) / min(harga_rata) - 1   AS ayunan
    FROM bulanan
    GROUP BY nama_varian, tahun
),
ringkasan AS (
    SELECT
        b.kategori,
        b.nama_varian,
        avg(b.koef_variasi)                                                   AS volatilitas_harian,
        (SELECT avg(p.ayunan) FROM per_tahun AS p
          WHERE p.nama_varian = b.nama_varian AND p.tahun <= 2025)            AS ayunan_tahunan,
        (SELECT p.harga_tahunan FROM per_tahun AS p
          WHERE p.nama_varian = b.nama_varian AND p.tahun = 2018)             AS harga_2018,
        (SELECT p.harga_tahunan FROM per_tahun AS p
          WHERE p.nama_varian = b.nama_varian AND p.tahun = 2025)             AS harga_2025
    FROM bulanan AS b
    GROUP BY b.kategori, b.nama_varian
)
SELECT
    rank() OVER (ORDER BY ayunan_tahunan DESC)                     AS peringkat,
    kategori,
    nama_varian,
    round(100 * volatilitas_harian, 1)                             AS volatilitas_harian_pct,
    round(100 * ayunan_tahunan, 1)                                 AS ayunan_tahunan_pct,
    round(harga_2018)                                              AS harga_2018,
    round(harga_2025)                                              AS harga_2025,
    round(100 * (harga_2025 / harga_2018 - 1), 1)                  AS kenaikan_pct,
    round(100 * (power(harga_2025 / harga_2018, 1.0 / 7) - 1), 1)  AS cagr_pct
FROM ringkasan
ORDER BY peringkat;
