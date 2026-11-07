# Changelog

Semua perubahan penting pada repo ini didokumentasikan di sini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/).

## [Unreleased]

### Added

- `docs/wayland-crd.md` — dokumentasi **terverifikasi** GNOME 26 Wayland di
  Chrome Remote Desktop: arsitektur, bukti run, video AV1/±60 fps, audio
  PipeWire, animasi, langkah verifikasi, dan batasan.
- `docs/images/wayland-proof-2026-11-07.png` — tangkapan compositor otomatis
  dari run 42378799566 sebagai bukti render Wayland (artifact GitHub hanya
  disimpan 3 hari).
- `.github/workflows/cinnamon.yml` — varian **Cinnamon 26** di runner
  `ubuntu-26.04`: Cinnamon 6.4 X11 + Muffin + Nemo (tanpa lightdm/slick-greeter),
  sesi CRD `cinnamon-session`, screensaver/lock off, Catppuccin (GTK + Cinnamon
  shell), Nemo/Terminal shortcuts, device CRD `cinnamon`, dan keep-alive 6 jam.
- `scripts/crd-web-auth.py` — server form otorisasi Chrome Remote Desktop
  berbasis Python stdlib. URL memakai token acak 128-bit, server hanya bind ke
  `127.0.0.1`, perintah divalidasi ketat, status ditampilkan live, dan hanya
  satu perintah yang diproses pada satu waktu.
- `scripts/crd-web-auth.py` — **UI form v2**: toggle bahasa Indonesia/English,
  tema Catppuccin Auto/Light/Dark, layout responsif dua kolom, panduan 4 langkah,
  badge status, hitung mundur + progress bar, validasi perintah di browser,
  tombol salin/tempel, shortcut Ctrl/Cmd+Enter, dan panel sukses. Respons
  `/status` kini menyertakan `server_time` (server version `2.0`).
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

- Banner README (`docs/images/banner.svg`) dirombak: palet **slate/indigo**
  selaras diagram alur, tanpa warna Catppuccin yang bertabrakan; teks
  diperbarui ke Ubuntu 24.04/26.04 + GNOME 26 Wayland/AV1/audio.
- README (ID & EN): diagram alur diganti dari Mermaid ke **SVG 3 fase**
  (`docs/images/workflow-id.svg` / `workflow-en.svg`) dengan palet slate/indigo
  yang konsisten dan tetap terbaca di mode terang maupun gelap.
- README (ID & EN): status GNOME 26 Wayland naik dari "eksperimental" menjadi
  **terverifikasi (7 Nov 2026)** — tabel fitur, callout, tautan dokumen, serta
  catatan batasan dan audio.
- `docs/faq.md` + `docs/troubleshooting.md`: Q&A Wayland/audio/codec serta
  bagian **#15–#17** (layar blank, audio, performa).
- Header `gnome26-wayland-beta.yml`: status terverifikasi + ringkasan fitur;
  nama file/workflow tidak diubah agar tautan dan riwayat run tetap valid.
- `gnome26.yml`: input `crd_host_command` menjadi **opsional** (fallback),
  header/instruksi memakai alur form web, komentar checkout diperbarui, dan
  keep-alive menghitung sisa waktu dari `JOB_START_EPOCH` (bukan `sleep 21600`).
- README (ID & EN): alur utama sekarang **GNOME 26** (Ubuntu 26.04 + form web),
  badge runner, diagram Mermaid, langkah authorize, keamanan token, troubleshooting,
  dan struktur repo diperbarui. Workflow lama `gnome.yml` tetap didokumentasikan
  sebagai legacy.
- `docs/troubleshooting.md`: tambah bagian form web/Cloudflare, registrasi gagal
  tanpa re-run, window 30 menit, dan update runner 26.04.
- `scripts/crd-web-auth.py`: branding desktop dan nama device sekarang dapat
  dikonfigurasi lewat `CRD_WEB_DESKTOP` / `CRD_WEB_DEVICE` (default tetap
  `GNOME`/`gnome`), dengan escaping HTML.
- README (ID & EN): tambah varian **Cinnamon 26**, tabel perbandingan GNOME vs
  Cinnamon, device `cinnamon`, dan catatan animasi software rendering.
- `docs/faq.md` dan `docs/troubleshooting.md`: tambah Q&A serta bagian khusus
  Cinnamon (fallback `cinnamon2d`, animasi, tanpa lightdm).
- `docs/faq.md`: tambah Q&A tentang kode auth setelah desktop siap, retry tanpa
  re-run, Cloudflare quick tunnel, keamanan URL form, dan perbedaan
  `gnome26.yml` vs `gnome.yml`.
- `.github/ISSUE_TEMPLATE/bug_report.yml`: opsi masalah form web, peringatan
  token URL, dan checklist retry tanpa re-run.

### Removed

- `.github/workflows/gnome.yml` — workflow alur lama (perintah CRD diambil
  **sebelum** run, ditempel ke input `crd_host_command`) dihapus. Semua
  workflow aktif kini memakai alur form otorisasi web.
- `.github/workflows/lint.yml`: `actionlint` mengabaikan label
  `ubuntu-26.04` yang belum dikenali actionlint 1.7.12.
- `.gitignore`: tambah `__pycache__/` dan `*.pyc` untuk skrip Python baru.
- `.github/workflows/gnome26.yml` **di-rename menjadi `gnome24.yml`** dan runner
  diubah ke `ubuntu-24.04` (GNOME 50/Trixie tidak tersedia; komentar header
  disesuaikan). Nama `gnome26.yml` pada entri historis di atas mengacu ke nama
  file sebelum rename.
- `.github/workflows/cinnamon.yml`: runner `ubuntu-26.04` → `ubuntu-24.04`.
- `gnome24.yml`: hapus step `Create Desktop Shortcuts` (shortcut Antigravity,
  VS Code, OpenCode di Desktop — aplikasi tetap tersedia via Activities/grid)
  dan akhirnya keep-alive ditingkatkan jadi **monitor loop**: log heartbeat tiap
  5 menit, auto-restart `chrome-remote-desktop@runner` yang mati, plus deteksi
  gnome-shell user `runner` yang hilang 2 cek berturut-turut (tanpa menabrak
  timeout job 360 menit).
- Form otorisasi web (`scripts/crd-web-auth.py`): tema diperbarui dari
  Catppuccin ke **grayscale monokrom** dengan mode Auto/Light/Dark.
- `.github/workflows/gnome26-wayland-beta.yml`: desktop jadi **vanilla** —
  hapus step `Create Desktop Shortcuts`, blok `SafeUpgrade.desktop`, step
  `Set Wallpaper` (Catppuccin), dan step `Install Catppuccin Theme`. Step
  Verify kini menuntut: tanpa aset Catppuccin, Desktop kosong, wallpaper default
  GNOME/Ubuntu. Jalur GNOME 24.04 & Cinnamon 26 tetap bertema.
- README (ID & EN) + `docs/faq.md` + `docs/troubleshooting.md`: sinkron penuh —
  nama workflow aktual (`gnome24.yml`, `gnome26-wayland-beta.yml`), runner per
  varian, resolusi per varian, tema form monokrom, tema/shortcut/wallpaper per
  workflow, dan referensi file yang dihapus/rename.
- `gnome26-wayland-beta.yml`: **dark theme otomatis** — dconf system default
  `/etc/dconf/db/local.d/97-crd-dark-mode` + fallback per-user gsettings
  (`color-scheme='prefer-dark'` untuk app libadwaita, `gtk-theme='Yaru-dark'`
  untuk app legacy GTK3). Wallpaper/tampilan Ubuntu kini di-set eksplisit
  lewat dconf (`96-crd-ubuntu-look`) karena CRD memaksa
  `XDG_CURRENT_DESKTOP=GNOME`. Step Verify meng-assert dark mode dan file
  wallpaper ada.
- `gnome24.yml` & `cinnamon.yml`: jeda sebelum tunnel Cloudflare ditutup
  dinaikkan `sleep 5` → `sleep 20` agar window polling browser form lebih aman
  (interval polling 2–10s + warm-up jaringan).

### Fixed

- **Layar blank GNOME 26 Wayland**: tambah mapping `video.convert` pada
  template PipeWire CRD, watchdog crash dump (auto-restart
  `chrome-remote-desktop@runner`), dan step `Capture desktop proof` + artifact
  untuk diagnosis. Crash EI (`gnome_remote_desktop_session.cc:319`) tetap bug
  upstream; dimitigasi lewat restart otomatis.
- **GNOME 26 Wayland: verify tidak lagi mematikan sesi.** Assertion
  `XDG_CURRENT_DESKTOP` harus `ubuntu` dihapus: Chrome Remote Desktop 157
  selalu memaksa `GNOME` untuk sesi GNOME Wayland (`shared_lib.py`), sehingga
  assertion itu mustahil lolos dan membuat step Verify gagal + Keep Alive
  di-skip. Verify kini memeriksa hal yang benar-benar dikontrol workflow.
- **Wallpaper biru solid `#023c88` di GNOME 26 Wayland.** Karena mode sesi
  selalu `GNOME`, `picture-uri(-dark)` jatuh ke `adwaita-*.jxl` yang tidak
  terpasang. Wallpaper + tampilan Ubuntu (Yaru, Ubuntu Sans) kini di-set
  eksplisit lewat dconf `96-crd-ubuntu-look` dan fallback gsettings, dengan
  `primary-color` aubergine sebagai fallback non-biru.
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
- **Status success form web kini terkirim ke browser di workflow
  `gnome26-wayland-beta.yml`.** Sebelumnya `set-status success` baru ditulis
  setelah tunnel Cloudflare ditutup + verifikasi Wayland (~10–90 detik), sehingga
  form terjebak "Memproses" walau registrasi berhasil (device tetap muncul di
  remotedesktop.google.com/access). Kini cek service + `set-status success`
  berjalan saat tunnel masih hidup, dan `set-status failed` di jalur
  gagal-late (Wayland gagal) tidak lagi menimpa success yang sudah terkirim.
- **Form web tidak lagi berdiam saat koneksi putus**: bila polling
  `/<token>/status` gagal saat masih `queued/registering/sending`, halaman
  menampilkan pesan bahwa registrasi kemungkinan berhasil (ID/EN) untuk dicek
  ke remotedesktop.google.com/access.
- **Keep-alive monitor Wayland BETA tidak lagi false-positive**: proses
  `Xwayland` (spawn normal gnome-shell untuk app X11 seperti Chrome) tidak lagi
  dilaporkan `[WARN]` "proses X-server hidup"; alarm hanya untuk `Xvfb`
  (indikasi sesi legacy X) dengan pesan
  "[WARN] proses Xvfb hidup (sesi legacy X, bukan Wayland headless)".

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
