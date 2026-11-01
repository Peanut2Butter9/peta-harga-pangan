# Fase 5 — Dashboard Tableau Public

Dashboard untuk tim procurement: tiga halaman yang menjawab **berapa harga sekarang**, **di mana lebih mahal**, dan **kapan harus waspada serta beli di mana**.

> 🔗 **Link Tableau Public:** [Peta Harga Pangan Indonesia](https://public.tableau.com/app/profile/moh.hasbi.alfarizi/viz/peta_harga_pangan/1Monitorharga)

| Halaman | Pertanyaan | Dari analisis |
|---|---|---|
| 1 · Monitor harga | Berapa harga minggu ini, naik atau turun, dan bulan apa biasanya mahal? | Q1, Q5 |
| 2 · Peta wilayah | Provinsi mana yang lebih mahal dari nasional, dan strategi apa untuk tiap kelompok provinsi? | Q2, Q8 |
| 3 · Rantai pasok & risiko | Beli di mata rantai mana? Apakah ada sinyal kenaikan dari Jawa? Kapan lonjakan musiman terjadi? | Q3, Q4, Q6, Q7 |

**Pembagian peran di fase ini:**

| Tool | Peran |
|---|---|
| **SQL** | Membentuk data untuk Tableau ([`sql/05_exports.sql`](../sql/05_exports.sql)). Menghitung perubahan mingguan, bulanan, dan tahunan dengan window function `RANGE` berbasis tanggal, ringkasan rantai pasok per provinsi, dan sinyal peringatan dini |
| **Python** | Menjalankan ekspor dan pengecekannya ([`src/export_tableau.py`](../src/export_tableau.py)), serta menyumbang hasil analisis (cluster, lead-lag, uji hari besar) |
| **Tableau** | Relationship antartabel, parameter, LOD expression, parameter action, dan desain dashboard |

---

## 1. Data untuk Tableau

Tableau Public tidak bisa terhubung ke PostgreSQL, jadi setiap tabel diekspor ke CSV di `data/exports/`, lalu semuanya digabung ke **`dashboard_pangan.xlsx`**, satu sheet per tabel. Tableau membuka file Excel ini, bukan CSV-nya.

Kenapa Excel? Untuk CSV, Tableau menebak pemisah kolom dan tanda desimal dari locale komputer. Di Mac dengan region Indonesia (desimal = koma), kolom `perubahan_*` terbaca sebagai teks, dan `jenis_pasar.csv` dipotong di tanda `_` karena koma dikira tanda desimal. Sel Excel menyimpan tipenya sendiri (angka, tanggal, boolean), jadi hasilnya sama di komputer mana pun.

Tabel fakta hanya berisi ID dan angka, sedangkan nama-namanya ada di tabel dimensi, sama seperti star schema di mart. Dengan cara ini file terbesar hanya 32 MB.

| Sheet / CSV | Grain | Baris | Sumber | Dipakai di |
|---|---|---|---|---|
| `harga_mingguan.csv` | minggu × provinsi × varian × jenis pasar | 683.837 | SQL | Halaman 1 (KPI, tren) |
| `harga_bulanan.csv` | bulan × provinsi × varian × jenis pasar | 157.811 | SQL | Halaman 1 (kalender), halaman 2 |
| `rantai_pasok.csv` | varian × jenis pasar (12 bulan terakhir) | 84 | SQL | Halaman 3 |
| `sinyal_jawa.csv` | minggu × varian (pasar tradisional) | 9.616 | SQL | Halaman 3 |
| `risiko_hari_besar.csv` | hari besar × varian | 42 | notebook 02 | Halaman 3 |
| `provinsi.csv` | provinsi (+ baris Nasional) | 35 | SQL + koordinat + notebook 03 & 04 | dimensi |
| `komoditas.csv` | varian | 21 | SQL | dimensi |
| `jenis_pasar.csv` | jenis pasar | 4 | SQL | dimensi |

Kolom penting:
- `minggu` adalah hari **Jumat** penutup minggu (Sabtu–Jumat), sama dengan analisis Q7.
- `perubahan_1_minggu`, `perubahan_4_minggu`, `perubahan_52_minggu`, `perubahan_bulanan`, dan `perubahan_tahunan` adalah rasio (0,05 = 5%). Nilainya kosong kalau periode pembandingnya tidak ada datanya.
- `persentil_sentra_jawa` adalah peringkat kenaikan minggu itu di sentra Jawa (Jawa Barat, Jawa Tengah, Jawa Timur), dibanding semua minggu 2018–2026 untuk varian yang sama. Nilai 0,9 berarti termasuk 10% kenaikan tertinggi. Ambangnya memakai persentil, bukan persen kenaikan, karena naik 5% seminggu itu biasa untuk cabai tapi ekstrem untuk beras.
- `lat`/`lon` di `provinsi.csv` adalah koordinat ibu kota provinsi ([`data/reference/koordinat_provinsi.csv`](../data/reference/koordinat_provinsi.csv)), sebagai cadangan kalau Tableau tidak mengenali nama provinsi.

Untuk membuat ulang semua file (setelah `build_warehouse.py` dan notebook 02–04):

```bash
uv run python src/export_tableau.py
```

Script ini juga mengecek bahwa kunci tiap file unik, semua ID punya pasangan di tabel dimensi, harga terisi, dan data sampai minggu terakhir, lalu menulis `dashboard_pangan.xlsx` (~35 detik). Tiga file terbesar (`harga_mingguan.csv`, `harga_bulanan.csv`, `dashboard_pangan.xlsx`) tidak di-commit ke git karena bisa dibuat ulang.

---

## 2. Desain

### Tata letak (ukuran tetap 1200 × 800 px)

**1 · Monitor harga**
```
┌──────────────────────────────────────────────────────────────────────────┐
│ Berapa harga pangan minggu ini?             [1 Monitor][2 Peta][3 Risiko]│
│ Data s.d. 30 Okt 2026 · Sumber: PIHPS Nasional, Bank Indonesia           │
│ Varian [Cabai Rawit Merah ▾]  Wilayah [Nasional ▾]  Pasar [Tradisional ▾]│
├────────────────┬────────────────┬────────────────┬───────────────────────┤
│ Harga minggu   │ Perubahan      │ Perubahan      │ Selisih vs            │
│ ini            │ 4 minggu       │ 1 tahun        │ nasional              │
│ Rp98.910       │ ▼ 1,4%         │ ▲ 144,3%       │ —                     │
├────────────────┴────────────────┴────────────────┴───────────────────────┤
│ Harga per minggu: wilayah terpilih vs nasional     Rentang [3 tahun ▾]   │
│ (garis)                                                                  │
├──────────────────────────────────────────────────────────────────────────┤
│ Kapan harga biasanya naik? Perubahan bulanan, tahun × bulan (heatmap)    │
└──────────────────────────────────────────────────────────────────────────┘
```

**2 · Peta wilayah**
```
┌──────────────────────────────────────────────────────────────────────────┐
│ Di mana harga lebih mahal dari nasional?    [1 Monitor][2 Peta][3 Risiko]│
│ Varian [▾]  Pasar [▾]  Tahun [2026 ▾]   Klik provinsi → dipakai di hal. 1│
├────────────────────────────────────────────────┬─────────────────────────┤
│ Peta: selisih vs nasional                      │ Peringkat provinsi      │
│ (biru = lebih murah, merah = lebih mahal)      │ (bar, urut menurun)     │
├────────────────────────────────────────────────┤                         │
│ Tiga kelompok provinsi (scatter) + strategi    │                         │
└────────────────────────────────────────────────┴─────────────────────────┘
```

**3 · Rantai pasok & risiko**
```
┌──────────────────────────────────────────────────────────────────────────┐
│ Kapan harus waspada, dan beli di mana?      [1 Monitor][2 Peta][3 Risiko]│
│ Varian [▾]   Ambang sinyal [10% tertinggi ▾]                             │
├────────────────────────────┬─────────────────────────────────────────────┤
│ Status sinyal minggu ini   │ Perubahan mingguan: sentra Jawa vs luar     │
│ (teks)                     │ Jawa, 52 minggu terakhir (garis)            │
├────────────────────────────┼─────────────────────────────────────────────┤
│ Harga di tiap mata rantai  │ Lonjakan di atas normal: Lebaran vs Nataru  │
│ (bar, 4 jenis pasar)       │ (dot plot per varian; klik → ganti varian)  │
└────────────────────────────┴─────────────────────────────────────────────┘
```

### Aturan visual

Aturannya sama dengan grafik di notebook ([`src/viz.py`](../src/viz.py)), supaya README, notebook, dan dashboard terlihat seperti satu sistem.

- **Palet:** salin [`tableau/Preferences.tps`](../tableau/Preferences.tps) ke `~/Documents/My Tableau Repository/` (folder ini dibuat Tableau Public saat pertama kali dibuka), lalu buka ulang Tableau Public. Muncul tiga palet:
  - **Pangan - Kategori** untuk identitas. Pakai berurutan dan jangan diulang. Untuk scatter dan peta, maksimal 3 warna pertama.
  - **Pangan - Divergen** untuk selisih dan perubahan. Biru = turun atau lebih murah, abu-abu = 0, merah = naik atau lebih mahal. Selalu atur **Center = 0**, dan biarkan *Use Full Color Range* **tidak** dicentang.
  - **Pangan - Sekuensial** untuk besaran.
  - **Pangan - Nasional vs Wilayah** khusus untuk garis tren: Nasional abu-abu, Wilayah terpilih biru. Pilih palet ini lalu klik *Assign Palette*, sehingga tidak perlu mengetik kode hex. Pastikan kedua seri sedang tampil, misalnya dengan memilih wilayah selain Nasional untuk sementara.
- **Warna mengikuti entitas, bukan peringkat.** Contohnya, "Nasional" selalu abu-abu `#898781` dan "Wilayah terpilih" selalu biru `#2a78d6`, apa pun wilayah yang dipilih.
- **Teks** selalu memakai warna teks (`#0b0b0b` untuk judul, `#52514e` untuk subjudul dan label), bukan warna seri.
- **Latar** `#fcfcfb`. Grid tipis `#e1e0d9`, tanpa border dan tanpa row banding. Garis 2 px.
- **Satu sumbu per grafik.** Jangan pakai dual axis.
- **Legenda** wajib kalau ada 2 seri atau lebih. Label langsung secukupnya, jangan angka di setiap titik.
- **Bahasa:** pakai *File → Workbook Locale → Indonesian*, supaya angka tampil sebagai `Rp98.910` dan `1,4%`, dan nama bulan dalam bahasa Indonesia.

---

## 3. Langkah membangun

### 3.1 Persiapan

1. Install **Tableau Public** (Tableau Desktop Public Edition, gratis), dari tableau.com/products/public/download atau dengan `brew install --cask tableau-public`. Akun Tableau Public diperlukan untuk publikasi.
2. Salin `tableau/Preferences.tps` seperti di atas, lalu buka Tableau Public.
3. Jalankan `uv run python src/export_tableau.py` supaya data di `data/exports/` paling baru.
4. Simpan pekerjaan secara lokal sejak awal: *File → Save As* → `tableau/peta_harga_pangan.twbx` (Tableau Packaged Workbook). Sejak 2024 versi gratis bisa menyimpan ke komputer, tidak hanya ke Tableau Public. Selalu simpan lewat menu *File*, karena di Tableau Public **Cmd+S berarti *Save to Tableau Public***, bukan simpan ke komputer.

### 3.2 Sambungkan data (5 data source)

Di halaman awal pilih *Connect → Microsoft Excel*, lalu buka `data/exports/dashboard_pangan.xlsx`. Panel kiri menampilkan 8 sheet. Seret sheet tabel utama ke kanvas, lalu seret sheet dimensi ke sampingnya. Tableau akan membuat **relationship** (garis penghubung). Semua garis harus berpangkal di tabel utama, membentuk bintang, bukan rantai. Cek kolom penghubungnya di setiap garis.

| Data source (ganti namanya) | Tabel utama | Relationship |
|---|---|---|
| **Mingguan** | `harga_mingguan` | `provinsi` (wilayah_id), `komoditas` (komoditas_id), `jenis_pasar` (jenis_pasar_id) |
| **Bulanan** | `harga_bulanan` | sama dengan Mingguan |
| **Rantai Pasok** | `rantai_pasok` | `komoditas`, `jenis_pasar` |
| **Sinyal** | `sinyal_jawa` | `komoditas` |
| **Risiko** | `risiko_hari_besar` | `komoditas` |

Data source berikutnya ditambahkan lewat *Data → New Data Source → Microsoft Excel*, dengan file yang sama.

Setelah itu, di setiap data source:
- Tableau otomatis merapikan nama kolom (`perubahan_4_minggu` jadi **Perubahan 4 Minggu**). Rumus di bawah memakai nama yang sudah dirapikan. Kalau ada dua kolom bernama sama, misalnya **Wilayah Id**, pakai yang dari tabel fakta.
- Ubah *Default Properties → Aggregation* menjadi **Average** untuk `Harga` dan semua kolom `Perubahan …`.
- Pastikan `Minggu` dan `Bulan` bertipe *Date* (bukan *Date & Time*), dan semua kolom `… Id` menjadi *Dimension*.

### 3.3 Parameter

Parameter dipakai sebagai pengganti filter, karena satu parameter bisa mengendalikan semua data source sekaligus.

| Parameter | Tipe | Isi | Default |
|---|---|---|---|
| **Pilih Varian** | String, *List* | *When workbook opens:* `Varian` | Cabai Rawit Merah |
| **Pilih Wilayah** | String, *List* | *When workbook opens:* `Wilayah` | Nasional |
| **Pilih Pasar** | String, *List* | *When workbook opens:* `Jenis Pasar` | Pasar Tradisional |
| **Rentang Tahun** | Integer, *List* | 1 = "1 tahun", 3 = "3 tahun", 5 = "5 tahun", 9 = "Semua" | 3 |
| **Tahun Peta** | Integer, *Range* | 2018 … 2026, step 1 | 2026 |
| **Ambang Sinyal** | Float, *List* | 0,8 = "20% tertinggi", 0,9 = "10% tertinggi", 0,95 = "5% tertinggi" | 0,9 |

Dengan region Indonesia, Tableau memakai koma sebagai tanda desimal, jadi nilai Ambang Sinyal diketik `0,9`, bukan `0.9`.

### 3.4 Calculated field

Filter berbentuk kalkulasi boolean. Taruh di *Filters*, lalu pilih **True**. Kalkulasi filter dibuat ulang di setiap data source yang membutuhkannya, dengan rumus yang sama.

**Semua data source yang punya `Varian`:**
```
// F Varian
[Varian] = [Pilih Varian]
```

**Mingguan dan Bulanan:**
```
// F Pasar
[Jenis Pasar] = [Pilih Pasar]

// F Wilayah Terpilih
[Wilayah] = [Pilih Wilayah]

// F Wilayah dan Nasional
[Wilayah] = [Pilih Wilayah] OR [Is Nasional]

// Seri  — warna garis tetap, apa pun wilayah yang dipilih
IF [Is Nasional] THEN "Nasional" ELSE "Wilayah terpilih" END
```

**Mingguan:**
```
// F Rentang  — {MAX(...)} = tanggal terakhir di seluruh data
[Minggu] > DATEADD('year', -[Rentang Tahun], {MAX([Minggu])})

// Minggu Terakhir  — minggu terakhir yang ada datanya, per seri harga
{FIXED [Wilayah Id], [Komoditas Id], [Jenis Pasar Id] : MAX([Minggu])}

// Harga Nasional  — harga nasional di minggu, varian, dan pasar yang sama
{FIXED [Minggu], [Komoditas Id], [Jenis Pasar Id] : AVG(IF [Wilayah Id] = 0 THEN [Harga] END)}

// KPI Harga
SUM(IF [Minggu] = [Minggu Terakhir] THEN [Harga] END)

// KPI 4 Minggu
SUM(IF [Minggu] = [Minggu Terakhir] THEN [Perubahan 4 Minggu] END)

// KPI 1 Tahun
SUM(IF [Minggu] = [Minggu Terakhir] THEN [Perubahan 52 Minggu] END)

// KPI vs Nasional
[KPI Harga] / SUM(IF [Minggu] = [Minggu Terakhir] THEN [Harga Nasional] END) - 1
```

LOD `FIXED` dihitung **sebelum** filter biasa. Karena itu, `Harga Nasional` tetap terisi walaupun baris Nasional sudah tersaring oleh `F Wilayah Terpilih`. Ini konsep LOD yang paling sering ditanyakan di interview.

**Bulanan:**
```
// F Tahun Peta
YEAR([Bulan]) = [Tahun Peta]

// Harga Nasional Bulanan
{FIXED [Bulan], [Komoditas Id], [Jenis Pasar Id] : AVG(IF [Wilayah Id] = 0 THEN [Harga] END)}

// Selisih vs Nasional
AVG([Harga]) / AVG([Harga Nasional Bulanan]) - 1

// Strategi Cluster  — dari playbook Q8 (docs/04)
CASE [Cluster]
WHEN "Murah tapi bergejolak" THEN "Beli lokal, kunci harga cabai & bawang lewat kontrak. Bisa jadi hub pasokan untuk provinsi lain."
WHEN "Mendekati rata-rata" THEN "Anggaran standar nasional. Pantau sinyal kenaikan dari sentra Jawa."
WHEN "Mahal tapi stabil" THEN "Anggaran premium 10–30%. Kontrak jangka panjang dengan supplier tetap, perhatikan ongkos kirim."
END
```

**Sinyal:**
```
// F 52 Minggu
[Minggu] > DATEADD('week', -52, {MAX([Minggu])})

// F Minggu Ini
[Minggu] = {MAX([Minggu])}

// Status Sinyal
IF SUM([Persentil Sentra Jawa]) >= [Ambang Sinyal] THEN "WASPADA"
ELSEIF SUM([Persentil Sentra Jawa]) <= 1 - [Ambang Sinyal] THEN "TURUN TAJAM"
ELSE "NORMAL"
END

// Luar Jawa Setelah Sinyal  — uji historis: rata-rata perubahan luar Jawa seminggu setelah sinyal
{FIXED [Komoditas Id] : AVG(IF [Persentil Sentra Jawa] >= [Ambang Sinyal]
                            THEN [Perubahan Luar Jawa Minggu Depan] END)}

// Luar Jawa Minggu Biasa
{FIXED [Komoditas Id] : AVG(IF [Persentil Sentra Jawa] < [Ambang Sinyal]
                            THEN [Perubahan Luar Jawa Minggu Depan] END)}
```

**Risiko:**
```
// Urutan Nataru  — urutkan varian berdasarkan lonjakan Nataru
{FIXED [Komoditas Id] : MAX(IF [Hari Besar] = "Nataru" THEN [Median Kelebihan] END)}

// Status Uji
IF [Signifikan] THEN "Signifikan (Holm p < 0,05)" ELSE "Belum signifikan" END
```

**Format angka** (klik kanan field → *Default Properties → Number Format → Custom*):

| Field | Format |
|---|---|
| Harga, KPI Harga, Harga Median Provinsi | `"Rp"#,##0` |
| KPI 4 Minggu, KPI 1 Tahun, KPI vs Nasional | `▲ 0.0%;▼ 0.0%;"—"` |
| Selisih vs Nasional, Perubahan …, Median Kelebihan | `+0%;-0%;0%` |
| Selisih Vs Tradisional | `+0%;-0%;"acuan"` |

### 3.5 Sheet

| Sheet | Data source | Bangun | Filter |
|---|---|---|---|
| **KPI** | Mingguan | *Columns:* Measure Names. *Text:* Measure Values (KPI Harga, KPI 4 Minggu, KPI 1 Tahun, KPI vs Nasional). Ganti alias Measure Names menjadi label kartu. Mark *Text*, ukuran angka 22 pt | F Varian, F Pasar, F Wilayah Terpilih |
| **Tren Harga** | Mingguan | *Columns:* Minggu (Exact Date, continuous). *Rows:* AVG(Harga). *Color:* Seri, palet Pangan - Nasional vs Wilayah (Wilayah terpilih `#2a78d6`, Nasional `#898781`). Judul dinamis: "Harga `<Pilih Varian>` per minggu, `<Pilih Wilayah>` vs nasional" | F Varian, F Pasar, F Wilayah dan Nasional, F Rentang |
| **Kalender** | Bulanan | *Columns:* MONTH(Bulan) diskret. *Rows:* YEAR(Bulan) diskret. Mark *Square*. *Color:* AVG(Perubahan Bulanan), palet Divergen, Center 0. *Label:* AVG(Perubahan Bulanan) | F Varian, F Pasar, F Wilayah Terpilih |
| **Peta** | Bulanan | Lihat [3.6](#36-peta-provinsi). *Color:* Selisih vs Nasional (Divergen, Center 0). *Tooltip:* Wilayah, Cluster, AVG(Harga), AVG(Harga Nasional Bulanan), Selisih | F Varian, F Pasar, F Tahun Peta, Is Nasional = False |
| **Peringkat** | Bulanan | *Rows:* Wilayah, urut menurun berdasarkan Selisih vs Nasional. *Columns:* Selisih vs Nasional. *Color:* sama dengan Peta. *Label:* selisih | sama dengan Peta |
| **Kelompok Provinsi** | Bulanan | *Columns:* AVG(Level Bumbu). *Rows:* AVG(Ayunan Cabai Bawang). *Detail:* Wilayah. *Color:* Cluster (Murah tapi bergejolak = warna 1, Mendekati rata-rata = warna 2, Mahal tapi stabil = warna 3). *Tooltip:* Strategi Cluster. Grafik ini tidak ikut filter varian, karena cluster dihitung sekali dari 4 fitur | Is Nasional = False |
| **Status Sinyal** | Sinyal | Mark *Text*: Status Sinyal (besar), lalu "Sentra Jawa minggu ini: `SUM(Perubahan Sentra Jawa)`". Di bawahnya: "Secara historis, seminggu setelah sinyal seperti ini harga luar Jawa berubah rata-rata `AVG(Luar Jawa Setelah Sinyal)` (minggu biasa: `AVG(Luar Jawa Minggu Biasa)`)" | F Varian, F Minggu Ini |
| **Sentra Jawa vs Luar Jawa** | Sinyal | *Columns:* Minggu (Exact Date). *Rows:* Measure Values (AVG Perubahan Sentra Jawa, AVG Perubahan Luar Jawa). *Color:* Measure Names (Sentra Jawa = warna 1, Luar Jawa = warna 2). Reference line konstan di 0 | F Varian, F 52 Minggu |
| **Rantai Pasok** | Rantai Pasok | *Rows:* Jenis Pasar, urut berdasarkan Urutan Rantai Pasok. *Columns:* SUM(Harga Median Provinsi). Satu warna `#2a78d6`. *Label:* harga + Selisih Vs Tradisional. *Tooltip:* "data dari `<N Provinsi>` provinsi, `<Periode Awal>`–`<Periode Akhir>`" | F Varian |
| **Kalender Risiko** | Risiko | *Rows:* Varian, urut menurun berdasarkan Urutan Nataru. *Columns:* AVG(Median Kelebihan). Mark *Shape*. *Color:* Hari Besar (Lebaran = warna 1, Nataru = warna 2). *Shape:* Status Uji (lingkaran penuh = signifikan, lingkaran kosong = belum). Reference line di 0. *Tooltip:* Median Lonjakan, Median Kenaikan Normal, "naik lebih dari normal di `<Naik Lebih Dari Normal>` dari `<N Kejadian>` tahun" | — |

Untuk setiap sheet: hapus border dan row banding, buat grid tipis, matikan zero line kecuali yang memang dipakai sebagai acuan, dan tulis tooltip dalam bahasa Indonesia.

### 3.6 Peta provinsi

**Cara A: peta berwarna (filled map).** Klik kanan `Wilayah` → *Geographic Role → State/Province*, lalu double-click `Wilayah`.
- Kalau di kanan bawah muncul "N unknown", klik tulisan itu → *Edit Locations*. Set *Country* = Indonesia, lalu cocokkan nama yang belum dikenali secara manual. Yang biasanya perlu dicocokkan: DKI Jakarta, DI Yogyakarta, dan Kepulauan Bangka Belitung.
- Kalau ada provinsi yang tidak tersedia di daftar Tableau, pakai Cara B.

**Cara B: peta titik (selalu berhasil).**
1. Set `Lat` → *Geographic Role → Latitude*, dan `Lon` → *Longitude*.
2. Taruh `Lon` di *Columns* dan `Lat` di *Rows*, lalu `Wilayah` di *Detail*.
3. Pakai mark *Circle* dengan ukuran tetap dan border putih tipis.

Titiknya ada di ibu kota provinsi.

### 3.7 Dashboard

1. Untuk setiap halaman: *New Dashboard*, *Size → Fixed 1200 × 800*, latar `#fcfcfb`. Susun dengan container vertikal dan horizontal sesuai tata letak di bagian 2.
2. **Header:** judul berupa pertanyaan (16 pt, tebal), lalu baris sumber data dan tanggal data terakhir (10 pt, `#52514e`).
3. **Kontrol:** tampilkan parameter yang relevan (*Show Parameter*) dalam satu baris di bawah header.
4. **Navigasi:** tambahkan objek *Navigation* ke setiap halaman, ditaruh di kanan atas.
5. **Action:**
   - Halaman 2: *Change Parameter* dari sheet Peta dan Peringkat ke **Pilih Wilayah** (field Wilayah, *On Select*). Provinsi yang diklik langsung terpakai di halaman 1. Tambahkan juga *Highlight* pada Wilayah di antara Peta, Peringkat, dan Kelompok Provinsi.
   - Halaman 3: *Change Parameter* dari Kalender Risiko ke **Pilih Varian** (field Varian). Mengklik satu varian langsung mengganti grafik rantai pasok dan sinyal.
6. **Catatan cara membaca:** satu baris kecil di bawah grafik yang perlu penjelasan. Contohnya, di Kalender Risiko: "Kenaikan H-14 dibanding H-90..H-61, dikurangi kenaikan normal di tanggal lain tahun yang sama".

### 3.8 Cek angka

Dengan default (Cabai Rawit Merah, Nasional, Pasar Tradisional, 2026), dashboard harus menampilkan angka berikut. Kalau berbeda, biasanya penyebabnya agregasi (SUM vs AVG) atau filter yang belum dipasang.

| Sheet | Angka yang benar |
|---|---|
| KPI | Rp98.910 (minggu 30 Okt 2026) · 4 minggu ▼ 1,4% · 1 tahun ▲ 144,3% · vs nasional — |
| Kalender (Nasional) | Sep 2026 +39%, Okt 2026 +11% |
| Peta / Peringkat | 32 provinsi. Termahal: Maluku Utara +52%, Maluku +48%, Papua +38%. Termurah: Sumatera Utara −38%, Sulawesi Barat −30%, Sulawesi Selatan −27% |
| Rantai Pasok | Produsen Rp50.074 (−29%) · Pedagang Besar Rp58.204 (−17%) · Pasar Tradisional Rp70.418 (acuan) · Pasar Modern Rp105.283 (+46%) |
| Status Sinyal | NORMAL. Sentra Jawa −8,9% minggu ini. Seminggu setelah sinyal, luar Jawa rata-rata +11,6% (minggu biasa −0,2%) |
| Kalender Risiko | Tiga teratas Nataru: Cabai Rawit Merah +35%, Cabai Rawit Hijau +27%, Bawang Merah Ukuran Sedang +23% di atas normal. Yang signifikan hanya dua, keduanya Lebaran: Daging Sapi Kualitas 1 +2,6% dan Kualitas 2 +2,1% (Holm p = 0,008) |

### 3.9 Publikasi

1. *File → Save to Tableau Public As…*, lalu masuk dengan akun Tableau Public-mu. Beri nama **Peta Harga Pangan Indonesia**.
2. Di halaman workbook (browser):
   - Matikan *Show workbook sheets as tabs*, karena navigasi sudah memakai tombol.
   - Isi deskripsi singkat dan link ke repo GitHub.
   - Izinkan download supaya orang lain bisa membuka workbook-nya.
3. Simpan juga versi lokal terakhir (*File → Save*) ke `tableau/peta_harga_pangan.twbx`, supaya file di repo sama dengan yang dipublikasikan.
4. Ambil screenshot halaman 1 untuk `reports/figures/05_dashboard.png`, lalu isi link Tableau Public di README dan di bagian atas dokumen ini.

---

## 4. Insight yang ditampilkan dashboard

1. **Cabai rawit merah naik 144% dalam setahun** (Rp98.910/kg di pasar tradisional, minggu 30 Okt 2026), walaupun 4 minggu terakhir mulai turun.
2. **Sinyal dari sentra Jawa bisa dipakai.** Setelah minggu dengan kenaikan 10% tertinggi di sentra Jawa, harga cabai rawit merah di luar Jawa naik rata-rata **11,6% minggu berikutnya**. Di minggu biasa, perubahannya −0,2%. Pola yang sama berlaku untuk bawang merah (+5,5% vs −0,4%) dan telur (+1,9% vs −0,1%), tapi tidak untuk daging sapi.
3. **Membeli dari pedagang besar 17–20% lebih murah** daripada pasar tradisional untuk cabai. Pasar modern 46–72% lebih mahal.
4. **Nataru lebih berisiko daripada Lebaran** untuk cabai, bawang merah, dan telur.
5. **Maluku, Maluku Utara, dan Papua** membayar 38–52% di atas harga nasional untuk cabai rawit merah pada 2026.

## 5. Keterbatasan

- Uji sinyal di dashboard bersifat historis (in-sample). Persentil dihitung dari seluruh data 2018–2026, jadi ini gambaran pola, bukan uji model prediksi.
- Data pasar modern, pedagang besar, dan produsen baru tersedia sejak 2023. Untuk tahun 2018–2022, peta dan kalender hanya terisi kalau yang dipilih Pasar Tradisional.
- Rantai pasok minyak goreng curah di pasar modern hanya dari 7 provinsi. Jumlah provinsi ditampilkan di tooltip.
- Harga dari provinsi yang datanya jarang diperbarui (misalnya DKI Jakarta dan Maluku Utara) membuat sinyal lead-lag kurang tajam (lihat [docs/04](04_analisis_python.md)). Penandanya ada di `provinsi.csv` (`data_jarang_diperbarui`).
- Koordinat titik peta adalah ibu kota provinsi, bukan titik tengah wilayah.
