# Fase 1 — Problem Definition

**Judul kerja:** Peta Harga Pangan Indonesia — Rantai Pasok, Disparitas Wilayah, dan Pola Musiman (2018–2026)
**Status:** draf · terakhir diperbarui 31 Oktober 2026

---

## 1. Latar belakang

Harga bahan pangan seperti cabai, bawang, beras, daging, dan minyak goreng adalah komponen biaya terbesar bagi bisnis F&B dan ritel. Harganya berbeda jauh antarwilayah, naik-turun tajam menjelang hari besar, dan berubah di setiap mata rantai: dari produsen, ke pedagang besar, sampai ke pasar.

Bank Indonesia mempublikasikan data ini setiap hari lewat **PIHPS Nasional** (Pusat Informasi Harga Pangan Strategis). Datanya mencakup 10 komoditas (31 varian) di 34 provinsi dan kabupaten/kotanya, untuk 4 jenis pasar: produsen, pedagang besar, pasar tradisional, dan pasar modern.

## 2. Skenario bisnis (fiktif)

Misalkan saya adalah data analyst di sebuah **jaringan restoran (fiktif)** yang punya outlet di banyak provinsi. Tim procurement membeli bahan baku secara lokal di setiap wilayah. Manajemen ingin tahu di mana dan kapan biaya bahan baku paling berisiko, supaya bisa merencanakan pembelian, stok, dan harga menu dengan lebih baik.

## 3. Stakeholder

| Stakeholder | Kebutuhan | Keputusan yang dibantu |
|---|---|---|
| Head of Procurement | Tahu kapan dan di mana harga bahan baku naik | Waktu pembelian stok, negosiasi kontrak dengan supplier |
| Finance / CFO | Memperkirakan risiko biaya bahan baku (COGS) | Budget bulanan, cadangan untuk lonjakan musiman |
| Supply Chain | Memahami selisih harga antarwilayah dan antar mata rantai | Pilihan sumber pasokan (beli dari pedagang besar vs pasar lokal, antarprovinsi) |
| Tim Menu & Pricing | Tahu komoditas mana yang paling tidak stabil | Penyesuaian harga menu, substitusi bahan |

## 4. Problem statement

> Biaya bahan baku perusahaan sangat bergantung pada harga pangan lokal yang berbeda antarwilayah dan berfluktuasi tajam. Saat ini belum ada gambaran terpadu tentang **komoditas mana yang paling berisiko**, **wilayah mana yang paling mahal**, **kapan lonjakan biasanya terjadi**, dan **berapa selisih harga di tiap mata rantai pasok**. Proyek ini menganalisis data harga harian PIHPS 2018–2026 untuk menjawab pertanyaan-pertanyaan tersebut, lalu menyajikannya dalam dashboard yang bisa dipantau rutin oleh tim procurement dan finance.

## 5. Pertanyaan bisnis

| # | Pertanyaan | Keputusan terkait | Tool utama |
|---|---|---|---|
| Q1 | Komoditas mana yang paling volatil, dan bagaimana trennya 2018–2026? | Prioritas komoditas yang perlu kontrak harga tetap | SQL → Python |
| Q2 | Provinsi mana yang harganya jauh di atas atau di bawah rata-rata nasional? Apakah disparitasnya makin melebar? | Alokasi budget per wilayah | SQL → Tableau (peta) |
| Q3 | Berapa selisih harga dari produsen → pedagang besar → pasar tradisional → pasar modern, per komoditas? | Beli langsung ke pedagang besar atau di pasar lokal | SQL |
| Q4 | Seberapa besar lonjakan harga menjelang Ramadan/Lebaran dan Nataru, dan berapa hari sebelumnya mulai naik? | Kapan stok harus diamankan | SQL + Python |
| Q5 | Bulan apa harga termurah dan termahal untuk tiap komoditas? | Kalender pembelian | SQL (window function) |
| Q6 | Pasar modern vs pasar tradisional: mana yang lebih murah, untuk komoditas apa? | Pilihan channel pembelian | SQL → Tableau |
| Q7 | Apakah kenaikan harga di satu provinsi diikuti provinsi lain beberapa hari kemudian? | Peringatan dini untuk outlet di provinsi lain | Python (lag correlation) |
| Q8 | Bisakah provinsi dikelompokkan berdasarkan pola harganya? | Strategi procurement per kelompok wilayah | Python (clustering) |

## 6. Definisi KPI

| KPI | Definisi / rumus | Catatan |
|---|---|---|
| Harga rata-rata | Rata-rata harga harian PIHPS dalam periode (Rp per satuan komoditas) | Cek satuan tiap komoditas (kg, liter, dll.) di tahap data understanding |
| Perubahan MoM / YoY | `harga_bulan_ini / harga_bulan_lalu − 1`, `harga_bulan_ini / harga_bulan_sama_tahun_lalu − 1` | Dihitung dari rata-rata bulanan |
| Volatilitas | Koefisien variasi (CV) = `STDDEV(harga harian) / AVG(harga harian)` per komoditas per bulan | Pakai varian (level 2), bukan kategori |
| Indeks disparitas wilayah | `harga provinsi / harga nasional − 1` | Positif = lebih mahal dari rata-rata nasional |
| Margin rantai pasok | `(harga di mata rantai berikutnya − harga produsen) / harga produsen` | Hanya untuk komoditas & wilayah yang punya data di kedua jenis pasar |
| Lonjakan musiman | `rata-rata harga H-30 s.d. H-1 hari besar / rata-rata harga 60 hari sebelum periode itu − 1` | Tanggal hari besar disusun manual sebagai tabel referensi |

## 7. Hipotesis awal

- **H1:** Cabai dan bawang merah adalah komoditas paling volatil; beras dan gula paling stabil.
- **H2:** Harga di Indonesia Timur (Maluku, Papua, NTT) konsisten lebih tinggi dari rata-rata nasional.
- **H3:** Margin produsen → pasar terbesar ada di komoditas yang mudah rusak (cabai, bawang, sayur).
- **H4:** Daging, ayam, dan telur naik signifikan menjelang Lebaran, mulai sekitar 2 minggu sebelumnya.
- **H5:** Pasar modern lebih mahal untuk komoditas segar, tapi bisa lebih murah untuk produk kemasan (minyak goreng, gula).

Setiap hipotesis akan diterima atau ditolak berdasarkan data. Hasil yang membantah hipotesis tetap ditulis sebagai insight.

## 8. Data

| Sumber | Isi | Peran di model data |
|---|---|---|
| **PIHPS Nasional** — [bi.go.id/hargapangan](https://www.bi.go.id/hargapangan) | Harga harian per komoditas × provinsi/kab-kota × jenis pasar | Tabel fakta utama |
| **BPS** — [bps.go.id](https://www.bps.go.id) | Penduduk, PDRB per kapita, inflasi per provinsi | Dimensi pengaya wilayah |
| **Kalender hari besar** (disusun manual) | Tanggal Ramadan, Lebaran, Natal & Tahun Baru 2018–2026 | Dimensi tanggal |
| **HET Bapanas** (opsional) | Harga eceran tertinggi beras, minyak goreng, gula | Pembanding di dashboard |

**Catatan awal tentang data PIHPS** (dari pengecekan 31 Okt 2026):
- Tersedia minimal sejak **Januari 2018** (dicek untuk pasar tradisional). Cakupan 3 jenis pasar lainnya perlu dicek.
- Tipe laporan bisa **harian, mingguan, atau bulanan**, dengan filter komoditas, provinsi, kab/kota, dan pasar.
- Formatnya **wide**: tanggal menjadi kolom. Perlu di-*unpivot* ke format long (`tanggal, wilayah, komoditas, jenis_pasar, harga`).
- Harga berupa teks dengan pemisah ribuan (`"11,050"`), jadi perlu dikonversi ke angka.
- Tidak ada data di akhir pekan atau hari libur. Ini perlu diperhitungkan saat menghitung rata-rata dan lag.
- Baris **kategori** (level 1, misalnya "Beras") dan **varian** (level 2, misalnya "Beras Kualitas Medium I") ada di tabel yang sama. Harus dipisah supaya tidak terhitung ganda.
- PIHPS masih memakai **34 provinsi**, sedangkan BPS sudah 38. Perlu tabel mapping wilayah.
- Tidak semua provinsi melaporkan semua varian (rata-rata ~20 dari 21 varian per provinsi pada Sep 2026).
- Cakupan per jenis pasar (dicek untuk Januari 2018, level nasional): pasar modern dan pedagang besar sudah ada, **produsen belum ada**. Tanggal mulai data produsen perlu dicek.
- Untuk pasar tradisional, DKI Jakarta hanya diwakili Kota Jakarta Pusat.

**Cara pengambilan data** (diputuskan di Fase 2): script Python [`src/fetch_pihps.py`](../src/fetch_pihps.py) memanggil endpoint JSON yang dipakai halaman Tabel Harga PIHPS.
- Data diambil per wilayah per bulan, karena request satu bulan butuh ~0,6 detik, sedangkan satu tahun ~45 detik.
- Ada jeda antar request, dan hasilnya disimpan sebagai snapshot JSON di `data/raw/pihps/`.
- Endpoint ini tidak terdokumentasi resmi dan bisa berubah. Karena itu analisis selalu memakai snapshot, bukan request langsung.

## 9. Ruang lingkup

- **Periode:** Januari 2018 – Oktober 2026 (disesuaikan setelah cakupan tiap jenis pasar dicek)
- **Granularitas utama:** provinsi × varian komoditas × jenis pasar × hari. Kab/kota hanya untuk deep-dive.
- **In scope:** analisis deskriptif, uji statistik, clustering, dashboard Tableau.
- **Out of scope:** klaim sebab-akibat (misalnya "kebijakan X menyebabkan harga turun"), dan forecasting (opsional sebagai bonus kalau waktu cukup).
- **Asumsi:**
  - Harga **pedagang besar** dipakai sebagai proxy harga beli perusahaan.
  - Harga PIHPS dianggap representatif untuk wilayahnya.

## 10. Deliverable & kriteria selesai

| Deliverable | Dianggap selesai jika... |
|---|---|
| Script pengambilan data (`src/`) | Bisa dijalankan ulang dan menghasilkan file raw yang sama untuk periode yang sama |
| Script SQL (`sql/`): staging, mart, quality checks | Bisa dijalankan dari nol; quality check lolos (tidak ada duplikat, harga ≤ 0, atau wilayah tak terpetakan) |
| Query analisis (`sql/analysis/`) | Satu file per pertanyaan Q1–Q6, dengan komentar berisi pertanyaan dan insight |
| Notebook EDA & statistik (`notebooks/`) | Q1–Q8 terjawab dengan angka plus satu kalimat insight; H1–H5 diputuskan |
| Dashboard Tableau Public | Menampilkan KPI di atas, filter komoditas, wilayah, jenis pasar, dan periode; ada peta provinsi |
| README | Memuat insight utama dan rekomendasi bisnis, bisa dipahami dalam 2 menit |

## 11. Risiko & mitigasi

| Risiko | Mitigasi |
|---|---|
| Endpoint atau format situs PIHPS berubah | Simpan semua data mentah di `data/raw/` begitu diunduh; analisis selalu dari snapshot |
| Banyak data kosong di wilayah atau jenis pasar tertentu | Ukur kelengkapan di Fase 3; tampilkan coverage di dashboard; jangan bandingkan wilayah dengan data terlalu sedikit |
| Nama wilayah PIHPS vs BPS tidak cocok | Tabel mapping manual `dim_wilayah` dengan kode BPS |
| Scope terlalu besar | Mulai dari 1 jenis pasar (tradisional) dan level provinsi; jenis pasar lain dan kab/kota ditambahkan setelah versi pertama selesai |
