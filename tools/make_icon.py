"""Generates the FreeTune app icon (1024x1024) — Apple Music style gradient
with a white double eighth-note and soft shadows."""
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
img = Image.new("RGB", (SIZE, SIZE))
draw = ImageDraw.Draw(img)

# --- Vertical gradient: bright violet -> deep indigo
top = (124, 58, 237)      # #7C3AED
mid = (88, 45, 190)
bottom = (30, 24, 72)     # #1E1848
for y in range(SIZE):
    t = y / (SIZE - 1)
    if t < 0.55:
        k = t / 0.55
        r = int(top[0] + (mid[0] - top[0]) * k)
        g = int(top[1] + (mid[1] - top[1]) * k)
        b = int(top[2] + (mid[2] - top[2]) * k)
    else:
        k = (t - 0.55) / 0.45
        r = int(mid[0] + (bottom[0] - mid[0]) * k)
        g = int(mid[1] + (bottom[1] - mid[1]) * k)
        b = int(mid[2] + (bottom[2] - mid[2]) * k)
    draw.line([(0, y), (SIZE, y)], fill=(r, g, b))

# --- Soft glow behind the note
glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
gdraw = ImageDraw.Draw(glow)
gdraw.ellipse((180, 140, 844, 804), fill=(255, 255, 255, 38))
glow = glow.filter(ImageFilter.GaussianBlur(120))
img = Image.alpha_composite(img.convert("RGBA"), glow)

# --- Subtle depth ring
ring = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
rdraw = ImageDraw.Draw(ring)
rdraw.ellipse((120, 120, 904, 904), outline=(255, 255, 255, 26), width=3)
img = Image.alpha_composite(img, ring)

# --- Note layer with soft drop shadow
W = (255, 255, 255, 255)
shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sdraw = ImageDraw.Draw(shadow)
def shadow_note(d):
    # shadow shapes offset down-right
    d.ellipse((198, 672, 438, 832), fill=(0, 0, 0, 70))
    d.rectangle((402, 316, 438, 742), fill=(0, 0, 0, 70))
    d.ellipse((578, 612, 818, 772), fill=(0, 0, 0, 70))
    d.rectangle((782, 242, 818, 682), fill=(0, 0, 0, 70))
    d.polygon([(402, 320), (818, 244), (818, 300), (402, 376)], fill=(0, 0, 0, 70))
shadow_note(sdraw)
shadow = shadow.filter(ImageFilter.GaussianBlur(14))
img = Image.alpha_composite(img, shadow)

note = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ndraw = ImageDraw.Draw(note)
# Head 1 + stem 1
ndraw.ellipse((178, 648, 418, 808), fill=W)
ndraw.rectangle((382, 296, 418, 722), fill=W)
# Head 2 + stem 2
ndraw.ellipse((558, 588, 798, 748), fill=W)
ndraw.rectangle((762, 222, 798, 662), fill=W)
# Connecting beam (slanted, thick)
ndraw.polygon([(382, 296), (798, 222), (798, 278), (382, 352)], fill=W)
img = Image.alpha_composite(img, note)

final = img.convert("RGB")
final.save(r"C:\Users\hamda\freetune\FreeTune\Assets.xcassets\AppIcon.appiconset\AppIcon.png", "PNG")
print("Icon written:", final.size)
