#!/usr/bin/env python3
"""Server web kecil untuk menerima perintah otorisasi Chrome Remote Desktop.

Dipakai oleh `.github/workflows/gnome26.yml` dan `.github/workflows/cinnamon.yml`
(STEP 17). Workflow menjalankan server ini di 127.0.0.1, lalu mengeksposnya
lewat Cloudflare quick tunnel.
User membuka URL publik, meng-*authorize* akun Google di halaman headless CRD,
lalu mem-paste perintah `start-host` ke form. Perintah disimpan ke file dan
diproses oleh workflow.

Kenapa ada: kode OAuth `--code=...` dari Google bersifat sekali pakai dan cepat
kadaluarsa, sedangkan instalasi desktop butuh 20-40 menit. Dengan form ini kode
baru dibuat SETELAH desktop siap, jadi tidak sempat kedaluwarsa.

Halaman form memakai tema Catppuccin Macchiato/Latte (auto mengikuti sistem,
bisa diganti manual), toggle bahasa Indonesia/English, stepper, validasi awal,
hitung mundur, progress bar, panel sukses, serta tombol salin/tempel.

Mode pemakaian:
    python3 crd-web-auth.py serve
    python3 crd-web-auth.py set-status waiting "Menunggu perintah..." \
        --deadline 1700000000
    python3 crd-web-auth.py get-state

Environment:
    CRD_WEB_TOKEN   token acak (wajib) - jadi bagian path URL
    CRD_WEB_STATE   direktori state (default: /tmp/crd-web-auth)
    CRD_WEB_PORT    port lokal (default: 8787)
    CRD_WEB_BIND    alamat bind (default: 127.0.0.1)
    CRD_WEB_DESKTOP nama desktop di halaman form (default: GNOME)
    CRD_WEB_DEVICE  nama device CRD yang tampil (default: gnome)

Hanya memakai standard library Python 3 (tidak perlu pip/venv).
"""

from __future__ import annotations

import hmac
import html
import json
import os
import re
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

STATE_DIR = os.environ.get("CRD_WEB_STATE", "/tmp/crd-web-auth")
TOKEN = os.environ.get("CRD_WEB_TOKEN", "")
PORT = int(os.environ.get("CRD_WEB_PORT", "8787"))
BIND = os.environ.get("CRD_WEB_BIND", "127.0.0.1")
DESKTOP_NAME = os.environ.get("CRD_WEB_DESKTOP", "GNOME")
DEVICE_NAME = os.environ.get("CRD_WEB_DEVICE", "gnome")

COMMAND_FILE = os.path.join(STATE_DIR, "command")
PROCESSING_FILE = os.path.join(STATE_DIR, "command.processing")
STATUS_FILE = os.path.join(STATE_DIR, "status.json")

MAX_BODY_BYTES = 16 * 1024
MAX_COMMAND_BYTES = 4096

# Karakter yang tidak dibutuhkan oleh perintah `start-host` yang sah dan bisa
# dipakai untuk menyisipkan perintah shell tambahan. Perintah dijalankan lewat
# `bash -c`, jadi validasi ini penting walaupun URL sudah memakai token.
FORBIDDEN = ("$(", "`", ";", "&", "|", ">", "<", "\\", "\n", "\r")

DEFAULT_STATUS = {
    "state": "waiting",
    "message": "Menunggu perintah Chrome Remote Desktop...",
    "attempts": 0,
    "updated_at": 0,
}


def _now() -> int:
    return int(time.time())


def _ensure_state_dir() -> None:
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    try:
        os.chmod(STATE_DIR, 0o700)
    except OSError:
        pass


def atomic_write_json(path: str, data: dict) -> None:
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)


def read_status() -> dict:
    try:
        with open(STATUS_FILE, encoding="utf-8") as handle:
            data = json.load(handle)
        if not isinstance(data, dict):
            raise ValueError("status.json bukan object")
        return data
    except (OSError, ValueError):
        return dict(DEFAULT_STATUS)


def set_status(
    state: str,
    message: str,
    *,
    error: str | None = None,
    attempts: int | None = None,
    deadline: int | None = None,
) -> None:
    data = read_status()
    data["state"] = state
    data["message"] = message
    data["updated_at"] = _now()
    if error is not None:
        data["last_error"] = error[:1000]
    elif state in ("success", "waiting", "queued", "registering"):
        data.pop("last_error", None)
    if attempts is not None:
        data["attempts"] = attempts
    if deadline is not None:
        data["deadline"] = deadline
    atomic_write_json(STATUS_FILE, data)


def normalize_command(raw: str) -> tuple[str | None, str | None]:
    """Bersihkan + validasi perintah. Return (command, error)."""
    command = raw.replace("\r", "").strip()

    if not command:
        return None, "Perintah masih kosong."
    if len(command.encode("utf-8")) > MAX_COMMAND_BYTES:
        return None, "Perintah terlalu panjang (maksimal 4096 byte)."

    # Buang --name=... (termasuk bentuk --name=$(hostname)). Workflow akan
    # menambahkan --name sendiri (mis. "gnome"/"cinnamon") supaya device
    # selalu tampil dengan nama yang konsisten.
    command = re.sub(r'--name=(?:"[^"]*"|\S+)', "", command).strip()

    if "\n" in command or "\r" in command:
        return None, "Perintah harus satu baris."
    if any(ord(ch) < 0x20 or ord(ch) == 0x7F for ch in command):
        return None, "Perintah mengandung karakter kontrol."
    if "start-host" not in command:
        return None, "Perintah tidak mengandung 'start-host'."
    if "--code=" not in command:
        return None, "Perintah tidak mengandung '--code='."
    if not (
        command.startswith("/opt/google/chrome-remote-desktop/start-host")
        or command.startswith("DISPLAY=")
    ):
        return None, (
            "Format tidak dikenali. Salin SELURUH perintah Debian Linux dari "
            "halaman headless Chrome Remote Desktop."
        )

    for bad in FORBIDDEN:
        if bad in command:
            return None, f"Perintah mengandung karakter yang tidak diizinkan: {bad!r}"

    return command, None


PAGE_TEMPLATE = r"""<!doctype html>
<html lang="id" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="color-scheme" content="dark light">
<meta name="theme-color" content="#0d0d0d">
<title>Otorisasi Chrome Remote Desktop</title>
<script>
(function () {
  try {
    var pref = localStorage.getItem("crd.theme") || "auto";
    var light = pref === "light" || (pref === "auto" && window.matchMedia("(prefers-color-scheme: light)").matches);
    document.documentElement.dataset.theme = light ? "light" : "dark";
    document.documentElement.dataset.themePref = pref;
  } catch (err) {
    document.documentElement.dataset.theme = "dark";
    document.documentElement.dataset.themePref = "auto";
  }
})();
</script>
<style>
  :root {
    /* Dark monokrom — semua nilai grayscale, tidak ada hue warna. */
    color-scheme: dark;
    --base: #0d0d0d;
    --mantle: #141414;
    --crust: #1a1a1a;
    --surface0: #222222;
    --surface1: #2a2a2a;
    --surface2: #333333;
    --text: #e8e8e8;
    --subtext1: #999999;
    --subtext0: #666666;
    --mauve: #ffffff;
    --blue: #b3b3b3;
    --green: #d4d4d4;
    --yellow: #c0c0c0;
    --red: #a8a8a8;
    --peach: #b8b8b8;
    --teal: #b0b0b0;
    --mauve-soft: rgba(255, 255, 255, .10);
    --blue-soft: rgba(179, 179, 179, .10);
    --green-soft: rgba(212, 212, 212, .10);
    --red-soft: rgba(168, 168, 168, .10);
    --yellow-soft: rgba(192, 192, 192, .10);
    --card: rgba(34, 34, 34, .72);
    --card-border: rgba(255, 255, 255, .08);
    --card-shadow: 0 24px 70px rgba(0, 0, 0, .45);
    --input: #1a1a1a;
    --input-border: #444444;
    --grid: rgba(255, 255, 255, .035);
    --glow1: rgba(255, 255, 255, .06);
    --glow2: rgba(255, 255, 255, .04);
    --on-accent: #0d0d0d;
  }
  :root[data-theme="light"] {
    /* Light monokrom — semua nilai grayscale, tidak ada hue warna. */
    color-scheme: light;
    --base: #f5f5f5;
    --mantle: #ededed;
    --crust: #e5e5e5;
    --surface0: #ffffff;
    --surface1: #f0f0f0;
    --surface2: #e8e8e8;
    --text: #222222;
    --subtext1: #666666;
    --subtext0: #999999;
    --mauve: #0d0d0d;
    --blue: #333333;
    --green: #555555;
    --yellow: #777777;
    --red: #666666;
    --peach: #6d6d6d;
    --teal: #606060;
    --mauve-soft: rgba(13, 13, 13, .06);
    --blue-soft: rgba(51, 51, 51, .06);
    --green-soft: rgba(85, 85, 85, .06);
    --red-soft: rgba(102, 102, 102, .06);
    --yellow-soft: rgba(119, 119, 119, .06);
    --card: rgba(255, 255, 255, .82);
    --card-border: rgba(0, 0, 0, .08);
    --card-shadow: 0 24px 70px rgba(0, 0, 0, .10);
    --input: #ffffff;
    --input-border: #cccccc;
    --grid: rgba(0, 0, 0, .035);
    --glow1: rgba(0, 0, 0, .05);
    --glow2: rgba(0, 0, 0, .04);
    --on-accent: #ffffff;
  }
  *, *::before, *::after { box-sizing: border-box; }
  html { scroll-behavior: smooth; }
  body {
    margin: 0;
    min-height: 100vh;
    overflow-x: hidden;
    color: var(--text);
    background:
      radial-gradient(1100px 620px at 8% -12%, var(--glow1), transparent 62%),
      radial-gradient(920px 540px at 102% 0%, var(--glow2), transparent 58%),
      var(--base);
    font-family: "Inter", "Segoe UI", system-ui, -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
    line-height: 1.5;
    -webkit-font-smoothing: antialiased;
    text-rendering: optimizeLegibility;
  }
  body::after {
    content: "";
    position: fixed;
    inset: 0;
    z-index: -1;
    pointer-events: none;
    opacity: .7;
    background-image:
      linear-gradient(var(--grid) 1px, transparent 1px),
      linear-gradient(90deg, var(--grid) 1px, transparent 1px);
    background-size: 48px 48px;
    mask-image: radial-gradient(circle at 50% 0%, #000 0%, transparent 78%);
    -webkit-mask-image: radial-gradient(circle at 50% 0%, #000 0%, transparent 78%);
  }
  a { color: var(--blue); text-decoration-thickness: 1px; text-underline-offset: 3px; }
  button, input, textarea { font: inherit; }
  button { color: inherit; }
  code, kbd, samp {
    font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", "SFMono-Regular", Consolas, monospace;
  }
  ::selection { background: var(--mauve-soft); color: var(--text); }
  [hidden] { display: none !important; }
  :focus-visible { outline: 2px solid var(--mauve); outline-offset: 3px; }
  .skip {
    position: fixed;
    left: 12px;
    top: -80px;
    z-index: 100;
    padding: 10px 14px;
    border-radius: 10px;
    background: var(--text);
    color: var(--base);
    font-weight: 800;
    font-size: .8rem;
    transition: top .18s ease;
  }
  .skip:focus { top: 12px; }
  .shell {
    width: min(1180px, 100%);
    margin: 0 auto;
    padding: 34px 22px 58px;
  }
  .hero {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 22px;
    padding-bottom: 24px;
  }
  .identity { display: flex; align-items: flex-start; gap: 16px; min-width: 0; }
  .logo {
    display: grid;
    place-items: center;
    flex: none;
    width: 56px;
    height: 56px;
    border-radius: 18px;
    color: var(--on-accent);
    background: linear-gradient(135deg, var(--mauve), var(--blue));
    box-shadow: 0 14px 34px var(--mauve-soft), inset 0 1px 0 rgba(255, 255, 255, .28);
  }
  .logo .icon { width: 28px; height: 28px; stroke-width: 1.8; }
  .eyebrow {
    margin: 2px 0 5px;
    color: var(--mauve);
    font-size: .66rem;
    font-weight: 800;
    letter-spacing: .19em;
    text-transform: uppercase;
  }
  h1 {
    margin: 0 0 7px;
    font-size: clamp(1.75rem, 3.5vw, 2.55rem);
    line-height: 1.08;
    letter-spacing: -.035em;
  }
  .lead {
    max-width: 62ch;
    margin: 0;
    color: var(--subtext1);
    font-size: .93rem;
    line-height: 1.6;
  }
  .toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; flex: none; }
  .segmented {
    display: flex;
    gap: 2px;
    padding: 3px;
    border: 1px solid var(--card-border);
    border-radius: 11px;
    background: var(--surface0);
  }
  .seg-btn {
    border: 0;
    border-radius: 7px;
    padding: 6px 10px;
    background: transparent;
    color: var(--subtext0);
    font-size: .72rem;
    font-weight: 800;
    letter-spacing: .03em;
    cursor: pointer;
    transition: background .18s ease, color .18s ease;
  }
  .seg-btn:hover { color: var(--text); }
  .seg-btn.active { background: var(--surface2); color: var(--text); box-shadow: 0 2px 7px rgba(0, 0, 0, .12); }
  .icon-btn {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    min-height: 34px;
    padding: 6px 11px;
    border: 1px solid var(--card-border);
    border-radius: 10px;
    background: var(--surface0);
    color: var(--subtext1);
    font-size: .72rem;
    font-weight: 700;
    cursor: pointer;
    transition: background .18s ease, color .18s ease, border-color .18s ease;
  }
  .icon-btn:hover { background: var(--surface1); color: var(--text); }
  .icon-btn .icon { width: 15px; height: 15px; }
  .meta-row { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; margin-bottom: 22px; }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    min-height: 32px;
    padding: 6px 11px;
    border: 1px solid var(--card-border);
    border-radius: 999px;
    background: var(--surface0);
    color: var(--subtext1);
    font-size: .76rem;
    white-space: nowrap;
  }
  .chip strong { color: var(--text); font-weight: 800; }
  .chip .icon { width: 14px; height: 14px; color: var(--subtext0); }
  .chip-button { cursor: pointer; transition: background .18s ease, border-color .18s ease; }
  .chip-button:hover { background: var(--surface1); border-color: var(--surface2); }
  .chip-time { margin-left: auto; font-variant-numeric: tabular-nums; }
  .dot {
    width: 8px;
    height: 8px;
    flex: none;
    border-radius: 50%;
    background: var(--green);
    box-shadow: 0 0 0 3px var(--green-soft);
  }
  .dot[data-ok="false"] { background: var(--yellow); box-shadow: 0 0 0 3px var(--yellow-soft); }
  .grid {
    display: grid;
    grid-template-columns: minmax(0, .9fr) minmax(0, 1.1fr);
    align-items: start;
    gap: 20px;
  }
  .column { display: flex; min-width: 0; flex-direction: column; gap: 18px; }
  .card {
    padding: 20px;
    border: 1px solid var(--card-border);
    border-radius: 18px;
    background: var(--card);
    box-shadow: var(--card-shadow);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
  }
  .card-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: 18px;
  }
  .card-head h2 { margin: 0 0 4px; font-size: 1.05rem; letter-spacing: -.015em; }
  .card-head p { margin: 0; color: var(--subtext0); font-size: .8rem; line-height: 1.55; }
  .badge {
    display: inline-flex;
    align-items: center;
    flex: none;
    padding: 5px 9px;
    border: 1px solid var(--card-border);
    border-radius: 999px;
    background: var(--surface1);
    color: var(--subtext1);
    font-size: .68rem;
    font-weight: 800;
    letter-spacing: .02em;
    white-space: nowrap;
  }
  .badge[data-state="queued"], .badge[data-state="registering"], .badge[data-state="sending"] {
    background: var(--yellow-soft);
    border-color: transparent;
    color: var(--yellow);
  }
  .badge[data-state="success"] { background: var(--green-soft); border-color: transparent; color: var(--green); }
  .badge[data-state="failed"], .badge[data-state="timeout"] { background: var(--red-soft); border-color: transparent; color: var(--red); }
  .steps { margin: 0; padding: 0; list-style: none; }
  .step {
    position: relative;
    display: grid;
    grid-template-columns: 34px minmax(0, 1fr);
    gap: 12px;
    padding-bottom: 20px;
  }
  .step:last-child { padding-bottom: 0; }
  .step:not(:last-child)::before {
    content: "";
    position: absolute;
    left: 16px;
    top: 39px;
    bottom: 3px;
    width: 2px;
    border-radius: 2px;
    background: var(--surface1);
  }
  .step-num {
    position: relative;
    z-index: 1;
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    border: 1px solid var(--surface2);
    border-radius: 50%;
    background: var(--surface0);
    color: var(--subtext0);
    font-size: .78rem;
    font-weight: 800;
  }
  .step-body { min-width: 0; padding-top: 1px; }
  .step-body h3 { margin: 2px 0 3px; font-size: .9rem; letter-spacing: -.01em; }
  .step-body p { margin: 0 0 9px; color: var(--subtext0); font-size: .79rem; line-height: 1.55; }
  .step[data-state="active"] .step-num {
    border-color: var(--mauve);
    background: var(--mauve);
    color: var(--on-accent);
    box-shadow: 0 0 0 4px var(--mauve-soft);
  }
  .step[data-state="active"] h3 { color: var(--mauve); }
  .step[data-state="done"] .step-num {
    border-color: var(--green);
    background: var(--green);
    color: var(--on-accent);
    font-size: 0;
  }
  .step[data-state="done"] .step-num::after { content: "✓"; font-size: .88rem; }
  .step[data-state="done"]:not(:last-child)::before { background: var(--green); opacity: .55; }
  .step[data-state="error"] .step-num {
    border-color: var(--red);
    background: var(--red);
    color: #fff;
    font-size: 0;
  }
  .step[data-state="error"] .step-num::after { content: "!"; font-size: .9rem; }
  .step[data-state="error"] h3 { color: var(--red); }
  .help { padding: 0; overflow: hidden; }
  .help summary {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 16px 18px;
    list-style: none;
    cursor: pointer;
    font-size: .86rem;
    font-weight: 800;
  }
  .help summary::-webkit-details-marker { display: none; }
  .summary-left { display: inline-flex; align-items: center; gap: 8px; }
  .summary-left .icon { color: var(--mauve); }
  .help .chevron { color: var(--subtext0); transition: transform .2s ease; }
  .help[open] .chevron { transform: rotate(90deg); }
  .help-list {
    margin: 0;
    padding: 0 22px 18px 38px;
    color: var(--subtext1);
    font-size: .8rem;
    line-height: 1.55;
  }
  .help-list li + li { margin-top: 8px; }
  .privacy {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin: 0 4px;
    color: var(--subtext0);
    font-size: .73rem;
    line-height: 1.5;
  }
  .privacy .icon { width: 15px; height: 15px; margin-top: 2px; color: var(--mauve); }
  .field-label { display: block; margin-bottom: 7px; font-size: .78rem; font-weight: 800; }
  .textarea-shell {
    overflow: hidden;
    border: 1px solid var(--input-border);
    border-radius: 14px;
    background: var(--input);
    transition: border-color .18s ease, box-shadow .18s ease;
  }
  .textarea-shell:focus-within {
    border-color: var(--mauve);
    box-shadow: 0 0 0 4px var(--mauve-soft);
  }
  textarea {
    display: block;
    width: 100%;
    min-height: 148px;
    resize: vertical;
    border: 0;
    outline: 0;
    padding: 14px;
    background: transparent;
    color: var(--text);
    font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", "SFMono-Regular", Consolas, monospace;
    font-size: .79rem;
    line-height: 1.55;
  }
  textarea::placeholder { color: var(--subtext0); opacity: .62; }
  textarea:disabled { opacity: .55; cursor: not-allowed; }
  .textarea-foot {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 7px 9px;
    border-top: 1px solid var(--input-border);
    background: var(--mantle);
  }
  .textarea-actions { display: flex; gap: 3px; }
  .char-count { color: var(--subtext0); font-size: .68rem; font-variant-numeric: tabular-nums; }
  .checks { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
  .check {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 4px 8px;
    border: 1px solid var(--card-border);
    border-radius: 999px;
    background: var(--surface0);
    color: var(--subtext0);
    font-size: .68rem;
    font-weight: 800;
  }
  .check::before { content: "?"; font-size: .62rem; }
  .check[data-ok="true"] { border-color: transparent; background: var(--green-soft); color: var(--green); }
  .check[data-ok="true"]::before { content: "✓"; }
  .check[data-ok="false"] { border-color: transparent; background: var(--red-soft); color: var(--red); }
  .check[data-ok="false"]::before { content: "!"; }
  .validation-msg { margin: 8px 0 0; color: var(--red); font-size: .76rem; line-height: 1.45; }
  .actions { display: flex; align-items: center; flex-wrap: wrap; gap: 12px; margin-top: 14px; }
  .keyboard-hint { color: var(--subtext0); font-size: .68rem; }
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    padding: 10px 15px;
    border: 1px solid transparent;
    border-radius: 10px;
    font-size: .79rem;
    font-weight: 800;
    text-decoration: none;
    white-space: nowrap;
    cursor: pointer;
    transition: transform .15s ease, filter .15s ease, background .15s ease, border-color .15s ease;
  }
  .btn:hover { filter: brightness(1.06); transform: translateY(-1px); }
  .btn:active { transform: translateY(0); }
  .btn:disabled { opacity: .48; cursor: not-allowed; transform: none; filter: none; }
  .btn-primary {
    background: linear-gradient(135deg, var(--mauve), var(--blue));
    color: var(--on-accent);
    box-shadow: 0 10px 26px var(--mauve-soft);
  }
  .btn-secondary { border-color: var(--surface2); background: var(--surface1); color: var(--text); }
  .btn-ghost { border-color: transparent; background: transparent; color: var(--subtext1); }
  .btn-ghost:hover { background: var(--surface1); color: var(--text); }
  .btn-xs { padding: 5px 8px; border-radius: 7px; font-size: .68rem; }
  .btn-sm { padding: 7px 11px; font-size: .73rem; }
  .btn .icon { width: 15px; height: 15px; }
  .spinner {
    width: 14px;
    height: 14px;
    flex: none;
    border: 2px solid currentColor;
    border-right-color: transparent;
    border-radius: 50%;
    animation: spin .8s linear infinite;
  }
  .icon.spinning { animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .status {
    display: flex;
    gap: 12px;
    margin-top: 16px;
    padding: 14px;
    border: 1px solid var(--card-border);
    border-left: 4px solid var(--blue);
    border-radius: 14px;
    background: var(--mantle);
  }
  .status[data-state="queued"], .status[data-state="registering"], .status[data-state="sending"] { border-left-color: var(--yellow); }
  .status[data-state="success"] { border-left-color: var(--green); }
  .status[data-state="failed"], .status[data-state="timeout"] { border-left-color: var(--red); }
  .status-icon {
    display: grid;
    place-items: center;
    flex: none;
    width: 36px;
    height: 36px;
    border-radius: 10px;
    background: var(--blue-soft);
    color: var(--blue);
  }
  .status[data-state="queued"] .status-icon,
  .status[data-state="registering"] .status-icon,
  .status[data-state="sending"] .status-icon { background: var(--yellow-soft); color: var(--yellow); }
  .status[data-state="success"] .status-icon { background: var(--green-soft); color: var(--green); }
  .status[data-state="failed"] .status-icon,
  .status[data-state="timeout"] .status-icon { background: var(--red-soft); color: var(--red); }
  .status-body { flex: 1; min-width: 0; }
  .status-top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .status-top strong { font-size: .85rem; }
  .status-body p { margin: 3px 0 0; color: var(--subtext1); font-size: .77rem; line-height: 1.5; overflow-wrap: anywhere; }
  .status-detail { color: var(--subtext0) !important; font-size: .71rem !important; }
  .progress { height: 6px; margin-top: 10px; overflow: hidden; border-radius: 99px; background: var(--surface1); }
  .progress span {
    display: block;
    width: 0;
    height: 100%;
    border-radius: inherit;
    background: linear-gradient(90deg, var(--blue), var(--mauve));
    transition: width 1s linear;
  }
  .progress[data-tone="warn"] span { background: linear-gradient(90deg, var(--yellow), var(--peach)); }
  .progress[data-tone="danger"] span { background: var(--red); }
  .status-meta { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 8px; color: var(--subtext0); font-size: .67rem; }
  .success { padding: 8px 4px 2px; text-align: center; }
  .success-icon {
    display: grid;
    place-items: center;
    width: 64px;
    height: 64px;
    margin: 0 auto 14px;
    border-radius: 20px;
    background: var(--green-soft);
    color: var(--green);
    box-shadow: 0 0 0 8px var(--green-soft);
  }
  .success-icon .icon { width: 32px; height: 32px; }
  .success h2 { margin: 0 0 6px; font-size: 1.3rem; letter-spacing: -.025em; }
  .success p { max-width: 48ch; margin: 0 auto 16px; color: var(--subtext1); font-size: .83rem; line-height: 1.6; }
  .device-box {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-wrap: wrap;
    gap: 8px;
    max-width: 360px;
    margin: 0 auto 16px;
    padding: 10px 12px;
    border: 1px solid var(--card-border);
    border-radius: 12px;
    background: var(--mantle);
    font-size: .78rem;
  }
  .device-box code { color: var(--mauve); font-size: .9rem; font-weight: 800; }
  .success-actions { display: flex; justify-content: center; flex-wrap: wrap; gap: 8px; }
  .pin-note { margin-top: 14px !important; color: var(--subtext0) !important; font-size: .72rem !important; }
  .foot {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 26px;
    padding: 0 4px;
    color: var(--subtext0);
    font-size: .71rem;
  }
  .foot p { margin: 0; }
  .foot-secret { opacity: .8; }
  .toast {
    position: fixed;
    left: 50%;
    bottom: 24px;
    z-index: 60;
    max-width: calc(100vw - 32px);
    padding: 9px 14px;
    transform: translateX(-50%);
    border: 1px solid var(--card-border);
    border-radius: 999px;
    background: var(--surface2);
    color: var(--text);
    box-shadow: var(--card-shadow);
    font-size: .76rem;
  }
  .noscript {
    margin: 20px auto;
    padding: 14px;
    border: 1px solid var(--red);
    border-radius: 12px;
    background: var(--red-soft);
    color: var(--text);
    font-size: .82rem;
    text-align: center;
  }
  .sprite { position: absolute; width: 0; height: 0; overflow: hidden; }
  .icon {
    width: 18px;
    height: 18px;
    flex: none;
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;
  }
  .icon-lg { width: 26px; height: 26px; }
  .icon-xl { width: 34px; height: 34px; }
  @media (max-width: 900px) {
    .hero { flex-direction: column; }
    .toolbar { align-self: flex-end; }
    .grid { grid-template-columns: minmax(0, 1fr); }
    .chip-time { margin-left: 0; }
  }
  @media (max-width: 560px) {
    .shell { padding: 22px 14px 44px; }
    .identity { gap: 12px; }
    .logo { width: 46px; height: 46px; border-radius: 15px; }
    .logo .icon { width: 24px; height: 24px; }
    h1 { font-size: clamp(1.3rem, 6vw, 1.5rem); }
    .lead { font-size: .86rem; }
    .card { padding: 16px; border-radius: 15px; }
    .meta-row { gap: 6px; }
    .chip { min-height: 30px; padding: 5px 9px; font-size: .71rem; }
    .actions .btn-primary { flex: 1; }
    .keyboard-hint { width: 100%; text-align: center; }
    .foot { flex-direction: column; align-items: flex-start; }
  }
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after {
      scroll-behavior: auto !important;
      animation-duration: .001ms !important;
      animation-iteration-count: 1 !important;
      transition-duration: .001ms !important;
    }
  }
</style>
</head>
<body>
<a class="skip" href="#main" data-i18n="skip">Langsung ke formulir</a>
<div class="shell">
  <header class="hero">
    <div class="identity">
      <div class="logo" aria-hidden="true"><svg class="icon icon-lg"><use href="#i-shield"/></svg></div>
      <div class="identity-text">
        <p class="eyebrow" data-i18n="eyebrow">CHROME REMOTE DESKTOP</p>
        <h1 data-i18n="heroTitle">Hubungkan desktop Anda</h1>
        <p class="lead" data-i18n="heroLead">Desktop {desktop} sudah siap. Tinggal menghubungkan perangkat ke akun Google Anda.</p>
      </div>
    </div>
    <div class="toolbar">
      <div class="segmented" role="group" aria-label="Pilih bahasa" data-i18n-aria="languageLabel">
        <button type="button" class="seg-btn active" data-lang-btn="id" aria-pressed="true">ID</button>
        <button type="button" class="seg-btn" data-lang-btn="en" aria-pressed="false">EN</button>
      </div>
      <button type="button" class="icon-btn" id="theme-btn" aria-label="Ganti tema">
        <svg class="icon" aria-hidden="true"><use id="theme-icon" href="#i-auto"/></svg>
        <span id="theme-label">Auto</span>
      </button>
    </div>
  </header>

  <div class="meta-row">
    <span class="chip"><span class="dot" id="conn-dot" data-ok="true"></span><span id="conn-text">Terhubung</span></span>
    <span class="chip"><svg class="icon" aria-hidden="true"><use href="#i-monitor"/></svg><span data-i18n="metaDesktop">Desktop</span><strong data-desktop>__DESKTOP__</strong></span>
    <span class="chip"><svg class="icon" aria-hidden="true"><use href="#i-terminal"/></svg><span data-i18n="metaDevice">Device</span><strong data-device>__DEVICE__</strong></span>
    <button type="button" class="chip chip-button" id="copy-device-meta"><svg class="icon" aria-hidden="true"><use href="#i-copy"/></svg><span data-i18n="copyDevice">Salin nama device</span></button>
    <span class="chip chip-time" id="countdown" hidden><svg class="icon" aria-hidden="true"><use href="#i-clock"/></svg><span id="countdown-text"></span></span>
  </div>

  <main id="main" class="grid">
    <div class="column">
      <section class="card guide" aria-labelledby="guide-title">
        <div class="card-head">
          <div>
            <h2 id="guide-title" data-i18n="guide.title">Panduan</h2>
            <p data-i18n="guide.subtitle">Ikuti empat langkah berikut. Halaman ini memperbarui status secara otomatis.</p>
          </div>
          <span class="badge" data-i18n="guide.badge">4 langkah</span>
        </div>
        <ol class="steps" id="steps">
          <li class="step" data-step="1" data-state="active">
            <span class="step-num" aria-hidden="true">1</span>
            <div class="step-body">
              <h3 data-i18n="step1.title">Buka halaman Google</h3>
              <p data-i18n="step1.desc">Login dengan akun Google yang akan dipakai, lalu klik Begin → Next → Authorize.</p>
              <a class="btn btn-secondary btn-sm" href="https://remotedesktop.google.com/headless" target="_blank" rel="noreferrer noopener">
                <svg class="icon" aria-hidden="true"><use href="#i-external"/></svg>
                <span data-i18n="step1.action">Buka halaman headless</span>
              </a>
            </div>
          </li>
          <li class="step" data-step="2" data-state="pending">
            <span class="step-num" aria-hidden="true">2</span>
            <div class="step-body">
              <h3 data-i18n="step2.title">Salin perintah Debian</h3>
              <p data-i18n="step2.desc">Di bagian “Set up another computer”, pilih Debian Linux dan salin SELURUH perintah yang muncul.</p>
            </div>
          </li>
          <li class="step" data-step="3" data-state="pending">
            <span class="step-num" aria-hidden="true">3</span>
            <div class="step-body">
              <h3 data-i18n="step3.title">Tempel dan kirim</h3>
              <p data-i18n="step3.desc">Tempel perintah ke formulir di samping, lalu kirim. Jangan tutup halaman ini saat proses berjalan.</p>
            </div>
          </li>
          <li class="step" data-step="4" data-state="pending">
            <span class="step-num" aria-hidden="true">4</span>
            <div class="step-body">
              <h3 data-i18n="step4.title">Hubungkan perangkat</h3>
              <p data-i18n="step4.desc">Setelah status berhasil, buka Remote Access, pilih device, lalu masukkan PIN.</p>
              <a class="btn btn-secondary btn-sm" href="https://remotedesktop.google.com/access" target="_blank" rel="noreferrer noopener">
                <svg class="icon" aria-hidden="true"><use href="#i-external"/></svg>
                <span data-i18n="step4.action">Buka Remote Access</span>
              </a>
            </div>
          </li>
        </ol>
      </section>

      <details class="card help">
        <summary>
          <span class="summary-left"><svg class="icon" aria-hidden="true"><use href="#i-key"/></svg><span data-i18n="help.title">Butuh bantuan?</span></span>
          <svg class="icon chevron" aria-hidden="true"><use href="#i-chevron"/></svg>
        </summary>
        <ul class="help-list">
          <li data-i18n="help.code">Kode --code=... hanya bisa dipakai sekali. Kalau registrasi gagal, buat kode baru dari halaman headless.</li>
          <li data-i18n="help.refresh">Jangan refresh workflow selama menunggu. Form ini tetap terbuka sampai batas waktu habis.</li>
          <li data-i18n="help.timeout">Kalau waktu habis, jalankan ulang workflow. Cache .deb membuat run berikutnya lebih cepat.</li>
          <li data-i18n="help.device">Device tidak muncul? Tunggu status berhasil, refresh halaman Remote Access, lalu cek service chrome-remote-desktop@runner.</li>
          <li data-i18n="help.pin">PIN default adalah 123456, kecuali Anda mengatur secret CRD_PIN.</li>
        </ul>
      </details>

      <p class="privacy">
        <svg class="icon" aria-hidden="true"><use href="#i-shield"/></svg>
        <span data-i18n="privacy">URL halaman ini mengandung token rahasia. Jangan dibagikan atau disimpan di tempat publik.</span>
      </p>
    </div>
    <div class="column">
      <section class="card form-card" aria-labelledby="form-title">
        <div class="card-head">
          <div>
            <h2 id="form-title" data-i18n="form.title">Perintah Chrome Remote Desktop</h2>
            <p data-i18n="form.subtitle">Tempel perintah Debian Linux yang Anda salin dari halaman headless.</p>
          </div>
          <span class="badge badge-state" id="state-badge" data-state="waiting">Menunggu</span>
        </div>

        <div id="form-wrap">
          <form id="form" autocomplete="off" novalidate>
            <label class="field-label" for="cmd" data-i18n="form.label">Perintah start-host</label>
            <div class="textarea-shell">
              <textarea id="cmd" name="command" spellcheck="false" autocapitalize="off" autocomplete="off" aria-describedby="validation-msg" placeholder="DISPLAY= /opt/google/chrome-remote-desktop/start-host --code=&quot;4/0...&quot; --redirect-url=&quot;https://remotedesktop.google.com/_/oauthredirect&quot; --name=$(hostname)"></textarea>
              <div class="textarea-foot">
                <div class="textarea-actions">
                  <button type="button" class="btn btn-ghost btn-xs" id="paste-btn">
                    <svg class="icon" aria-hidden="true"><use href="#i-paste"/></svg>
                    <span data-i18n="form.paste">Tempel</span>
                  </button>
                  <button type="button" class="btn btn-ghost btn-xs" id="clear-btn">
                    <svg class="icon" aria-hidden="true"><use href="#i-trash"/></svg>
                    <span data-i18n="form.clear">Bersihkan</span>
                  </button>
                </div>
                <span class="char-count" id="char-count">0 / 4096</span>
              </div>
            </div>
            <div class="checks" id="checks" hidden aria-live="polite"></div>
            <p class="validation-msg" id="validation-msg" role="alert" hidden></p>
            <div class="actions">
              <button type="submit" class="btn btn-primary" id="submit-btn" disabled>
                <span class="spinner" id="submit-spinner" aria-hidden="true" hidden></span>
                <span id="submit-label">Kirim &amp; daftarkan</span>
              </button>
              <span class="keyboard-hint" data-i18n="form.keyboard">Ctrl/Cmd + Enter untuk mengirim</span>
            </div>
          </form>

          <section class="status" id="status" data-state="waiting" role="status" aria-live="polite" aria-atomic="true">
            <div class="status-icon" id="status-icon"><svg class="icon" aria-hidden="true"><use id="status-icon-use" href="#i-clock"/></svg></div>
            <div class="status-body">
              <div class="status-top"><strong id="status-title">Menunggu perintah</strong></div>
              <p id="status-message">Buka halaman Google di langkah 1, authorize, lalu tempel perintah di formulir.</p>
              <p class="status-detail" id="status-detail" hidden></p>
              <div class="progress" id="progress" hidden><span id="progress-bar"></span></div>
              <div class="status-meta"><span id="status-attempts"></span><span id="status-updated"></span></div>
            </div>
          </section>
        </div>

        <section class="success" id="success" aria-live="polite" hidden>
          <div class="success-icon"><svg class="icon icon-xl" aria-hidden="true"><use href="#i-check"/></svg></div>
          <h2 data-i18n="success.title">Berhasil terhubung</h2>
          <p data-i18n="success.desc">Perangkat sudah terdaftar di akun Google Anda. Tinggal buka Remote Access dan masukkan PIN.</p>
          <div class="device-box">
            <span data-i18n="success.deviceLabel">Device</span>
            <code data-device>__DEVICE__</code>
            <button type="button" class="btn btn-ghost btn-xs" id="copy-device-success">
              <svg class="icon" aria-hidden="true"><use href="#i-copy"/></svg>
              <span data-i18n="success.copy">Salin</span>
            </button>
          </div>
          <div class="success-actions">
            <a class="btn btn-primary" href="https://remotedesktop.google.com/access" target="_blank" rel="noreferrer noopener">
              <svg class="icon" aria-hidden="true"><use href="#i-external"/></svg>
              <span data-i18n="success.open">Buka Remote Access</span>
            </a>
          </div>
          <p class="pin-note" data-i18n="success.pin">Gunakan user runner dan PIN yang Anda atur (default 123456).</p>
        </section>
      </section>
    </div>
  </main>

  <footer class="foot">
    <p data-i18n="footer.note">Halaman ini hanya aktif selama workflow menunggu.</p>
    <p class="foot-secret" data-i18n="footer.secret">URL ini bersifat rahasia — jangan dibagikan.</p>
  </footer>
</div>

<div class="toast" id="toast" role="status" aria-live="polite" hidden></div>
<noscript><div class="noscript" data-i18n="noscript">JavaScript diperlukan untuk validasi dan pembaruan status otomatis.</div></noscript>

<svg class="sprite" aria-hidden="true" focusable="false">
  <symbol id="i-shield" viewBox="0 0 24 24"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></symbol>
  <symbol id="i-monitor" viewBox="0 0 24 24"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/></symbol>
  <symbol id="i-terminal" viewBox="0 0 24 24"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="m6 9 3 3-3 3M13 15h5"/></symbol>
  <symbol id="i-copy" viewBox="0 0 24 24"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></symbol>
  <symbol id="i-check" viewBox="0 0 24 24"><path d="m20 6-11 11-5-5"/></symbol>
  <symbol id="i-alert" viewBox="0 0 24 24"><path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/></symbol>
  <symbol id="i-clock" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></symbol>
  <symbol id="i-spinner" viewBox="0 0 24 24"><path d="M21 12a9 9 0 1 1-6.2-8.6"/></symbol>
  <symbol id="i-sun" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></symbol>
  <symbol id="i-moon" viewBox="0 0 24 24"><path d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8z"/></symbol>
  <symbol id="i-auto" viewBox="0 0 24 24"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/><path d="M8 8h4M8 11h8"/></symbol>
  <symbol id="i-external" viewBox="0 0 24 24"><path d="M15 3h6v6M10 14 21 3M21 14v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5"/></symbol>
  <symbol id="i-chevron" viewBox="0 0 24 24"><path d="m9 18 6-6-6-6"/></symbol>
  <symbol id="i-paste" viewBox="0 0 24 24"><rect x="8" y="2" width="8" height="4" rx="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/></symbol>
  <symbol id="i-trash" viewBox="0 0 24 24"><path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></symbol>
  <symbol id="i-key" viewBox="0 0 24 24"><circle cx="7.5" cy="15.5" r="5.5"/><path d="m21 2-9.6 9.6M15.5 7.5l3 3L22 7l-3-3"/></symbol>
</svg>
<script>
(function () {
  "use strict";

  var DESKTOP = __DESKTOP_JSON__;
  var DEVICE = __DEVICE_JSON__;
  var TOKEN = __TOKEN_JSON__;
  var BASE = "/" + TOKEN;
  var MAX_BYTES = 4096;
  var THEME_ORDER = ["auto", "light", "dark"];

  var I18N = {
    id: {
      "docTitle": "Otorisasi Chrome Remote Desktop",
      "eyebrow": "CHROME REMOTE DESKTOP",
      "heroTitle": "Hubungkan desktop Anda",
      "heroLead": "Desktop {desktop} sudah siap. Tinggal menghubungkan perangkat ke akun Google Anda.",
      "skip": "Langsung ke formulir",
      "languageLabel": "Pilih bahasa",
      "theme.auto": "Auto",
      "theme.light": "Terang",
      "theme.dark": "Gelap",
      "theme.switch": "Ganti tema",
      "connection.online": "Terhubung",
      "connection.offline": "Menyambung ulang...",
      "metaDesktop": "Desktop",
      "metaDevice": "Device",
      "copyDevice": "Salin nama device",
      "copyDeviceShort": "Salin",
      "guide.title": "Panduan",
      "guide.subtitle": "Ikuti empat langkah berikut. Halaman ini memperbarui status secara otomatis.",
      "guide.badge": "4 langkah",
      "step1.title": "Buka halaman Google",
      "step1.desc": "Login dengan akun Google yang akan dipakai, lalu klik Begin → Next → Authorize.",
      "step1.action": "Buka halaman headless",
      "step2.title": "Salin perintah Debian",
      "step2.desc": "Di bagian “Set up another computer”, pilih Debian Linux dan salin SELURUH perintah yang muncul.",
      "step3.title": "Tempel dan kirim",
      "step3.desc": "Tempel perintah ke formulir di samping, lalu kirim. Jangan tutup halaman ini saat proses berjalan.",
      "step4.title": "Hubungkan perangkat",
      "step4.desc": "Setelah status berhasil, buka Remote Access, pilih device, lalu masukkan PIN.",
      "step4.action": "Buka Remote Access",
      "help.title": "Butuh bantuan?",
      "help.code": "Kode --code=... hanya bisa dipakai sekali. Kalau registrasi gagal, buat kode baru dari halaman headless.",
      "help.refresh": "Jangan refresh workflow selama menunggu. Form ini tetap terbuka sampai batas waktu habis.",
      "help.timeout": "Kalau waktu habis, jalankan ulang workflow. Cache .deb membuat run berikutnya lebih cepat.",
      "help.device": "Device tidak muncul? Tunggu status berhasil, refresh halaman Remote Access, lalu cek service chrome-remote-desktop@runner.",
      "help.pin": "PIN default adalah 123456, kecuali Anda mengatur secret CRD_PIN.",
      "privacy": "URL halaman ini mengandung token rahasia. Jangan dibagikan atau disimpan di tempat publik.",
      "form.title": "Perintah Chrome Remote Desktop",
      "form.subtitle": "Tempel perintah Debian Linux yang Anda salin dari halaman headless.",
      "form.label": "Perintah start-host",
      "form.paste": "Tempel",
      "form.clear": "Bersihkan",
      "form.submit": "Kirim & daftarkan",
      "form.submitting": "Mengirim...",
      "form.keyboard": "Ctrl/Cmd + Enter untuk mengirim",
      "form.checks.format": "Format",
      "form.checks.code": "Kode OAuth",
      "form.checks.line": "Satu baris",
      "form.checks.size": "Ukuran",
      "validation.empty": "Tempel perintah terlebih dahulu.",
      "validation.format": "Format belum dikenali. Salin seluruh perintah Debian Linux dari halaman headless.",
      "validation.code": "Perintah belum mengandung --code=.",
      "validation.line": "Perintah harus satu baris.",
      "validation.size": "Perintah terlalu panjang (maksimal 4096 byte).",
      "validation.forbidden": "Perintah mengandung karakter yang tidak diizinkan.",
      "validation.control": "Perintah mengandung karakter kontrol.",
      "status.waiting.label": "Menunggu",
      "status.waiting.title": "Menunggu perintah",
      "status.waiting.message": "Buka halaman Google di langkah 1, authorize, lalu tempel perintah di formulir.",
      "status.queued.label": "Diterima",
      "status.queued.title": "Perintah diterima",
      "status.queued.message": "Menunggu proses registrasi dimulai...",
      "status.registering.label": "Memproses",
      "status.registering.title": "Mendaftarkan perangkat",
      "status.registering.message": "Jangan tutup halaman ini. Registrasi biasanya selesai dalam beberapa detik.",
      "status.sending.label": "Mengirim",
      "status.sending.title": "Mengirim perintah",
      "status.sending.message": "Menghubungi server untuk memulai registrasi...",
      "status.success.label": "Berhasil",
      "status.success.title": "Perangkat berhasil didaftarkan",
      "status.success.message": "Buka Remote Access dan pilih device {device}.",
      "status.failed.label": "Gagal",
      "status.failed.title": "Registrasi gagal",
      "status.failed.message": "Ambil kode baru di halaman headless lalu kirim lagi. Tidak perlu re-run workflow.",
      "status.timeout.label": "Waktu habis",
      "status.timeout.title": "Waktu tunggu habis",
      "status.timeout.message": "Jalankan ulang workflow untuk membuka form baru.",
      "status.attempts": "Percobaan: {n}",
      "status.updated": "Diperbarui {time}",
      "status.remaining": "Sisa {time}",
      "status.expired": "Waktu habis",
      "status.detail": "Detail: {detail}",
      "success.title": "Berhasil terhubung",
      "success.desc": "Perangkat sudah terdaftar di akun Google Anda. Tinggal buka Remote Access dan masukkan PIN.",
      "success.deviceLabel": "Device",
      "success.copy": "Salin",
      "success.open": "Buka Remote Access",
      "success.pin": "Gunakan user runner dan PIN yang Anda atur (default 123456).",
      "footer.note": "Halaman ini hanya aktif selama workflow menunggu.",
      "footer.secret": "URL ini bersifat rahasia — jangan dibagikan.",
      "toast.copied": "Nama device disalin.",
      "toast.copyFailed": "Tidak bisa menyalin. Salin nama device secara manual.",
      "toast.pasteEmpty": "Clipboard kosong. Tempel manual dengan Ctrl/Cmd + V.",
      "toast.pasteFailed": "Tidak bisa membaca clipboard. Tempel manual dengan Ctrl/Cmd + V.",
      "toast.pasted": "Perintah ditempel dari clipboard.",
      "toast.submitFailed": "Perintah belum terkirim. Periksa pesan di bawah formulir.",
      "noscript": "JavaScript diperlukan untuk validasi dan pembaruan status otomatis."
    },
    en: {
      "docTitle": "Chrome Remote Desktop Authorization",
      "eyebrow": "CHROME REMOTE DESKTOP",
      "heroTitle": "Connect your desktop",
      "heroLead": "The {desktop} desktop is ready. All that's left is linking it to your Google account.",
      "skip": "Skip to form",
      "languageLabel": "Choose language",
      "theme.auto": "Auto",
      "theme.light": "Light",
      "theme.dark": "Dark",
      "theme.switch": "Change theme",
      "connection.online": "Connected",
      "connection.offline": "Reconnecting...",
      "metaDesktop": "Desktop",
      "metaDevice": "Device",
      "copyDevice": "Copy device name",
      "copyDeviceShort": "Copy",
      "guide.title": "Guide",
      "guide.subtitle": "Follow the four steps below. This page updates the status automatically.",
      "guide.badge": "4 steps",
      "step1.title": "Open the Google page",
      "step1.desc": "Sign in with the Google account you want to use, then click Begin → Next → Authorize.",
      "step1.action": "Open headless page",
      "step2.title": "Copy the Debian command",
      "step2.desc": "Under “Set up another computer”, choose Debian Linux and copy the ENTIRE command shown.",
      "step3.title": "Paste and submit",
      "step3.desc": "Paste the command into the form and submit. Keep this page open while it runs.",
      "step4.title": "Connect the device",
      "step4.desc": "When the status turns successful, open Remote Access, pick the device, and enter your PIN.",
      "step4.action": "Open Remote Access",
      "help.title": "Need help?",
      "help.code": "The --code=... value is single-use. If registration fails, create a new code on the headless page.",
      "help.refresh": "Do not refresh the workflow while waiting. This form stays open until the deadline.",
      "help.timeout": "If time runs out, re-run the workflow. The .deb cache makes the next run much faster.",
      "help.device": "Device not showing up? Wait for success, refresh Remote Access, then check chrome-remote-desktop@runner.",
      "help.pin": "The default PIN is 123456 unless you configured the CRD_PIN secret.",
      "privacy": "This page URL contains a secret token. Do not share it or save it in a public place.",
      "form.title": "Chrome Remote Desktop command",
      "form.subtitle": "Paste the Debian Linux command you copied from the headless page.",
      "form.label": "start-host command",
      "form.paste": "Paste",
      "form.clear": "Clear",
      "form.submit": "Submit & register",
      "form.submitting": "Submitting...",
      "form.keyboard": "Ctrl/Cmd + Enter to submit",
      "form.checks.format": "Format",
      "form.checks.code": "OAuth code",
      "form.checks.line": "Single line",
      "form.checks.size": "Size",
      "validation.empty": "Paste a command first.",
      "validation.format": "Unrecognized format. Copy the entire Debian Linux command from the headless page.",
      "validation.code": "The command does not contain --code=.",
      "validation.line": "The command must be a single line.",
      "validation.size": "The command is too long (maximum 4096 bytes).",
      "validation.forbidden": "The command contains a forbidden character.",
      "validation.control": "The command contains a control character.",
      "status.waiting.label": "Waiting",
      "status.waiting.title": "Waiting for a command",
      "status.waiting.message": "Open the Google page in step 1, authorize, then paste the command into the form.",
      "status.queued.label": "Received",
      "status.queued.title": "Command received",
      "status.queued.message": "Waiting for registration to start...",
      "status.registering.label": "Processing",
      "status.registering.title": "Registering the device",
      "status.registering.message": "Keep this page open. Registration usually finishes in a few seconds.",
      "status.sending.label": "Sending",
      "status.sending.title": "Sending the command",
      "status.sending.message": "Contacting the server to start registration...",
      "status.success.label": "Success",
      "status.success.title": "Device registered successfully",
      "status.success.message": "Open Remote Access and select device {device}.",
      "status.failed.label": "Failed",
      "status.failed.title": "Registration failed",
      "status.failed.message": "Create a new code on the headless page and submit again. No workflow re-run needed.",
      "status.timeout.label": "Expired",
      "status.timeout.title": "Time is up",
      "status.timeout.message": "Re-run the workflow to open a new form.",
      "status.attempts": "Attempts: {n}",
      "status.updated": "Updated {time}",
      "status.remaining": "{time} left",
      "status.expired": "Expired",
      "status.detail": "Detail: {detail}",
      "success.title": "Connected successfully",
      "success.desc": "The device is registered to your Google account. Open Remote Access and enter your PIN.",
      "success.deviceLabel": "Device",
      "success.copy": "Copy",
      "success.open": "Open Remote Access",
      "success.pin": "Use user runner and the PIN you configured (default 123456).",
      "footer.note": "This page is only active while the workflow is waiting.",
      "footer.secret": "This URL is secret — do not share it.",
      "toast.copied": "Device name copied.",
      "toast.copyFailed": "Could not copy. Copy the device name manually.",
      "toast.pasteEmpty": "Clipboard is empty. Paste manually with Ctrl/Cmd + V.",
      "toast.pasteFailed": "Could not read the clipboard. Paste manually with Ctrl/Cmd + V.",
      "toast.pasted": "Command pasted from the clipboard.",
      "toast.submitFailed": "The command was not sent. Check the message below the form.",
      "noscript": "JavaScript is required for validation and automatic status updates."
    }
  };

  var ui = {
    lang: "id",
    themePref: "auto",
    busy: false,
    connected: true,
    deadline: 0,
    initialRemaining: 0,
    serverOffset: 0,
    lastStatus: null,
    lastState: "waiting",
    polling: false,
    toastTimer: 0
  };

  function $(selector, root) { return (root || document).querySelector(selector); }
  function $$(selector, root) { return Array.prototype.slice.call((root || document).querySelectorAll(selector)); }

  function t(key, vars) {
    var table = I18N[ui.lang] || I18N.id;
    var text = table[key];
    if (text === undefined) text = I18N.id[key];
    if (text === undefined) text = key;
    if (vars) {
      Object.keys(vars).forEach(function (name) {
        text = text.split("{" + name + "}").join(String(vars[name]));
      });
    }
    return text;
  }

  function byteLength(value) {
    try { return new TextEncoder().encode(value).length; }
    catch (err) { return unescape(encodeURIComponent(value)).length; }
  }

  function safeStore(key, value) {
    try { localStorage.setItem(key, value); } catch (err) { /* private mode */ }
  }

  function formatDuration(seconds) {
    var total = Math.max(0, Math.round(seconds));
    var mins = Math.floor(total / 60);
    var secs = total % 60;
    return mins + ":" + (secs < 10 ? "0" : "") + secs;
  }

  function formatTime(epoch) {
    try {
      return new Date(epoch * 1000).toLocaleTimeString(ui.lang === "en" ? "en-GB" : "id-ID", {
        hour: "2-digit", minute: "2-digit", second: "2-digit"
      });
    } catch (err) { return ""; }
  }

  function serverNow() { return (Date.now() / 1000) + ui.serverOffset; }

  function isLocked(state) {
    return state === "queued" || state === "registering" || state === "success" || state === "timeout" || state === "sending";
  }

  function updateThemeButton() {
    var label = t("theme." + ui.themePref);
    var button = $("#theme-btn");
    var text = $("#theme-label");
    if (text) text.textContent = label;
    if (button) button.setAttribute("aria-label", t("theme.switch") + ": " + label);
  }

  function applyTheme(pref, persist) {
    if (THEME_ORDER.indexOf(pref) === -1) pref = "auto";
    ui.themePref = pref;
    if (persist !== false) safeStore("crd.theme", pref);
    var light = pref === "light" || (pref === "auto" && window.matchMedia("(prefers-color-scheme: light)").matches);
    var resolved = light ? "light" : "dark";
    document.documentElement.dataset.theme = resolved;
    document.documentElement.dataset.themePref = pref;
    document.documentElement.style.colorScheme = resolved;
    var icon = $("#theme-icon");
    if (icon) icon.setAttribute("href", "#i-" + (pref === "auto" ? "auto" : resolved));
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", light ? "#f5f5f5" : "#0d0d0d");
    updateThemeButton();
  }

  function cycleTheme() {
    var index = THEME_ORDER.indexOf(ui.themePref);
    applyTheme(THEME_ORDER[(index + 1) % THEME_ORDER.length]);
  }
  function updateSubmitLabel() {
    var label = $("#submit-label");
    if (label) label.textContent = ui.busy ? t("form.submitting") : t("form.submit");
  }

  function setConnection(ok) {
    ui.connected = ok;
    var dot = $("#conn-dot");
    var text = $("#conn-text");
    if (dot) dot.dataset.ok = ok ? "true" : "false";
    if (text) text.textContent = t(ok ? "connection.online" : "connection.offline");
  }

  function showToast(message) {
    var toast = $("#toast");
    if (!toast) return;
    toast.textContent = message;
    toast.hidden = false;
    clearTimeout(ui.toastTimer);
    ui.toastTimer = setTimeout(function () { toast.hidden = true; }, 2800);
  }

  function copyText(value) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(value).then(function () { return true; }, function () { return fallbackCopy(value); });
    }
    return Promise.resolve(fallbackCopy(value));
  }

  function fallbackCopy(value) {
    var area = document.createElement("textarea");
    area.value = value;
    area.setAttribute("readonly", "readonly");
    area.style.position = "fixed";
    area.style.top = "-1000px";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
    document.body.removeChild(area);
    return ok;
  }

  function copyDevice() {
    copyText(DEVICE).then(function (ok) {
      showToast(t(ok ? "toast.copied" : "toast.copyFailed"));
    });
  }

  function pasteCommand() {
    var field = $("#cmd");
    if (!field) return;
    if (!navigator.clipboard || !window.isSecureContext) {
      field.focus();
      showToast(t("toast.pasteFailed"));
      return;
    }
    navigator.clipboard.readText().then(function (text) {
      if (!text || !text.trim()) {
        field.focus();
        showToast(t("toast.pasteEmpty"));
        return;
      }
      field.value = text;
      field.dispatchEvent(new Event("input", { bubbles: true }));
      field.focus();
      showToast(t("toast.pasted"));
    }, function () {
      field.focus();
      showToast(t("toast.pasteFailed"));
    });
  }

  function applyLanguage(lang, persist) {
    ui.lang = lang === "en" ? "en" : "id";
    document.documentElement.lang = ui.lang;
    if (persist !== false) safeStore("crd.lang", ui.lang);
    $$("[data-i18n]").forEach(function (el) {
      el.textContent = t(el.dataset.i18n, { desktop: DESKTOP, device: DEVICE });
    });
    $$("[data-i18n-aria]").forEach(function (el) {
      el.setAttribute("aria-label", t(el.dataset.i18nAria));
    });
    $$("[data-lang-btn]").forEach(function (btn) {
      var active = btn.dataset.langBtn === ui.lang;
      btn.classList.toggle("active", active);
      btn.setAttribute("aria-pressed", active ? "true" : "false");
    });
    document.title = t("docTitle") + " · " + DESKTOP;
    updateSubmitLabel();
    updateThemeButton();
    setConnection(ui.connected);
    if (ui.lastStatus) renderStatus(ui.lastStatus);
    updateChecks();
    renderCountdown();
  }

  function validateCommand(raw) {
    var cleaned = raw.replace(/--name=(?:"[^"]*"|\S+)/g, "").trim();
    var singleLine = !/[\r\n]/.test(raw.trim());
    var hasStart = cleaned.indexOf("start-host") !== -1;
    var hasCode = cleaned.indexOf("--code=") !== -1;
    var startsOk = cleaned.indexOf("/opt/google/chrome-remote-desktop/start-host") === 0 || cleaned.indexOf("DISPLAY=") === 0;
    var forbidden = ["$(", "`", ";", "&", "|", ">", "<", "\\"].some(function (ch) { return cleaned.indexOf(ch) !== -1; });
    var control = /[\x00-\x1f\x7f]/.test(cleaned);
    var sizeOk = byteLength(raw) <= MAX_BYTES;
    var format = singleLine && hasStart && startsOk && !control;
    var ok = format && hasCode && sizeOk && !forbidden;
    return {
      ok: ok,
      format: format,
      code: hasCode,
      singleLine: singleLine,
      size: sizeOk,
      safe: !forbidden && !control,
      forbidden: forbidden,
      control: control,
      empty: !raw.trim()
    };
  }

  function updateChecks() {
    var field = $("#cmd");
    if (!field) return;
    var raw = field.value;
    var check = validateCommand(raw);
    var hasInput = !check.empty;
    var checks = $("#checks");
    var message = $("#validation-msg");
    var count = $("#char-count");
    var submit = $("#submit-btn");

    if (count) count.textContent = byteLength(raw) + " / " + MAX_BYTES;
    if (checks) {
      checks.hidden = !hasInput;
      checks.replaceChildren();
      if (hasInput) {
        [
          ["form.checks.format", check.format],
          ["form.checks.code", check.code],
          ["form.checks.line", check.singleLine],
          ["form.checks.size", check.size]
        ].forEach(function (item) {
          var chip = document.createElement("span");
          chip.className = "check";
          chip.dataset.ok = item[1] ? "true" : "false";
          chip.textContent = t(item[0]);
          checks.appendChild(chip);
        });
      }
    }

    var error = "";
    if (hasInput) {
      if (!check.singleLine) error = "validation.line";
      else if (!check.format) error = "validation.format";
      else if (!check.code) error = "validation.code";
      else if (!check.size) error = "validation.size";
      else if (check.control) error = "validation.control";
      else if (!check.safe) error = "validation.forbidden";
    }
    if (message) {
      if (ui.serverError && !ui.busy) {
        message.textContent = ui.serverError;
        message.hidden = false;
      } else if (error && !ui.busy) {
        message.textContent = t(error);
        message.hidden = false;
      } else {
        message.hidden = true;
        message.textContent = "";
      }
    }
    field.setAttribute("aria-invalid", hasInput && !check.ok ? "true" : "false");
    if (submit) submit.disabled = !check.ok || isLocked(ui.lastState) || ui.busy;
  }

  function setBusy(busy) {
    ui.busy = busy;
    var spinner = $("#submit-spinner");
    var field = $("#cmd");
    if (spinner) spinner.hidden = !busy;
    if (field) field.setAttribute("aria-busy", busy ? "true" : "false");
    updateSubmitLabel();
    updateChecks();
  }
  function updateSteps(state) {
    var states = ["pending", "pending", "pending", "pending"];
    if (state === "waiting") {
      states[0] = "active";
    } else if (state === "queued" || state === "registering" || state === "sending") {
      states[0] = "done";
      states[1] = "done";
      states[2] = "active";
    } else if (state === "success") {
      states = ["done", "done", "done", "done"];
    } else if (state === "failed" || state === "timeout") {
      states[0] = "done";
      states[1] = "done";
      states[2] = "error";
    }
    $$("#steps .step").forEach(function (step, index) {
      var value = states[index] || "pending";
      step.dataset.state = value;
      if (value === "active") step.setAttribute("aria-current", "step");
      else step.removeAttribute("aria-current");
    });
  }

  function renderCountdown() {
    var chip = $("#countdown");
    var text = $("#countdown-text");
    var progress = $("#progress");
    var bar = $("#progress-bar");
    if (!ui.deadline || ui.lastState === "success") {
      if (chip) chip.hidden = true;
      if (progress) progress.hidden = true;
      return;
    }
    var left = Math.max(0, Math.round(ui.deadline - serverNow()));
    var total = ui.initialRemaining > 0 ? ui.initialRemaining : Math.max(left, 1);
    var percent = Math.max(0, Math.min(100, (left / total) * 100));
    if (chip) chip.hidden = false;
    if (text) text.textContent = left > 0 ? t("status.remaining", { time: formatDuration(left) }) : t("status.expired");
    if (progress) {
      progress.hidden = false;
      progress.dataset.tone = left <= 0 ? "danger" : (left <= 300 ? "warn" : "normal");
    }
    if (bar) bar.style.width = percent.toFixed(2) + "%";
    if (left <= 0 && ui.lastState !== "timeout" && ui.lastStatus && ui.lastStatus.state !== "success") {
      renderStatus(ui.lastStatus);
    }
  }

  function renderStatus(data) {
    ui.lastStatus = data;
    if (typeof data.server_time === "number") {
      ui.serverOffset = data.server_time - (Date.now() / 1000);
    } else {
      ui.serverOffset = 0;
    }
    var now = serverNow();
    var expired = !!data.deadline && data.deadline <= now && data.state !== "success";
    var stateName = expired ? "timeout" : (data.state || "waiting");
    ui.lastState = stateName;

    if (data.deadline) {
      if (ui.deadline !== data.deadline) {
        ui.deadline = data.deadline;
        ui.initialRemaining = Math.max(data.deadline - now, 1);
      }
    } else {
      ui.deadline = 0;
      ui.initialRemaining = 0;
    }

    var badge = $("#state-badge");
    var status = $("#status");
    var title = $("#status-title");
    var message = $("#status-message");
    var detail = $("#status-detail");
    var attempts = $("#status-attempts");
    var updated = $("#status-updated");
    var iconUse = $("#status-icon-use");
    var statusSvg = $("#status-icon svg");
    var field = $("#cmd");
    var success = stateName === "success";
    var spinnerState = stateName === "registering" || stateName === "sending";

    if (badge) {
      badge.dataset.state = stateName;
      badge.textContent = t("status." + stateName + ".label");
    }
    if (status) {
      status.dataset.state = stateName;
      status.setAttribute("aria-busy", spinnerState ? "true" : "false");
    }
    if (title) title.textContent = t("status." + stateName + ".title");
    if (message) {
      var body = t("status." + stateName + ".message", { device: DEVICE });
      if (ui.lang === "id" && data.message && !expired && !success) body = data.message;
      message.textContent = body;
    }
    if (detail) {
      if (data.last_error) {
        detail.textContent = t("status.detail", { detail: data.last_error });
        detail.hidden = false;
      } else {
        detail.textContent = "";
        detail.hidden = true;
      }
    }
    if (attempts) attempts.textContent = data.attempts ? t("status.attempts", { n: data.attempts }) : "";
    if (updated) updated.textContent = data.updated_at ? t("status.updated", { time: formatTime(data.updated_at) }) : "";
    if (iconUse) {
      var icon = stateName === "success" ? "check"
        : stateName === "failed" ? "alert"
        : stateName === "timeout" ? "clock"
        : spinnerState ? "spinner"
        : "clock";
      iconUse.setAttribute("href", "#i-" + icon);
    }
    if (statusSvg) statusSvg.classList.toggle("spinning", spinnerState);

    var formWrap = $("#form-wrap");
    var successPanel = $("#success");
    if (formWrap) formWrap.hidden = success;
    if (successPanel) successPanel.hidden = !success;

    updateSteps(stateName);
    updateChecks();
    if (field) field.disabled = isLocked(stateName) || ui.busy;
    renderCountdown();
    if (success || stateName === "timeout") ui.stopped = true;
  }

  function showTransientStatus(stateName) {
    ui.lastState = stateName;
    var badge = $("#state-badge");
    var status = $("#status");
    var title = $("#status-title");
    var message = $("#status-message");
    var detail = $("#status-detail");
    var attempts = $("#status-attempts");
    var updated = $("#status-updated");
    var iconUse = $("#status-icon-use");
    var statusSvg = $("#status-icon svg");
    if (badge) {
      badge.dataset.state = stateName;
      badge.textContent = t("status." + stateName + ".label");
    }
    if (status) {
      status.dataset.state = stateName;
      status.setAttribute("aria-busy", "true");
    }
    if (title) title.textContent = t("status." + stateName + ".title");
    if (message) message.textContent = t("status." + stateName + ".message", { device: DEVICE });
    if (detail) { detail.hidden = true; detail.textContent = ""; }
    if (attempts) attempts.textContent = "";
    if (updated) updated.textContent = "";
    if (iconUse) iconUse.setAttribute("href", "#i-spinner");
    if (statusSvg) statusSvg.classList.add("spinning");
    updateSteps(stateName);
    updateChecks();
    var field = $("#cmd");
    if (field) field.disabled = true;
  }

  function schedulePoll(delay) {
    clearTimeout(ui.pollTimer);
    if (ui.stopped) return;
    ui.pollTimer = setTimeout(poll, delay || (document.hidden ? 10000 : 2000));
  }

  function poll() {
    if (ui.polling || ui.stopped) return;
    ui.polling = true;
    var controller = window.AbortController ? new AbortController() : null;
    var timer = controller ? setTimeout(function () { controller.abort(); }, 8000) : 0;
    fetch(BASE + "/status", {
      cache: "no-store",
      headers: { "Accept": "application/json" },
      signal: controller ? controller.signal : undefined
    }).then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.json();
    }).then(function (data) {
      setConnection(true);
      renderStatus(data);
    }).catch(function () {
      if (ui.lastState !== "success") setConnection(false);
    }).then(function () {
      if (timer) clearTimeout(timer);
      ui.polling = false;
      schedulePoll();
    });
  }

  function submitCommand(event) {
    event.preventDefault();
    if (ui.busy) return;
    var field = $("#cmd");
    if (!field) return;
    var check = validateCommand(field.value);
    if (!check.ok) {
      updateChecks();
      field.focus();
      return;
    }
    var body = new URLSearchParams();
    body.set("command", field.value);
    ui.serverError = "";
    setBusy(true);
    showTransientStatus("sending");
    fetch(BASE + "/submit", {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"
      },
      body: body.toString()
    }).then(function (response) {
      return response.json().catch(function () { return {}; }).then(function (data) {
        if (!response.ok) throw new Error(data.error || ("HTTP " + response.status));
        return data;
      });
    }).then(function () {
      field.value = "";
      ui.serverError = "";
      updateChecks();
      ui.lastStatus = {
        state: "queued",
        message: "",
        attempts: 0,
        updated_at: Math.floor(Date.now() / 1000),
        deadline: ui.deadline,
        server_time: serverNow()
      };
      renderStatus(ui.lastStatus);
      showToast(t("status.queued.message"));
      schedulePoll(500);
    }).catch(function (err) {
      ui.serverError = String((err && err.message) || err);
      if (ui.lastStatus) renderStatus(ui.lastStatus);
      updateChecks();
      showToast(t("toast.submitFailed"));
    }).then(function () {
      setBusy(false);
    });
  }

  function wireEvents() {
    var form = $("#form");
    var field = $("#cmd");
    var themeBtn = $("#theme-btn");
    var pasteBtn = $("#paste-btn");
    var clearBtn = $("#clear-btn");
    var copyMeta = $("#copy-device-meta");
    var copySuccess = $("#copy-device-success");

    if (themeBtn) themeBtn.addEventListener("click", cycleTheme);
    $$("[data-lang-btn]").forEach(function (button) {
      button.addEventListener("click", function () { applyLanguage(button.dataset.langBtn); });
    });
    if (form) form.addEventListener("submit", submitCommand);
    if (field) {
      field.addEventListener("input", function () {
        ui.serverError = "";
        updateChecks();
      });
      field.addEventListener("keydown", function (event) {
        if ((event.ctrlKey || event.metaKey) && event.key === "Enter") {
          event.preventDefault();
          if (form) form.requestSubmit();
        }
      });
    }
    if (pasteBtn) pasteBtn.addEventListener("click", pasteCommand);
    if (clearBtn) clearBtn.addEventListener("click", function () {
      if (!field) return;
      field.value = "";
      ui.serverError = "";
      updateChecks();
      field.focus();
    });
    if (copyMeta) copyMeta.addEventListener("click", copyDevice);
    if (copySuccess) copySuccess.addEventListener("click", copyDevice);
    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) {
        clearTimeout(ui.pollTimer);
        poll();
      }
    });
  }

  function init() {
    ui.serverError = "";
    ui.pollTimer = 0;
    ui.stopped = false;
    $$("[data-desktop]").forEach(function (el) { el.textContent = DESKTOP; });
    $$("[data-device]").forEach(function (el) { el.textContent = DEVICE; });

    var savedLang = "id";
    try { savedLang = localStorage.getItem("crd.lang") === "en" ? "en" : "id"; } catch (err) { savedLang = "id"; }
    applyTheme(document.documentElement.dataset.themePref || "auto", false);
    applyLanguage(savedLang, false);
    renderStatus({ state: "waiting", message: "", attempts: 0, updated_at: 0 });
    wireEvents();

    if (window.matchMedia) {
      var query = window.matchMedia("(prefers-color-scheme: light)");
      var onChange = function () { if (ui.themePref === "auto") applyTheme("auto", false); };
      if (query.addEventListener) query.addEventListener("change", onChange);
      else if (query.addListener) query.addListener(onChange);
    }

    setInterval(renderCountdown, 1000);
    poll();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
</script>
</body>
</html>
"""


def _js_json(value: str) -> str:
    """JSON yang aman disisipkan di dalam tag <script>."""
    return (
        json.dumps(value)
        .replace("<", "\\u003c")
        .replace(">", "\\u003e")
        .replace("&", "\\u0026")
    )


def _page() -> bytes:
    return (
        PAGE_TEMPLATE
        .replace("__TOKEN_JSON__", _js_json(TOKEN))
        .replace("__DESKTOP_JSON__", _js_json(DESKTOP_NAME))
        .replace("__DEVICE_JSON__", _js_json(DEVICE_NAME))
        .replace("__DESKTOP__", html.escape(DESKTOP_NAME, quote=True))
        .replace("__DEVICE__", html.escape(DEVICE_NAME, quote=True))
    ).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    server_version = "crd-web-auth/2.0"
    sys_version = ""

    # ---- helpers ---------------------------------------------------------
    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'none'; style-src 'unsafe-inline'; "
            "script-src 'unsafe-inline'; connect-src 'self'; "
            "form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
        )
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, code: int, payload: dict) -> None:
        self._send(code, json.dumps(payload).encode("utf-8"), "application/json; charset=utf-8")

    def _not_found(self) -> None:
        self._send(404, b"Not found\n", "text/plain; charset=utf-8")

    def _valid_token(self, parts: list[str]) -> bool:
        return bool(TOKEN) and len(parts) >= 1 and hmac.compare_digest(parts[0], TOKEN)

    def log_message(self, fmt: str, *args: object) -> None:
        # Jangan bocorkan token ke log workflow.
        message = fmt % args
        if TOKEN:
            message = message.replace(TOKEN, "<token>")
        sys.stderr.write("%s - %s\n" % (self.address_string(), message))

    # ---- routes ----------------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802 (nama wajib dari BaseHTTPRequestHandler)
        parts = [p for p in urlsplit(self.path).path.split("/") if p]
        if not self._valid_token(parts):
            self._not_found()
            return
        if len(parts) == 1:
            self._send(200, _page(), "text/html; charset=utf-8")
            return
        if len(parts) == 2 and parts[1] == "status":
            status = read_status()
            status["server_time"] = _now()
            self._json(200, status)
            return
        if len(parts) == 2 and parts[1] == "health":
            self._send(200, b"ok\n", "text/plain; charset=utf-8")
            return
        self._not_found()

    def do_POST(self) -> None:  # noqa: N802
        parts = [p for p in urlsplit(self.path).path.split("/") if p]
        if not self._valid_token(parts) or len(parts) != 2 or parts[1] != "submit":
            self._not_found()
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY_BYTES:
            self._json(413, {"ok": False, "error": "Ukuran form tidak valid."})
            return

        raw = self.rfile.read(length)
        try:
            fields = parse_qs(raw.decode("utf-8"), keep_blank_values=True)
        except UnicodeDecodeError:
            self._json(400, {"ok": False, "error": "Encoding form tidak valid."})
            return

        command, error = normalize_command((fields.get("command") or [""])[0])
        if error:
            self._json(400, {"ok": False, "error": error})
            return

        status = read_status()
        state = status.get("state", "waiting")
        if state in ("registering", "success", "timeout"):
            messages = {
                "registering": "Perintah sedang diproses. Tunggu sampai selesai.",
                "success": "Registrasi sudah berhasil. Tidak perlu submit lagi.",
                "timeout": "Waktu tunggu sudah habis. Jalankan ulang workflow.",
            }
            self._json(409, {"ok": False, "error": messages[state]})
            return
        if os.path.exists(PROCESSING_FILE):
            self._json(409, {"ok": False, "error": "Perintah sedang diproses."})
            return

        try:
            fd = os.open(COMMAND_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            self._json(409, {"ok": False, "error": "Perintah sudah dikirim. Tunggu hasilnya."})
            return

        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(command + "\n")

        set_status("queued", "Perintah diterima. Menunggu proses registrasi...")
        self._json(202, {"ok": True, "message": "Perintah diterima."})


def serve() -> None:
    if not TOKEN:
        sys.exit("CRD_WEB_TOKEN wajib diisi.")
    _ensure_state_dir()
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    server.daemon_threads = True
    server.allow_reuse_address = True
    print(f"crd-web-auth listening on http://{BIND}:{PORT}/<token>/", flush=True)

    def _stop(_signum: int, _frame: object) -> None:
        # shutdown() memblokir sampai loop berhenti, jadi jangan dipanggil dari
        # signal handler thread utama (bisa deadlock). Jalankan di thread lain.
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        server.server_close()


def _cli(argv: list[str]) -> None:
    _ensure_state_dir()
    if len(argv) >= 2 and argv[0] == "set-status":
        if len(argv) < 3:
            sys.exit("usage: set-status <state> <message> [--error TEXT] [--attempts N] [--deadline EPOCH]")
        state, message = argv[1], argv[2]
        error = None
        attempts = None
        deadline = None
        rest = argv[3:]
        index = 0
        while index < len(rest):
            flag = rest[index]
            value = rest[index + 1] if index + 1 < len(rest) else ""
            if flag == "--error":
                error = value
            elif flag == "--attempts":
                try:
                    attempts = int(value)
                except ValueError:
                    pass
            elif flag == "--deadline":
                try:
                    deadline = int(value)
                except ValueError:
                    pass
            index += 2
        set_status(state, message, error=error, attempts=attempts, deadline=deadline)
        return
    if len(argv) >= 1 and argv[0] == "get-state":
        print(read_status().get("state", "waiting"))
        return
    serve()


if __name__ == "__main__":
    _cli(sys.argv[1:])
