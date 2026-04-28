"""Generate the Musense app icon as a 1024x1024 PNG (rendered at 4x supersample)."""
from PIL import Image, ImageDraw
import math

OUTPUT_SIZE = 1024
SCALE = 4
SIZE = OUTPUT_SIZE * SCALE
img = Image.new("RGB", (SIZE, SIZE), color=(34, 54, 168))


def gradient_fill():
    """Diagonal gradient at low resolution then resized for speed."""
    top = (34, 54, 168)
    mid = (66, 87, 212)
    bot = (77, 140, 255)
    small_size = 256
    small = Image.new("RGB", (small_size, small_size))
    pixels = small.load()
    for y in range(small_size):
        for x in range(small_size):
            t = (x + y) / (2 * small_size)
            if t < 0.5:
                k = t * 2
                r = int(top[0] + (mid[0] - top[0]) * k)
                g = int(top[1] + (mid[1] - top[1]) * k)
                b = int(top[2] + (mid[2] - top[2]) * k)
            else:
                k = (t - 0.5) * 2
                r = int(mid[0] + (bot[0] - mid[0]) * k)
                g = int(mid[1] + (bot[1] - mid[1]) * k)
                b = int(mid[2] + (bot[2] - mid[2]) * k)
            pixels[x, y] = (r, g, b)
    return small.resize((SIZE, SIZE), Image.LANCZOS)


img = gradient_fill()
draw = ImageDraw.Draw(img, "RGBA")

W = SIZE
H = SIZE

m_stroke = int(W * 0.075)
arc_inner_w = int(W * 0.035)
arc_outer_w = int(W * 0.028)


def line(p1, p2, width):
    draw.line([p1, p2], fill=(255, 255, 255, 255), width=width)


def quad_curve(start, control, end, width, steps=400):
    points = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * start[0] + 2 * (1 - t) * t * control[0] + t ** 2 * end[0]
        y = (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * control[1] + t ** 2 * end[1]
        points.append((x, y))
    draw.line(points, fill=(255, 255, 255, 255), width=width, joint="curve")
    for pt in points[::20]:
        round_cap(pt, width)


def round_cap(pos, width):
    r = width // 2
    draw.ellipse(
        [pos[0] - r, pos[1] - r, pos[0] + r, pos[1] + r],
        fill=(255, 255, 255, 255),
    )


# M shape (matches SwiftUI MusenseLogoMark)
p1 = (W * 0.22, H * 0.72)
p2 = (W * 0.22, H * 0.28)
p3 = (W * 0.50, H * 0.50)
p4 = (W * 0.78, H * 0.28)
p5 = (W * 0.78, H * 0.72)

c1 = (W * 0.33, H * 0.24)
c2 = (W * 0.67, H * 0.24)

line(p1, p2, m_stroke)
quad_curve(p2, c1, p3, m_stroke)
quad_curve(p3, c2, p4, m_stroke)
line(p4, p5, m_stroke)
for cap in (p1, p2, p3, p4, p5):
    round_cap(cap, m_stroke)

# Center dot
dot_r = int(W * 0.045)
cx, cy = W * 0.50, H * 0.68
draw.ellipse(
    [cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r],
    fill=(255, 255, 255, 255),
)


def radio_arc(center, radius, start_deg, end_deg, width, alpha=255):
    bbox = [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius]
    draw.arc(bbox, start=start_deg, end=end_deg, fill=(255, 255, 255, alpha), width=width)


# Inner arcs flanking the dot
inner_radius = int(W * 0.15)
radio_arc((cx, cy), inner_radius, 138, 222, arc_inner_w, alpha=255)
radio_arc((cx, cy), inner_radius, 318, 42, arc_inner_w, alpha=255)

# Outer arcs farther out
outer_radius = int(W * 0.24)
radio_arc((cx, cy), outer_radius, 132, 228, arc_outer_w, alpha=235)
radio_arc((cx, cy), outer_radius, 312, 48, arc_outer_w, alpha=235)

OUT = "/Users/arkanfadhilkautsar/Downloads/CIS 1951_Final Project_Musense/Musense/Musense/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
import os
os.makedirs(os.path.dirname(OUT), exist_ok=True)
final = img.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.LANCZOS)
final.save(OUT, "PNG")
print(f"saved -> {OUT} ({OUTPUT_SIZE}x{OUTPUT_SIZE})")
