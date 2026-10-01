#!/usr/bin/env python3
"""Turns one character picture on a chroma-green background into a looping,
transparent 256 x 256 GIF for public/characters/.

    python3 scripts/character-gif.py art/characters/penguin.png public/characters/penguin.gif --motion waddle

Motions: waddle (side to side), float (drifts up and down), bounce (happy
hop), wobble (sits still, then twitches), orbit (a small moon circles the body,
for planets) and twinkle (little stars sparkle around the body, for moons).
Needs Pillow and numpy.
After adding the GIF, add a line to BUILT_IN in src-tauri/src/characters.rs.
"""
import argparse
import math

import numpy as np
from PIL import Image, ImageDraw

SIZE = 256
WORK = 4  # draw at 4x, then shrink, for smooth edges


def key_out_green(path):
    """Alpha from how green each pixel is; green fringes are removed."""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    greenness = g - np.maximum(r, b)
    alpha = np.clip((160.0 - greenness) / 120.0, 0.0, 1.0)
    g = np.minimum(g, np.maximum(r, b))  # despill
    out = np.dstack([r, g, b, alpha * 255.0]).astype(np.uint8)
    image = Image.fromarray(out, "RGBA")
    return image.crop(image.getchannel("A").point(lambda a: 255 if a > 12 else 0).getbbox())


def motion(kind, t):
    """(angle in degrees, x shift, y shift, x scale, y scale) at phase t in [0, 1)."""
    s = math.sin(2 * math.pi * t)
    if kind == "waddle":
        return 5.0 * s, 0.0, -5.0 * abs(s), 1.0, 1.0
    if kind == "float":
        return 2.5 * math.cos(2 * math.pi * t), 0.0, -9.0 * s, 1.0, 1.0
    if kind == "bounce":
        hop = max(0.0, s)
        squash = 0.035 * math.cos(4 * math.pi * t) if s < 0 else 0.0
        return 0.0, 0.0, -10.0 * hop, 1.0 + squash, 1.0 - squash
    if kind == "wobble":
        # Still most of the time; a small, slightly pathetic twitch.
        if 0.55 <= t < 0.8:
            u = (t - 0.55) / 0.25
            return 4.0 * math.sin(6 * math.pi * u) * (1 - u), 0.0, -2.0 * math.sin(math.pi * u), 1.0, 1.0
        return 0.0, 0.0, 0.0, 1.0, 1.0
    raise SystemExit(f"unknown motion {kind}")


FRAMES = {"waddle": (24, 60), "float": (30, 70), "bounce": (20, 60), "wobble": (30, 80), "orbit": (60, 50), "twinkle": (40, 60)}
OUTLINE = (28, 26, 30, 255)
CREAM = (243, 236, 217, 255)
STAR = (255, 233, 168, 255)
ORBIT_LINE = (205, 200, 188, 255)


def ellipse_point(cx, cy, rx, ry, tilt, theta):
    x, y = rx * math.cos(theta), ry * math.sin(theta)
    return cx + x * math.cos(tilt) - y * math.sin(tilt), cy + x * math.sin(tilt) + y * math.cos(tilt)


def draw_arc(draw, cx, cy, rx, ry, tilt, start, end, width):
    points = [ellipse_point(cx, cy, rx, ry, tilt, start + (end - start) * i / 80) for i in range(81)]
    draw.line(points, fill=ORBIT_LINE, width=width, joint="curve")


def draw_moon(draw, x, y, r):
    w = max(2, round(r * 0.28))
    draw.ellipse((x - r, y - r, x + r, y + r), fill=CREAM, outline=OUTLINE, width=w)
    d = r * 0.28
    draw.ellipse((x - r * 0.35 - d, y - r * 0.2 - d, x - r * 0.35 + d, y - r * 0.2 + d), fill=OUTLINE)


def draw_star(draw, x, y, r):
    """A four-point sparkle with the same dark outline as the characters."""
    k = 0.32
    points = []
    for i in range(8):
        a = -math.pi / 2 + i * math.pi / 4
        radius = r if i % 2 == 0 else r * k
        points.append((x + radius * math.cos(a), y + radius * math.sin(a)))
    draw.polygon(points, fill=STAR, outline=OUTLINE, width=max(2, round(r * 0.16)))


def render_space(body, kind):
    count, duration = FRAMES[kind]
    big = SIZE * WORK
    fill = 0.62 if kind == "orbit" else 0.70
    scale = min(big * fill / body.height, big * fill / body.width)
    base = body.resize((round(body.width * scale), round(body.height * scale)), Image.LANCZOS)
    cx, cy = big / 2, big / 2 + big * 0.02
    frames = []
    for index in range(count):
        t = index / count
        canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        draw = ImageDraw.Draw(canvas)
        bob = -4.0 * WORK * math.sin(2 * math.pi * t)
        if kind == "orbit":
            rx, ry, tilt = big * 0.45, big * 0.12, math.radians(-14)
            theta = 2 * math.pi * t + math.pi / 2
            moon_x, moon_y = ellipse_point(cx, cy + bob, rx, ry, tilt, theta)
            behind = math.sin(theta) < 0
            draw_arc(draw, cx, cy + bob, rx, ry, tilt, math.pi, 2 * math.pi, 2 * WORK)
            if behind:
                draw_moon(draw, moon_x, moon_y, big * 0.07)
            canvas.alpha_composite(base, (round(cx - base.width / 2), round(cy + bob - base.height / 2)))
            draw = ImageDraw.Draw(canvas)
            draw_arc(draw, cx, cy + bob, rx, ry, tilt, 0, math.pi, 2 * WORK)
            if not behind:
                draw_moon(draw, moon_x, moon_y, big * 0.07)
        else:
            angle = 4.0 * math.sin(2 * math.pi * t)
            turned = base.rotate(angle, resample=Image.BICUBIC, expand=True)
            canvas.alpha_composite(turned, (round(cx - turned.width / 2), round(cy + bob - turned.height / 2)))
            draw = ImageDraw.Draw(canvas)
            for (sx, sy, sr, phase) in ((0.80, 0.22, 0.075, 0.0), (0.86, 0.62, 0.055, 0.33), (0.66, 0.84, 0.045, 0.66)):
                pulse = 0.5 + 0.5 * math.sin(2 * math.pi * (t + phase))
                draw_star(draw, big * sx, big * sy + bob * 0.5, big * sr * (0.55 + 0.45 * pulse))
        frames.append(canvas.resize((SIZE, SIZE), Image.LANCZOS))
    return frames, duration


def render(character, kind):
    count, duration = FRAMES[kind]
    big = SIZE * WORK
    # The character fills about 84% of the height, standing on the bottom margin.
    target_h = int(big * 0.84)
    scale = min(target_h / character.height, big * 0.9 / character.width)
    base = character.resize((round(character.width * scale), round(character.height * scale)), Image.LANCZOS)
    frames = []
    for index in range(count):
        angle, dx, dy, sx, sy = motion(kind, index / count)
        body = base.resize((round(base.width * sx), round(base.height * sy)), Image.LANCZOS)
        # Rotate around the feet so it rocks instead of spinning.
        pad = Image.new("RGBA", (body.width * 2, body.height * 2), (0, 0, 0, 0))
        pad.alpha_composite(body, (body.width // 2, 0))
        pad = pad.rotate(angle, resample=Image.BICUBIC, center=(body.width, body.height))
        canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        x = (big - pad.width) // 2 + round(dx * WORK)
        y = big - int(big * 0.05) - body.height + round(dy * WORK)
        canvas.alpha_composite(pad, (x, y))
        frames.append(canvas.resize((SIZE, SIZE), Image.LANCZOS))
    return frames, duration


def save_gif(frames, duration, path):
    """GIF has on/off transparency: half-transparent edge pixels become solid."""
    palette_source = Image.new("RGB", (SIZE, SIZE * len(frames)))
    for index, frame in enumerate(frames):
        palette_source.paste(frame.convert("RGB"), (0, SIZE * index))
    palette = palette_source.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    out = []
    for frame in frames:
        indexed = frame.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE)
        mask = frame.getchannel("A").point(lambda a: 255 if a < 128 else 0)
        indexed.paste(255, mask=mask)
        out.append(indexed)
    out[0].save(path, save_all=True, append_images=out[1:], duration=duration, loop=0,
                transparency=255, disposal=2, optimize=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source")
    parser.add_argument("output")
    parser.add_argument("--motion", choices=sorted(FRAMES), required=True)
    args = parser.parse_args()
    body = key_out_green(args.source)
    if args.motion in ("orbit", "twinkle"):
        frames, duration = render_space(body, args.motion)
    else:
        frames, duration = render(body, args.motion)
    save_gif(frames, duration, args.output)
    print(f"{args.output}: {len(frames)} frames, {duration} ms each")


if __name__ == "__main__":
    main()
