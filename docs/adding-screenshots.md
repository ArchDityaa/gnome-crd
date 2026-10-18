# Menambahkan screenshot ke README

README repo ini punya slot screenshot yang **belum diaktifkan** (sengaja
dikomentari) sampai ada gambar asli. Panduan ini menjelaskan cara mengambil
screenshot dari sesi Chrome Remote Desktop dan memasukkannya ke repo.

---

## 1. Ambil screenshot di dalam sesi CRD

Cara termudah, semuanya dari dalam desktop GNOME:

| Cara | Perintah / tombol |
|---|---|
| Tombol | <kbd>Print Screen</kbd> (seluruh layar) atau <kbd>Alt</kbd>+<kbd>Print</kbd> (jendela aktif) |
| GUI | Tekan <kbd>Super</kbd> → cari **Screenshot** |
| Terminal | `gnome-screenshot -f ~/Pictures/desktop.png` |
| Terminal (delay 5 dtk) | `sleep 5; gnome-screenshot -f ~/Pictures/overview.png` |

Hasilnya tersimpan di `~/Pictures` (folder yang sama dengan wallpaper).

> Tips: aktifkan dulu animasi & tema supaya screenshot mewakili tampilan asli.
> Workflow sudah menyiapkan Catppuccin Macchiato dan animasi GNOME.

---

## 2. Bawa keluar dari sesi CRD

Runner akan mati saat sesi berakhir, jadi **gambar harus dipindahkan sebelum
logout**. Pilih salah satu:

### Cara A — lewat Chrome di dalam sesi (paling mudah, tanpa token)

1. Buka Google Chrome **di dalam sesi CRD**.
2. Masuk ke repo GitHub Anda → buka file `README.md` → klik ikon pensil
   (**Edit this file**).
3. Dari File Manager, **drag & drop** file PNG dari `~/Pictures` ke dalam area
   teks editor. GitHub akan meng-upload dan menyisipkan link
   `https://user-images.githubusercontent.com/...` secara otomatis.
4. Simpan (commit) langsung ke `main`.

Cara ini tidak butuh PAT dan tidak perlu `git` sama sekali.

### Cara B — lewat git + Personal Access Token

```bash
git clone https://github.com/<USER>/gnome-crd.git
cd gnome-crd
cp ~/Pictures/*.png docs/images/
git checkout -b docs/screenshots
git add docs/images/*.png
git commit -m "docs: tambah screenshot desktop"
git push -u origin docs/screenshots
# lalu buka Pull Request di GitHub
```

Saat `git push` diminta password, masukkan **Personal Access Token**
(scope `repo`) — bukan password akun. Buat di
<https://github.com/settings/tokens>.

### Cara C — kirim ke pemelihara repo

Lampirkan gambar ke chat/issue/PR, lalu pemelihara repo yang memasangnya.

---

## 3. Standar gambar

Supaya README tetap cepat di-load dan terlihat rapi:

- **Format:** PNG (default `gnome-screenshot`) atau WebP.
- **Lebar:** maksimal ~1600 px (CRD berjalan 1024x768, jadi sudah pas).
- **Ukuran file:** usahakan < 500 KB per gambar.
- **Lokasi:** `docs/images/`.
- **Penamaan:** huruf kecil, pakai tanda hubung.

Nama yang sudah disiapkan di README:

| Nama file | Isi yang disarankan |
|---|---|
| `docs/images/desktop.png` | Tampilan utama: wallpaper, top bar, terminal terbuka |
| `docs/images/overview.png` | GNOME **Activities / overview** (menunjukkan animasi hidup) |
| `docs/images/apps.png` | VS Code dan/atau Chrome sedang dipakai |
| `docs/images/access-page.png` | Halaman `remotedesktop.google.com/access` dengan device **gnome** |
| `docs/images/safe-upgrade.png` | Terminal menjalankan `sudo safe-upgrade` |

Screenshot `access-page.png` diambil dari komputer lokal (bukan dari sesi), cukup
browser + halaman Remote Access.

---

## 4. Aktifkan slot di README

Di `README.md` dan `README.en.md` ada blok yang dikomentari:

```html
<!-- SCREENSHOTS ...
## Tangkapan layar
...
-->
```

Setelah file gambar tersedia di `docs/images/`, hapus pembuka `<!-- SCREENSHOTS`
dan penutup `-->` pada blok tersebut. Commit, lalu README akan menampilkan
galeri screenshot.

---

## 5. Tautan langsung (tanpa file)

Kalau tidak mau menaruh file di repo, Anda bisa memakai URL hasil upload GitHub
(`https://user-images.githubusercontent.com/...`) langsung di dalam blok
`<img src="...">`. Cara A di atas menghasilkan URL seperti itu secara otomatis.
