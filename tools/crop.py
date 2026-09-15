# Crop a PNG and scale it up with nearest-neighbour, so a 37pt strip can be
# looked at. Stdlib only, same reason as pixel_check.py.
#   /usr/bin/python3 tools/crop.py in.png out.png X Y W H [SCALE]
import struct, sys, zlib
sys.path.insert(0, 'tools')


def decode(path):
    data = open(path, 'rb').read()
    pos, idat, ihdr = 8, b'', None
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos + 4])[0]
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + ln]
        if kind == b'IHDR':
            ihdr = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            idat += body
        pos += 12 + ln
    w, h, colour = ihdr[0], ihdr[1], ihdr[3]
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(idat)
    rows, prev, i = [], bytearray(w * bpp), 0
    for _ in range(h):
        f = raw[i]; i += 1
        line = bytearray(raw[i:i + w * bpp]); i += w * bpp
        for x in range(len(line)):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(bytes(line)); prev = line
    return w, h, bpp, rows


def chunk(kind, body):
    return (struct.pack('>I', len(body)) + kind + body
            + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff))


def write(path, w, h, rows):
    raw = b''.join(b'\x00' + r for r in rows)
    out = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 6))
           + chunk(b'IEND', b''))
    open(path, 'wb').write(out)


src, dst = sys.argv[1], sys.argv[2]
x, y, cw, ch = (int(v) for v in sys.argv[3:7])
scale = int(sys.argv[7]) if len(sys.argv) > 7 else 1
w, h, bpp, rows = decode(src)
out = []
for row in rows[y:y + ch]:
    px = []
    for cx in range(x, min(x + cw, w)):
        o = cx * bpp
        rgba = (row[o], row[o + 1], row[o + 2], row[o + 3] if bpp == 4 else 255)
        # Flatten onto black: a transparent window region has undefined RGB and
        # a viewer will composite it onto white, which makes an empty panel look
        # like a white one.
        a = rgba[3] / 255
        px.extend([int(rgba[0] * a), int(rgba[1] * a), int(rgba[2] * a), 255] * scale)
    for _ in range(scale):
        out.append(bytes(px))
write(dst, min(cw, w - x) * scale, len(rows[y:y + ch]) * scale, out)
print('%s -> %dx%d' % (dst, min(cw, w - x) * scale, len(out)))
