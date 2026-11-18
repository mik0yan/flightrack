#!/usr/bin/env python3
"""Render the original vector app mark. Requires Pillow only for regeneration."""
from pathlib import Path
from PIL import Image, ImageDraw

scale = 3
canvas = Image.new("RGB", (1024 * scale, 1024 * scale), (6, 11, 20))
draw = ImageDraw.Draw(canvas)

def line(points, color, width):
    draw.line([(x * scale, y * scale) for x, y in points], fill=color, width=width * scale)

for radius in (210, 340, 465):
    draw.ellipse(tuple(v * scale for v in (512-radius, 512-radius, 512+radius, 512+radius)),
                 outline=(17, 46, 53), width=8 * scale)
line([(96, 512), (928, 512)], (17, 46, 53), 5)
line([(512, 96), (512, 928)], (17, 46, 53), 5)
line([(512, 512), (795, 226)], (34, 112, 125), 12)
points = [(512,219),(557,276),(557,462),(787,598),(787,672),(554,593),
          (548,739),(640,797),(640,850),(512,816),(384,850),(384,797),
          (476,739),(470,593),(237,672),(237,598),(467,462),(467,276)]
draw.polygon([(x * scale, y * scale) for x, y in points], fill=(61, 217, 230))
output = Path(__file__).resolve().parents[1] / "FlightTrack/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
canvas.resize((1024, 1024), Image.Resampling.LANCZOS).save(output)
print("Generated opaque 1024×1024 AppIcon.png")
