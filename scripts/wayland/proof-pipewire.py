import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception as exc:
    print("pw-dump tidak tersedia:", exc)
    sys.exit(0)
for obj in data:
    if obj.get("type") != "PipeWire:Interface:Node":
        continue
    info = obj.get("info", {})
    name = info.get("props", {}).get("node.name", "")
    if name not in ("gnome-shell", "chrome-remote-desktop-host"):
        continue
    print("node", name, "id", obj.get("id"))
    for fmt in info.get("params", {}).get("EnumFormat", [])[:4]:
        keys = ("mediaType", "format", "size", "colorPrimaries", "transferFunction")
        print("  ", {k: fmt[k] for k in keys if k in fmt})
