#!/usr/bin/env python3
"""
Post-process a generated fish PNG into a macOS menu bar template image set.

The generator (OpenAI gpt-image-1) cannot output real transparency — it
paints the checkerboard pattern into the RGB and sets alpha=255 everywhere.
This script thresholds by luminance: dark pixels become pure black with
alpha=255 (the silhouette), everything else becomes alpha=0 (transparent).

Outputs MenuBarIcon.png/@2x/@3x sized for an 18pt menu bar status item.
"""
import sys
from pathlib import Path
from PIL import Image, ImageFilter

SRC = Path(sys.argv[1])
OUT_DIR = Path(sys.argv[2])
BASE_NAME = "MenuBarIcon"

# Logical 18pt menu bar size; ship @1x/@2x/@3x for retina.
SIZES = {
    "":      18,
    "@2x":   36,
    "@3x":   54,
}

# Threshold: any pixel darker than this becomes solid black.
# The gen image has black fish (luminance ~0) on a light checkerboard
# (luminance >180). Threshold ~100 leaves a comfortable margin.
LUMA_THRESHOLD = 100

def main():
    img = Image.open(SRC).convert("RGBA")
    print(f"input: {SRC.name} {img.size}")

    # Build a luminance map from RGB only (ignore current alpha which is bogus)
    rgb = img.convert("RGB")
    luma = rgb.convert("L")

    # Binary mask: 255 where dark, 0 elsewhere
    mask = luma.point(lambda p: 255 if p < LUMA_THRESHOLD else 0, mode="L")

    # Build the template image: solid black RGB with alpha = mask
    black = Image.new("RGB", img.size, (0, 0, 0))
    template = Image.new("RGBA", img.size)
    template.paste(black, mask=mask)
    template.putalpha(mask)

    # Trim transparent borders, then re-pad so we have ~8% breathing room
    bbox = template.getbbox()
    if bbox is None:
        raise SystemExit("no opaque pixels in mask — threshold too aggressive?")
    cropped = template.crop(bbox)
    w, h = cropped.size
    side = max(w, h)
    pad = int(side * 0.10)  # 10% padding on the longer dimension
    canvas_side = side + pad * 2
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.paste(cropped, ((canvas_side - w) // 2, (canvas_side - h) // 2), cropped)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for suffix, px in SIZES.items():
        out_path = OUT_DIR / f"{BASE_NAME}{suffix}.png"
        # High-quality downscale with LANCZOS
        scaled = canvas.resize((px, px), Image.LANCZOS)
        # Re-binarize alpha after downscale to keep crisp template edges
        # (preserves macOS template semantics: only fully opaque or fully transparent)
        # Note: keep some anti-alias for visual smoothness; macOS template
        # tolerates partial alpha. Use a midpoint threshold.
        r, g, b, a = scaled.split()
        a = a.point(lambda p: 255 if p >= 128 else 0, mode="L")
        scaled = Image.merge("RGBA", (r, g, b, a))
        # Ensure RGB is pure black wherever there's any alpha
        scaled_data = scaled.load()
        for y in range(scaled.height):
            for x in range(scaled.width):
                _r, _g, _b, _a = scaled_data[x, y]
                if _a > 0:
                    scaled_data[x, y] = (0, 0, 0, 255)
                else:
                    scaled_data[x, y] = (0, 0, 0, 0)
        scaled.save(out_path)
        print(f"  → {out_path.name}  {px}×{px}")

    print("done")

if __name__ == "__main__":
    main()
