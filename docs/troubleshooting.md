# Troubleshooting

Panduan lengkap untuk masalah yang paling sering muncul saat menjalankan
**RICH LINUX (GNOME + Chrome Remote Desktop)**.

> **Jangan pernah paste** isi `crd_host_command`, kode OAuth (`--code=...`),
> atau PIN Anda ke issue/log publik.

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

## 2. Gagal di step *Register Chrome Remote Desktop*

**Gejala:** log berakhir dengan:

```
[FAIL] Registrasi Chrome Remote Desktop gagal (OAuth error).
```

**Penyebab tersering:** kode `--code=...` bersifat **sekali pakai** dan cepat
kadaluarsa (biasanya beberapa menit). Kalau Anda menunggu lama sebelum run,
atau re-run dengan perintah lama, registrasi akan gagal.

**Solusi (tanpa install ulang):**

1. Buka <https://remotedesktop.google.com/headless>.
2. **Begin → Next → Authorize** sampai muncul perintah **Debian Linux** yang baru.
3. Copy **seluruh** perintah baru tersebut.
4. Di tab Actions, buka run yang gagal → **Re-run all jobs** → paste perintah
   baru di kolom `crd_host_command`.

Karena cache `.deb` sudah tersimpan (step **Save apt package cache**), re-run jauh
lebih cepat daripada run pertama.

**Penyebab lain:**

- Perintah yang di-paste terpotong. Pastikan seluruh baris ikut ter-copy
  (termasuk `DISPLAY= ... --name=$(hostname)`).
- Anda meng-copy perintah **Windows/macOS** alih-alih **Debian Linux**.

---

## 3. Workflow "READY" tapi device tidak muncul di Remote Access

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

Filename device yang muncul adalah **gnome** (di-override di workflow), bukan
hostname runner.

---

## 4. Tidak bisa connect / PIN ditolak

- PIN default adalah `123456`. Kalau Anda set secret `CRD_PIN`, pakai nilai itu
  (minimal 6 digit).
- Halaman CRD kadang butuh beberapa detik setelah device muncul; coba lagi.
- Kalau PIN salah terus, hentikan workflow, ambil perintah `headless` baru
  (registrasi ulang akan mengganti PIN), lalu run ulang.

---

## 5. Sesi putus tiba-tiba

**Penyebab paling umum:** menjalankan `sudo apt upgrade -y` polos di dalam sesi.
itu me-restart `chrome-remote-desktop@runner`, `gnome-shell`, atau systemd,
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

## 6. Sesi berakhir sendiri setelah beberapa jam

Itu **perilaku normal**. Job GitHub-hosted maksimum **6 jam**; workflow sengaja
tidur (`sleep 21600`) lalu runner dimatikan. Simpan pekerjaan Anda ke
GitHub/cloud sebelum berakhir — VM tidak memiliki penyimpanan permanen.

---

## 7. Resolusi layar aneh / terlalu kecil

Workflow mengunci resolusi ke **1024x768**, yang merupakan mode native driver
`dummy` pada sesi CRD headless (jadi tahan re-attach). Ubah sementara lewat
**Settings → Displays**, atau sesuaikan nilai `WANT=` di
`/usr/local/bin/set-resolution.sh` dan `1024x768` di
`~/.chrome-remote-desktop-session` bila Anda ingin permanen.

---

## 8. `virt-manager` / GNOME Boxes bermasalah

**"Permission denied" saat akses libvirt socket:**

Sesi Anda mungkin dijalankan sebelum `runner` masuk grup `libvirt`/`kvm`.

1. Log out lalu login kembali di sesi GNOME (keluar dan masuk lagi), atau
2. `sudo systemctl restart chrome-remote-desktop@runner` (dari terminal; sesi
   akan terputus lalu sambung lagi).

**"Cannot access KVM" / VM sangat lambat:**

Runner x86 `ubuntu-24.04` punya `/dev/kvm`. Cek:

```bash
ls -l /dev/kvm      # harus ada
groups runner       # harus memuat kvm dan libvirt
```

Kalau `/dev/kvm` tidak ada, runner tersebut tidak menyediakan nested
virtualization (jarang terjadi di x86). VM masih bisa jalan, tapi memakai
emulasi software (jauh lebih lambat).

---

## 9. Tema / ikon tidak berubah

Catppuccin Macchiato (Mauve) sudah diterapkan lewat `gsettings` untuk user
`runner`. Kalau aplikasi tertentu (khususnya GTK4/libadwaita) masih terlihat
default:

- Aplikasi perlu **di-restart** setelah tema dipasang.
- Beberapa app libadwaita butuh override di `~/.config/gtk-4.0` (sudah disiapkan
  workflow). Cek: `ls ~/.config/gtk-4.0/gtk.css`.
- Ganti flavor lewat **Tweaks → Appearance** untuk perubahan cepat.

---

## 10. Cara mengambil log untuk laporan issue

1. Buka tab **Actions** → klik run yang bermasalah.
2. Klik job **build** → klik step yang gagal untuk expand log.
3. Copy **potongan** log yang relevan (jangan seluruhnya, dan **jangan** sertakan
   kode OAuth/PIN).
4. Buka issue dengan template **Bug report**.

---

## 11. Re-run cepat vs. run dari nol

| | Run dari nol | Re-run setelah gagal |
|---|---|---|
| Cache `.deb` | kosong (unduh ~GB) | terpakai |
| Perkiraan waktu | 20–40 menit | jauh lebih cepat |

Jika gagal di langkah registrasi (OAuth), **selalu pilih Re-run**, bukan run
baru, supaya cache terpakai. Jangan lupa ambil perintah CRD **baru** dulu.
