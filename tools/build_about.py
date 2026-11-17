"""Builds the About page's QR codes from tools/about.json.

  images/qr-donate.png   when "donate_url" is set
  images/qr-project.png  when "project_url" is set
  images/about.json      the labels and links the app shows

QR modules come from tools/qr_matrix.js (npm package "qrcode"); set
BOXSTREAM_NODE_MODULES to the node_modules folder that has it.
"""
import json
import os
import subprocess

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GREEN = (57, 255, 136)
BLUE = (46, 160, 255)


def matrix(text):
    env = dict(os.environ)
    if os.environ.get("BOXSTREAM_NODE_MODULES"):
        env["NODE_PATH"] = os.environ["BOXSTREAM_NODE_MODULES"]
    out = subprocess.run(["node", os.path.join(ROOT, "tools", "qr_matrix.js"), text], capture_output=True, text=True, env=env, check=True)
    return json.loads(out.stdout)


def qr_image(text, size=420):
    rows = matrix(text)
    n = len(rows)
    quiet = 3
    cell = (size - 40) // (n + quiet * 2)
    inner = cell * (n + quiet * 2)
    tile = Image.new("RGBA", (inner, inner), (255, 255, 255, 255))
    d = ImageDraw.Draw(tile)
    for y, row in enumerate(rows):
        for x, bit in enumerate(row):
            if bit == "1":
                x0 = (x + quiet) * cell
                y0 = (y + quiet) * cell
                d.rectangle([x0, y0, x0 + cell - 1, y0 + cell - 1], fill=(6, 8, 13, 255))
    # Rounded white tile inside a neon frame with a soft glow.
    out = Image.new("RGBA", (size, size))
    frame = Image.new("RGBA", (size, size))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle([6, 6, size - 7, size - 7], 26, outline=GREEN + (255,), width=5)
    glow = frame.filter(ImageFilter.GaussianBlur(6))
    out.alpha_composite(glow)
    out.alpha_composite(glow)
    mask = Image.new("L", (inner, inner), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner - 1, inner - 1], 16, fill=255)
    tile.putalpha(mask)
    offset = (size - inner) // 2
    out.alpha_composite(tile, (offset, offset))
    out.alpha_composite(frame)
    return out


def main():
    config = json.load(open(os.path.join(ROOT, "tools", "about.json"), encoding="utf-8"))
    images = os.path.join(ROOT, "images")
    info = {"donateLabel": config.get("donate_label", ""), "donateHint": config.get("donate_hint", ""), "credit": config.get("credit", ""), "donateUrl": "", "projectUrl": "", "donateQr": "", "projectQr": ""}
    for key, name in (("donate_url", "qr-donate.png"), ("project_url", "qr-project.png")):
        path = os.path.join(images, name)
        url = config.get(key, "").strip()
        if url:
            # The QR can hold a payment link ("bitcoin:...") while the text shows the address.
            qr_text = config.get("donate_qr", "").strip() if key == "donate_url" else ""
            qr_image(qr_text or url).save(path, optimize=True)
            info["donateUrl" if key == "donate_url" else "projectUrl"] = url
            info["donateQr" if key == "donate_url" else "projectQr"] = "pkg:/images/" + name
            print(name, url)
        elif os.path.exists(path):
            os.remove(path)
    json.dump(info, open(os.path.join(images, "about.json"), "w", encoding="utf-8"), indent=2)


if __name__ == "__main__":
    main()
