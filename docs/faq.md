# FAQ

## Apakah ini benar-benar gratis?

Ya. Runner **publik** GitHub Actions tidak memakai kuota menit — gratis dan tidak
terbatas. Yang Anda pakai adalah VM GitHub selama maksimal **6 jam per run**.

Kalau fork Anda **private**, run akan memakai kuota menit gratis akun Anda
(2.000 menit/bulan untuk akun gratis) sehingga lebih cepat habis.

## Berapa lama sesi bisa hidup?

Maksimum **6 jam** per run (batas job GitHub-hosted). Workflow mengatur
`timeout-minutes: 360` dan tidur sampai batas itu, lalu runner dimatikan.

## Apakah data saya tersimpan?

Tidak. Setiap run adalah VM baru dari nol. Apa pun yang Anda buat akan hilang
saat sesi berakhir. Simpan hasil ke GitHub, Google Drive, atau layanan cloud
lainnya.

## Bolehkah saya memakainya untuk mining / hosting / komputasi umum?

**Tidak.** GitHub Actions hanya boleh dipakai untuk aktivitas yang berkaitan
dengan *production, testing, deployment, atau publication* sebuah proyek
software. Repo ini ditujukan untuk **eksperimen dan pengujian tools**. Pelanggaran
dapat menyebabkan akun Anda dibatasi.

## Kenapa GNOME, bukan XFCE/Mate/Cinnamon?

GNOME adalah target repo ini. Struktur repo sengaja dibuat rapi (workflow terpisah
+ `scripts/` bersama) agar desktop environment lain bisa ditambahkan kemudian
tanpa mengubah GNOME.

## Bisa install software sendiri di dalam sesi?

Bisa. Anda punya akses `sudo` penuh sebagai user `runner` (password: `root`).
Install lewat `apt`, `snap` tidak tersedia (sengaja dihapus), atau pakai
AppImage/Flatpak manual.

## Kenapa `snap` tidak ada?

Snapd dihapus untuk menghemat waktu & ruang build, dan karena beberapa paket
transisi (thunderbird/firefox) memaksa unduhan dari Snap Store yang bisa membuat
build menggantung lama. Pakai `.deb`, Flatpak, atau versi resmi dari vendor
(Chrome, VS Code) yang sudah disiapkan workflow.

## Bagaimana cara mengubah PIN?

Buat repository secret bernama `CRD_PIN` dengan nilai minimal 6 digit
(**Settings → Secrets and variables → Actions → New repository secret**).
Kalau tidak diisi, PIN default `123456`.

## Kenapa nama device-nya "gnome"?

Workflow sengaja meng-override `--name` menjadi `gnome` supaya mudah dikenali di
daftar perangkat Remote Access (kalau tidak, namanya akan berupa hostname acak
milik runner).

## Apakah aman? Apakah orang lain bisa masuk?

Akses Chrome Remote Desktop tetap memerlukan **login akun Google** pemilik
perintah `headless` **dan** PIN. Meski begitu, ganti PIN default dan jangan
bagikan kode OAuth. Kode OAuth (`--code=`) bersifat sekali pakai sehingga tidak
berguna bagi orang lain setelah dipakai.

## Bisakah menjalankan lebih dari satu sesi sekaligus?

Bisa, jalankan workflow beberapa kali. Tapi perhatikan batas bersamaan akun
GitHub dan pastikan sumber daya runner mencukupi. Setiap run adalah mesin
terpisah.

## Kenapa resolusi terkunci 1024x768?

Driver grafis `dummy` pada sesi CRD headless menyediakan `1024x768` sebagai mode
native. Mode ini dipilih agar stabil dan tahan saat shell di-reload. Ubah lewat
**Settings → Displays** untuk kebutuhan sementara.

## Bagaimana memperbarui fork saya dengan perbaikan terbaru?

Di halaman repo fork Anda, klik **Sync fork → Update branch**. Perubahan pada
`.github/workflows/` dan `scripts/` akan ikut tersinkron.

## Kenapa build pertama lama?

Karena harus mengunduh dan memasang GNOME, Chrome, VS Code, CRD, theme, dan font
(beberapa GB). Setelah run pertama, cache `.deb` tersimpan sehingga run
berikutnya (dan re-run) jauh lebih cepat.

## Apakah bisa diakses lewat VNC/RDP, bukan Chrome Remote Desktop?

Bisa, tapi tidak disiapkan oleh repo ini secara default. Sesi GNOME sudah berjalan
X11 headless; Anda tinggal memasang `x11vnc`/`tigervnc` di dalam sesi dan
meneruskan portnya lewat tunnel. Di luar cakupan repo ini.

## Sesi saya putus saat menjalankan `apt upgrade`, kenapa?

`apt upgrade` memicu needrestart yang me-restart `chrome-remote-desktop@runner`
dan/atau `gnome-shell`. Gunakan `sudo safe-upgrade` (sudah dipasang, juga ada
shortcut di Desktop) yang mencegah restart otomatis.
