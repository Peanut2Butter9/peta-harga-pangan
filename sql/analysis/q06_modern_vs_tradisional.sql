-- =============================================================================
-- Q6. Pasar modern vs pasar tradisional: mana yang lebih murah, untuk komoditas apa?
-- Keputusan terkait: pilihan channel pembelian.
--
-- Data: 12 bulan terakhir (Nov 2025 - Okt 2026), harga bulanan per provinsi.
-- Metode:
--   selisih_modern_pct      = pasar modern / pasar tradisional - 1, untuk wilayah, varian,
--                             dan bulan yang punya data di kedua jenis pasar
--   median_selisih_provinsi_pct = median dari selisih per provinsi; lebih tahan terhadap
--                             perbedaan cakupan provinsi antar jenis pasar di angka nasional
--   provinsi_modern_lebih_murah = jumlah provinsi yang rata-rata harga modernnya
--                             lebih murah dari pasar tradisional
--
-- INSIGHT (Nov 2025 - Okt 2026, memakai median per provinsi):
--   1. Pasar modern jauh lebih mahal untuk komoditas segar: cabai +46% s.d. +72%, bawang
--      merah +42%, bawang putih +27%, daging sapi +23%, daging ayam +16%. Untuk cabai dan
--      bawang merah, pasar modern lebih murah hanya di 0-2 dari 27-34 provinsi.
--   2. Untuk beras dan minyak goreng kemasan, harganya praktis setara (0% s.d. +4%).
--   3. Gula pasir justru lebih murah di pasar modern: premium -6,1%, lokal -2,9%, dan
--      lebih murah di 24 dan 28 dari 34 provinsi. Angka nasional gula premium (+3,9%)
--      berlawanan arah dengan median provinsi, jadi angka nasional tidak dipakai di sini.
--   4. Telur ada di tengah: +4,8% (nasional +10,1%).
--   -> H5 sebagian: bagian "modern lebih mahal untuk komoditas segar" sangat kuat, tetapi
--      "lebih murah untuk kemasan" hanya berlaku untuk gula; beras & minyak goreng setara.
--   Catatan: produk segar di pasar modern biasanya sudah disortir dan dikemas, jadi
--   sebagian selisih adalah selisih mutu dan layanan, bukan hanya harga.
--   Minyak goreng curah hanya ada di pasar modern di 7 provinsi.
--   Rekomendasi: belanja bahan segar (cabai, bawang, daging, ayam) di pasar tradisional
--   atau pedagang besar. Beras, minyak goreng kemasan, dan gula bisa dibeli di ritel
--   modern tanpa rugi harga, dengan bonus faktur resmi dan pembayaran nontunai.
-- =============================================================================

WITH pivot AS (
    SELECT
        b.bulan,
        b.wilayah_id,
        b.komoditas_id,
        max(b.harga_rata) FILTER (WHERE jp.nama_jenis_pasar = 'Pasar Modern')      AS modern,
        max(b.harga_rata) FILTER (WHERE jp.nama_jenis_pasar = 'Pasar Tradisional') AS tradisional
    FROM mart.fact_harga_bulanan AS b
    JOIN mart.dim_jenis_pasar AS jp USING (jenis_pasar_id)
    WHERE b.bulan BETWEEN '2025-11-01' AND '2026-10-01'
    GROUP BY b.bulan, b.wilayah_id, b.komoditas_id
),
per_provinsi AS (
    SELECT wilayah_id, komoditas_id, avg(modern / tradisional - 1) AS selisih
    FROM pivot
    WHERE wilayah_id <> 0 AND modern IS NOT NULL AND tradisional IS NOT NULL
    GROUP BY wilayah_id, komoditas_id
)
SELECT
    k.kategori,
    k.nama_varian,
    round(100 * (SELECT avg(p.modern / p.tradisional - 1) FROM pivot AS p
                  WHERE p.wilayah_id = 0 AND p.komoditas_id = k.komoditas_id), 1)
                                                        AS selisih_modern_nasional_pct,
    round(100 * percentile_cont(0.5) WITHIN GROUP (ORDER BY pp.selisih)::numeric, 1)
                                                        AS median_selisih_provinsi_pct,
    count(*) FILTER (WHERE pp.selisih < 0)              AS provinsi_modern_lebih_murah,
    count(pp.selisih)                                   AS provinsi_berdata
FROM mart.dim_komoditas AS k
LEFT JOIN per_provinsi AS pp USING (komoditas_id)
GROUP BY k.kategori, k.nama_varian, k.komoditas_id, k.urutan
ORDER BY median_selisih_provinsi_pct DESC NULLS LAST;
