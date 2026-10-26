#!/usr/bin/env python3
# Generates the Google Play store icon (512x512) and feature graphic (1024x500).
# Black-hole motif (lensed accretion disk + photon ring) matching the app, with
# an IBM Plex Mono wordmark. Rendered supersampled then downscaled for clean AA.
import math, random
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

PLEX_MONO_MED = "/tmp/plex/IBMPlexMono-Medium.ttf"
PLEX_MONO_REG = "/tmp/plex/IBMPlexMono-Regular.ttf"

# ---- palette ----
BG0 = (9, 12, 20)       # outer
BG1 = (16, 21, 34)      # inner glow of background
DISK_WARM = (255, 150, 70)
DISK_HOT = (255, 224, 168)
DOPPLER = (255, 248, 232)
PHOTON = (190, 244, 255)
ACCENT = (140, 242, 255)
WHITE = (242, 246, 250)


def radial_bg(size, c_in, c_out, cx=None, cy=None, falloff=1.15):
    w, h = size
    cx = w / 2 if cx is None else cx
    cy = h / 2 if cy is None else cy
    maxd = math.hypot(max(cx, w - cx), max(cy, h - cy))
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy) / maxd
            t = min(1.0, d ** falloff)
            px[x, y] = (
                int(c_in[0] * (1 - t) + c_out[0] * t),
                int(c_in[1] * (1 - t) + c_out[1] * t),
                int(c_in[2] * (1 - t) + c_out[2] * t),
            )
    return img


def starfield(img, n, cx, cy, avoid_r, seed=7):
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img, "RGBA")
    w, h = img.size
    for _ in range(n):
        x = rnd.uniform(0, w); y = rnd.uniform(0, h)
        if math.hypot(x - cx, y - cy) < avoid_r:
            continue
        r = rnd.uniform(0.6, 2.4) * (w / 512)
        a = int(rnd.uniform(40, 170))
        col = rnd.choice([(255, 255, 255), (200, 220, 255), (255, 235, 210)])
        d.ellipse([x - r, y - r, x + r, y + r], fill=col + (a,))
    return img


def doppler_mask(size, cx, bright_left=True):
    """Horizontal brightness gradient (one side brighter) as an L mask."""
    w, h = size
    m = Image.new("L", size, 0)
    px = m.load()
    for x in range(w):
        t = x / w
        v = (1 - t) if bright_left else t
        val = int(70 + 185 * (v ** 1.4))
        for y in range(h):
            px[x, y] = val
    return m


def black_hole(size, scale, cx, cy):
    """Returns an emissive RGBA layer with the lensed disk + photon ring."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer, "RGBA")

    R = scale  # base radius unit
    # --- accretion disk band (tilted ellipse annulus) ---
    disk = Image.new("RGBA", size, (0, 0, 0, 0))
    dd = ImageDraw.Draw(disk, "RGBA")
    ox, oy = 2.55 * R, 0.86 * R       # outer semi-axes
    ix, iy = 1.18 * R, 0.50 * R       # inner semi-axes
    dd.ellipse([cx - ox, cy - oy, cx + ox, cy + oy], fill=DISK_WARM + (255,))
    # warmer/hotter inner edge
    dd.ellipse([cx - ox * 0.74, cy - oy * 0.74, cx + ox * 0.74, cy + oy * 0.74],
               fill=DISK_HOT + (255,))
    dd.ellipse([cx - ix, cy - iy, cx + ix, cy + iy], fill=(0, 0, 0, 0))
    # Doppler: brighten left side
    dm = doppler_mask(size, cx, bright_left=True)
    disk.putalpha(ImageChops.multiply(disk.getchannel("A"), dm))
    layer = Image.alpha_composite(layer, disk)

    # --- lensed halo ring (near-circular: light wrapping over top/bottom) ---
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo, "RGBA")
    hr = 1.30 * R
    hw = 0.16 * R
    hd.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], outline=DISK_HOT + (255,),
               width=int(hw))
    halo.putalpha(ImageChops.multiply(halo.getchannel("A"),
                                      doppler_mask(size, cx, True)))
    layer = Image.alpha_composite(layer, halo)

    d = ImageDraw.Draw(layer, "RGBA")
    # --- photon ring (thin, bright, cyan-white) ---
    pr = 1.12 * R
    d.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], outline=PHOTON + (255,),
              width=max(2, int(0.045 * R)))
    return layer


def compose(size, scale, cx, cy, n_stars):
    big = radial_bg(size, BG1, BG0, cx=cx, cy=cy).convert("RGBA")
    big = starfield(big, n_stars, cx, cy, scale * 1.55)

    emissive = black_hole(size, scale, cx, cy)

    # Bloom: blurred copies of the emissive layer added underneath for glow.
    glow1 = emissive.filter(ImageFilter.GaussianBlur(scale * 0.10))
    glow2 = emissive.filter(ImageFilter.GaussianBlur(scale * 0.32))
    big = Image.alpha_composite(big, Image.eval(glow2, lambda v: int(v * 0.85)))
    big = Image.alpha_composite(big, glow1)
    big = Image.alpha_composite(big, emissive)

    # Event-horizon shadow on top (pure black sphere, soft edge).
    sh = Image.new("RGBA", size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh, "RGBA")
    rh = 1.0 * scale
    sd.ellipse([cx - rh, cy - rh, cx + rh, cy + rh], fill=(0, 0, 0, 255))
    sh = sh.filter(ImageFilter.GaussianBlur(scale * 0.012))
    big = Image.alpha_composite(big, sh)
    return big


def tracked_text(draw, xy, text, font, fill, tracking):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        w = draw.textlength(ch, font=font)
        x += w + tracking
    return x


def text_width(draw, text, font, tracking):
    return sum(draw.textlength(c, font=font) + tracking for c in text) - tracking


# =========================== ICON 512x512 ===========================
SS = 4
S = 512 * SS
icon = compose((S, S), scale=0.300 * S / 2, cx=S / 2, cy=S * 0.52, n_stars=90)
# Play store icon must be a 32-bit PNG (with alpha channel), fully opaque.
icon = icon.convert("RGBA").resize((512, 512), Image.LANCZOS)
icon.save("/tmp/out/play-store-icon-512.png")

# ======================= FEATURE GRAPHIC 1024x500 =======================
SS2 = 2
FW, FH = 1024 * SS2, 500 * SS2
# Black hole on the right, text on the left.
bh_cx, bh_cy = FW * 0.82, FH * 0.5
feat = compose((FW, FH), scale=0.155 * FH, cx=bh_cx, cy=bh_cy, n_stars=140)
draw = ImageDraw.Draw(feat, "RGBA")

word_font = ImageFont.truetype(PLEX_MONO_MED, int(0.150 * FH))
tag_font = ImageFont.truetype(PLEX_MONO_REG, int(0.044 * FH))
sub_font = ImageFont.truetype(PLEX_MONO_REG, int(0.030 * FH))

left = int(0.06 * FW)
word_tr = int(0.012 * FH)
tag_tr = int(0.010 * FH)

# vertical centering of the text block
wh = (word_font.getbbox("BLACKHOLE")[3] - word_font.getbbox("BLACKHOLE")[1])
ty = FH * 0.40
tracked_text(draw, (left, ty), "BLACKHOLE", word_font, WHITE + (255,), word_tr)
# accent divider
dy = ty + wh + 0.06 * FH
dx_end = left + text_width(draw, "BLACKHOLE", word_font, word_tr)
draw.line([(left + 4, dy), (dx_end, dy)], fill=ACCENT + (180,), width=max(2, int(0.006 * FH)))
# tagline
tracked_text(draw, (left, dy + 0.04 * FH), "REAL-TIME KERR BLACK HOLE SIMULATOR",
             tag_font, ACCENT + (235,), tag_tr)
# credit
tracked_text(draw, (left, dy + 0.13 * FH), "ORCH AEROSPACE",
             sub_font, (170, 185, 205, 220), int(0.014 * FH))

feat = feat.convert("RGB").resize((1024, 500), Image.LANCZOS)
feat.save("/tmp/out/feature-graphic-1024x500.png")
print("done")
