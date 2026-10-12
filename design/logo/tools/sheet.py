import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = os.path.join(ROOT, "build-test", "out")
CONCEPTS = [("A", "hung-a"), ("B", "hung-b"), ("C", "hung-c")]
SHOTS = [
    ("Default light", "h_default_light", {"hung-a": (741, 666), "hung-b": (1019, 666), "hung-c": (187, 967)}),
    ("Default dark", "h_default_dark", {"hung-a": (741, 666), "hung-b": (1019, 666), "hung-c": (187, 967)}),
    ("Clear light", "h_clear_light", {"hung-a": (741, 666), "hung-b": (1019, 666), "hung-c": (187, 967)}),
    ("Clear dark", "h_clear_dark", {"hung-a": (741, 666), "hung-b": (1019, 666), "hung-c": (187, 967)}),
    ("Tinted light", "h_tinted_light", {"hung-a": (741, 666), "hung-b": (1019, 666), "hung-c": (187, 967)}),
    ("Tinted dark", "h_tinted_dark", {"hung-a": (741, 666), "hung-b": (1019, 666), "hung-c": (187, 967)}),
    ("iOS 18.3 fallback", "h_ios18", {"hung-a": (466, 652), "hung-b": (737, 652), "hung-c": (1009, 652)}),
]
BOX = 236
font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 26)
small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 18)

crops = {}
for label, shot, pos in SHOTS:
    im = Image.open(f"{S}/{shot}.png")
    for _, c in CONCEPTS:
        x, y = pos[c]
        crop = im.crop((x - BOX // 2, y - BOX // 2 - 10, x + BOX // 2, y + BOX // 2 - 10))
        crops[(label, c)] = crop
        d = f"{ROOT}/concepts/{c}/preview"
        os.makedirs(d, exist_ok=True)
        crop.save(f"{d}/homescreen-3x-{shot.replace('h_', '')}.png")

LARGE = 400
cell_w = LARGE + 24
rows = len(SHOTS)
W = 200 + len(CONCEPTS) * cell_w + 40 + len(CONCEPTS) * 92
H = 120 + LARGE + 40 + rows * (BOX + 34) + 60
sheet = Image.new("RGB", (W, H), "#1c1917")
dr = ImageDraw.Draw(sheet)
dr.text((24, 20), "iFramed You - hung refinements A / B / C", fill="white", font=font)
dr.text((24, 56), "Row 1: actool-flattened 1024 px Default render (Apple toolchain, what iOS 17-18 ships). Rows below: real iOS 26.5 home-screen renders at native 3x (left) and at 1x home-screen size (right).", fill="#bdad98", font=small)
y0 = 100
for i, (letter, c) in enumerate(CONCEPTS):
    x = 200 + i * cell_w
    big = Image.open(f"{ROOT}/concepts/{c}/preview/actool-flattened-1024-light.png").resize((LARGE, LARGE), Image.LANCZOS)
    sheet.paste(big, (x, y0))
    dr.text((x, y0 - 30), f"{letter}  ({c})", fill="white", font=font)
y = y0 + LARGE + 40
for label, shot, _ in SHOTS:
    dr.text((24, y + BOX // 2 - 14), label, fill="white", font=font)
    for i, (letter, c) in enumerate(CONCEPTS):
        x = 200 + i * cell_w
        sheet.paste(crops[(label, c)], (x, y))
        sx = 200 + len(CONCEPTS) * cell_w + 40 + i * 92
        tiny = crops[(label, c)].resize((BOX // 3, BOX // 3), Image.LANCZOS)
        sheet.paste(tiny, (sx, y + BOX // 2 - BOX // 6))
        if label == SHOTS[0][0]:
            dr.text((sx + 20, y - 30), letter, fill="white", font=font)
    y += BOX + 34
sheet.save(f"{ROOT}/contact-sheet.png")
print("sheet", sheet.size)
