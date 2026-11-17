"""Draws every Box://Stream image: logo, icons, splash, background and the
bezel / neon pieces the theme is built from. Run: python tools/build_assets.py

The wordmark uses Noto Sans (SIL Open Font License), read from the system
fonts folder or the path in BOXSTREAM_FONT_DIR; the font itself is not shipped.
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "images")
FONT_DIR = os.environ.get("BOXSTREAM_FONT_DIR", r"C:\Windows\Fonts")

BG = (6, 8, 13)
PANEL = (16, 20, 29)
GREEN = (57, 255, 136)
BLUE = (46, 160, 255)
CYAN = (40, 220, 255)
WHITE = (240, 246, 255)


def font(weight, size):
    return ImageFont.truetype(os.path.join(FONT_DIR, f"NotoSans-{weight}.ttf"), size)


def app_version():
    import re
    text = open(os.path.join(ROOT, "manifest"), encoding="utf-8").read()
    return ".".join(re.search(rf"{k}_version=(\d+)", text).group(1) for k in ("major", "minor", "build"))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gradient(size, start, end, horizontal=True):
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = x / max(1, w - 1) if horizontal else y / max(1, h - 1)
            c = lerp(start, end, t)
            px[x, y] = c + (255,) if len(c) == 3 else c
    return img


def diag_gradient(size, start, end):
    w, h = size
    small = Image.new("RGB", (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            px[x, y] = lerp(start, end, (x + y) / 126)
    return small.resize(size, Image.BICUBIC).convert("RGBA")


def glow(layer, radius, strength=1.0):
    """Returns layer blurred into a soft glow (alpha boosted)."""
    blurred = layer.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        r, g, b, a = blurred.split()
        a = a.point(lambda v: min(255, int(v * strength)))
        blurred = Image.merge("RGBA", (r, g, b, a))
    return blurred


def colorize(mask, fill):
    """Fills a mask (L) with a color or an RGBA image."""
    if isinstance(fill, tuple):
        fill = Image.new("RGBA", mask.size, fill + (255,))
    out = fill.copy()
    out.putalpha(ImageChops.multiply(fill.getchannel("A"), mask))
    return out


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path, optimize=True)
    print(name, img.size)


# ---------------------------------------------------------------- the mark ---
def cube_mark(size):
    """Isometric box drawn as glowing edges, with a play triangle on its face.
    Drawn 4x then reduced for smooth lines."""
    s = 4
    W = size * s
    c = W / 2
    r = W * 0.36
    top = (c, c - r)
    ur = (c + r * math.cos(math.radians(30)), c - r / 2)
    lr = (c + r * math.cos(math.radians(30)), c + r / 2)
    bot = (c, c + r)
    ll = (c - r * math.cos(math.radians(30)), c + r / 2)
    ul = (c - r * math.cos(math.radians(30)), c - r / 2)
    mid = (c, c)

    img = Image.new("RGBA", (W, W))
    # Faces: dark glass with a faint tint, lit from the top-left.
    faces = [
        ([top, ur, mid, ul], (26, 54, 48, 235)),   # lid, green tint
        ([ul, mid, bot, ll], (14, 22, 30, 240)),   # left
        ([mid, ur, lr, bot], (16, 30, 52, 240)),   # right, blue tint
    ]
    d = ImageDraw.Draw(img)
    for pts, fill in faces:
        d.polygon(pts, fill=fill)

    # Edge masks: outer outline and inner Y, gradient green -> blue.
    width = int(W * 0.028)
    edges = Image.new("L", (W, W), 0)
    e = ImageDraw.Draw(edges)
    outline = [top, ur, lr, bot, ll, ul, top]
    e.line(outline, fill=255, width=width, joint="curve")
    for p in (top, ur, lr, bot, ll, ul):
        e.ellipse([p[0] - width / 2, p[1] - width / 2, p[0] + width / 2, p[1] + width / 2], fill=255)
    inner = Image.new("L", (W, W), 0)
    i = ImageDraw.Draw(inner)
    for p in (ul, ur, bot):
        i.line([mid, p], fill=255, width=int(width * 0.7))
    i.ellipse([mid[0] - width * 0.4, mid[1] - width * 0.4, mid[0] + width * 0.4, mid[1] + width * 0.4], fill=255)

    grad = gradient((W, W), GREEN, BLUE, horizontal=False)
    edge_layer = colorize(edges, grad)
    inner_layer = colorize(inner.point(lambda v: int(v * 0.75)), grad)

    # Play triangle on the right face, skewed to the face's plane.
    tri = Image.new("L", (W, W), 0)
    t = ImageDraw.Draw(tri)
    fx, fy = (mid[0] + lr[0]) / 2 - r * 0.02, (ur[1] + bot[1]) / 2 + r * 0.04
    k = r * 0.40
    skew = math.tan(math.radians(30))
    pts = [(fx - k * 0.45, fy - k * 0.55 - (-k * 0.45) * skew),
           (fx - k * 0.45, fy + k * 0.55 - (-k * 0.45) * skew),
           (fx + k * 0.65, fy - (k * 0.65) * skew)]
    t.polygon(pts, fill=255)
    tri_layer = colorize(tri, CYAN)

    out = Image.new("RGBA", (W, W))
    out.alpha_composite(glow(edge_layer, W * 0.035, 1.6))
    out.alpha_composite(img)
    out.alpha_composite(glow(tri_layer, W * 0.02, 1.4))
    out.alpha_composite(tri_layer)
    out.alpha_composite(inner_layer)
    out.alpha_composite(edge_layer)
    # A bright specular line along the lid's front edges.
    spec = Image.new("L", (W, W), 0)
    ImageDraw.Draw(spec).line([ul, top, ur], fill=170, width=max(2, width // 4))
    out.alpha_composite(colorize(spec, WHITE))
    return out.resize((size, size), Image.LANCZOS)


# ------------------------------------------------------------ the wordmark ---
def wordmark(height, mark=True):
    """Box://Stream: white Box and Stream, neon gradient ://, optional cube."""
    s = 3
    H = height * s
    bold = font("Bold", int(H * 0.62))
    regular = font("Regular", int(H * 0.62))
    parts = [("Box", bold, WHITE), ("://", bold, None), ("Stream", regular, WHITE)]
    widths = [p[1].getlength(p[0]) for p in parts]
    gap = H * 0.02
    mark_w = int(H * 1.05) if mark else 0
    W = int(mark_w + sum(widths) + gap * 2 + H * 0.3)
    img = Image.new("RGBA", (W, H))
    x = mark_w + (H * 0.12 if mark else H * 0.05)
    baseline = H * 0.80
    for (text, f, color), w in zip(parts, widths):
        mask = Image.new("L", (W, H), 0)
        ImageDraw.Draw(mask).text((x, baseline), text, font=f, fill=255, anchor="ls")
        if color is None:
            fill = Image.new("RGBA", (W, H))
            fill.paste(gradient((int(w) + 2, H), GREEN, BLUE), (int(x), 0))
            layer = colorize(mask, fill)
            img.alpha_composite(glow(layer, H * 0.06, 1.8))
        else:
            layer = colorize(mask, color)
            img.alpha_composite(glow(colorize(mask, (120, 170, 255)), H * 0.05, 0.35))
        img.alpha_composite(layer)
        x += w + gap
    if mark:
        cube = cube_mark(int(H * 1.05))
        img.alpha_composite(cube, (0, int((H - cube.height) / 2)))
    return img.resize((W // s, height), Image.LANCZOS)


# ---------------------------------------------------------- bezel pieces ---
def rounded_mask(size, radius, inset=0):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([inset, inset, size[0] - 1 - inset, size[1] - 1 - inset], radius, fill=255)
    return m


def bezel(size, radius, base=PANEL, depth=1.0, glass=True):
    """A raised 3D panel: dark body with a vertical sheen, a bright top/left
    edge, a dark bottom/right edge and an inner shadow line."""
    w, h = size
    s = 3
    W, H, R = w * s, h * s, radius * s
    body = gradient((W, H), lerp(base, WHITE, 0.07 * depth), lerp(base, BG, 0.55), horizontal=False)
    out = colorize(rounded_mask((W, H), R), body)
    # Outer rim: light from the top, dark at the bottom.
    rim = gradient((W, H), (150, 175, 210), (10, 12, 18), horizontal=False)
    ring = ImageChops.subtract(rounded_mask((W, H), R), rounded_mask((W, H), R - s, s * 2))
    out.alpha_composite(colorize(ring.point(lambda v: int(v * 0.85)), rim))
    # Inner bevel: a second, fainter ring inset a few pixels.
    inner = ImageChops.subtract(rounded_mask((W, H), R - 3 * s, 3 * s), rounded_mask((W, H), R - 4 * s, 4 * s))
    out.alpha_composite(colorize(inner.point(lambda v: int(v * 0.35)), gradient((W, H), (0, 0, 0), (90, 110, 140), horizontal=False)))
    if glass:
        # Glass sheen across the top third.
        sheen = Image.new("L", (W, H), 0)
        ImageDraw.Draw(sheen).rounded_rectangle([3 * s, 3 * s, W - 3 * s, int(H * 0.42)], max(1, R - 3 * s), fill=255)
        top_h = int(H * 0.42)
        fade = Image.new("L", (W, H), 0)
        fade.paste(gradient((W, top_h), (255, 255, 255), (0, 0, 0), horizontal=False).getchannel("R"), (0, 0))
        fade = fade.point(lambda v: int((v / 255) ** 1.8 * 255 * 0.09))
        out.alpha_composite(colorize(ImageChops.multiply(sheen, fade), WHITE))
    return out.resize(size, Image.LANCZOS)


def nine_patch(img, stretch_x, stretch_y, pad=None):
    """Adds the 1px Roku 9-patch border. stretch_*: (start, end) in image px."""
    w, h = img.size
    out = Image.new("RGBA", (w + 2, h + 2))
    out.paste(img, (1, 1))
    d = ImageDraw.Draw(out)
    black = (0, 0, 0, 255)
    d.line([(stretch_x[0] + 1, 0), (stretch_x[1], 0)], fill=black)
    d.line([(0, stretch_y[0] + 1), (0, stretch_y[1])], fill=black)
    if pad:
        d.line([(pad[0] + 1, h + 1), (w - pad[0], h + 1)], fill=black)
        d.line([(w + 1, pad[1] + 1), (w + 1, h - pad[1])], fill=black)
    return out


def neon_ring(size, radius, color, color2=None, thickness=4, blur=10, margin=36):
    """A glowing focus outline with a transparent middle."""
    w, h = size
    s = 2
    W, H = w * s, h * s
    m = margin * s
    ring = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(ring)
    d.rounded_rectangle([m, m, W - 1 - m, H - 1 - m], (radius + 2) * s, outline=255, width=thickness * s)
    fill = gradient((W, H), color, color2) if color2 else Image.new("RGBA", (W, H), color + (255,))
    layer = colorize(ring, fill)
    out = Image.new("RGBA", (W, H))
    out.alpha_composite(glow(layer, blur * s, 2.2))
    out.alpha_composite(glow(layer, blur * s * 0.4, 1.5))
    out.alpha_composite(layer)
    hot = colorize(ring.filter(ImageFilter.GaussianBlur(s)).point(lambda v: int(v * 0.55)), WHITE)
    out.alpha_composite(hot)
    return out.resize(size, Image.LANCZOS)


# ------------------------------------------------------------- the icons ---
def line_icon(kind, size, color):
    s = 4
    W = size * s
    m = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(m)
    lw = int(W * 0.085)
    if kind == "movie":
        d.rounded_rectangle([W * .12, W * .30, W * .88, W * .86], W * .06, outline=255, width=lw)
        for i in range(4):
            x = W * (.16 + i * .19)
            d.polygon([(x, W * .14), (x + W * .12, W * .14), (x + W * .17, W * .28), (x + W * .05, W * .28)], fill=255)
        d.polygon([(W * .43, W * .45), (W * .43, W * .72), (W * .64, W * .585)], fill=255)
    elif kind == "tv":
        d.rounded_rectangle([W * .10, W * .24, W * .90, W * .78], W * .07, outline=255, width=lw)
        d.line([(W * .32, W * .90), (W * .68, W * .90)], fill=255, width=lw)
        d.line([(W * .38, W * .08), (W * .50, W * .22), (W * .62, W * .08)], fill=255, width=int(lw * .8))
    elif kind == "music":
        d.ellipse([W * .14, W * .62, W * .40, W * .86], fill=255)
        d.ellipse([W * .56, W * .54, W * .82, W * .78], fill=255)
        d.line([(W * .37, W * .74), (W * .37, W * .20)], fill=255, width=lw)
        d.line([(W * .79, W * .66), (W * .79, W * .12)], fill=255, width=lw)
        d.polygon([(W * .33, W * .16), (W * .83, W * .06), (W * .83, W * .22), (W * .33, W * .32)], fill=255)
    elif kind == "folder":
        d.rounded_rectangle([W * .10, W * .28, W * .90, W * .84], W * .07, outline=255, width=lw)
        d.polygon([(W * .10, W * .30), (W * .14, W * .16), (W * .42, W * .16), (W * .48, W * .28)], fill=255)
    elif kind == "home":
        d.line([(W * .12, W * .50), (W * .50, W * .14), (W * .88, W * .50)], fill=255, width=lw, joint="curve")
        d.rounded_rectangle([W * .24, W * .46, W * .76, W * .88], W * .05, outline=255, width=lw)
        d.rectangle([W * .43, W * .64, W * .57, W * .88], fill=255)
    elif kind == "settings":
        c = W / 2
        for k in range(8):
            a = math.radians(k * 45)
            d.line([(c + math.cos(a) * W * .22, c + math.sin(a) * W * .22), (c + math.cos(a) * W * .42, c + math.sin(a) * W * .42)], fill=255, width=int(lw * 1.5))
        d.ellipse([c - W * .28, c - W * .28, c + W * .28, c + W * .28], outline=255, width=lw)
        d.ellipse([c - W * .10, c - W * .10, c + W * .10, c + W * .10], fill=255)
    elif kind == "search":
        d.ellipse([W * .12, W * .12, W * .64, W * .64], outline=255, width=lw)
        d.line([(W * .58, W * .58), (W * .88, W * .88)], fill=255, width=int(lw * 1.3))
    elif kind == "play":
        d.polygon([(W * .26, W * .14), (W * .26, W * .86), (W * .86, W * .50)], fill=255)
    elif kind == "pause":
        d.rounded_rectangle([W * .22, W * .14, W * .42, W * .86], W * .04, fill=255)
        d.rounded_rectangle([W * .58, W * .14, W * .78, W * .86], W * .04, fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    return colorize(m, color)


def placeholder(kind, size, accent):
    """Poster stand-in: deep tinted gradient, a big faint icon and grain."""
    w, h = size
    img = gradient(size, lerp(PANEL, accent, 0.18), BG, horizontal=False)
    icon = line_icon(kind, int(w * 0.42), accent)
    a = icon.getchannel("A").point(lambda v: int(v * 0.55))
    icon.putalpha(a)
    img.alpha_composite(glow(icon, w * 0.04, 1.2), (int(w * 0.29), int(h * 0.30)))
    img.alpha_composite(icon, (int(w * 0.29), int(h * 0.30)))
    return img


# --------------------------------------------------------- big pictures ---
def background(size):
    """Near-black with a cool vignette, two soft neon blooms and a faint
    perspective floor grid."""
    w, h = size
    img = Image.new("RGBA", size, BG + (255,))
    bloom = Image.new("RGBA", size)
    d = ImageDraw.Draw(bloom)
    d.ellipse([-w * .25, -h * .55, w * .45, h * .45], fill=(30, 140, 90, 70))
    d.ellipse([w * .55, h * .35, w * 1.3, h * 1.4], fill=(30, 90, 200, 80))
    img.alpha_composite(bloom.filter(ImageFilter.GaussianBlur(w * .12)))
    grid = Image.new("L", size, 0)
    g = ImageDraw.Draw(grid)
    horizon = h * .62
    vx = w / 2
    for i in range(-24, 25):
        g.line([(vx + i * w * .015, horizon), (vx + i * w * .16, h)], fill=26, width=2)
    y = horizon
    step = 6
    while y < h:
        g.line([(0, y), (w, y)], fill=22, width=2)
        y += step
        step *= 1.32
    fade = gradient(size, (0, 0, 0), (255, 255, 255), horizontal=False).getchannel("R")
    fade = fade.point(lambda v: 0 if v < 158 else int((v - 158) * 2.6))
    grid = ImageChops.multiply(grid, fade)
    img.alpha_composite(colorize(grid, gradient(size, GREEN, BLUE)))
    vignette = Image.new("L", size, 0)
    ImageDraw.Draw(vignette).ellipse([-w * .2, -h * .3, w * 1.2, h * 1.3], fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(w * .08))
    dark = Image.new("RGBA", size, (0, 0, 0, 200))
    dark.putalpha(ImageChops.invert(vignette).point(lambda v: int(v * .75)))
    img.alpha_composite(dark)
    return img


def hero_fade(size):
    """Darkens a backdrop: solid on the left and bottom, clear top-right."""
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    for y in range(h):
        for x in range(w):
            tx = max(0.0, 1 - x / (w * .72))
            ty = max(0.0, (y - h * .45) / (h * .55))
            a = min(1.0, tx ** 0.8 + ty ** 1.4 * 0.95 + 0.18)
            px[x, y] = BG + (int(255 * a),)
    return img


def splash(size):
    w, h = size
    img = background(size)
    mark = wordmark(int(h * 0.15))
    img.alpha_composite(mark, ((w - mark.width) // 2, int(h * .40)))
    tag = font("Regular", int(h * 0.026))
    d = ImageDraw.Draw(img)
    d.text((w / 2, h * .62), "MOVIES  ·  TV  ·  MUSIC", font=tag, fill=(150, 170, 200, 255), anchor="mm")
    d.text((w - h * .05, h * .95), "v" + app_version(), font=font("Regular", int(h * 0.022)), fill=(90, 105, 130, 255), anchor="rs")
    return img


def channel_icon(size):
    """Home-screen tile: a bezel slab with the cube and wordmark."""
    w, h = size
    img = background((w, h)).resize((w, h))
    slab = bezel((int(w * .92), int(h * .88)), int(h * .08), base=(14, 18, 26))
    img.alpha_composite(slab, ((w - slab.width) // 2, (h - slab.height) // 2))
    cube = cube_mark(int(h * .56))
    img.alpha_composite(cube, ((w - cube.width) // 2, int(h * .08)))
    mark = wordmark(int(h * .17), mark=False)
    img.alpha_composite(mark, ((w - mark.width) // 2, int(h * .66)))
    return img.convert("RGB")


def splash_only():
    big = splash((1920, 1080))
    save(big.convert("RGB"), "splash_fhd.png")
    save(big.resize((1280, 720), Image.LANCZOS).convert("RGB"), "splash_hd.png")


def main():
    import sys
    os.makedirs(OUT, exist_ok=True)
    if "--splash" in sys.argv:
        splash_only()
        return
    save(wordmark(84), "logo.png")
    save(wordmark(200), "logo-large.png")
    save(cube_mark(256), "mark.png")
    save(channel_icon((540, 405)), "icon_fhd.png")
    save(channel_icon((290, 218)), "icon_hd.png")
    save(channel_icon((246, 140)), "icon_sd.png")
    big = splash((1920, 1080))
    save(big.convert("RGB"), "splash_fhd.png")
    save(big.resize((1280, 720), Image.LANCZOS).convert("RGB"), "splash_hd.png")
    save(background((1920, 1080)).convert("RGB"), "background.jpg")
    save(hero_fade((960, 540)), "hero-fade.png")

    # 9-patch bezels. Corners stay fixed; the middle stretches.
    card = bezel((64, 64), 14)
    save(nine_patch(card, (20, 44), (20, 44)), "card.9.png")
    panel = bezel((96, 96), 22, base=(14, 18, 27))
    save(nine_patch(panel, (30, 66), (30, 66)), "panel.9.png")
    button = bezel((64, 64), 16, base=(24, 30, 44), depth=1.6)
    save(nine_patch(button, (22, 42), (22, 42)), "button.9.png")
    pressed = bezel((64, 64), 16, base=(18, 64, 52), depth=2.2)
    save(nine_patch(pressed, (22, 42), (22, 42)), "button-on.9.png")
    pill = bezel((48, 48), 23, base=(20, 26, 38), depth=1.4)
    save(nine_patch(pill, (23, 25), (23, 25)), "pill.9.png")
    # Focus glows: 18px of glow around a ring.
    for name, c1, c2 in (("focus", GREEN, BLUE), ("focus-green", GREEN, None), ("focus-blue", BLUE, CYAN)):
        ring = neon_ring((136, 136), 14, c1, c2)
        save(nine_patch(ring, (60, 76), (60, 76)), name + ".9.png")
    tab = neon_ring((108, 76), 18, GREEN, BLUE, thickness=3, blur=7, margin=24)
    save(nine_patch(tab, (48, 60), (36, 40)), "focus-tab.9.png")
    # A thin neon bar for progress and underlines.
    bar = Image.new("RGBA", (64, 12))
    bar.alpha_composite(glow(colorize(rounded_mask((64, 12), 3, 3), gradient((64, 12), GREEN, BLUE)), 2, 1.5))
    bar.alpha_composite(colorize(rounded_mask((64, 12), 3, 3), gradient((64, 12), GREEN, BLUE)))
    save(nine_patch(bar, (8, 56), (4, 8)), "neon-bar.9.png")
    track = colorize(rounded_mask((64, 12), 3, 3), (40, 48, 66))
    save(nine_patch(track, (8, 56), (4, 8)), "track.9.png")

    # Shades for the top bar and the player overlay (stretched sideways).
    top = Image.new("RGBA", (8, 256))
    for y in range(256):
        a = int(235 * (1 - y / 255) ** 1.6)
        for x in range(8):
            top.putpixel((x, y), BG + (a,))
    save(top, "shade-top.png")
    save(top.transpose(Image.FLIP_TOP_BOTTOM), "shade-bottom.png")
    for kind in ("movie", "tv", "music", "folder", "home", "settings", "search", "play", "pause"):
        save(line_icon(kind, 48, WHITE), f"icon-{kind}.png")
    save(placeholder("movie", (300, 450), GREEN), "poster-movie.png")
    save(placeholder("tv", (300, 450), BLUE), "poster-tv.png")
    save(placeholder("music", (400, 400), CYAN), "poster-music.png")
    save(placeholder("folder", (300, 450), (140, 160, 190)), "poster-folder.png")
    save(placeholder("movie", (480, 270), BLUE), "thumb-episode.png")


if __name__ == "__main__":
    main()
