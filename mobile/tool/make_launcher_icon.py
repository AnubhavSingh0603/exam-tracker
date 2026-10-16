"""Builds the JobSummit launcher icon ("Summit trail") from one description.

Writes, under android/app/src/main/res:
  drawable/ic_launcher_background.xml   sky, stars and sun (vector)
  drawable/ic_launcher_foreground.xml   mountains, trail and flag (vector)
  drawable/ic_launcher_monochrome.xml   one-colour version for Android 13+ themed icons
  mipmap-anydpi-v26/ic_launcher(.xml|_round.xml)
  mipmap-*/ic_launcher.png, ic_launcher_round.png   for Android 7.x (rendered with Chrome)
and branding/ (repo root): jobsummit-icon.svg, -512.png (store / site), -120.png (Google branding).

Usage (from mobile/):  python tool/make_launcher_icon.py
The PNGs need Chrome or Edge; pass --skip-png to write only the vectors.
"""

from __future__ import annotations

import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
BRANDING = ROOT.parent / "branding"

# The art is drawn on the 108 x 108 adaptive-icon canvas. The scene is lowered
# by LIFT so the flag sits inside the 66-unit safe circle every launcher keeps.
LIFT = 6


def lin(x1, y1, x2, y2, *stops):
    return {"type": "linear", "x1": x1, "y1": y1, "x2": x2, "y2": y2, "stops": stops}


def rad(cx, cy, r, *stops):
    return {"type": "radial", "cx": cx, "cy": cy, "r": r, "stops": stops}


def circle(cx, cy, r):
    return f"M{cx - r:g},{cy}a{r:g},{r:g} 0 1,0 {2 * r:g},0a{r:g},{r:g} 0 1,0 {-2 * r:g},0Z"


def cubic(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u**3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t**3 * d for a, b, c, d in zip(p0, p1, p2, p3))


def trail_dots(lift, r=1.45, every=6.0):
    """The dotted trail up the mountain, as dots spaced evenly along the curve."""
    segments = [
        ((30, 108), (40, 98), (60, 96), (50, 86)),
        ((50, 86), (42, 78), (60, 72), (55, 62)),
        ((55, 62), (51, 55), (56, 50), (54, 42)),
    ]
    points = [cubic(*s, i / 400) for s in segments for i in range(401)]
    out, walked, next_at = [], 0.0, every / 2
    for a, b in zip(points, points[1:]):
        walked += math.dist(a, b)
        if walked >= next_at:
            out.append(circle(round(b[0], 2), round(b[1] + lift, 2), r))
            next_at += every
    return "".join(out)


def background():
    return [
        {"d": "M0,0h108v108h-108z", "fill": lin(0, 0, 0, 108, (0, "#16203A"), (0.55, "#34508C"), (1, "#E8A86A"))},
        {"d": circle(8, 12, 0.9), "fill": "#FFFFFF", "alpha": 0.8},
        {"d": circle(22, 7, 0.7), "fill": "#FFFFFF", "alpha": 0.6},
        {"d": circle(96, 14, 0.8), "fill": "#FFFFFF", "alpha": 0.7},
        {"d": circle(86, 6, 0.6), "fill": "#FFFFFF", "alpha": 0.5},
        {"d": circle(14, 26, 0.6), "fill": "#FFFFFF", "alpha": 0.45},
        {"d": circle(76, 44, 22), "fill": rad(76, 44, 22, (0, "#FFF3CC"), (0.6, "#F6C86E"), (1, "#F6C86E", 0))},
        {"d": circle(76, 44, 9), "fill": "#FFF3CC"},
    ]


def foreground(lift=LIFT):
    def up(d):
        return _shift(d, lift)

    return [
        {"d": up("M0,78L20,58L32,66L50,46L66,60L80,50L108,74L108,120L0,120Z"),
         "fill": lin(0, 46 + lift, 0, 108, (0, "#3A4F80"), (1, "#1F2A47"))},
        {"d": up("M4,120L54,30L110,120Z"), "fill": lin(4, 30 + lift, 104, 108 + lift, (0, "#2A3658"), (1, "#151C30"))},
        {"d": up("M54,30L110,120L68,120L60,76Z"), "fill": lin(54, 30 + lift, 104, 108 + lift, (0, "#8FA9DA"), (1, "#4C6496")),
         "alpha": 0.9},
        {"d": up("M54,30L46,43L50,41L54,46L57,41L62,44Z"), "fill": "#F4F7FC"},
        {"d": trail_dots(lift), "fill": "#F6C86E"},
        {"d": up("M54,42L54,20"), "stroke": "#F4F7FC", "width": 2.2},
        {"d": up("M55,20L71,24.5L55,29Z"), "fill": "#8FD19E"},
        {"d": up("M59,24.6L61.3,26.8L65.5,22.6"), "stroke": "#14301D", "width": 1.5},
        # soft top light over the whole tile
        {"d": "M0,0h108v108h-108z", "fill": lin(0, 0, 0, 108, (0, "#FFFFFF", 0.18), (0.5, "#FFFFFF", 0))},
    ]


def monochrome(lift=LIFT):
    """Android tints this with the wallpaper colour; only alpha matters."""
    return [
        {"d": _shift("M0,78L20,58L32,66L50,46L66,60L80,50L108,74L108,120L0,120Z", lift), "fill": "#FFFFFF", "alpha": 0.35},
        {"d": _shift("M4,120L54,30L110,120Z", lift), "fill": "#FFFFFF", "alpha": 0.75},
        {"d": _shift("M54,30L46,43L50,41L54,46L57,41L62,44Z", lift), "fill": "#FFFFFF"},
        {"d": _shift("M54,42L54,20", lift), "stroke": "#FFFFFF", "width": 2.4},
        {"d": _shift("M55,20L71,24.5L55,29Z", lift), "fill": "#FFFFFF"},
    ]


def _shift(d, dy):
    """Moves an absolute M/L path (as written above) down by dy."""
    out = []
    for part in d.replace("Z", " Z").replace("M", " M ").replace("L", " L ").split():
        if part in ("M", "L", "Z"):
            out.append(part)
            continue
        x, y = part.split(",")
        out.append(f"{x},{float(y) + dy:g}")
    return "".join(p if p in ("M", "L", "Z") else p + " " for p in out).replace(" Z", "Z").strip()


# ---------------------------------------------------------------- Android XML

def _argb(color, opacity=1.0):
    a = round(opacity * 255)
    return f"#{a:02X}{color[1:].upper()}"


def _vector(layers, name):
    body = []
    for el in layers:
        attrs = [f'android:pathData="{el["d"]}"']
        child = ""
        fill = el.get("fill")
        if isinstance(fill, str):
            attrs.append(f'android:fillColor="{_argb(fill)}"')
        elif isinstance(fill, dict):
            items = "".join(
                f'\n                <item android:offset="{s[0]:g}" android:color="{_argb(s[1], s[2] if len(s) > 2 else 1)}"/>'
                for s in fill["stops"]
            )
            if fill["type"] == "linear":
                geo = (f'android:type="linear" android:startX="{fill["x1"]:g}" android:startY="{fill["y1"]:g}" '
                       f'android:endX="{fill["x2"]:g}" android:endY="{fill["y2"]:g}"')
            else:
                geo = (f'android:type="radial" android:centerX="{fill["cx"]:g}" android:centerY="{fill["cy"]:g}" '
                       f'android:gradientRadius="{fill["r"]:g}"')
            child = (f'\n        <aapt:attr name="android:fillColor">\n            <gradient {geo}>{items}'
                     f'\n            </gradient>\n        </aapt:attr>\n    ')
        if "stroke" in el:
            attrs += [f'android:strokeColor="{_argb(el["stroke"])}"', f'android:strokeWidth="{el["width"]:g}"',
                      'android:strokeLineCap="round"', 'android:strokeLineJoin="round"']
        if "alpha" in el:
            attrs.append(f'android:fillAlpha="{el["alpha"]:g}"')
        head = "\n        ".join(attrs)
        body.append(f"    <path\n        {head}>{child}</path>" if child else f"    <path\n        {head}/>")
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f"<!-- {name}. Generated by tool/make_launcher_icon.py: edit that, not this. -->\n"
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    xmlns:aapt="http://schemas.android.com/aapt"\n'
        '    android:width="108dp" android:height="108dp"\n'
        '    android:viewportWidth="108" android:viewportHeight="108">\n'
        + "\n".join(body)
        + "\n</vector>\n"
    )


ADAPTIVE = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
"""

# ---------------------------------------------------------------------- SVG

def svg(layers, size=None, clip=None):
    defs, paths = [], []
    for i, el in enumerate(layers):
        fill = el.get("fill")
        attrs = [f'd="{el["d"]}"']
        if isinstance(fill, dict):
            gid = f"g{i}"
            stops = "".join(
                f'<stop offset="{s[0]:g}" stop-color="{s[1]}" stop-opacity="{s[2] if len(s) > 2 else 1:g}"/>'
                for s in fill["stops"]
            )
            if fill["type"] == "linear":
                defs.append(f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{fill["x1"]:g}" '
                            f'y1="{fill["y1"]:g}" x2="{fill["x2"]:g}" y2="{fill["y2"]:g}">{stops}</linearGradient>')
            else:
                defs.append(f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{fill["cx"]:g}" '
                            f'cy="{fill["cy"]:g}" r="{fill["r"]:g}">{stops}</radialGradient>')
            attrs.append(f'fill="url(#{gid})"')
        elif fill:
            attrs.append(f'fill="{fill}"')
        else:
            attrs.append('fill="none"')
        if "stroke" in el:
            attrs.append(f'stroke="{el["stroke"]}" stroke-width="{el["width"]:g}" stroke-linecap="round" '
                         'stroke-linejoin="round"')
        if "alpha" in el:
            attrs.append(f'fill-opacity="{el["alpha"]:g}"')
        paths.append(f'<path {" ".join(attrs)}/>')
    if clip:
        defs.append(f'<clipPath id="shape"><path d="{clip}"/></clipPath>')
    dims = f' width="{size}" height="{size}"' if size else ""
    group = f'<g clip-path="url(#shape)">{"".join(paths)}</g>' if clip else "".join(paths)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108"{dims}>'
            f'<defs>{"".join(defs)}</defs>{group}</svg>')


def rounded_square(inset, radius):
    a, b = inset, 108 - inset
    r = radius
    return (f"M{a + r},{a}H{b - r}A{r},{r} 0 0 1 {b},{a + r}V{b - r}A{r},{r} 0 0 1 {b - r},{b}"
            f"H{a + r}A{r},{r} 0 0 1 {a},{b - r}V{a + r}A{r},{r} 0 0 1 {a + r},{a}Z")


# --------------------------------------------------------------- rendering

def _browser():
    for p in (r"C:\Program Files\Google\Chrome\Application\chrome.exe",
              r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
              shutil.which("google-chrome"), shutil.which("chromium")):
        if p and Path(p).exists():
            return p
    sys.exit("Chrome or Edge is needed for the PNGs (or pass --skip-png).")


def render(svg_text, px, out, browser, work):
    page = work / f"{out.stem}-{px}.html"
    page.write_text(
        f"<!doctype html><html><body style='margin:0;background:transparent'>"
        f"<div style='width:{px}px;height:{px}px'>{svg_text.replace('<svg ', f'<svg width={px} height={px} ', 1)}"
        f"</div></body></html>",
        encoding="utf-8",
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [browser, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
         "--default-background-color=00000000", f"--window-size={px},{px}", f"--screenshot={out}",
         page.as_uri()],
        check=True, capture_output=True, timeout=60,
    )


def main():
    full = background() + foreground()
    files = {
        RES / "drawable/ic_launcher_background.xml": _vector(background(), "Launcher background"),
        RES / "drawable/ic_launcher_foreground.xml": _vector(foreground(), "Launcher foreground"),
        RES / "drawable/ic_launcher_monochrome.xml": _vector(monochrome(), "Themed (one-colour) launcher icon"),
        RES / "mipmap-anydpi-v26/ic_launcher.xml": ADAPTIVE,
        RES / "mipmap-anydpi-v26/ic_launcher_round.xml": ADAPTIVE,
        BRANDING / "jobsummit-icon.svg": svg(full, 512),
    }
    for path, text in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        print("wrote", path.relative_to(ROOT.parent))
    if "--skip-png" in sys.argv:
        return

    browser = _browser()
    square = svg(full, clip=rounded_square(4, 20))  # Android 7 launchers show the PNG as is
    round_ = svg(full, clip=circle(54, 54, 50))
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for density, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
            render(square, px, RES / f"mipmap-{density}/ic_launcher.png", browser, work)
            render(round_, px, RES / f"mipmap-{density}/ic_launcher_round.png", browser, work)
        render(svg(full), 512, BRANDING / "jobsummit-icon-512.png", browser, work)  # full square: stores mask it
        render(svg(full), 120, BRANDING / "jobsummit-icon-120.png", browser, work)
    print("wrote PNGs (mipmaps, branding/)")


if __name__ == "__main__":
    main()
