#!/usr/bin/env python3
"""Generate a 480x864 row-address diagnostic image and RGB565 data."""

import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WIDTH = 480
HEIGHT = 864
HERE = Path(__file__).resolve().parent
PREVIEW_PATH = HERE / "lcd_row_test_preview.png"
RAW_PATH = HERE / "lcd_row_test_480x864_rgb565.raw"


def load_font(size):
    paths = (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    )
    for path in paths:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


image = Image.new("RGB", (WIDTH, HEIGHT), (8, 32, 64))
draw = ImageDraw.Draw(image)
font = load_font(18)
small_font = load_font(13)

# Ordinary rows use alternating dark bands so vertical continuity is obvious.
for y0 in range(0, 800, 100):
    color = (10, 45, 80) if (y0 // 100) % 2 == 0 else (18, 62, 96)
    draw.rectangle((0, y0, WIDTH - 1, y0 + 99), fill=color)
    draw.text((18, y0 + 34), f"ROWS {y0:03d} - {y0 + 99:03d}",
              font=font, fill=(255, 255, 255))

# A red top marker must remain at the physical top when there is no wrap.
draw.rectangle((0, 0, WIDTH - 1, 7), fill=(255, 0, 0))
draw.text((250, 14), "TOP / Y=0", font=font, fill=(255, 96, 96))

# Mark every 50th logical row.
for y in range(50, 800, 50):
    draw.line((0, y, WIDTH - 1, y), fill=(255, 255, 255), width=1)
    draw.text((390, y + 2), f"Y={y}", font=small_font,
              fill=(255, 255, 255))

# These three colors uniquely identify the likely controller wrap height.
draw.rectangle((0, 800, WIDTH - 1, 839), fill=(0, 255, 0))
draw.text((12, 808), "Y=800..839  GREEN", font=font, fill=(0, 0, 0))

draw.rectangle((0, 840, WIDTH - 1, 853), fill=(255, 0, 255))
draw.text((12, 839), "840..853 MAGENTA", font=small_font,
          fill=(255, 255, 255))

draw.rectangle((0, 854, WIDTH - 1, 863), fill=(255, 255, 0))
draw.text((300, 851), "854..863", font=small_font, fill=(0, 0, 0))

image.save(PREVIEW_PATH)

raw = bytearray(WIDTH * HEIGHT * 2)
for index, (red, green, blue) in enumerate(image.getdata()):
    rgb565 = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
    struct.pack_into("<H", raw, index * 2, rgb565)

RAW_PATH.write_bytes(raw)
print(f"preview: {PREVIEW_PATH}")
print(f"raw:     {RAW_PATH} ({len(raw)} bytes)")
