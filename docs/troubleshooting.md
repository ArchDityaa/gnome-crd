# Troubleshooting

Panduan lengkap untuk masalah yang paling sering muncul saat menjalankan
**GNOME 26 (GNOME + Chrome Remote Desktop)**.

> **Jangan pernah paste** URL form (mengandung token), isi `crd_host_command`,
> kode OAuth (`--code=...`), atau PIN Anda ke issue/log publik. Cukup potongan
> log yang relevan.

---

## 1. Workflow tidak muncul di tab Actions

**Gejala:** tab Actions kosong, atau muncul banner "Workflows aren't being run on
this repository".

**Penyebab:** GitHub menonaktifkan workflow pada repo hasil fork.

**Solusi:** **Settings → Actions → General → Allow all actions and reusable
workflows → Save**. Lalu refresh tab Actions; workflow akan muncul.

> Catatan: `workflow_dispatch` (tombol **Run workflow**) hanya tampil setelah
> workflow ada di branch default. Karena workflow ini sudah ada di `main` di repo
> asal, setelah fork + enable Actions tombol tersebut langsung tersedia.

---

## 2. URL form otorisasi tidak muncul / error Cloudflare

**Gejala:**

- Instalasi sudah lama, tetapi log belum menampilkan `[OK] FORM OTORISASI SIAP`.
- URL form sudah muncul, tetapi halaman menampilkan **Cloudflare 1033/502**.

**Penyebab & solusi:**

1. **Instalasi belum selesai.** Form baru dibuat setelah desktop siap
   (±20–40 menit). Tunggu step **Authorize & Register Chrome Remote Desktop
   (Web UI)** mulai berjalan.
2. **Tunnel sedang warm-up.** Cloudflare quick tunnel kadang butuh ±15 detik
   sebelum URL bisa dibuka. Tunggu lalu refresh.
3. **Cloudflare gagal dibuat.** Cari log:

   ```
   [FAIL] Cloudflare quick tunnel tidak bisa dibuat.
   ```

   Workflow akan mencoba QUIC lalu HTTP/2. Kalau keduanya gagal:
   - jalankan ulang workflow (cache `.deb` dipakai lagi), atau
   - isi `crd_host_command` saat dispatch sebagai fallback. **Perhatian:** kode
     fallback dibuat di awal run dan bisa kedaluwarsa selama instalasi; ini
     hanya berguna kalau instalasi sudah hangat/cache.
4. **Tunnel mati di tengah jalan.** Workflow mencoba restart hingga 3 kali.
   URL publik akan **berubah**; URL baru dicetak di log dan Job Summary. Token
   tetap sama, tetapi URL lama tidak bisa dipakai lagi.
5. **Window 30 menit habis.** Workflow berhenti dan meninggalkan status
   `timeout`. Jalankan ulang workflow; cache membuat re-run lebih cepat.

> URL form hanya berlaku ±30 menit. Jangan menutup tab form sebelum registrasi
> selesai; kalau tab tertutup, buka lagi URL yang sama selama window masih ada.

---

## 3. Registrasi CRD gagal / kode auth bermasalah

**Gejala:** form menampilkan status **Gagal**, atau log berakhir dengan:

```
[FAIL] Registrasi Chrome Remote Desktop gagal.
```

**Penyebab tersering:** kode `--code=...` bersifat **sekali pakai** dan cepat
kadaluarsa. Bisa juga karena:

- Anda login akun Google yang berbeda dengan yang dipakai di halaman headless.
- Perintah yang di-paste terpotong.
- Anda meng-copy perintah **Windows/macOS**, bukan **Debian Linux**.
- Kode sudah pernah dipakai di run/submit sebelumnya.

**Solusi (tanpa re-run):**

1. Jangan tutup workflow. Setelah registrasi gagal, form **aktif lagi**
   (status `failed`).
2. Buka <https://remotedesktop.google.com/headless>.
3. **Begin → Next → Authorize** sampai muncul perintah **Debian Linux** yang
   baru. Pastikan akun Google-nya sama.
4. Copy **seluruh** perintah baru tersebut.
5. Paste ke form yang sama, lalu submit lagi.

Workflow akan mencoba mendaftarkan kode baru itu. Anda bisa mengulang selama
window **30 menit** masih berjalan. Tidak perlu re-run workflow.

Kalau window sudah habis atau tunnel sudah tidak ada, jalankan ulang workflow.
Cache `.deb` sudah tersimpan sebelum registrasi, jadi re-run jauh lebih cepat.

> Untuk workflow lama **`gnome.yml`**: alurnya berbeda. Ambil perintah baru,
> lalu **Re-run** workflow dan paste perintah itu ke input `crd_host_command`.

---

## 4. Workflow "READY" tapi device tidak muncul di Remote Access

1. Pastikan log benar-benar sudah mencapai:

   ```
   [OK] CHROME REMOTE DESKTOP READY
   ```

2. Refresh <https://remotedesktop.google.com/access> dan tunggu ~1 menit.
3. Pastikan Anda login akun Google yang **sama** dengan yang dipakai di halaman
   `headless` saat mengambil perintah.
4. Cek service di dalam sesi (kalau sudah bisa masuk lewat terminal mana pun):

   ```bash
   systemctl status chrome-remote-desktop@runner
   ```

   Kalau statusnya tidak `active`, jalankan:

   ```bash
   sudo systemctl start chrome-remote-desktop@runner
   ```

Nama device yang muncul adalah **gnome** (di-override di workflow), bukan
hostname runner.

---

## 5. Tidak bisa connect / PIN ditolak

- PIN default adalah `123456`. Kalau Anda set secret `CRD_PIN`, pakai nilai itu
  (minimal 6 digit).
- Halaman CRD kadang butuh beberapa detik setelah device muncul; coba lagi.
- Kalau PIN salah terus, hentikan workflow, jalankan ulang, lalu registrasi
  ulang dengan perintah `headless` baru (registrasi baru akan mengganti PIN).

---

## 6. Sesi putus tiba-tiba

**Penyebab paling umum:** menjalankan `sudo apt upgrade -y` polos di dalam sesi.
Itu me-restart `chrome-remote-desktop@runner`, `gnome-shell`, atau systemd,
sehingga koneksi terputus.

**Solusi:** selalu pakai:

```bash
sudo safe-upgrade
```

Script ini meng-upgrade tanpa me-restart service sesi, dan melaporkan paket yang
butuh restart **tanpa** mengeksekusinya.

Kalau sesi sudah terlanjur putus, biasanya cukup:

1. Tunggu ~1–2 menit (systemd mencoba memulihkan service).
2. Connect lagi dari <https://remotedesktop.google.com/access>.
3. Kalau tetap gagal, hentikan workflow dan jalankan ulang (lingkungan bersih).

---

## 7. Sesi berakhir sendiri setelah beberapa jam

Itu **perilaku normal**. Job GitHub-hosted maksimum **6 jam**. Workflow
menghitung sisa waktu dari awal job lalu tidur sampai mendekati batas itu
(bukan `sleep 21600` tetap), setelah itu runner dimatikan.

Simpan pekerjaan Anda ke GitHub/cloud sebelum berakhir — VM tidak memiliki
penyimpanan permanen. Ingat juga bahwa window otorisasi 30 menit memakai waktu
dari batas 6 jam yang sama.

---

## 8. Resolusi layar aneh / terlalu kecil

Workflow mengunci resolusi ke **1024x768**, yang merupakan mode native driver
`dummy` pada sesi CRD headless (jadi tahan re-attach). Ubah sementara lewat
**Settings → Displays**, atau sesuaikan nilai `WANT=` di
`/usr/local/bin/set-resolution.sh` dan `1024x768` di
`~/.chrome-remote-desktop-session` bila Anda ingin permanen.

---

## 9. `virt-manager` / GNOME Boxes bermasalah

**"Permission denied" saat akses libvirt socket:**

Sesi Anda mungkin dijalankan sebelum `runner` masuk grup `libvirt`/`kvm`.

1. Log out lalu login kembali di sesi GNOME (keluar dan masuk lagi), atau
2. `sudo systemctl restart chrome-remote-desktop@runner` (dari terminal; sesi
   akan terputus lalu sambung lagi).

**"Cannot access KVM" / VM sangat lambat:**

Runner x86 **`ubuntu-26.04`** (workflow `gnome26.yml`) punya `/dev/kvm`. Workflow
lama `gnome.yml` memakai `ubuntu-24.04`. Cek:

```bash
ls -l /dev/kvm      # harus ada
groups runner       # harus memuat kvm dan libvirt
```

Kalau `/dev/kvm` tidak ada, runner tersebut tidak menyediakan nested
virtualization (jarang terjadi di x86). VM masih bisa jalan, tapi memakai
emulasi software (jauh lebih lambat).

---

## 10. Tema / ikon tidak berubah

Catppuccin Macchiato (Mauve) sudah diterapkan lewat `gsettings` untuk user
`runner`. Kalau aplikasi tertentu (khususnya GTK4/libadwaita) masih terlihat
default:

- Aplikasi perlu **di-restart** setelah tema dipasang.
- Beberapa app libadwaita butuh override di `~/.config/gtk-4.0` (sudah disiapkan
  workflow). Cek: `ls ~/.config/gtk-4.0/gtk.css`.
- Ganti flavor lewat **Tweaks → Appearance** untuk perubahan cepat.

---

## 11. Cara mengambil log untuk laporan issue

1. Buka tab **Actions** → klik run yang bermasalah.
2. Klik job **build** → klik step yang gagal untuk expand log.
3. Copy **potongan** log yang relevan. **Jangan** sertakan:
   - URL form / token,
   - kode OAuth (`--code=...`),
   - PIN,
   - isi `crd_host_command`.
4. Buka issue dengan template **Bug report**.

---

## 12. Re-run cepat vs. run dari nol

| | Run dari nol | Re-run setelah gagal |
|---|---|---|
| Cache `.deb` | kosong (unduh ~GB) | terpakai |
| Perkiraan waktu | 20–40 menit | jauh lebih cepat |

Untuk workflow **GNOME 26**:

- Registrasi gagal karena kode auth → **tidak perlu re-run**; ambil kode baru
  dan submit lagi di form selama window 30 menit.
- Window otorisasi habis atau tunnel gagal → baru lakukan re-run.

Untuk workflow lama **`gnome.yml`**:

- Registrasi gagal → ambil perintah CRD baru, lalu **Re-run** dan paste ke input
  `crd_host_command`.
