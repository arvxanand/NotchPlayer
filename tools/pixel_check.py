# Assertions about a captured PNG. Stdlib only -- no Pillow, no numpy, no venv
# -- because a check that needs installing is a check that stops being run.
#
# Two modes, both over a `screencapture -l <windowid>` image of the panel:
#
#   --unlit X,Y,W,H     nothing legible is drawn in that band (the camera
#                       housing). Points; the backing scale is worked out from
#                       --size.
#   --bounds WxH        the opaque content measures exactly that, +/- the
#                       shoulder overhang, which is reported separately.
#
# Both need --size W,H (the window in points) to resolve the scale.
import struct, sys, zlib


def decode(path):
    data = open(path, 'rb').read()
    pos, idat, ihdr = 8, b'', None
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
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
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(bytes(line)); prev = line
    return w, h, bpp, rows


def arg(name, default=None):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


path = sys.argv[1]
w, h, bpp, rows = decode(path)
size = arg('--size')
if not size:
    sys.exit('need --size W,H in points')
sw, sh = (int(v) for v in size.split(','))
scale = w / float(sw)
if abs(scale - h / float(sh)) > 0.01:
    sys.exit('non-square scale: %sx%s px for %sx%s pt' % (w, h, sw, sh))

# Colour channels only. Alpha is 255 across a transparent window region in
# some captures and was giving a false positive in the original; and a fully
# transparent pixel has undefined RGB, so opacity is read from alpha and
# lightness from RGB, never one from the other.
THRESHOLD = 24


def px(row, x):
    o = x * bpp
    rgb = max(row[o], row[o + 1], row[o + 2]) if bpp >= 3 else row[o]
    alpha = row[o + 3] if bpp == 4 else 255
    return rgb, alpha


fail = 0

band = arg('--unlit')
if band:
    bx, by, bw, bh = (int(v) for v in band.split(','))
    x0, y0 = int(bx * scale), int(by * scale)
    x1, y1 = int((bx + bw) * scale), int((by + bh) * scale)
    peak, lit = 0, 0
    for y in range(y0, min(y1, h)):
        for x in range(x0, min(x1, w)):
            rgb, alpha = px(rows[y], x)
            if alpha <= 128:
                continue
            peak = max(peak, rgb)
            if rgb > THRESHOLD:
                lit += 1
    total = (x1 - x0) * (y1 - y0)
    print('housing %dx%d pt  peak RGB: %d/255  lit: %d/%d' % (bw, bh, peak, lit, total))
    if lit:
        print('FAIL  content behind the camera housing -- invisible on real hardware')
        fail = 1
    else:
        print('CLEAN nothing drawn behind the camera housing')

bounds = arg('--bounds')
if bounds:
    ew, eh = (int(v) for v in bounds.replace('x', ',').split(','))
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if px(rows[y], x)[1] > 128:
                xs.append(x); ys.append(y)
    if not xs:
        print('FAIL  nothing opaque in the capture at all')
        sys.exit(1)
    # The shoulders overhang the shell, so the widest row is wider than the
    # shell by design. The shell's own width is the *narrowest* opaque row
    # inside the body, which is why both are reported.
    widths = []
    for y in range(h):
        row_xs = [x for x in range(w) if px(rows[y], x)[1] > 128]
        if row_xs:
            widths.append(max(row_xs) - min(row_xs) + 1)
    body = max(set(widths), key=widths.count) / scale
    top = max(widths) / scale
    tall = (max(ys) - min(ys) + 1) / scale
    print('shell %gx%g pt  widest row (shoulders) %g pt  overhang %g pt each side'
          % (body, tall, top, (top - body) / 2))
    if abs(body - ew) > 1 or abs(tall - eh) > 1:
        print('FAIL  expected %dx%d pt' % (ew, eh))
        fail = 1
    else:
        print('OK    matches %dx%d pt' % (ew, eh))

sys.exit(fail)
