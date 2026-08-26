#!/usr/bin/env python3
"""런처 아이콘을 코드로 그려 android/app/src/main/res 에 써 넣습니다.

`flutter create` 가 넣어 주는 아이콘은 어느 Flutter 프로젝트나 똑같아서, 같은
방식으로 만든 다른 앱과 홈 화면에서 구분되지 않습니다. 사진을 다루는 앱이라는
것이 아이콘만 보고도 보이도록 사진 카드(산과 해)를 그립니다.

**그림을 파일이 아니라 코드로 두는 이유.** 이 저장소에는 android/ 폴더가 없고
빌드할 때마다 `flutter create` 로 새로 만듭니다. 그래서 아이콘도 매번 다시
넣어야 하는데, PNG 를 커밋해 두면 무엇이 어떻게 바뀌었는지 diff 로 볼 수 없고
크기별로 열 몇 개를 손으로 맞춰야 합니다. 코드로 그리면 색이나 모양을 한 줄
고쳐 모든 밀도를 다시 뽑을 수 있습니다.

표준 라이브러리만 씁니다. Pillow 나 ImageMagick 을 CI 에 더 얹지 않으려고
PNG 인코더와 래스터라이저를 직접 두었습니다. 도형마다 부호 있는 거리(SDF)로
픽셀 덮임을 계산하므로 확대해도 계단이 지지 않습니다.

만드는 것:
  mipmap-<밀도>/ic_launcher.png             옛 방식(안드로이드 7 이하) 아이콘
  mipmap-<밀도>/ic_launcher_foreground.png  적응형 아이콘 앞면
  mipmap-<밀도>/ic_launcher_monochrome.png  테마 아이콘(안드로이드 13+)
  mipmap-anydpi-v26/ic_launcher.xml         적응형 아이콘 정의
  values/ic_launcher_background.xml         적응형 아이콘 뒷면 색
"""

import math
import os
import struct
import sys
import zlib

RES = 'android/app/src/main/res'

# 밀도별 배율. 적응형 앞면은 108dp, 옛 아이콘은 48dp 가 기준입니다.
DENSITIES = {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
}

# --- 색 -------------------------------------------------------------------
# 앱 테마의 시드(0xFF4C6EF5) 계열로 맞춥니다.
BG_TOP = (0x5B, 0x7C, 0xFA)
BG_BOTTOM = (0x33, 0x4B, 0xD6)
CARD = (0xFF, 0xFF, 0xFF)
SKY = (0xE9, 0xEF, 0xFF)
MOUNTAIN = (0x2B, 0x3C, 0x9E)
MOUNTAIN_FAR = (0x5B, 0x7C, 0xFA)
SUN = (0xFF, 0xB0, 0x2E)

# --- 그림 (72 단위 정사각형 안에서 정의) ----------------------------------
# 적응형 아이콘의 안전 영역은 108dp 캔버스 한가운데 지름 72dp 원입니다. 카드가
# 그 원 밖으로 나가면 기기 모양(원/스퀘어클)에 따라 모서리가 잘립니다.
# 52x40 이면 반대각선이 32.8 로 반지름 36 안에 여유 있게 들어갑니다.
ART = 72.0
CARD_BOX = (36.0, 36.0, 26.0, 20.0, 5.5)   # cx, cy, 반너비, 반높이, 모서리
PHOTO_BOX = (36.0, 36.0, 22.0, 16.0, 2.5)
SUN_C = (47.0, 27.5, 4.5)                   # cx, cy, r
FLOOR = 52.0                                # 사진 영역 아래쪽
PEAK_NEAR = [(16.0, FLOOR), (30.0, 30.0), (44.0, FLOOR)]
PEAK_FAR = [(36.0, FLOOR), (47.0, 37.5), (58.0, FLOOR)]


# --- 도형의 부호 있는 거리 -------------------------------------------------

def sd_round_rect(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def sd_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sd_triangle(px, py, tri):
    worst = -1e9
    for i in range(3):
        ax, ay = tri[i]
        bx, by = tri[(i + 1) % 3]
        ex, ey = bx - ax, by - ay
        length = math.hypot(ex, ey) or 1e-9
        worst = max(worst, ((px - ax) * ey - (py - ay) * ex) / length)
    return worst


def coverage(d):
    """거리를 0..1 덮임으로. 경계 한 픽셀에 걸쳐 부드럽게 넘어갑니다."""
    return min(1.0, max(0.0, 0.5 - d))


def _inside_negative(tri):
    """안쪽이 음수가 되도록 세 점의 순서를 맞춥니다.

    화면 좌표는 y 가 아래로 커져서 감는 방향을 손으로 따지면 부호를 틀리기
    쉽습니다(실제로 처음에 틀려서 산이 통째로 사라졌습니다). 중심점을
    sd_triangle 에 넣어 직접 확인하고 필요하면 뒤집습니다.
    """
    cx = sum(p[0] for p in tri) / 3.0
    cy = sum(p[1] for p in tri) / 3.0
    flipped = [tri[0], tri[2], tri[1]]
    result = tri if sd_triangle(cx, cy, tri) < 0 else flipped
    assert sd_triangle(cx, cy, result) < 0, '삼각형 방향을 잡지 못했습니다.'
    return list(result)


PEAK_NEAR = _inside_negative(PEAK_NEAR)
PEAK_FAR = _inside_negative(PEAK_FAR)


# --- 캔버스 ---------------------------------------------------------------

class Canvas:
    """스트레이트 알파 RGBA 버퍼."""

    def __init__(self, size):
        self.size = size
        self.buf = [0.0] * (size * size * 4)

    def fill_rect_gradient(self, top, bottom, radius):
        n = self.size
        for y in range(n):
            t = y / max(n - 1, 1)
            r = (top[0] + (bottom[0] - top[0]) * t) / 255.0
            g = (top[1] + (bottom[1] - top[1]) * t) / 255.0
            b = (top[2] + (bottom[2] - top[2]) * t) / 255.0
            for x in range(n):
                d = sd_round_rect(x + 0.5, y + 0.5, n / 2, n / 2,
                                  n / 2, n / 2, radius)
                a = coverage(d)
                if a > 0:
                    self._over(x, y, r, g, b, a)

    def draw(self, shape, color, clip=None, bbox=None):
        """shape(px, py) 가 거리, clip(px, py) 이 있으면 그 안쪽으로만."""
        n = self.size
        x0, y0, x1, y1 = bbox if bbox else (0, 0, n, n)
        x0 = max(0, int(x0) - 2)
        y0 = max(0, int(y0) - 2)
        x1 = min(n, int(x1) + 2)
        y1 = min(n, int(y1) + 2)
        r, g, b = color[0] / 255.0, color[1] / 255.0, color[2] / 255.0
        for y in range(y0, y1):
            py = y + 0.5
            for x in range(x0, x1):
                px = x + 0.5
                a = coverage(shape(px, py))
                if a <= 0:
                    continue
                if clip is not None:
                    a = min(a, coverage(clip(px, py)))
                    if a <= 0:
                        continue
                self._over(x, y, r, g, b, a)

    def _over(self, x, y, r, g, b, a):
        i = (y * self.size + x) * 4
        buf = self.buf
        da = buf[i + 3]
        out_a = a + da * (1 - a)
        if out_a <= 0:
            return
        buf[i] = (r * a + buf[i] * da * (1 - a)) / out_a
        buf[i + 1] = (g * a + buf[i + 1] * da * (1 - a)) / out_a
        buf[i + 2] = (b * a + buf[i + 2] * da * (1 - a)) / out_a
        buf[i + 3] = out_a

    def to_bytes(self):
        return bytes(
            min(255, max(0, int(v * 255 + 0.5))) for v in self.buf
        )


def write_png(path, canvas):
    n = canvas.size
    data = canvas.to_bytes()
    raw = b''.join(
        b'\x00' + data[y * n * 4:(y + 1) * n * 4] for y in range(n)
    )

    def chunk(tag, payload):
        body = tag + payload
        return (struct.pack('>I', len(payload)) + body
                + struct.pack('>I', zlib.crc32(body) & 0xFFFFFFFF))

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', n, n, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, 'wb') as f:
        f.write(png)
    return len(png)


# --- 장면 -----------------------------------------------------------------

def art_shapes(scale, offset):
    """72 단위 그림을 픽셀 좌표로 옮긴 도형들을 돌려줍니다."""

    def to_px(u):
        return offset + u * scale

    def rrect(box):
        cx, cy, hw, hh, r = box
        return (lambda px, py: sd_round_rect(
            px, py, to_px(cx), to_px(cy), hw * scale, hh * scale, r * scale))

    def rrect_bbox(box):
        cx, cy, hw, hh, _ = box
        return (to_px(cx - hw), to_px(cy - hh), to_px(cx + hw), to_px(cy + hh))

    def tri(points):
        pts = [(to_px(x), to_px(y)) for x, y in points]
        return lambda px, py: sd_triangle(px, py, pts)

    def tri_bbox(points):
        xs = [to_px(x) for x, _ in points]
        ys = [to_px(y) for _, y in points]
        return (min(xs), min(ys), max(xs), max(ys))

    cx, cy, r = SUN_C
    sun = lambda px, py: sd_circle(px, py, to_px(cx), to_px(cy), r * scale)
    sun_bbox = (to_px(cx - r), to_px(cy - r), to_px(cx + r), to_px(cy + r))

    return {
        'card': (rrect(CARD_BOX), rrect_bbox(CARD_BOX)),
        'photo': (rrect(PHOTO_BOX), rrect_bbox(PHOTO_BOX)),
        'sun': (sun, sun_bbox),
        'near': (tri(PEAK_NEAR), tri_bbox(PEAK_NEAR)),
        'far': (tri(PEAK_FAR), tri_bbox(PEAK_FAR)),
    }


def paint_art(canvas, scale, offset):
    s = art_shapes(scale, offset)
    photo_shape, _ = s['photo']
    canvas.draw(s['card'][0], CARD, bbox=s['card'][1])
    canvas.draw(s['photo'][0], SKY, bbox=s['photo'][1])
    canvas.draw(s['sun'][0], SUN, clip=photo_shape, bbox=s['sun'][1])
    canvas.draw(s['far'][0], MOUNTAIN_FAR, clip=photo_shape, bbox=s['far'][1])
    canvas.draw(s['near'][0], MOUNTAIN, clip=photo_shape, bbox=s['near'][1])


def render_foreground(px):
    """적응형 앞면. 108dp 캔버스 한가운데에 72 단위 그림을 놓습니다."""
    canvas = Canvas(px)
    scale = px / 108.0
    paint_art(canvas, scale, offset=18.0 * scale)
    return canvas


def render_legacy(px):
    """옛 아이콘. 마스크가 없으므로 배경까지 직접 그리고 여백을 줄입니다."""
    canvas = Canvas(px)
    canvas.fill_rect_gradient(BG_TOP, BG_BOTTOM, radius=px * 0.22)
    scale = px * 0.86 / ART
    paint_art(canvas, scale, offset=px * 0.07)
    return canvas


def render_monochrome(px):
    """테마 아이콘. 시스템이 한 가지 색으로 칠하므로 실루엣만 남깁니다.

    카드를 통째로 칠하면 그냥 둥근 사각형 덩어리가 되어 무엇인지 알 수 없습니다.
    테두리로만 그리고 안에 산과 해를 채웁니다.
    """
    canvas = Canvas(px)
    scale = px / 108.0
    offset = 18.0 * scale
    s = art_shapes(scale, offset)
    outer, outer_bbox = s['card']
    inner = s['photo'][0]
    white = (0xFF, 0xFF, 0xFF)

    # 테두리 = 바깥 사각형에서 안쪽 사각형을 뺀 것.
    ring = lambda px_, py_: max(outer(px_, py_), -inner(px_, py_))
    canvas.draw(ring, white, bbox=outer_bbox)
    canvas.draw(s['sun'][0], white, clip=inner, bbox=s['sun'][1])
    canvas.draw(s['near'][0], white, clip=inner, bbox=s['near'][1])
    canvas.draw(s['far'][0], white, clip=inner, bbox=s['far'][1])
    return canvas


ADAPTIVE_XML = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
'''

BACKGROUND_XML = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#4358E0</color>
</resources>
'''


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else RES
    if not os.path.isdir(os.path.dirname(root)) and not os.path.isdir(root):
        print('❌ %s 가 없습니다. flutter create 를 먼저 실행하세요.' % root,
              file=sys.stderr)
        return 1

    made = 0
    for density, mult in DENSITIES.items():
        out = os.path.join(root, 'mipmap-' + density)
        made += bool(write_png(os.path.join(out, 'ic_launcher.png'),
                               render_legacy(round(48 * mult))))
        made += bool(write_png(os.path.join(out, 'ic_launcher_foreground.png'),
                               render_foreground(round(108 * mult))))
        made += bool(write_png(os.path.join(out, 'ic_launcher_monochrome.png'),
                               render_monochrome(round(108 * mult))))

    xml_dir = os.path.join(root, 'mipmap-anydpi-v26')
    os.makedirs(xml_dir, exist_ok=True)
    with open(os.path.join(xml_dir, 'ic_launcher.xml'), 'w',
              encoding='utf-8') as f:
        f.write(ADAPTIVE_XML)

    values_dir = os.path.join(root, 'values')
    os.makedirs(values_dir, exist_ok=True)
    with open(os.path.join(values_dir, 'ic_launcher_background.xml'), 'w',
              encoding='utf-8') as f:
        f.write(BACKGROUND_XML)

    print('✅ 런처 아이콘 %d 개 + 적응형/테마 정의 생성' % made)
    return 0


if __name__ == '__main__':
    sys.exit(main())
