# Changelog

Semua perubahan penting pada repo ini didokumentasikan di sini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/).

## [Unreleased]

### Added

- `scripts/crd-web-auth.py` — server form otorisasi Chrome Remote Desktop
  berbasis Python stdlib. URL memakai token acak 128-bit, server hanya bind ke
  `127.0.0.1`, perintah divalidasi ketat, status ditampilkan live, dan hanya
  satu perintah yang diproses pada satu waktu.
- `.github/workflows/gnome26.yml` — STEP 17 baru: form otorisasi web lewat
  **Cloudflare quick tunnel** setelah desktop siap. Kode OAuth dibuat setelah
  instalasi, window 30 menit, status `waiting/queued/registering/success/failed`,
  retry kode baru tanpa re-run, restart tunnel otomatis, dan fallback opsional
  `crd_host_command`.
- `.github/workflows/lint.yml` — CI yang memvalidasi seluruh file YAML
  (`yamllint`), workflow GitHub Actions (`actionlint`, binary diunduh dari rilis
  resmi dengan verifikasi checksum), dan skrip shell (`shellcheck`). Berjalan
  pada setiap push ke `main` dan setiap pull request.
- `.yamllint.yml` — konfigurasi linter YAML (batas panjang baris dimatikan karena
  workflow berisi perintah shell yang panjang).
- `docs/images/banner.svg` — banner untuk README.
- `docs/adding-screenshots.md` — panduan mengambil screenshot dari sesi CRD dan
  memasukkannya ke repo (3 cara, termasuk drag & drop lewat Chrome di dalam sesi).

### Changed

- `gnome26.yml`: input `crd_host_command` menjadi **opsional** (fallback),
  header/instruksi memakai alur form web, komentar checkout diperbarui, dan
  keep-alive menghitung sisa waktu dari `JOB_START_EPOCH` (bukan `sleep 21600`).
- README (ID & EN): alur utama sekarang **GNOME 26** (Ubuntu 26.04 + form web),
  badge runner, diagram Mermaid, langkah authorize, keamanan token, troubleshooting,
  dan struktur repo diperbarui. Workflow lama `gnome.yml` tetap didokumentasikan
  sebagai legacy.
- `docs/troubleshooting.md`: tambah bagian form web/Cloudflare, registrasi gagal
  tanpa re-run, window 30 menit, dan update runner 26.04.
- `docs/faq.md`: tambah Q&A tentang kode auth setelah desktop siap, retry tanpa
  re-run, Cloudflare quick tunnel, keamanan URL form, dan perbedaan
  `gnome26.yml` vs `gnome.yml`.
- `.github/ISSUE_TEMPLATE/bug_report.yml`: opsi masalah form web, peringatan
  token URL, dan checklist retry tanpa re-run.
- `.github/workflows/lint.yml`: `actionlint` mengabaikan label
  `ubuntu-26.04` yang belum dikenali actionlint 1.7.12.
- `.gitignore`: tambah `__pycache__/` dan `*.pyc` untuk skrip Python baru.

### Fixed

- **Kode OAuth tidak lagi kedaluwarsa selama instalasi.** Registrasi CRD kini
  meminta kode setelah desktop siap lewat form web, bukan di awal run.
- **Registrasi gagal tidak lagi memaksa re-run.** Form aktif lagi setelah
  `failed`; user bisa mengambil kode baru dan submit ulang dalam window 30 menit.
- **Validasi perintah menolak metakarakter shell** (`$(`, backtick, `;`, `&`,
  `|`, `>`, `<`, `\`, newline, dan karakter kontrol).
- **Cleanup tunnel/server deterministik**: SIGTERM, tunggu, lalu SIGKILL bila
  proses tidak berhenti.
- **Prepare System tidak lagi menunggu snap store**: `snapd` + paket transisi
  `firefox`/`thunderbird` dihapus dan di-hold sebelum `apt-get upgrade` di
  `gnome.yml` dan `gnome26.yml`, sehingga upgrade tidak memicu
  “Installing the firefox snap”.

## [1.0.0] - 2026-10-18

Rilis awal repo yang bisa langsung di-fork dan dijalankan.

### Added

- `.github/workflows/gnome.yml` — workflow utama GNOME + Chrome Remote Desktop
  (dipindah dari root ke lokasi yang dikenali GitHub Actions).
- `scripts/safe-upgrade.sh` — helper `apt upgrade` yang tidak memutus sesi CRD
  (menggantikan file yang sebelumnya direferensikan workflow tapi belum ada).
- `README.md` (Indonesia) dan `README.en.md` (English) — panduan *fork & run*
  lengkap.
- `docs/troubleshooting.md` dan `docs/faq.md`.
- `LICENSE` (MIT), `CHANGELOG.md`, `.gitignore`.
- `.github/ISSUE_TEMPLATE/` (bug report + config).
- `.github/dependabot.yml` untuk memperbarui action secara otomatis.

### Fixed

- **Workflow sebelumnya akan GAGAL di step *Install Safe Upgrade Helper***
  karena `scripts/safe-upgrade.sh` tidak ada (step melakukan `exit 1`). Kini file
  tersebut tersedia sehingga workflow bisa selesai sampai CRD siap.
- **Cache `.deb` tidak pernah tersimpan saat job gagal.** `actions/cache` dengan
  `save-always: true` sudah deprecated dan tidak berfungsi sesuai niat
  (sumber: `action.yml` resmi `actions/cache`). Diganti dengan pola resmi
  `actions/cache/restore` + `actions/cache/save` (`if: always()`), dan
  diletakkan sebelum registrasi CRD agar cache tetap tersimpan walau re-run
  diperlukan.
- **KVM/`/dev/kvm` bisa "permission denied".** Ditambahkan udev rule resmi
  (`MODE="0666"`) sebelum menambahkan user `runner` ke grup `kvm`, sehingga
  `virt-manager`, GNOME Boxes, dan QEMU dapat memakai akselerasi hardware.
- **Service CRD bisa tidak berjalan setelah registrasi.** `start-host` mencoba
  `sudo`/`pkexec systemctl enable --now chrome-remote-desktop@<user>`, yang bisa
  gagal senyap tanpa TTY. Ditambahkan fallback `systemctl enable/start` beserta
  laporan status di akhir step registrasi.

### Changed

- Menambahkan header komentar berisi langkah pemakaian di bagian atas workflow.
- Step *Checkout repository* diperjelas (untuk `scripts/safe-upgrade.sh`).

### Notes

- Tidak ada perubahan pada nilai default (device `gnome`, PIN `123456`,
  timezone `Asia/Jakarta`, resolusi `1024x768`, theme Catppuccin Macchiato/Mauve).
