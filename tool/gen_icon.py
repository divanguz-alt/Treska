"""Generates the Android launcher icons for Treska.

Run from the project root:  python3 tool/gen_icon.py
Requires Pillow. The design mirrors the app: amber tram front on a near-black
LED-board background.
"""
from pathlib import Path

from PIL import Image, ImageDraw

AMBER = (255, 170, 0, 255)
AMBER_DIM = (196, 126, 0, 255)
BLACK = (8, 8, 8, 255)
PANEL = (13, 13, 13, 255)
BORDER = (46, 46, 46, 255)

S = 1024
BASE = Path(__file__).resolve().parent.parent
RES = BASE / "android/app/src/main/res"


def draw_icon(round_icon: bool) -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if round_icon:
        d.ellipse((0, 0, S - 1, S - 1), fill=PANEL)
    else:
        d.rounded_rectangle((0, 0, S - 1, S - 1), radius=180, fill=PANEL)

    # Inner display frame.
    d.rounded_rectangle(
        (64, 64, S - 65, S - 65),
        radius=140,
        outline=BORDER,
        width=8,
    )

    # Pantograph.
    d.line([(404, 262), (512, 158), (620, 262)], fill=AMBER, width=18, joint="curve")
    d.line([(470, 158), (554, 158)], fill=AMBER, width=18)

    # Tram body.
    d.rounded_rectangle((252, 250, 772, 792), radius=76, fill=AMBER)

    # Roof shade.
    d.rounded_rectangle((252, 250, 772, 316), radius=76, fill=AMBER_DIM)
    d.rectangle((252, 292, 772, 316), fill=AMBER_DIM)

    # Windscreen.
    d.rounded_rectangle((322, 344, 702, 566), radius=34, fill=BLACK)

    # Destination sign.
    d.rounded_rectangle((372, 282, 652, 318), radius=10, fill=BLACK)

    # Headlights.
    for x in (378, 646):
        d.ellipse((x - 36, 628, x + 36, 700), fill=BLACK)

    # Bumper.
    d.rounded_rectangle((314, 728, 710, 752), radius=10, fill=BLACK)

    # Small amber status dot, echoing the live indicator.
    d.ellipse((742, 108, 782, 148), fill=AMBER)

    return img


def main() -> None:
    square = draw_icon(round_icon=False)
    circle = draw_icon(round_icon=True)

    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, px in sizes.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        square.resize((px, px), Image.LANCZOS).save(
            folder / "ic_launcher.png", optimize=True
        )
        circle.resize((px, px), Image.LANCZOS).save(
            folder / "ic_launcher_round.png", optimize=True
        )

    # Play-store / reference asset.
    out = BASE / "docs"
    out.mkdir(exist_ok=True)
    square.resize((512, 512), Image.LANCZOS).save(out / "icon.png", optimize=True)
    print("icons written")


if __name__ == "__main__":
    main()
