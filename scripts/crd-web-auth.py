#!/usr/bin/env python3
"""Server web kecil untuk menerima perintah otorisasi Chrome Remote Desktop.

Dipakai oleh `.github/workflows/gnome26.yml` (STEP 17). Workflow menjalankan
server ini di 127.0.0.1, lalu mengeksposnya lewat Cloudflare quick tunnel.
User membuka URL publik, meng-*authorize* akun Google di halaman headless CRD,
lalu mem-paste perintah `start-host` ke form. Perintah disimpan ke file dan
diproses oleh workflow.

Kenapa ada: kode OAuth `--code=...` dari Google bersifat sekali pakai dan cepat
kadaluarsa, sedangkan instalasi desktop butuh 20-40 menit. Dengan form ini kode
baru dibuat SETELAH desktop siap, jadi tidak sempat kedaluwarsa.

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

Hanya memakai standard library Python 3 (tidak perlu pip/venv).
"""

from __future__ import annotations

import hmac
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
    # menambahkan --name="gnome" sendiri supaya device selalu tampil "gnome".
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


PAGE_TEMPLATE = """<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Otorisasi Chrome Remote Desktop</title>
<style>
  :root {
    --bg: #1e1e2e; --surface: #313244; --surface2: #45475a;
    --text: #cdd6f4; --subtext: #a6adc8; --mauve: #cba6f7;
    --green: #a6e3a1; --yellow: #f9e2af; --red: #f38ba8; --blue: #89b4fa;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 24px 16px 48px; background: var(--bg); color: var(--text);
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    line-height: 1.55;
  }
  .wrap { max-width: 720px; margin: 0 auto; }
  h1 { font-size: 1.45rem; margin: 0 0 4px; color: var(--mauve); }
  .lead { color: var(--subtext); margin: 0 0 24px; }
  .card {
    background: var(--surface); border: 1px solid var(--surface2);
    border-radius: 12px; padding: 18px 20px; margin-bottom: 18px;
  }
  h2 { font-size: 1rem; margin: 0 0 10px; color: var(--mauve); }
  ol { margin: 0; padding-left: 22px; }
  li { margin-bottom: 8px; }
  a { color: var(--blue); }
  code {
    background: #181825; border-radius: 5px; padding: 1px 5px;
    font-family: ui-monospace, "JetBrains Mono", Consolas, monospace;
    font-size: 0.88em; overflow-wrap: anywhere;
  }
  textarea {
    width: 100%; min-height: 130px; resize: vertical; padding: 12px;
    border-radius: 9px; border: 1px solid var(--surface2);
    background: #181825; color: var(--text);
    font-family: ui-monospace, "JetBrains Mono", Consolas, monospace;
    font-size: 0.85rem; line-height: 1.45;
  }
  textarea:focus { outline: 2px solid var(--mauve); border-color: transparent; }
  textarea:disabled { opacity: 0.6; }
  button {
    margin-top: 12px; padding: 11px 20px; border: 0; border-radius: 9px;
    background: var(--mauve); color: #11111b; font-weight: 700;
    font-size: 0.95rem; cursor: pointer;
  }
  button:hover { filter: brightness(1.08); }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  #status {
    border-left: 4px solid var(--blue); background: #181825;
    padding: 12px 14px; border-radius: 8px; margin-top: 18px;
  }
  #status[data-state="queued"], #status[data-state="registering"] { border-color: var(--yellow); }
  #status[data-state="success"] { border-color: var(--green); }
  #status[data-state="failed"], #status[data-state="timeout"] { border-color: var(--red); }
  .msg { font-weight: 600; }
  .detail { color: var(--subtext); font-size: 0.85rem; overflow-wrap: anywhere; }
  .foot { color: var(--subtext); font-size: 0.8rem; margin-top: 28px; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<div class="wrap">
  <h1>🔐 Otorisasi Chrome Remote Desktop</h1>
  <p class="lead">
    Desktop GNOME sudah siap. Tinggal menghubungkan perangkat ke akun Google Anda.
    <span id="countdown"></span>
  </p>

  <div class="card">
    <h2>Langkah-langkah</h2>
    <ol>
      <li>
        Buka
        <a href="https://remotedesktop.google.com/headless" target="_blank" rel="noreferrer noopener">
          remotedesktop.google.com/headless</a>
        (login akun Google Anda), lalu klik <strong>Begin → Next → Authorize</strong>.
      </li>
      <li>Di bagian <strong>“Set up another computer” / “Debian Linux”</strong>, copy <strong>SELURUH</strong> perintah yang muncul.</li>
      <li>Paste perintah itu ke kotak di bawah, lalu klik <strong>Kirim &amp; Daftarkan</strong>.</li>
      <li>Tunggu sampai status berubah menjadi <strong>Berhasil</strong>, lalu buka
        <a href="https://remotedesktop.google.com/access" target="_blank" rel="noreferrer noopener">
          Remote Access</a> dan pilih device <code>gnome</code>.</li>
    </ol>
    <p class="detail" style="margin-bottom:0">
      Kode <code>--code=...</code> bersifat <strong>sekali pakai</strong>. Jangan
      membuat kode baru sebelum halaman ini terbuka, dan langsung submit setelah
      Anda meng-<em>authorize</em>. Kalau registrasi gagal, buat kode baru lalu
      submit lagi (tidak perlu re-run workflow).
    </p>
  </div>

  <div class="card">
    <h2>Perintah Chrome Remote Desktop</h2>
    <form id="form" autocomplete="off">
      <textarea id="cmd" spellcheck="false" autocapitalize="off" autocomplete="off"
        placeholder='DISPLAY= /opt/google/chrome-remote-desktop/start-host --code="4/0..." --redirect-url="https://remotedesktop.google.com/_/oauthredirect" --name=$(hostname)'></textarea>
      <button id="btn" type="submit">Kirim &amp; Daftarkan</button>
    </form>
    <div id="status" data-state="waiting">
      <div class="msg">Menunggu perintah...</div>
      <div class="detail" id="detail"></div>
      <div id="success-extra" hidden>
        <p style="margin-bottom:0">
          Buka <a href="https://remotedesktop.google.com/access" target="_blank" rel="noreferrer noopener">
          remotedesktop.google.com/access</a>, pilih device <strong>gnome</strong>,
          lalu masukkan PIN Anda.
        </p>
      </div>
    </div>
  </div>

  <p class="foot">
    Halaman ini hanya aktif selama workflow menunggu. Jangan tutup atau
    refresh workflow. URL ini bersifat rahasia — jangan dibagikan.
  </p>
</div>
<script>
  const TOKEN = __TOKEN_JSON__;
  const BASE = "/" + TOKEN;
  const form = document.getElementById("form");
  const box = document.getElementById("status");
  const msg = box.querySelector(".msg");
  const detail = document.getElementById("detail");
  const extra = document.getElementById("success-extra");
  const field = document.getElementById("cmd");
  const btn = document.getElementById("btn");
  const countdown = document.getElementById("countdown");
  let deadline = 0;
  let busy = false;

  function renderCountdown() {
    if (!deadline) { countdown.textContent = ""; return; }
    const left = deadline - Math.floor(Date.now() / 1000);
    if (left <= 0) { countdown.textContent = "(waktu tunggu habis)"; return; }
    const m = Math.floor(left / 60);
    const s = String(left % 60).padStart(2, "0");
    countdown.textContent = "(sisa waktu tunggu " + m + ":" + s + ")";
  }
  setInterval(renderCountdown, 1000);

  function render(state) {
    box.dataset.state = state.state || "waiting";
    msg.textContent = state.message || "";
    detail.textContent = state.last_error
      ? "Detail: " + state.last_error
      : (state.attempts ? "Percobaan registrasi: " + state.attempts : "");
    if (state.deadline) deadline = state.deadline;
    renderCountdown();

    const done = state.state === "success";
    const active = state.state === "queued" || state.state === "registering";
    extra.hidden = !done;
    form.hidden = done;
    field.disabled = active || done;
    btn.disabled = active || done || busy;
  }

  async function poll() {
    try {
      const resp = await fetch(BASE + "/status", { cache: "no-store" });
      if (resp.ok) render(await resp.json());
    } catch (err) {
      /* tunnel mungkin sedang reconnect; coba lagi */
    }
    setTimeout(poll, 2000);
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (busy) return;
    busy = true;
    btn.disabled = true;
    box.dataset.state = "registering";
    msg.textContent = "Mengirim perintah...";
    detail.textContent = "";
    try {
      const resp = await fetch(BASE + "/submit", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ command: field.value }),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data.error || ("HTTP " + resp.status));
      field.value = "";
      msg.textContent = "Perintah diterima. Mendaftarkan perangkat...";
    } catch (err) {
      box.dataset.state = "failed";
      msg.textContent = "Gagal mengirim perintah.";
      detail.textContent = String(err.message || err);
      btn.disabled = false;
    } finally {
      busy = false;
    }
  });

  poll();
</script>
</body>
</html>
"""


def _page() -> bytes:
    return PAGE_TEMPLATE.replace("__TOKEN_JSON__", json.dumps(TOKEN)).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    server_version = "crd-web-auth/1.0"
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
            self._json(200, read_status())
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
