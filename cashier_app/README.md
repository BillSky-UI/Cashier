# Aplikasi Kasir (POS) — Flutter

Aplikasi Point of Sales (POS) Android offline berbasis Flutter, menggunakan **sqflite** untuk penyimpanan lokal dan **Material 3** untuk antarmuka.

## Fitur

- **Manajemen Produk**: tambah, edit, cari, dan hapus produk (nama, harga, stok, kategori), dengan penanda stok menipis/habis otomatis.
- **Kasir / Transaksi**: klik produk untuk masuk keranjang, hitung otomatis subtotal, biaya admin, diskon/voucher, total, dan kembalian. Pembayaran tunai memakai **keypad angka in-app** (tanpa keyboard sistem) plus tombol uang cepat (Pas, 5k, 10k, 20k, 50k, 100k).
- **Riwayat Transaksi**: lihat detail & hapus riwayat.
- **Laporan & Tutup Kasir**: rekap harian & bulanan (penjualan, item, metode pembayaran). **Pemilih tanggal interaktif** — ketuk hari tertentu untuk melihat rincian harian (total pendapatan, total pengeluaran, jumlah transaksi). Serta **ekspor PDF** laporan bulanan dengan rincian pengeluaran.
- **Arsip Rekap Bulanan**: di awal setiap bulan baru data rekap bulan sebelumnya otomatis "ditutup" dan disimpan sebagai PDF permanen di dalam penyimpanan aplikasi (`.../rekap/`). Arsip PDF bulan-bulan lalu dapat dibuka kapan saja (via galeri PDF eksternal) atau dibagikan.
- **Pengeluaran Toko**: catat biaya operasional di luar penjualan (dipakai dalam laporan & PDF).
- **Backup & Restore**: simpan salinan database ke perangkat/cloud dan pulihkan kembali.
- **Kustomisasi Struk**: atur nama/alamat/telepon toko, **logo toko** (dari galeri atau logo bawaan, tampil di bagian atas struk), dan **footer** pesan penutup (tampil di bagian bawah struk) — berlaku untuk preview digital, struk termal, dan PDF.
- **Penyimpanan Lokal**: semua data (produk, transaksi, pengeluaran) tersimpan di database SQLite pada memori *handphone*, sepenuhnya *offline*.
- **UI Material 3**: responsif, portrait-friendly; pada layar lebar kartu produk & panel keranjang tampil berdampingan.

## Struktur Folder

```
cashier_app/
├── pubspec.yaml                  # Konfigurasi dependensi
├── analysis_options.yaml
├── android/                      # Proyek Android (native)
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/com/cashier/cashier_app/MainActivity.kt
│       └── res/                  # Ikon & tema
├── lib/
│   ├── main.dart                 # Entry point aplikasi
│   ├── models/
│   │   ├── product.dart          # Model Produk
│   │   ├── transaction.dart      # Model Transaksi & Item
│   │   ├── category.dart         # Model Kategori
│   │   ├── admin_fee.dart        # Model Biaya Admin
│   │   └── expense.dart          # Model Pengeluaran
│   ├── database/
│   │   └── database_helper.dart  # Helper sqflite (CRUD + migrasi)
│   ├── screens/
│   │   ├── home_screen.dart      # Navigasi bawah (tab)
│   │   ├── pos_screen.dart       # Halaman Kasir (+ keypad tunai)
│   │   ├── product_screen.dart   # Manajemen Produk
│   │   ├── history_screen.dart   # Riwayat Transaksi
│   │   ├── report_screen.dart    # Laporan & ekspor PDF
│   │   ├── expense_screen.dart   # Pengeluaran Toko
│   │   ├── settings_screen.dart  # Pengaturan (tema, struk, backup)
│   │   ├── recap_archive_screen.dart # Arsip rekap PDF bulanan
│   │   └── receipt_screen.dart   # Preview / struk digital
│   ├── services/
│   │   ├── app_settings.dart     # Preferensi & identitas toko/struk
│   │   ├── app_bus.dart          # Sinyal muat-ulang antar layar
│   │   ├── backup_service.dart   # Backup & restore database
│   │   ├── pdf_report_service.dart # Ekspor laporan PDF
│   │   ├── recap_archive_service.dart # Arsip & reset rekap bulanan
│   │   └── thermal_printer.dart  # Cetak termal (BT/USB/network)
│   ├── widgets/
│   │   ├── product_grid_card.dart# Kartu produk di grid kasir
│   │   ├── receipt_paper.dart    # Layout struk (preview)
│   │   └── cash_input_pad.dart   # Keypad angka & uang cepat
│   └── utils/
│       └── format.dart           # Format Rupiah & tanggal
└── test/
    └── widget_test.dart
```

## Cara Build ke APK

> Flutter harus terinstal: https://flutter.dev (gunakan versi stable terbaru) +
> Android Studio/SDK.

Versi aplikasi diatur pada `pubspec.yaml` (mis. `version: 1.4.1+11` → `versionName 1.4.1`, `versionCode 11`).

```bash
cd cashier_app

# 1) Regenerasi folder platform agar versi Gradle/Kotlin cocok dengan SDK Flutter Anda.
#    (lib/ dan pubspec.yaml TIDAK terpengaruh & tetap dipertahankan)
flutter create .

# 2) Unduh dependensi
flutter pub get

# 3) Build APK release (Android)
flutter build apk --release
```

Hasil build tersimpan di:
```
build/app/outputs/flutter-apk/app-release.apk
```

### Build + Rename Otomatis (BillFlow-vX.Y.Z.apk)

Untuk menghasilkan file release yang langsung diberi nama sesuai versi (mis. `BillFlow-v1.4.1.apk`), gunakan skrip bawaan:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1
```

Skrip ini menjalankan build release lalu menyalin output menjadi
`build/app/outputs/flutter-apk/BillFlow-v<versionName>.apk`.

### Instalasi ke HP Android

```bash
flutter install            # jika HP terhubung via USB (mode developer)
```
atau pindahkan `app-release.apk` (atau `BillFlow-vX.Y.Z.apk`) ke HP dan install secara manual.