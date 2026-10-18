# Changelog

Semua perubahan penting pada repo ini didokumentasikan di sini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/).

## [Unreleased]

### Added

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

- README (ID & EN): banner, badge (status CI Lint, lisensi, runner, desktop,
  PRs welcome), diagram alur Mermaid, bagian Kontribusi, dan slot galeri
  screenshot (dikomentari sampai gambar asli tersedia).

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
