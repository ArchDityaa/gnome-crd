import os, time

steps, order = {}, []
try:
    for line in open('/tmp/ci-steps.tsv'):
        p = line.rstrip('\n').split('\t')
        if p[0] == 'S' and len(p) >= 4:
            steps[p[1]] = {'title': p[2], 'dur': None}
            order.append(p[1])
        elif p[0] == 'D' and len(p) >= 3 and p[1] in steps:
            steps[p[1]]['dur'] = int(p[2])
except FileNotFoundError:
    pass

def fmt(s):
    s = int(s)
    return f"{s // 60}m{s % 60:02d}s" if s >= 60 else f"{s}s"

failed = [i for i in order if steps[i]['dur'] is None]
start = os.environ.get('JOB_START_EPOCH', '')
total = fmt(time.time() - int(start)) if start.isdigit() else '-'

out = ['## 🖥️ GNOME 26 + Chrome Remote Desktop (Wayland BETA)', '']
if failed:
    out.append(f"❌ **Gagal / terhenti** di step `{failed[0]}` · {steps[failed[0]]['title']}. "
               "Log lengkap tersedia di artifact `install-logs-<run id>`.")
else:
    out.append(f"✅ **Siap digunakan** · total {total}")
out += ['', '| Step | Status | Durasi |', '|---|:---:|---:|']
for i in order:
    s = steps[i]
    done = s['dur'] is not None
    out.append(f"| {i} · {s['title']} | {'✅' if done else '❌'} | {fmt(s['dur']) if done else '-'} |")

if not failed:
    pin = ('secret `CRD_PIN`' if os.environ.get('CRD_PIN_SOURCE') == 'secret'
           else 'default `123456` (belum ada secret `CRD_PIN`)')
    out += ['', '### Akses', '',
            '- URL: https://remotedesktop.google.com/access',
            '- Perangkat: `gnome` · Pengguna: `runner`',
            f'- PIN: {pin}']
    vers = [('GNOME Shell', 'GNOME_V'), ('Chrome', 'CHROME_V'), ('VS Code', 'CODE_V'),
            ('OpenCode', 'OC_V'), ('Chrome Remote Desktop', 'CRD_V')]
    out += ['', '### Versi terpasang', '', '| Komponen | Versi |', '|---|---|']
    for name, key in vers:
        out.append(f"| {name} | {os.environ.get(key) or '-'} |")

with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as fh:
    fh.write('\n'.join(out) + '\n')
