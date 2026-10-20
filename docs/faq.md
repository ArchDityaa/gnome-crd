# FAQ

## Apakah ini benar-benar gratis?

Ya. Runner **publik** GitHub Actions tidak memakai kuota menit — gratis dan tidak
terbatas. Yang Anda pakai adalah VM GitHub selama maksimal **6 jam per run**.

Kalau fork Anda **private**, run akan memakai kuota menit gratis akun Anda
(2.000 menit/bulan untuk akun gratis) sehingga lebih cepat habis.

## Berapa lama sesi bisa hidup?

Maksimum **6 jam** per run (batas job GitHub-hosted). Workflow mengatur
`timeout-minutes: 360` dan menghitung sisa waktu dari awal job, lalu runner
dimatikan. Window otorisasi 30 menit memakai bagian dari waktu tersebut.

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

## Kenapa kode auth baru diminta setelah desktop siap?

Kode `--code=...` dari halaman `headless` bersifat **sekali pakai** dan cepat
kedaluwarsa. Instalasi desktop memakan **20–40 menit**, jadi kalau kode diambil
di awal, kode sudah mati saat registrasi.

Workflow baru menunggu desktop siap, lalu menampilkan **form web**. Anda baru
membuat kode setelah itu, lalu langsung paste ke form. Dengan begitu kode segar
saat dipakai.

## Bagaimana cara authorize di workflow GNOME 26?

1. Jalankan workflow **GNOME 26** tanpa input auth.
2. Tunggu sampai log menampilkan `[OK] FORM OTORISASI SIAP` (±20–40 menit).
3. Buka URL form dari log atau **Job Summary**.
4. Di tab lain, buka <https://remotedesktop.google.com/headless>, lalu
   **Begin → Next → Authorize**.
5. Copy **seluruh** perintah **Debian Linux**, paste ke form, submit.
6. Setelah `[OK] CHROME REMOTE DESKTOP READY`, buka
   <https://remotedesktop.google.com/access>.

## Kalau kode auth gagal, apakah harus re-run workflow?

**Tidak**, selama window 30 menit masih berjalan. Setelah registrasi gagal,
form aktif lagi. Ambil kode **baru** di halaman headless, lalu submit lagi ke
form yang sama. Workflow akan mencoba mendaftarkan kode baru tanpa re-run.

Re-run baru diperlukan kalau:
- window 30 menit habis,
- tunnel Cloudflare gagal dibuat,
- atau workflow sudah berhenti.

## Apa itu form web dan Cloudflare quick tunnel? Perlu akun Cloudflare?

Form web adalah halaman kecil yang dijalankan workflow di dalam runner
(`127.0.0.1`) dan diekspos lewat **Cloudflare quick tunnel**. Fungsinya supaya
Anda bisa mengirim perintah CRD dari HP/jaringan lain setelah desktop siap.

**Tidak perlu akun Cloudflare.** Quick tunnel membuat URL acak
`https://....trycloudflare.com` tanpa login. Konsekuensinya tidak ada SLA;
kadang URL perlu ±15 detik untuk aktif, dan bisa berubah kalau tunnel restart.

## Apakah form web aman? Siapa yang bisa submit?

URL form mengandung **token acak 128-bit**. Tanpa token, server mengembalikan
404. Server hanya mendengarkan di `127.0.0.1`; satu-satunya jalan masuk adalah
tunnel Cloudflare. Perintah yang masuk juga divalidasi ketat (harus
`start-host`, tidak boleh mengandung metakarakter shell).

Tetap ada risiko: **siapa pun yang melihat URL itu selama window 30 menit bisa
mengirim perintah**. Di repo **publik**, URL terlihat di log dan Job Summary
selama run. Karena itu:

- jangan bagikan URL form,
- tutup tab setelah selesai,
- kalau repo Anda publik dan ini sensitif, gunakan **fork private**.

Akses CRD tetap memerlukan login akun Google Anda **dan** PIN.

## Apakah orang lain bisa masuk ke desktop saya?

Tidak tanpa akses ke akun Google yang dipakai untuk registrasi **dan** PIN.
Namun, kalau seseorang sempat memakai URL form untuk mendaftarkan device ke akun
Google **miliknya**, device itu menjadi miliknya. Karena itu URL form harus
dirahasiakan selama 30 menit.

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

## Apa bedanya `gnome26.yml` dan `gnome.yml`?

- **`gnome26.yml` (GNOME 26)** — alur terbaru, Ubuntu 26.04, form otorisasi web
  setelah desktop siap. Ini yang sebaiknya dipakai.
- **`gnome.yml` (RICH LINUX)** — alur lama, Ubuntu 24.04, perintah CRD diambil
  **sebelum** run lalu di-paste ke input `crd_host_command`.

## Apakah bisa diakses lewat VNC/RDP, bukan Chrome Remote Desktop?

Bisa, tapi tidak disiapkan oleh repo ini secara default. Sesi GNOME sudah berjalan
X11 headless; Anda tinggal memasang `x11vnc`/`tigervnc` di dalam sesi dan
meneruskan portnya lewat tunnel. Di luar cakupan repo ini.

## Sesi saya putus saat menjalankan `apt upgrade`, kenapa?

`apt upgrade` memicu needrestart yang me-restart `chrome-remote-desktop@runner`
dan/atau `gnome-shell`. Gunakan `sudo safe-upgrade` (sudah dipasang, juga ada
shortcut di Desktop) yang mencegah restart otomatis.
