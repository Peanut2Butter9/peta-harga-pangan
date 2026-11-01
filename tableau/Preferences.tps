<?xml version='1.0'?>
<!--
  Palet warna dashboard, sama dengan src/viz.py (grafik notebook).
  Salin file ini ke folder repository Tableau, lalu buka ulang Tableau:
    Tableau Public : ~/Documents/My Tableau Public Repository/Preferences.tps
    Tableau Desktop: ~/Documents/My Tableau Repository/Preferences.tps
  Palet yang sudah dipakai ikut tersimpan di workbook, jadi tetap tampil setelah dipublikasikan.
-->
<workbook>
  <preferences>
    <!-- Kategori: pakai berurutan dari atas, jangan diulang. Untuk peta dan scatter, maksimal 3 warna pertama. -->
    <color-palette name="Pangan - Kategori" type="regular">
      <color>#2a78d6</color>
      <color>#eb6834</color>
      <color>#1baf7a</color>
      <color>#eda100</color>
      <color>#e87ba4</color>
      <color>#008300</color>
      <color>#6250d6</color>
      <color>#e34948</color>
    </color-palette>
    <!-- Sekuensial: besaran (terang = kecil, gelap = besar) -->
    <color-palette name="Pangan - Sekuensial" type="ordered-sequential">
      <color>#cde2fb</color>
      <color>#9ec5f4</color>
      <color>#6da7ec</color>
      <color>#3987e5</color>
      <color>#256abf</color>
      <color>#184f95</color>
      <color>#0d366b</color>
    </color-palette>
    <!-- Divergen: biru = lebih murah / turun, abu-abu = 0, merah = lebih mahal / naik -->
    <color-palette name="Pangan - Divergen" type="ordered-diverging">
      <color>#184f95</color>
      <color>#3987e5</color>
      <color>#9ec5f4</color>
      <color>#f0efec</color>
      <color>#f4b1b0</color>
      <color>#e66767</color>
      <color>#b02a2a</color>
    </color-palette>
  </preferences>
</workbook>
