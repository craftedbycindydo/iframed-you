import json, math, os, shutil, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C = 1024

INK = "#352e28"
INK_DARK = "#241f1c"
CREAM = "#faf7f0"
LINEN = "#eee8dd"
PEACH = "#e7b487"
PEACH_DEEP = "#d99a66"
TERRA = "#9a513b"
TERRA_DEEP = "#7d3f2e"
OLIVE = "#8d9e7e"
FACE = "#3c3531"
EYE = "#fff0cc"
PLUM_DARK = "#2a2029"


def hex_to_srgb(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def svg(body, w=C, h=C):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{body}</svg>'


def rrect(x, y, w, h, r, fill, rot=0, cx=None, cy=None):
    t = ""
    if rot:
        cx = x + w / 2 if cx is None else cx
        cy = y + h / 2 if cy is None else cy
        t = f' transform="rotate({rot} {cx} {cy})"'
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" ry="{r}" fill="{fill}"{t}/>'


def circle(cx, cy, r, fill):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"/>'


def ring_path(x, y, w, h, r, inset, ri):
    outer = rrect_path(x, y, w, h, r)
    inner = rrect_path(x + inset, y + inset, w - 2 * inset, h - 2 * inset, ri, ccw=True)
    return f'<path d="{outer} {inner}" fill-rule="evenodd"/>'


def rrect_path(x, y, w, h, r, ccw=False):
    k = 0.5523 * r
    pts = []
    if not ccw:
        return (f"M{x + r},{y} L{x + w - r},{y} C{x + w - r + k},{y} {x + w},{y + r - k} {x + w},{y + r} "
                f"L{x + w},{y + h - r} C{x + w},{y + h - r + k} {x + w - r + k},{y + h} {x + w - r},{y + h} "
                f"L{x + r},{y + h} C{x + r - k},{y + h} {x},{y + h - r + k} {x},{y + h - r} "
                f"L{x},{y + r} C{x},{y + r - k} {x + r - k},{y} {x + r},{y} Z")
    return (f"M{x + r},{y} C{x + r - k},{y} {x},{y + r - k} {x},{y + r} "
            f"L{x},{y + h - r} C{x},{y + h - r + k} {x + r - k},{y + h} {x + r},{y + h} "
            f"L{x + w - r},{y + h} C{x + w - r + k},{y + h} {x + w},{y + h - r + k} {x + w},{y + h - r} "
            f"L{x + w},{y + r} C{x + w},{y + r - k} {x + w - r + k},{y} {x + w - r},{y} Z")


def glow_png(path, cx, cy, r0, r1, color, alpha=1.0):
    im = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rgb = tuple(int(color.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    steps = 60
    for i in range(steps, 0, -1):
        rr = r0 + (r1 - r0) * i / steps
        a = int(255 * alpha * (1 - i / steps) ** 1.6)
        layer = Image.new("RGBA", (C, C), (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=rgb + (a,))
        im = Image.alpha_composite(im, layer)
    im = im.filter(ImageFilter.GaussianBlur(28))
    im.save(path)


def layer(name, image, glass=True, fill=None, dark_fill=None, hidden_in=(), opacity=None, blend=None):
    L = {"name": name, "image-name": image, "glass": glass}
    if fill:
        L["fill"] = {"solid": hex_to_srgb(fill)}
    spec = []
    if dark_fill:
        spec.append({"appearance": "dark", "value": {"solid": hex_to_srgb(dark_fill)}})
    if spec:
        L["fill-specializations"] = spec
    if hidden_in:
        L["hidden-specializations"] = [{"appearance": a, "value": True} for a in hidden_in]
    if opacity is not None:
        L["opacity"] = opacity
    if blend:
        L["blend-mode"] = blend
    return L


def group(layers, translucency=0.5, shadow=0.5, specular=True):
    return {"layers": layers,
            "shadow": {"kind": "neutral", "opacity": shadow},
            "specular": specular,
            "translucency": {"enabled": translucency > 0, "value": translucency}}


def icon_json(fill, groups, gradient=True):
    return {"fill": {"automatic-gradient" if gradient else "solid": hex_to_srgb(fill)},
            "groups": groups,
            "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}}


def write(dest, name, assets, doc):
    bundle = os.path.join(dest, name, "AppIcon.icon")
    layers = os.path.join(dest, name, "layers")
    for d in (bundle, layers):
        shutil.rmtree(d, ignore_errors=True)
    os.makedirs(os.path.join(bundle, "Assets"))
    os.makedirs(layers)
    for fname, content in assets.items():
        p = os.path.join(bundle, "Assets", fname)
        if isinstance(content, str):
            open(p, "w").write(content)
        else:
            content(p)
        shutil.copy(p, os.path.join(layers, fname))
    json.dump(doc, open(os.path.join(bundle, "icon.json"), "w"), indent=2)


def concept_panes():
    s = 500
    r = 118
    assets = {
        "1-pane-back.svg": svg(rrect(160, 160, s, s, r, TERRA)),
        "2-pane-mid.svg": svg(rrect(262, 262, s, s, r, PEACH)),
        "3-pane-front.svg": svg(rrect(364, 364, s, s, r, CREAM)),
    }
    doc = icon_json(INK, [group([
        layer("pane-back", "1-pane-back.svg"),
        layer("pane-mid", "2-pane-mid.svg"),
        layer("pane-front", "3-pane-front.svg"),
    ], translucency=0.6)])
    return assets, doc


def concept_momo():
    rot = -5
    shell = rrect(150, 262, 724, 530, 190, CREAM, rot)
    face = rrect(196, 304, 632, 446, 160, FACE, rot)
    eyes = (rrect(360, 430, 76, 170, 38, EYE, rot, 512, 527) +
            rrect(592, 462, 72, 112, 36, EYE, rot + 9, 512, 527))
    ears = (rrect(96, 460, 70, 130, 35, OLIVE, rot, 512, 527) +
            rrect(858, 420, 70, 130, 35, OLIVE, rot, 512, 527))
    assets = {
        "1-ears.svg": svg(ears),
        "2-shell.svg": svg(shell),
        "3-face.svg": svg(face),
        "4-eyes.svg": svg(eyes),
    }
    doc = icon_json(TERRA, [
        group([layer("ears", "1-ears.svg"), layer("shell", "2-shell.svg")], translucency=0.3),
        group([layer("face", "3-face.svg", glass=False), layer("eyes", "4-eyes.svg", glass=True)], translucency=0.0, shadow=0.3),
    ])
    return assets, doc


def concept_window():
    assets = {
        "1-glow.png": lambda p: glow_png(p, 512, 540, 120, 520, PEACH, 0.95),
        "2-pane.svg": svg(rrect(252, 212, 520, 600, 120, CREAM)),
    }
    doc = icon_json(INK_DARK, [
        group([layer("glow", "1-glow.png", glass=False)], translucency=0.0, shadow=0.0, specular=False),
        group([layer("pane", "2-pane.svg")], translucency=0.55),
    ])
    return assets, doc


def concept_figures():
    pane = rrect(212, 172, 600, 680, 140, CREAM)
    back = circle(620, 470, 118, TERRA) + rrect(470, 560, 300, 400, 150, TERRA)
    front = circle(412, 530, 128, PEACH) + rrect(248, 640, 328, 400, 164, PEACH)
    assets = {
        "1-pane.svg": svg(pane),
        "2-figure-back.svg": svg(back),
        "3-figure-front.svg": svg(front),
    }
    doc = icon_json(TERRA_DEEP, [
        group([layer("pane", "1-pane.svg")], translucency=0.4),
        group([layer("figure-back", "2-figure-back.svg"), layer("figure-front", "3-figure-front.svg")], translucency=0.5),
    ])
    return assets, doc


def concept_ring():
    ring = f'<g fill="{CREAM}">{ring_path(172, 172, 680, 680, 170, 124, 92)}</g>'
    assets = {
        "1-dot.svg": svg(circle(512, 512, 150, PEACH)),
        "2-ring.svg": svg(ring),
    }
    doc = icon_json(TERRA, [
        group([layer("dot", "1-dot.svg")], translucency=0.3),
        group([layer("ring", "2-ring.svg")], translucency=0.6),
    ])
    return assets, doc


def concept_tile():
    pane = rrect(212, 212, 600, 600, 140, CREAM)
    light = (f'<clipPath id="c"><rect x="212" y="212" width="600" height="600" rx="140"/></clipPath>'
             f'<polygon clip-path="url(#c)" points="212,212 812,212 812,430 212,820" fill="{PEACH}"/>')
    assets = {"1-pane.svg": svg(pane), "2-light.svg": svg(light)}
    doc = icon_json(TERRA, [group([layer("pane", "1-pane.svg"), layer("light", "2-light.svg")], translucency=0.5)])
    return assets, doc


def concept_arch():
    arch = f'<path d="M232,900 L232,472 A280,280 0 0 1 792,472 L792,900 Q792,940 752,940 L272,940 Q232,940 232,900 Z" fill="{CREAM}"/>'
    glow = f'<path d="M292,940 L292,700 A220,220 0 0 1 732,700 L732,940 Z" fill="{PEACH}"/>'
    assets = {"1-arch.svg": svg(arch), "2-glow.svg": svg(glow)}
    doc = icon_json(INK_DARK, [group([layer("arch", "1-arch.svg"), layer("glow", "2-glow.svg")], translucency=0.55)])
    return assets, doc


def ring_svg(x, y, w, h, r, inset, ri, fill):
    return f'<g fill="{fill}">{ring_path(x, y, w, h, r, inset, ri)}</g>'


def figure(cx, head_y, head_r, shoulder_w, bottom, fill):
    top = head_y + head_r * 0.9
    return (circle(cx, head_y, head_r, fill) +
            rrect(cx - shoulder_w / 2, top, shoulder_w, bottom - top, shoulder_w / 2, fill))


def concept_momo_peek():
    rot = -5
    cx, cy = 512, 640
    frame = ring_svg(152, 152, 720, 720, 186, 96, 100, CREAM)
    shell = rrect(302, 396, 420, 460, 160, CREAM, rot, cx, cy)
    face = rrect(328, 422, 368, 420, 136, FACE, rot, cx, cy)
    eyes = (rrect(402, 496, 68, 158, 34, EYE, rot, cx, cy) +
            rrect(588, 522, 64, 104, 32, EYE, rot + 10, cx, cy))
    ears = (rrect(256, 560, 54, 116, 27, OLIVE, rot, cx, cy) +
            rrect(714, 540, 54, 116, 27, OLIVE, rot, cx, cy))
    assets = {"1-frame.svg": svg(frame), "2-eyes.svg": svg(eyes), "3-face.svg": svg(face),
              "4-shell.svg": svg(shell), "5-ears.svg": svg(ears)}
    doc = icon_json(TERRA, [
        group([layer("frame", "1-frame.svg")], translucency=0.35),
        group([layer("eyes", "2-eyes.svg"), layer("face", "3-face.svg"),
               layer("shell", "4-shell.svg"), layer("ears", "5-ears.svg")], translucency=0.1, shadow=0.45),
    ])
    return assets, doc


def concept_hung():
    nail = circle(512, 112, 46, PEACH)
    wire = f'<polygon points="512,112 276,432 748,432" fill="{CREAM}"/>'
    frame = rrect(212, 376, 600, 556, 104, CREAM)
    photo = rrect(272, 436, 480, 436, 52, PEACH)
    people = (figure(462, 582, 80, 200, 872, TERRA_DEEP) + figure(618, 668, 60, 146, 872, OLIVE))
    assets = {"1-nail.svg": svg(nail), "2-people.svg": svg(people), "3-photo.svg": svg(photo),
              "4-frame.svg": svg(frame), "5-wire.svg": svg(wire)}
    doc = icon_json("#3b2a22", [
        group([layer("nail", "1-nail.svg")], translucency=0.2),
        group([layer("people", "2-people.svg"), layer("photo", "3-photo.svg")], translucency=0.4, shadow=0.3),
        group([layer("frame", "4-frame.svg")], translucency=0.3),
        group([layer("wire", "5-wire.svg")], translucency=0.9, shadow=0.15),
    ])
    return assets, doc


def concept_door():
    body = ring_svg(180, 232, 520, 560, 110, 86, 48, CREAM)
    light = rrect(266, 318, 348, 388, 48, PEACH)
    leaf = f'<polygon points="716,248 884,164 884,860 716,776" fill="{CREAM}" stroke="{CREAM}" stroke-width="34" stroke-linejoin="round"/>'
    spill = f'<polygon points="700,262 1100,20 1100,1004 700,762" fill="{PEACH}"/>'
    assets = {"1-leaf.svg": svg(leaf), "2-body.svg": svg(body), "3-light.svg": svg(light), "4-spill.svg": svg(spill),
              "5-glow.png": lambda p: glow_png(p, 820, 512, 120, 560, PEACH, 0.9)}
    doc = icon_json(INK_DARK, [
        group([layer("leaf", "1-leaf.svg")], translucency=0.75, shadow=0.4),
        group([layer("body", "2-body.svg")], translucency=0.3),
        group([layer("light", "3-light.svg"), layer("spill", "4-spill.svg")], translucency=0.8, shadow=0.0, specular=False),
        group([layer("glow", "5-glow.png", glass=False)], translucency=0.0, shadow=0.0, specular=False),
    ])
    return assets, doc


def concept_family():
    frame = ring_svg(152, 152, 720, 720, 184, 104, 96, CREAM)
    bottom = 768
    people = (figure(560, 420, 96, 232, bottom, TERRA) +
              figure(392, 470, 82, 196, bottom, PEACH) +
              figure(640, 560, 60, 144, bottom, OLIVE))
    assets = {"1-frame.svg": svg(frame), "2-people.svg": svg(people)}
    doc = icon_json(TERRA_DEEP, [
        group([layer("frame", "1-frame.svg")], translucency=0.4),
        group([layer("people", "2-people.svg")], translucency=0.5, shadow=0.4),
    ])
    return assets, doc


def strand(x1, y1, x2, y2, w, color):
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{w}" stroke-linecap="round"/>'


def hung_doc(fill, nail, people, photo, frame, wire, mat=None, wire_t=0.9, photo_t=0.4):
    frame_layers = [layer("frame", "4-frame.svg")]
    assets = {"1-nail.svg": nail, "2-people.svg": people, "3-photo.svg": photo, "4-frame.svg": frame, "5-wire.svg": wire}
    if mat:
        assets["4b-mat.svg"] = mat
        frame_layers = [layer("mat", "4b-mat.svg"), layer("frame", "4-frame.svg")]
    doc = icon_json(fill, [
        group([layer("nail", "1-nail.svg")], translucency=0.2),
        group([layer("people", "2-people.svg"), layer("photo", "3-photo.svg")], translucency=photo_t, shadow=0.3),
        group(frame_layers, translucency=0.3),
        group([layer("wire", "5-wire.svg")], translucency=wire_t, shadow=0.15),
    ])
    return assets, doc


def concept_hung_a():
    nail = svg(circle(512, 108, 48, PEACH))
    wire = svg(f'<polygon points="512,108 262,420 762,420" fill="{CREAM}"/>')
    frame = svg(rrect(204, 366, 616, 580, 108, CREAM))
    photo = svg(rrect(266, 428, 492, 456, 54, PEACH))
    people = svg(figure(452, 584, 84, 210, 884, TERRA_DEEP) + figure(622, 676, 62, 152, 884, OLIVE))
    return hung_doc("#3b2a22", nail, people, photo, frame, wire)


def concept_hung_b():
    nail = svg(circle(512, 104, 44, INK))
    wire = svg(strand(512, 104, 290, 404, 40, INK) + strand(512, 104, 734, 404, 40, INK))
    frame = svg(rrect(196, 362, 632, 600, 60, TERRA_DEEP))
    mat = svg(rrect(252, 418, 520, 488, 28, CREAM))
    photo = svg(rrect(316, 482, 392, 360, 20, PEACH))
    people = svg(figure(430, 600, 66, 162, 842, TERRA) + figure(560, 572, 76, 186, 842, TERRA_DEEP) + figure(640, 690, 46, 110, 842, OLIVE))
    return hung_doc(LINEN, nail, people, photo, frame, wire, mat=mat, wire_t=0.1, photo_t=0.35)


def concept_hung_c():
    rot = -6
    cx, cy = 512, 660
    nail = svg(circle(512, 104, 46, PEACH))
    wire = svg(strand(512, 104, 262, 402, 42, CREAM) + strand(512, 104, 742, 446, 42, CREAM))
    frame = svg(rrect(204, 372, 616, 580, 112, CREAM, rot, cx, cy))
    photo = svg(rrect(268, 436, 488, 452, 56, PEACH, rot, cx, cy))
    people = svg(f'<g transform="rotate({rot} {cx} {cy})">' + figure(452, 590, 86, 214, 888, TERRA_DEEP) + figure(626, 684, 64, 156, 888, OLIVE) + '</g>')
    return hung_doc(INK_DARK, nail, people, photo, frame, wire, wire_t=0.5)


CONCEPTS = {
    "hung-a": concept_hung_a,
    "hung-b": concept_hung_b,
    "hung-c": concept_hung_c,
    "momo-peek": concept_momo_peek,
    "hung": concept_hung,
    "door": concept_door,
    "family": concept_family,
    "panes": concept_panes,
    "momo": concept_momo,
    "window": concept_window,
    "figures": concept_figures,
    "ring": concept_ring,
    "tile": concept_tile,
    "arch": concept_arch,
}

if __name__ == "__main__":
    dest = os.path.join(ROOT, sys.argv[1] if len(sys.argv) > 1 else "explore")
    names = sys.argv[2:] or list(CONCEPTS)
    for n in names:
        assets, doc = CONCEPTS[n]()
        write(dest, n, assets, doc)
        print("wrote", n)
