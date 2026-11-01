-- =============================================================================
-- Q4. Seberapa besar lonjakan harga menjelang Lebaran, dan kapan mulai naik?
-- Keputusan terkait: kapan stok harus diamankan sebelum Lebaran.
--
-- Data: harga nasional, pasar tradisional, Lebaran 2018-2026 (9 kali).
-- Metode, per Lebaran dan per varian:
--   baseline   = rata-rata harga H-90 s.d. H-61 (sebelum efek Ramadan)
--   menjelang  = rata-rata harga H-14 s.d. H-1
--   lonjakan   = menjelang / baseline - 1
-- Lalu diambil MEDIAN dari 9 Lebaran, supaya tidak didominasi tahun yang tidak biasa
-- (mis. 2020 pandemi, 2022 krisis minyak goreng).
--   hari_mulai_naik = hari pertama ketika kurva rata-rata (harga / baseline) mencapai
--                     >= 3% di atas baseline dan tidak turun lagi di bawahnya sampai H-1.
--
-- INSIGHT (Lebaran 2018-2026):
--   1. Lonjakan Lebaran lebih kecil dan lebih telat dari dugaan. Median kenaikan H-14..H-1
--      tertinggi hanya ~4,6% (daging ayam, bawang merah), lalu bawang putih 4,4%.
--   2. Yang paling KONSISTEN adalah daging sapi: naik di 9 dari 9 Lebaran (+2,8-2,9%,
--      maksimal 8,5%). Daging ayam naik di 8 dari 9 Lebaran.
--   3. Kenaikan baru terasa (>= 3%) sekitar H-9 untuk ayam dan H-5 untuk daging sapi & telur.
--   4. Cabai rawit justru cenderung LEBIH MURAH menjelang Lebaran (median -6% s.d. -8%), dengan
--      rentang sangat lebar (-30% s.d. +41%). Harga cabai lebih dipengaruhi musim panen/cuaca
--      daripada Lebaran (lihat Q5).
--   -> H4 sebagian benar: daging & ayam memang naik, tapi kecil (< 5%) dan baru mulai
--      ~1-2 minggu sebelum Lebaran, bukan "naik signifikan".
--   Sensitivitas: hasil hampir sama kalau harga bertanda anomali ikut dihitung
--   (hanya 29 sel anomali di jendela H-90..H-1 untuk harga nasional).
--   Rekomendasi: amankan stok daging sapi & ayam paling lambat ~H-14; tidak perlu
--   menimbun cabai menjelang Lebaran.
-- =============================================================================

WITH lebaran AS (
    SELECT tanggal AS tgl_lebaran, tahun
    FROM mart.dim_tanggal
    WHERE nama_hari_besar = 'Idulfitri'
),
harian AS (
    SELECT
        l.tahun,
        f.tanggal - l.tgl_lebaran AS h,          -- -7 = H-7
        k.kategori,
        k.nama_varian,
        f.harga
    FROM mart.fact_harga_harian AS f
    JOIN lebaran AS l ON f.tanggal BETWEEN l.tgl_lebaran - 90 AND l.tgl_lebaran - 1
    JOIN mart.dim_komoditas AS k USING (komoditas_id)
    WHERE f.wilayah_id = 0
      AND f.jenis_pasar_id = 1
      AND f.harga IS NOT NULL
),
per_lebaran AS (
    SELECT
        tahun,
        kategori,
        nama_varian,
        avg(harga) FILTER (WHERE h BETWEEN -90 AND -61) AS baseline,
        avg(harga) FILTER (WHERE h BETWEEN -14 AND -1)  AS menjelang
    FROM harian
    GROUP BY tahun, kategori, nama_varian
),
kurva AS (
    -- indeks harga rata-rata dari 9 Lebaran untuk setiap H-n
    SELECT hr.nama_varian, hr.h, avg(hr.harga / p.baseline) AS indeks
    FROM harian AS hr
    JOIN per_lebaran AS p USING (tahun, nama_varian)
    WHERE hr.h BETWEEN -60 AND -1
    GROUP BY hr.nama_varian, hr.h
),
mulai_naik AS (
    SELECT k.nama_varian, min(k.h) AS hari_mulai_naik
    FROM kurva AS k
    WHERE k.indeks >= 1.03
      AND NOT EXISTS (
          SELECT 1 FROM kurva AS k2
          WHERE k2.nama_varian = k.nama_varian AND k2.h > k.h AND k2.indeks < 1.03
      )
    GROUP BY k.nama_varian
)
SELECT
    p.kategori,
    p.nama_varian,
    round(100 * percentile_cont(0.5) WITHIN GROUP (ORDER BY p.menjelang / p.baseline - 1)::numeric, 1)
                                                      AS median_lonjakan_pct,
    round(100 * min(p.menjelang / p.baseline - 1), 1) AS lonjakan_terendah_pct,
    round(100 * max(p.menjelang / p.baseline - 1), 1) AS lonjakan_tertinggi_pct,
    count(*) FILTER (WHERE p.menjelang > p.baseline)  AS n_lebaran_naik,
    count(*)                                          AS n_lebaran,
    'H' || m.hari_mulai_naik                          AS mulai_naik_3pct
FROM per_lebaran AS p
LEFT JOIN mulai_naik AS m USING (nama_varian)
WHERE p.baseline IS NOT NULL AND p.menjelang IS NOT NULL
GROUP BY p.kategori, p.nama_varian, m.hari_mulai_naik
ORDER BY median_lonjakan_pct DESC;
