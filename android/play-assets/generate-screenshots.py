#!/usr/bin/env python3
# Google Play screenshots (phone / 7" / 10") from the cross-platform black-hole
# renders. Crops macOS chrome, then composes each scene as a rounded hero card
# on a branded dark canvas with an IBM Plex Mono caption + sub-caption.
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC = "/Users/johnseong/Documents/GitHub2/blackhole-simulation/apple/screenshots"
OUT = "/Users/johnseong/Documents/GitHub2/blackhole-simulation/android/play-assets/screenshots"
os.makedirs(OUT, exist_ok=True)
PLEX_MED = "/tmp/plex/IBMPlexMono-Medium.ttf"
PLEX_REG = "/tmp/plex/IBMPlexMono-Regular.ttf"
ACCENT = (140, 242, 255); WHITE = (238, 243, 248); DIM = (155, 170, 192)
try:
    import numpy as np; HAVE_NP = True
except Exception:
    HAVE_NP = False


def crop_window(path):
    im = Image.open(path).convert("RGB"); w, h = im.size
    if HAVE_NP:
        a = np.asarray(im).astype(int); r, g, b = a[..., 0], a[..., 1], a[..., 2]
        content = ~((g > r * 1.08) & (g > b * 1.08) & (g > 55))
        ys, xs = np.where(content)
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    else:
        x0, y0, x1, y1 = int(.04*w), int(.035*h), int(.96*w), int(.945*h)
    y0 += int(0.075 * (y1 - y0))
    return im.crop((x0 + 3, y0, x1 - 3, y1 - 3))


def rounded(img, rad):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, *img.size], radius=rad, fill=255)
    o = img.convert("RGBA"); o.putalpha(m); return o


def bg_canvas(W, H):
    top, bot = (12, 16, 26), (4, 6, 11)
    col = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / H
        col.putpixel((0, y), tuple(int(top[i]*(1-t)+bot[i]*t) for i in range(3)))
    return col.resize((W, H)).convert("RGBA")


def glow(canvas, cx, cy, r, color, alpha):
    g = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse([cx-r, cy-r, cx+r, cy+r], fill=color+(alpha,))
    canvas.alpha_composite(g.filter(ImageFilter.GaussianBlur(r*0.45)))


def tracked(draw, xy, text, font, fill, tr):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill); x += draw.textlength(ch, font=font)+tr
    return x


def tw(draw, text, font, tr):
    return sum(draw.textlength(c, font=font)+tr for c in text) - tr


def fit(draw, text, path, max_w, start, tr_px):
    s = start
    while s > 12:
        f = ImageFont.truetype(path, s)
        if tw(draw, text, f, tr_px) <= max_w:
            return f
        s -= 2
    return ImageFont.truetype(path, s)


def make(out, W, H, hero, main, sub, landscape):
    c = bg_canvas(W, H); d = ImageDraw.Draw(c); cx = W/2
    tr = max(2, int(H*0.006))
    # caption (auto-fit to 88% width)
    cf = fit(d, main, PLEX_MED, W*0.88, int(H*(0.040 if not landscape else 0.058)), tr)
    cy = int(H*0.05)
    tracked(d, (cx - tw(d, main, cf, tr)/2, cy), main, cf, WHITE+(255,), tr)
    ch = cf.getbbox(main)[3]-cf.getbbox(main)[1]
    uy = cy + ch + int(H*0.016)
    cw = tw(d, main, cf, tr)
    d.line([(cx-cw/2, uy), (cx+cw/2, uy)], fill=ACCENT+(210,), width=max(2, int(H*0.0028)))
    # sub-caption
    sf = fit(d, sub, PLEX_REG, W*0.86, int(H*(0.022 if not landscape else 0.030)), int(H*0.003))
    sy = uy + int(H*0.022)
    tracked(d, (cx - tw(d, sub, sf, int(H*0.003))/2, sy), sub, sf, DIM+(255,), int(H*0.003))

    # hero card centered in the band below text and above the footer mark
    band_top = sy + (sf.getbbox(sub)[3]-sf.getbbox(sub)[1]) + int(H*0.04)
    band_bot = H - int(H*(0.075 if not landscape else 0.10))
    max_w, max_h = int(W*0.92), int((band_bot-band_top))
    cw0, ch0 = hero.size
    s = min(max_w/cw0, max_h/ch0)
    nw, nh = int(cw0*s), int(ch0*s)
    card = rounded(hero.resize((nw, nh), Image.LANCZOS), int(nw*0.026))
    x = int(cx-nw/2); y = int(band_top + (max_h-nh)/2)
    glow(c, cx, y+nh/2, int(nw*0.42), (255, 150, 70), 26)
    sh = Image.new("RGBA", c.size, (0, 0, 0, 0))
    p = int(nw*0.02)
    ImageDraw.Draw(sh).rounded_rectangle([x-p, y-p+int(nh*.02), x+nw+p, y+nh+p+int(nh*.02)],
                                         radius=int(nw*0.026)+p, fill=(0, 0, 0, 175))
    c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(int(nw*0.025))))
    bd = Image.new("RGBA", c.size, (0, 0, 0, 0))
    ImageDraw.Draw(bd).rounded_rectangle([x, y, x+nw, y+nh], radius=int(nw*0.026),
                                         outline=ACCENT+(70,), width=max(1, nw//600))
    c.alpha_composite(bd); c.alpha_composite(card, (x, y))
    # footer mark
    mf = ImageFont.truetype(PLEX_REG, int(H*(0.018 if not landscape else 0.024)))
    mk = "BLACKHOLE  ·  ORCH AEROSPACE"
    tracked(d, (cx - tw(d, mk, mf, int(H*0.004))/2, H-int(H*(0.052 if not landscape else 0.075))),
            mk, mf, DIM+(220,), int(H*0.004))
    c.convert("RGB").save(out); print("wrote", os.path.basename(out))


heroes = {
    "lensing": (crop_window(f"{SRC}/macos-home-1.png"), "GRAVITATIONAL LENSING",
                "Light bent around the event horizon, in real time."),
    "jets": (crop_window(f"{SRC}/macos-home-2.png"), "RELATIVISTIC JETS",
             "Frame-dragging, Doppler beaming and polar jets."),
    "controls": (crop_window(f"{SRC}/macos-controls.png"), "FULL CONTROL",
                 "Tune mass, spin and the accretion disk live."),
}
targets = [("phone", 1080, 1920, False), ("tablet7", 1920, 1200, True),
           ("tablet10", 2560, 1600, True)]
order = ["lensing", "jets", "controls"]
for ff, W, H, land in targets:
    for i, k in enumerate(order, 1):
        hero, main, sub = heroes[k]
        make(f"{OUT}/{ff}-{i}-{k}.png", W, H, hero, main, sub, land)
print("ALL DONE")
