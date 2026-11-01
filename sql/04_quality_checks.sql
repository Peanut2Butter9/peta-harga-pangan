-- =============================================================================
-- 04_quality_checks.sql
-- Pemeriksaan kualitas data setelah staging & mart dibangun.
-- Satu baris = satu pemeriksaan: (cek, nilai, lolos).
-- Dijalankan oleh src/build_warehouse.py; build dianggap gagal kalau ada yang tidak lolos.
-- =============================================================================

WITH raw_terisi AS (
    SELECT count(*) AS n
    FROM raw.pihps_harga AS h
    CROSS JOIN LATERAL jsonb_each_text(h.prices) AS kv(key, value)
    WHERE h.row_level = 2 AND kv.value <> '-'
),
rentang_data AS (
    SELECT min(tanggal) AS awal, max(tanggal) AS akhir FROM mart.fact_harga_harian
),
checks (urutan, cek, nilai, lolos) AS (
    -- 1. Tidak ada data yang hilang atau bertambah antara raw dan mart
    SELECT 1, 'Rekonsiliasi: sel harga terisi di raw = baris fact_harga_harian',
           format('raw %s, fact %s', r.n, f.n), r.n = f.n
    FROM raw_terisi AS r, (SELECT count(*) AS n FROM mart.fact_harga_harian) AS f

    UNION ALL
    -- 2. Semua nama varian di raw dikenali
    SELECT 2, 'Baris varian di raw yang tidak terpetakan ke dim_komoditas',
           count(*)::text, count(*) = 0
    FROM raw.pihps_harga AS h
    LEFT JOIN mart.dim_komoditas AS k ON k.nama_varian = trim(h.row_name)
    WHERE h.row_level = 2 AND k.komoditas_id IS NULL

    UNION ALL
    -- 3. Semua wilayah di raw dikenali
    SELECT 3, 'Wilayah di raw yang tidak ada di dim_wilayah',
           count(DISTINCT h.province_id)::text, count(DISTINCT h.province_id) = 0
    FROM raw.pihps_harga AS h
    LEFT JOIN mart.dim_wilayah AS w ON w.wilayah_id = coalesce(h.province_id, 0)
    WHERE w.wilayah_id IS NULL

    UNION ALL
    -- 4. Harga harus positif
    SELECT 4, 'Harga <= 0',
           count(*)::text, count(*) = 0
    FROM mart.fact_harga_harian
    WHERE harga_asli <= 0

    UNION ALL
    -- 5. PIHPS hanya melaporkan hari kerja
    SELECT 5, 'Data pada hari Sabtu/Minggu',
           count(*)::text, count(*) = 0
    FROM mart.fact_harga_harian AS f
    JOIN mart.dim_tanggal AS d USING (tanggal)
    WHERE NOT d.is_hari_kerja

    UNION ALL
    -- 6. Anomali harus jarang; kalau banyak, aturan anomalinya perlu ditinjau ulang
    SELECT 6, 'Proporsi harga bertanda anomali (batas < 0,1%)',
           round(100.0 * avg(is_anomali::int), 3) || '% (' || sum(is_anomali::int) || ' sel)',
           avg(is_anomali::int) < 0.001
    FROM mart.fact_harga_harian

    UNION ALL
    -- 7. Setiap wilayah punya data pasar tradisional di setiap bulan
    SELECT 7, 'Kombinasi wilayah x bulan tanpa data pasar tradisional',
           count(*)::text, count(*) = 0
    FROM mart.dim_wilayah AS w
    CROSS JOIN (
        SELECT DISTINCT awal_bulan
        FROM mart.dim_tanggal, rentang_data
        WHERE tanggal BETWEEN rentang_data.awal AND rentang_data.akhir
    ) AS b
    WHERE NOT EXISTS (
        SELECT 1 FROM mart.fact_harga_bulanan AS fb
        WHERE fb.wilayah_id = w.wilayah_id AND fb.bulan = b.awal_bulan AND fb.jenis_pasar_id = 1
    )

    UNION ALL
    -- 8. Semua provinsi masuk ke salah satu kelompok pulau
    SELECT 8, 'Wilayah tanpa kelompok pulau',
           count(*)::text, count(*) = 0
    FROM mart.dim_wilayah
    WHERE pulau IS NULL

    UNION ALL
    -- 9. Konsistensi agregat bulanan
    SELECT 9, 'Baris bulanan dengan harga_rata di luar rentang min-max',
           count(*)::text, count(*) = 0
    FROM mart.fact_harga_bulanan
    WHERE harga_rata < harga_min - 1 OR harga_rata > harga_max + 1   -- toleransi pembulatan

    UNION ALL
    -- 10. Penanda musiman tersedia untuk setiap tahun data
    SELECT 10, 'Tahun data tanpa tanggal Idulfitri di dim_tanggal',
           count(*)::text, count(*) = 0
    FROM (
        SELECT tahun FROM mart.dim_tanggal, rentang_data
        WHERE tanggal BETWEEN rentang_data.awal AND rentang_data.akhir
        GROUP BY tahun
        HAVING count(hari_ke_idulfitri) = 0
    ) AS t
)
SELECT cek, nilai, lolos
FROM checks
ORDER BY urutan;
