# Fase 3 — Analisis SQL

Setiap pertanyaan bisnis dijawab oleh satu file di [`sql/analysis/`](../sql/analysis/). Di bagian atas setiap file ada pertanyaan, metode, insight, dan rekomendasi.

Kecuali disebut lain, angka di bawah memakai **harga nasional di pasar tradisional**, dengan data sampai 30 Oktober 2026.

## Ringkasan untuk manajemen

1. **Cabai dan bawang merah adalah risiko biaya terbesar.** Harganya bisa berayun hingga 2× dalam setahun. Beras dan daging sapi stabil, tapi naik pelan sekitar 4% per tahun.
2. **September–Oktober adalah waktu termurah** untuk hampir semua komoditas segar. Cabai paling mahal di Januari–Maret, bawang merah di Juni.
3. **Lonjakan Lebaran lebih kecil dari dugaan** (< 5%) dan baru terasa sekitar H-9 sampai H-5. Daging sapi naik di setiap Lebaran sejak 2018. Cabai justru cenderung turun.
4. **Outlet di Maluku & Papua menanggung harga 15–25% di atas rata-rata nasional**, dan selisihnya terhadap Jawa melebar ke titik tertinggi pada 2026. Sulawesi Selatan dan Jawa Timur adalah yang termurah.
5. **Beli cabai, bawang merah, dan ayam langsung ke pedagang besar.** Harga di pasar tradisional 19–29% di atas pedagang besar. Untuk beras, minyak goreng, dan daging sapi, selisihnya hanya 3–10%.
6. **Jangan beli bahan segar di pasar modern**: cabai 46–72% lebih mahal, daging sapi 23%, ayam 16%. Beras, minyak goreng kemasan, dan gula harganya setara atau lebih murah di ritel modern.

## Q1. Volatilitas & tren — [`q01_volatilitas_komoditas.sql`](../sql/analysis/q01_volatilitas_komoditas.sql)

| Komoditas | Ayunan harga dalam setahun* | Kenaikan 2018→2025 | CAGR |
|---|---|---|---|
| Cabai Rawit Merah | **102%** | +49% | 5,9% |
| Cabai Merah Keriting | 83% | +52% | 6,2% |
| Bawang Merah | 64% | +57% | 6,6% |
| Daging Ayam Ras | 19% | +6% | 0,9% |
| Minyak Goreng Curah | 16% | **+60%** | 6,9% |
| Beras Medium I | 6% | +32% | 4,0% |
| Daging Sapi Kualitas 1 | 4% | +18% | 2,4% |

\* rata-rata per tahun dari harga bulan termahal ÷ bulan termurah − 1

**Rekomendasi:** kontrak harga tetap atau forward buying untuk cabai dan bawang merah. Untuk beras dan minyak goreng, cukup anggarkan kenaikan tahunan sekitar 4–7%.

## Q2. Disparitas antarwilayah — [`q02_disparitas_wilayah.sql`](../sql/analysis/q02_disparitas_wilayah.sql)

Rata-rata selisih harga 21 varian terhadap nasional, Nov 2025 – Okt 2026:

| Termahal | vs nasional | Termurah | vs nasional |
|---|---|---|---|
| Papua | +25,6% | Sulawesi Selatan | −14,9% |
| Maluku Utara | +21,1% | Jawa Timur | −12,3% |
| Papua Barat | +14,7% | NTB | −10,9% |
| Kalimantan Tengah | +13,1% | Sulawesi Barat | −9,6% |
| Kalimantan Utara | +11,3% | Jawa Tengah | −8,6% |

- Disparitas keseluruhan stabil: koefisien variasi antarprovinsi 13–14% per tahun.
- Tetapi selisih Maluku & Papua dibanding Jawa naik dari 18,5% (2023) ke **25,0% (2026)**, tertinggi sejak 2018.

**Rekomendasi:** naikkan budget bahan baku 15–25% untuk outlet di Maluku & Papua. Kaji Sulawesi Selatan sebagai hub pasokan wilayah timur, dengan menghitung juga ongkos kirim yang tidak ada di data ini.

## Q3. Selisih harga di rantai pasok — [`q03_margin_rantai_pasok.sql`](../sql/analysis/q03_margin_rantai_pasok.sql)

Harga nasional rata-rata Nov 2025 – Okt 2026 (Rp/kg), diurutkan dari selisih total terbesar:

| Komoditas | Produsen | Pedagang besar | Pasar tradisional | Produsen → PB | PB → pasar | Total |
|---|---|---|---|---|---|---|
| Cabai Merah Keriting | 34.207 | 43.261 | 55.325 | +26,4% | +28,7% | **+62,6%** |
| Cabai Rawit Merah | 49.492 | 59.391 | 73.151 | +20,8% | +24,0% | +50,0% |
| Bawang Merah | 30.364 | 35.492 | 44.572 | +16,9% | +25,7% | +46,9% |
| Daging Ayam Ras | 29.215 | 33.812 | 40.321 | +15,8% | +19,3% | +38,2% |
| Beras Medium I | 13.628 | 15.172 | 16.179 | +11,4% | +6,6% | +18,7% |
| Telur Ayam Ras | 27.238 | 27.756 | 31.089 | +1,9% | +12,1% | +14,2% |
| Daging Sapi Kualitas 1 | 133.507 | 138.162 | 147.387 | +3,5% | +6,7% | +10,4% |

- Komoditas segar yang cepat rusak punya selisih 38–63%. Komoditas tahan simpan hanya 10–25%.
- Untuk cabai, bawang merah, dan ayam, porsi terbesar ada di mata rantai terakhir (pedagang besar → pasar). Untuk beras, porsi terbesar justru ada di produsen → pedagang besar.
- Selisih pedagang besar → pasar paling besar di **Papua (+30,7%)**, Kalimantan Selatan (+24,5%), NTB (+21,9%), Sumatera Selatan (+21,6%), dan Sulawesi Tengah (+20,0%).
- Bawang putih (+84%) tidak dipakai untuk kesimpulan, karena harga produsennya hanya dari 2 provinsi. Sebagian besar bawang putih diimpor.

**Rekomendasi:** beli cabai, bawang merah, dan ayam langsung ke pedagang besar, terutama di lima provinsi di atas. Untuk beras, minyak goreng, dan daging sapi, selisih 3–10% kemungkinan tidak sebanding dengan repotnya logistik.

## Q4. Lonjakan menjelang Lebaran — [`q04_lonjakan_lebaran.sql`](../sql/analysis/q04_lonjakan_lebaran.sql)

Median dari 9 Lebaran (2018–2026), harga H-14..H-1 dibanding H-90..H-61:

| Komoditas | Median lonjakan | Naik di berapa Lebaran | Mulai naik ≥ 3% |
|---|---|---|---|
| Daging Ayam Ras | +4,6% | 8 dari 9 | H-9 |
| Bawang Merah | +4,6% | 5 dari 9 | — |
| Daging Sapi Kualitas 2 | +2,9% | **9 dari 9** | H-5 |
| Telur Ayam Ras | +1,8% | 7 dari 9 | H-5 |
| Cabai Rawit Merah | **−8,1%** | 4 dari 9 | — |

**Rekomendasi:** amankan stok daging sapi dan ayam paling lambat H-14. Tidak perlu menimbun cabai menjelang Lebaran.

## Q5. Kalender harga — [`q05_kalender_harga.sql`](../sql/analysis/q05_kalender_harga.sql)

Indeks musiman (harga ÷ tren 12 bulan), rata-rata Jan 2018 – Okt 2026:

| Komoditas | Termurah | Termahal | Selisih |
|---|---|---|---|
| Bawang Merah | Okt (−17,7%) | Jun (+16,3%) | 41% |
| Cabai Rawit Merah | Sep (−16,0%) | Mar (+18,0%) | 40% |
| Cabai Rawit Hijau | Okt (−10,0%) | Jan (+9,5%) | 22% |
| Bawang Putih | Okt (−7,0%) | Mei (+12,8%) | 21% |
| Daging Ayam Ras | Sep (−4,1%) | Jun (+4,8%) | 9% |
| Beras (semua kualitas) | Agu | Mar | < 2% |

**Rekomendasi:** tambah stok komoditas yang tahan disimpan (bawang, gula, minyak goreng) di September–Oktober. Untuk cabai, siapkan kontrak harga atau cabai beku/kering untuk Januari–Maret.

## Q6. Pasar modern vs tradisional — [`q06_modern_vs_tradisional.sql`](../sql/analysis/q06_modern_vs_tradisional.sql)

Selisih harga pasar modern dibanding pasar tradisional, median dari selisih per provinsi, Nov 2025 – Okt 2026:

| Komoditas | Pasar modern vs tradisional | Provinsi yang modern-nya lebih murah |
|---|---|---|
| Cabai Merah Besar | **+72,1%** | 0 dari 27 |
| Cabai Merah Keriting | +53,3% | 1 dari 34 |
| Bawang Merah | +42,2% | 2 dari 34 |
| Daging Sapi Kualitas 1 | +23,0% | 3 dari 33 |
| Daging Ayam Ras | +15,5% | 4 dari 33 |
| Telur Ayam Ras | +4,8% | 7 dari 34 |
| Beras Medium I | +1,3% | 11 dari 33 |
| Minyak Goreng Kemasan Bermerk 1 | +0,4% | 15 dari 34 |
| Gula Pasir Lokal | −2,9% | 28 dari 34 |
| Gula Pasir Premium | **−6,1%** | 24 dari 34 |

- Pakai median per provinsi, bukan angka nasional. Contohnya gula premium: angka nasionalnya +3,9%, berlawanan arah dengan 24 dari 34 provinsi.
- Produk segar di pasar modern biasanya sudah disortir dan dikemas. Jadi sebagian selisih adalah selisih mutu dan layanan, bukan hanya harga.

**Rekomendasi:** belanja bahan segar di pasar tradisional atau pedagang besar. Beras, minyak goreng kemasan, dan gula bisa dibeli di ritel modern tanpa rugi harga, ditambah faktur resmi dan pembayaran nontunai.

## Status hipotesis

Status di bawah ini berdasarkan analisis deskriptif. Keputusan final setelah uji statistik ada di [docs/04_analisis_python.md](04_analisis_python.md#2-uji-hipotesis).

| Hipotesis | Status | Bukti |
|---|---|---|
| H1: Cabai & bawang merah paling volatil, beras & gula paling stabil | ✅ Diterima | Q1: ayunan cabai rawit 102%, bawang merah 64%; beras < 7% |
| H2: Indonesia Timur (Maluku, Papua, NTT) konsisten lebih mahal | ⚠️ Sebagian | Q2: Maluku & Papua +11% s.d. +26%, tapi NTT −3%; Kalimantan juga mahal |
| H3: Margin produsen → pasar terbesar di komoditas mudah rusak | ✅ Diterima | Q3: cabai, bawang merah, ayam +38% s.d. +63%; beras, minyak, gula, daging sapi +10% s.d. +25%. Pengecualian: telur +14% |
| H4: Daging, ayam, telur naik signifikan menjelang Lebaran, mulai ~2 minggu sebelumnya | ⚠️ Sebagian | Q4: naik konsisten tapi kecil (< 5%), mulai H-9 s.d. H-5 |
| H5: Pasar modern lebih mahal untuk komoditas segar, lebih murah untuk kemasan | ⚠️ Sebagian | Q6: segar +16% s.d. +72%; tapi beras & minyak goreng kemasan setara, hanya gula yang lebih murah (−3% s.d. −6%) |

## Teknik SQL yang dipakai

| Teknik | Dipakai di |
|---|---|
| CTE berlapis untuk memecah logika | Semua query |
| Window function: `RANK()`, `avg() OVER (ROWS BETWEEN …)` | Q1, Q2, Q3, Q5 (moving average 2×12 bulan) |
| Agregasi bersyarat `FILTER (WHERE …)` untuk pivot | Q2, Q3, Q4, Q6 |
| `percentile_cont` (median) | Q4, Q6 |
| Self-join tabel fakta (provinsi vs nasional) | Q2 |
| Subquery berkorelasi | Q6 |
| `NOT EXISTS` untuk kondisi "tidak pernah turun lagi" | Q4 |
| `array_agg(… ORDER BY …)` untuk argmin/argmax | Q5 |

## Keterbatasan

- Harga PIHPS adalah rata-rata pasar yang disurvei, bukan harga beli aktual perusahaan.
- Selisih antarwilayah dan antar mata rantai belum memasukkan ongkos kirim.
- Data pasar modern, pedagang besar, dan produsen hanya diambil mulai 2023. Harga produsen tidak tersedia di semua provinsi (lihat kolom `provinsi_ada_produsen` di Q3).
- Tanggal hari besar 2018–2025 belum dicocokkan dengan SKB libur nasional (lihat `sql/02_staging.sql`).
