-- =============================================================================
-- Q3. Berapa selisih harga dari produsen -> pedagang besar -> pasar tradisional,
--     per komoditas, dan di wilayah mana selisihnya paling besar?
-- Keputusan terkait: beli langsung ke pedagang besar atau di pasar lokal.
--
-- Data: 12 bulan terakhir (Nov 2025 - Okt 2026), harga bulanan.
-- Metode: selisih dihitung per wilayah, varian, dan bulan yang punya data di kedua
-- jenis pasar yang dibandingkan, lalu dirata-ratakan.
--   produsen_ke_pb_pct   = pedagang besar / produsen - 1
--   pb_ke_pasar_pct      = pasar tradisional / pedagang besar - 1
--   total_pct            = pasar tradisional / produsen - 1
-- Catatan: ini selisih harga, bukan margin keuntungan; di dalamnya ada ongkos angkut,
-- penyusutan, dan biaya lain di setiap mata rantai.
--
-- INSIGHT (Nov 2025 - Okt 2026):
--   1. Selisih produsen -> pasar paling besar di komoditas segar yang cepat rusak:
--      cabai +48% s.d. +63%, bawang merah +47%, daging ayam +38%. Komoditas tahan simpan
--      jauh lebih kecil: beras +15% s.d. +21%, minyak goreng +14% s.d. +20%, gula +14%
--      s.d. +25%, daging sapi +10% s.d. +12%.
--   2. Untuk cabai merah, bawang merah, dan ayam, porsi terbesar ada di mata rantai
--      terakhir: harga pasar tradisional 19-29% di atas pedagang besar. Untuk beras
--      sebaliknya: produsen -> pedagang besar 11-15%, pedagang besar -> pasar hanya 3-7%.
--   3. Telur adalah pengecualian: mudah rusak tapi selisih totalnya kecil (+14%), dan
--      hampir semuanya di mata rantai pedagang besar -> pasar (+12%).
--   4. Selisih pedagang besar -> pasar paling besar di Papua (+30,7%), Kalimantan Selatan
--      (+24,5%), NTB (+21,9%), Sumatera Selatan (+21,6%), dan Sulawesi Tengah (+20,0%).
--   -> H3 diterima, dengan pengecualian telur.
--   Keandalan: bawang putih (+84%) tidak dipakai untuk kesimpulan karena harga
--   produsennya hanya dari 2 provinsi (sebagian besar bawang putih diimpor). Median
--   per provinsi memberi pola yang sama untuk komoditas lain (cabai +48% s.d. +61%,
--   ayam +38%, beras +8% s.d. +18%, daging sapi +10% s.d. +11%).
--   Rekomendasi: beli cabai, bawang merah, dan ayam langsung ke pedagang besar,
--   terutama di provinsi pada poin 4. Untuk beras, minyak goreng, dan daging sapi,
--   selisihnya (3-10%) mungkin tidak sebanding dengan repotnya logistik.
-- =============================================================================


-- Q3a. Per varian, harga nasional ------------------------------------------------
WITH pivot AS (
    SELECT
        b.bulan,
        b.wilayah_id,
        b.komoditas_id,
        max(b.harga_rata) FILTER (WHERE jp.nama_jenis_pasar = 'Produsen')          AS produsen,
        max(b.harga_rata) FILTER (WHERE jp.nama_jenis_pasar = 'Pedagang Besar')    AS pedagang_besar,
        max(b.harga_rata) FILTER (WHERE jp.nama_jenis_pasar = 'Pasar Tradisional') AS pasar
    FROM mart.fact_harga_bulanan AS b
    JOIN mart.dim_jenis_pasar AS jp USING (jenis_pasar_id)
    WHERE b.bulan BETWEEN '2025-11-01' AND '2026-10-01'
    GROUP BY b.bulan, b.wilayah_id, b.komoditas_id
),
cakupan AS (
    -- harga produsen nasional hanya bisa dipercaya kalau datanya dari banyak provinsi
    SELECT komoditas_id, count(DISTINCT wilayah_id) AS provinsi_ada_produsen
    FROM pivot
    WHERE wilayah_id <> 0 AND produsen IS NOT NULL
    GROUP BY komoditas_id
)
SELECT
    k.kategori,
    k.nama_varian,
    round(avg(p.produsen))                                  AS produsen,
    round(avg(p.pedagang_besar))                            AS pedagang_besar,
    round(avg(p.pasar))                                     AS pasar_tradisional,
    round(100 * avg(p.pedagang_besar / p.produsen - 1), 1)  AS produsen_ke_pb_pct,
    round(100 * avg(p.pasar / p.pedagang_besar - 1), 1)     AS pb_ke_pasar_pct,
    round(100 * avg(p.pasar / p.produsen - 1), 1)           AS total_pct,
    c.provinsi_ada_produsen
FROM pivot AS p
JOIN mart.dim_komoditas AS k USING (komoditas_id)
LEFT JOIN cakupan AS c USING (komoditas_id)
WHERE p.wilayah_id = 0
GROUP BY k.kategori, k.nama_varian, k.urutan, c.provinsi_ada_produsen
ORDER BY total_pct DESC NULLS LAST, k.urutan;


-- Q3b. Selisih pedagang besar -> pasar tradisional per provinsi -----------------
-- (rata-rata semua varian; 10 provinsi dengan selisih terbesar)
WITH pivot AS (
    SELECT
        b.bulan,
        b.wilayah_id,
        b.komoditas_id,
        max(b.harga_rata) FILTER (WHERE jp.nama_jenis_pasar = 'Pedagang Besar')    AS pedagang_besar,
        max(b.harga_rata) FILTER (WHERE jp.nama_jenis_pasar = 'Pasar Tradisional') AS pasar
    FROM mart.fact_harga_bulanan AS b
    JOIN mart.dim_jenis_pasar AS jp USING (jenis_pasar_id)
    WHERE b.bulan BETWEEN '2025-11-01' AND '2026-10-01'
    GROUP BY b.bulan, b.wilayah_id, b.komoditas_id
)
SELECT
    rank() OVER (ORDER BY avg(p.pasar / p.pedagang_besar - 1) DESC)  AS peringkat,
    w.nama_wilayah,
    w.pulau,
    round(100 * avg(p.pasar / p.pedagang_besar - 1), 1)              AS pb_ke_pasar_pct,
    count(DISTINCT p.komoditas_id)                                   AS n_varian
FROM pivot AS p
JOIN mart.dim_wilayah AS w USING (wilayah_id)
WHERE NOT w.is_nasional
  AND p.pedagang_besar IS NOT NULL
  AND p.pasar IS NOT NULL
GROUP BY w.nama_wilayah, w.pulau
ORDER BY peringkat
LIMIT 10;
