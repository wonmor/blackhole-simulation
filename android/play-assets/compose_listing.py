#!/usr/bin/env python3
"""BlackHole Play listing art (1.3.0): phone/tablet screenshots and the feature
graphic, composed from real Android captures (emulator screenshots and the
app's own 4K poster export). Usage: compose_listing.py <captures dir> <out dir>
Captures expected (PNG): hero.png, poster.png, wallpaper.png, controls.png,
lesson.png, eqs.png, export.png. Missing ones are skipped."""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
HEL = "/System/Library/Fonts/HelveticaNeue.ttc"
def font(size, bold=True):
    return ImageFont.truetype(HEL, size, index=1 if bold else 0)
ACCENT = (140, 242, 255); WHITE = (240, 244, 248); DIM = (160, 172, 190)

SHOTS = [  # file, caption, sub-caption
    ("hero.png", "A real black hole,\nray traced live", "Every pixel is a light ray bent by Kerr spacetime"),
    ("wallpaper.png", "Live wallpaper\non your home screen", "The black hole, animated, in the look you set"),
    ("poster.png", "Export 4K posters\nand orbit videos", "3840 px, 500 ray steps, 16-pass supersampling"),
    ("controls.png", "Tune mass, spin\nand the disk", "Ten scenarios, from Sgr A* to M87*"),
    ("lesson.png", "Learn the physics\nin eight lessons", "Shadow, lensing, Doppler beaming, ISCO, jets"),
    ("eqs.png", "Every equation,\nwith its citation", "Horizon, photon sphere and ISCO from a Rust engine"),
]

def canvas(W, H):
    im = Image.new("RGB", (W, H), (5, 7, 11))
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / H
        c = tuple(int(a * (1 - t) + b * t) for a, b in zip((14, 18, 30), (3, 4, 8)))
        d.line([(0, y), (W, y)], fill=c)
    return im

def rounded(img, rad):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=rad, fill=255)
    o = img.convert("RGBA"); o.putalpha(m); return o

def fit(img, w, h):
    """Cover-crop img to w x h (centre)."""
    iw, ih = img.size; s = max(w / iw, h / ih)
    img = img.resize((int(iw * s + 0.5), int(ih * s + 0.5)), Image.LANCZOS)
    x = (img.size[0] - w) // 2; y = (img.size[1] - h) // 2
    return img.crop((x, y, x + w, y + h))

def shot(src, cap, sub, W, H, name):
    im = canvas(W, H); d = ImageDraw.Draw(im)
    pad = int(W * 0.07)
    fs = int(W * 0.075); f1 = font(fs); f2 = font(int(W * 0.034), bold=False)
    y = int(H * 0.05)
    for line in cap.split("\n"):
        d.text((pad, y), line, font=f1, fill=WHITE); y += int(fs * 1.12)
    y += int(fs * 0.25)
    d.text((pad, y), sub, font=f2, fill=ACCENT); y += int(W * 0.06)
    cw = W - 2 * pad; ch = H - y - int(H * 0.035)
    srcim = Image.open(src).convert("RGB")
    # Show the whole capture: scale to fit the space, centred horizontally.
    s = min(cw / srcim.size[0], ch / srcim.size[1])
    cw, ch = int(srcim.size[0] * s), int(srcim.size[1] * s)
    card = srcim.resize((cw, ch), Image.LANCZOS)
    pad = (W - cw) // 2
    rc = rounded(card, int(W * 0.045))
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([pad - 6, y - 6, pad + cw + 6, y + ch + 6], radius=int(W * 0.05), fill=(140, 242, 255, 50))
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    im = Image.alpha_composite(im.convert("RGBA"), glow)
    im.alpha_composite(rc, (pad, y))
    im.convert("RGB").save(os.path.join(OUT, name), optimize=True)

sizes = {"phone": (1080, 1920), "tablet7": (1200, 1920), "tablet10": (1600, 2560)}
for kind, (W, H) in sizes.items():
    n = 0
    for f, cap, sub in SHOTS:
        p = os.path.join(SRC, f)
        if not os.path.exists(p): continue
        n += 1
        shot(p, cap, sub, W, H, f"{kind}-{n}-{f[:-4]}.png")

# Feature graphic 1024x500: the wide home-screen render (hole + disk band),
# shifted right of the title, over black space.
src = Image.open(os.path.join(SRC, "wallpaper.png")).convert("RGB")
band = src.crop((0, 1020 - 300, src.size[0], 1020 + 300)).resize((1024, 569), Image.LANCZOS)
fg = Image.new("RGB", (1024, 500), (3, 4, 8))
b = band.crop((0, 34, 1024, 534)).convert("RGBA")
m = Image.new("L", b.size, 255); md = ImageDraw.Draw(m)
for x in range(300):
    md.line([(x, 0), (x, 500)], fill=int(255 * (x / 300) ** 1.5))
b.putalpha(m)
fg = fg.convert("RGBA"); fg.alpha_composite(b, (230, 0)); fg = fg.convert("RGB")
shade = Image.new("RGBA", (1024, 500), (0, 0, 0, 0)); sd = ImageDraw.Draw(shade)
for x in range(1024):
    a = int(max(0, 1 - x / 660) ** 1.1 * 235)
    sd.line([(x, 0), (x, 500)], fill=(3, 4, 8, a))
fg = Image.alpha_composite(fg.convert("RGBA"), shade); d = ImageDraw.Draw(fg)
d.text((56, 150), "BlackHole", font=font(78), fill=WHITE)
d.text((60, 250), "Real Kerr physics, ray traced live", font=font(30, bold=False), fill=ACCENT)
d.text((60, 296), "Live wallpaper  |  4K posters  |  Orbit videos", font=font(24, bold=False), fill=DIM)
fg.convert("RGB").save(os.path.join(OUT, "feature-graphic-1024x500.png"), optimize=True)
print("ok", sorted(os.listdir(OUT)))
