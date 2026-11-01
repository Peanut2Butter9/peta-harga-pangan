-- =============================================================================
-- Q2. Provinsi mana yang harganya jauh di atas/bawah rata-rata nasional,
--     dan apakah disparitas antarwilayah makin melebar?
-- Keputusan terkait: alokasi budget bahan baku per wilayah.
--
-- Data: pasar tradisional, 21 varian.
-- Metode:
--   Q2a. selisih vs nasional = harga provinsi / harga nasional - 1, untuk varian & bulan
--        yang sama, lalu dirata-ratakan per provinsi (12 bulan terakhir: Nov 2025 - Okt 2026).
--   Q2b. per tahun: (1) koefisien variasi harga antarprovinsi, rata-rata semua varian;
--        (2) selisih harga rata-rata Maluku & Papua dibanding Jawa.
--
-- INSIGHT (data s.d. 30 Okt 2026):
--   1. Termahal: Papua (+25,6% vs nasional), Maluku Utara (+21,1%), Papua Barat (+14,7%).
--      Kalimantan juga mahal: Kalimantan Tengah (+13,1%) dan Kalimantan Utara (+11,3%).
--   2. Termurah: Sulawesi Selatan (-14,9%), Jawa Timur (-12,3%), NTB (-10,9%), Jawa Tengah
--      (-8,6%), yaitu provinsi sentra produksi.
--      -> H2 hanya sebagian benar: Maluku & Papua memang mahal, tapi NTT justru di bawah
--         rata-rata nasional (-3,1%), sementara Kalimantan ikut mahal.
--   3. Disparitas keseluruhan relatif stabil (CV antarprovinsi 13-14%), tapi selisih
--      Maluku & Papua vs Jawa melebar ke 25,0% pada 2026, tertinggi sejak 2018.
--   Catatan: Gorontalo hanya punya 15 dari 21 varian, jadi perbandingannya kurang setara.
--   Rekomendasi: alokasikan budget bahan baku ~15-25% lebih tinggi untuk outlet di
--   Maluku & Papua; pertimbangkan Sulawesi Selatan sebagai hub pasokan untuk wilayah
--   timur (perlu dihitung bersama ongkos kirim, yang tidak ada di data ini).
-- =============================================================================


-- Q2a. Peringkat provinsi, 12 bulan terakhir --------------------------------
WITH indeks AS (
    SELECT
        w.nama_wilayah,
        w.pulau,
        b.komoditas_id,
        b.harga_rata / n.harga_rata - 1 AS selisih_vs_nasional
    FROM mart.fact_harga_bulanan AS b
    JOIN mart.fact_harga_bulanan AS n
      ON  n.bulan = b.bulan
      AND n.komoditas_id = b.komoditas_id
      AND n.jenis_pasar_id = b.jenis_pasar_id
      AND n.wilayah_id = 0
    JOIN mart.dim_wilayah AS w ON w.wilayah_id = b.wilayah_id
    WHERE b.jenis_pasar_id = 1
      AND NOT w.is_nasional
      AND b.bulan BETWEEN '2025-11-01' AND '2026-10-01'
)
SELECT
    rank() OVER (ORDER BY avg(selisih_vs_nasional) DESC)  AS peringkat,
    nama_wilayah,
    pulau,
    round(100 * avg(selisih_vs_nasional), 1)              AS pct_vs_nasional,
    count(DISTINCT komoditas_id)                          AS n_varian
FROM indeks
GROUP BY nama_wilayah, pulau
ORDER BY peringkat;


-- Q2b. Tren disparitas per tahun ---------------------------------------------
WITH tahunan AS (
    SELECT d.tahun, b.wilayah_id, w.pulau, b.komoditas_id, avg(b.harga_rata) AS harga
    FROM mart.fact_harga_bulanan AS b
    JOIN mart.dim_tanggal AS d ON d.tanggal = b.bulan
    JOIN mart.dim_wilayah AS w USING (wilayah_id)
    WHERE b.jenis_pasar_id = 1 AND NOT w.is_nasional
    GROUP BY d.tahun, b.wilayah_id, w.pulau, b.komoditas_id
),
per_varian AS (
    SELECT
        tahun,
        komoditas_id,
        stddev_samp(harga) / avg(harga)                     AS cv_antar_provinsi,
        avg(harga) FILTER (WHERE pulau = 'Maluku & Papua')
          / avg(harga) FILTER (WHERE pulau = 'Jawa') - 1    AS selisih_timur_vs_jawa
    FROM tahunan
    GROUP BY tahun, komoditas_id
)
SELECT
    tahun,
    round(100 * avg(cv_antar_provinsi), 1)      AS cv_antar_provinsi_pct,
    round(100 * avg(selisih_timur_vs_jawa), 1)  AS maluku_papua_vs_jawa_pct
FROM per_varian
GROUP BY tahun
ORDER BY tahun;   -- catatan: 2026 = Januari s.d. Oktober
