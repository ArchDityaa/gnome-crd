import sys
try:
    from gi.repository import GdkPixbuf
except Exception as exc:
    print("GdkPixbuf tidak tersedia:", exc)
    sys.exit(0)
pb = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1])
width, height = pb.get_width(), pb.get_height()
pixels = pb.get_pixels()
rowstride = pb.get_rowstride()
channels = pb.get_n_channels()
total = 0
count = 0
peak = 0
for y in range(0, height, 16):
    for x in range(0, width, 16):
        idx = y * rowstride + x * channels
        r, g, b = pixels[idx], pixels[idx + 1], pixels[idx + 2]
        total += r + g + b
        count += 1
        peak = max(peak, r, g, b)
avg = total / (count * 3) if count else 0
print(f"{width}x{height}, brightness rata-rata {avg:.1f}, puncak {peak}")
sys.exit(3 if avg < 5 else 0)
