"""Generates the Windows and macOS app icons.

Draws the "M↓" Markdown mark on an opaque rounded tile with a gradient, glossy
highlight, extruded edge and drop shadow (3D look), so the icon stays visible
on both light and dark backgrounds. Outputs:

  windows/runner/resources/app_icon.ico             (16-256 px, tile fills the canvas)
  macos/Runner/Assets.xcassets/AppIcon.appiconset/  (16-1024 px PNGs, macOS icon grid:
                                                     824/1024 tile with room for the shadow)

Requires Pillow and NumPy:  python -m pip install pillow numpy
Run from the repo root:      python tool/generate_app_icons.py
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT_ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
MACOS_DIR = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]

S = 2048  # master canvas (supersampled, downscaled at the end)

# Tile geometry per platform, as fractions of the canvas:
# (face box, corner radius, thickness of the extruded bottom edge).
WINDOWS_GEOMETRY = ((0.055, 0.045, 0.945, 0.915), 0.2, 0.035)
MACOS_GEOMETRY = ((100 / 1024, 96 / 1024, 924 / 1024, 896 / 1024), 185 / 1024, 0.026)

# Palette.
TOP_COLOR = (92, 150, 255)  # light blue (top-left)
BOTTOM_COLOR = (58, 52, 214)  # indigo (bottom-right)
EDGE_COLOR = (34, 30, 130)  # extruded side
GLYPH_TOP = (255, 255, 255)
GLYPH_BOTTOM = (220, 228, 255)
GLYPH_SIDE = (30, 32, 120)

# "M↓" glyph polygons, taken from base.svg (its own coordinate space).
M_POLY = [(145, 464), (145, 791), (241, 791), (241, 603), (337, 723),
          (433, 603), (433, 791), (529, 791), (529, 464), (433, 464),
          (337, 584), (241, 464)]
ARROW_POLY = [(697, 464), (697, 632), (601, 632), (745, 791), (889, 632),
              (793, 632), (793, 464)]
GLYPH_BOX = (145, 464, 889, 791)


def rounded_mask(box, radius):
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def gradient(c1, c2, diagonal=True):
    """Full-canvas RGB gradient from c1 (top/top-left) to c2 (bottom/bottom-right)."""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / (S - 1)
    t = (x * 0.35 + y * 0.65) if diagonal else y
    t = t[..., None]
    arr = np.array(c1, np.float32) * (1 - t) + np.array(c2, np.float32) * t
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def glyph_mask(tile, edge, dy=0.0):
    x0, y0, x1, y1 = GLYPH_BOX
    tw = tile[2] - tile[0]
    scale = (tw * 0.74) / (x1 - x0)
    cx = (tile[0] + tile[2]) / 2
    cy = (tile[1] + tile[3]) / 2 - edge * 0.3
    ox = cx - (x0 + x1) / 2 * scale
    oy = cy - (y0 + y1) / 2 * scale + dy

    def tr(poly):
        return [(ox + px * scale, oy + py * scale) for px, py in poly]

    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    d.polygon(tr(M_POLY), fill=255)
    d.polygon(tr(ARROW_POLY), fill=255)
    return mask


def solid(color, alpha_mask):
    layer = Image.new("RGBA", (S, S), color + (0,))
    layer.putalpha(alpha_mask)
    return layer


def scale_alpha(mask, factor):
    return mask.point(lambda v: int(v * factor))


def build_master(geometry):
    box, radius, edge = geometry
    tile = tuple(v * S for v in box)
    radius *= S
    edge *= S
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    x0, y0, x1, y1 = tile

    # Soft drop shadow under the whole tile.
    shadow = rounded_mask((x0, y0 + edge * 1.6, x1, y1 + edge * 1.6), radius)
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.022))
    canvas.alpha_composite(solid((10, 10, 40), scale_alpha(shadow, 0.55)))

    # Extruded side (the tile "thickness").
    side = rounded_mask((x0, y0 + edge, x1, y1 + edge), radius)
    side_grad = gradient((52, 46, 170), EDGE_COLOR, diagonal=False).convert("RGBA")
    side_grad.putalpha(side)
    canvas.alpha_composite(side_grad)

    # Tile face with diagonal gradient.
    face = rounded_mask(tile, radius)
    face_img = gradient(TOP_COLOR, BOTTOM_COLOR).convert("RGBA")
    face_img.putalpha(face)
    canvas.alpha_composite(face_img)

    # Glossy highlight on the upper part of the face.
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).ellipse(
        (x0 - S * 0.25, y0 - S * 0.62, x1 + S * 0.25, y0 + (y1 - y0) * 0.5),
        fill=255)
    gloss = gloss.filter(ImageFilter.GaussianBlur(S * 0.07))
    ramp = Image.linear_gradient("L").resize((S, S)).point(
        lambda v: int(max(0, 255 - v * 1.6)))
    gloss = ImageChops.multiply(ImageChops.multiply(gloss, face), ramp)
    canvas.alpha_composite(solid((255, 255, 255), scale_alpha(gloss, 0.28)))

    # Bevel: bright rim along the top edge, darker rim along the bottom edge.
    inner = rounded_mask((x0 + S * 0.012, y0 + S * 0.012,
                          x1 - S * 0.012, y1 - S * 0.012), radius - S * 0.012)
    rim = ImageChops.subtract(face, inner)
    top_ramp = Image.linear_gradient("L").resize((S, S)).point(
        lambda v: 255 - v)
    bottom_ramp = Image.linear_gradient("L").resize((S, S))
    canvas.alpha_composite(solid(
        (255, 255, 255),
        scale_alpha(ImageChops.multiply(rim, top_ramp), 0.55)))
    canvas.alpha_composite(solid(
        (20, 16, 90),
        scale_alpha(ImageChops.multiply(rim, bottom_ramp), 0.45)))

    # Glyph: soft shadow, extruded side, then the face.
    depth = (x1 - x0) * 0.02
    g_shadow = glyph_mask(tile, edge, dy=depth + S * 0.012).filter(
        ImageFilter.GaussianBlur(S * 0.012))
    canvas.alpha_composite(solid((10, 10, 60), scale_alpha(g_shadow, 0.45)))

    steps = int(depth)
    side_mask = Image.new("L", (S, S), 0)
    for i in range(1, steps + 1, 2):
        side_mask = ImageChops.lighter(side_mask, glyph_mask(tile, edge, dy=i))
    canvas.alpha_composite(solid(GLYPH_SIDE, side_mask))

    g_face = glyph_mask(tile, edge)
    g_img = gradient(GLYPH_TOP, GLYPH_BOTTOM, diagonal=False).convert("RGBA")
    g_img.putalpha(g_face)
    canvas.alpha_composite(g_img)

    return canvas


def write_windows():
    master = build_master(WINDOWS_GEOMETRY)
    frames = [master.resize((n, n), Image.LANCZOS) for n in ICO_SIZES]
    frames[-1].save(OUT_ICO, format="ICO",
                    sizes=[(n, n) for n in ICO_SIZES],
                    append_images=frames[:-1])
    print(f"Wrote {OUT_ICO.relative_to(ROOT)} ({', '.join(map(str, ICO_SIZES))} px)")


def write_macos():
    master = build_master(MACOS_GEOMETRY)
    for n in MACOS_SIZES:
        master.resize((n, n), Image.LANCZOS).save(
            MACOS_DIR / f"app_icon_{n}.png", optimize=True)
    print(f"Wrote {MACOS_DIR.relative_to(ROOT)} "
          f"(app_icon_{{{','.join(map(str, MACOS_SIZES))}}}.png)")


def main():
    write_windows()
    write_macos()


if __name__ == "__main__":
    main()
