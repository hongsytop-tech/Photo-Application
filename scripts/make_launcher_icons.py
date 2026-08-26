#!/usr/bin/env python3
"""런처 아이콘을 코드로 그려 android/app/src/main/res 에 써 넣습니다.

`flutter create` 가 넣어 주는 아이콘은 어느 Flutter 프로젝트나 똑같아서, 같은
방식으로 만든 다른 앱과 홈 화면에서 구분되지 않습니다. 사진을 다루는 앱이라는
것이 아이콘만 보고도 보이도록 즉석카메라를 그립니다.

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
  drawable/ic_launcher_background.xml       적응형 아이콘 뒷면
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
# 하늘색에서 파랑으로 내려오는 바탕 위에 흰 카메라. 몸체를 흰색으로 두어야
# 어떤 파랑에서도 형태가 또렷하게 뜹니다.
BG_TOP = (0xB4, 0xE7, 0xFF)
BG_BOTTOM = (0x3A, 0x8B, 0xFF)
BODY = (0xFF, 0xFF, 0xFF)
PANEL = (0x2B, 0x3C, 0x5E)
LENS = (0x1B, 0x25, 0x3D)
GLASS = (0x8E, 0xE3, 0xFF)
GLINT = (0xFF, 0xFF, 0xFF)
STRIPES = [
    (0xFF, 0x6F, 0xAC),
    (0xFF, 0xC1, 0x07),
    (0x2B, 0xC9, 0xA0),
]

# --- 그림 (72 단위 정사각형 안에서 정의) ----------------------------------
# 적응형 아이콘의 안전 영역은 108dp 캔버스 한가운데 지름 72dp 원입니다. 몸체가
# 그 원 밖으로 나가면 기기 모양(원/스퀘어클)에 따라 모서리가 잘립니다.
# 50x44 면 반대각선이 33.3 으로 반지름 36 안에 들어갑니다.
ART = 72.0
BODY_BOX = (36.0, 37.0, 25.0, 22.0, 7.0)   # cx, cy, 반너비, 반높이, 모서리
PANEL_BOX = (36.0, 32.0, 19.0, 13.0, 4.0)  # 렌즈가 앉는 어두운 판
LENS_C = (36.0, 32.0, 9.5)                  # cx, cy, r
GLASS_C = (36.0, 32.0, 5.5)
GLINT_C = (33.0, 29.0, 2.4)
# 아래쪽 색 띠. 즉석카메라의 장난감스러운 인상은 거의 이 셋에서 나옵니다.
STRIPE_Y = 51.0
STRIPE_X0 = 20.5
STRIPE_GAP = 4.2
STRIPE_BOX = (1.7, 3.2, 0.8)                # 반너비, 반높이, 모서리


# --- 도형의 부호 있는 거리 -------------------------------------------------

def sd_round_rect(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def sd_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def coverage(d):
    """거리를 0..1 덮임으로. 경계 한 픽셀에 걸쳐 부드럽게 넘어갑니다."""
    return min(1.0, max(0.0, 0.5 - d))


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
    """72 단위 그림을 픽셀 좌표로 옮긴 (도형, 경계상자) 들을 돌려줍니다."""

    def to_px(u):
        return offset + u * scale

    def rrect(cx, cy, hw, hh, r):
        shape = (lambda px, py: sd_round_rect(
            px, py, to_px(cx), to_px(cy), hw * scale, hh * scale, r * scale))
        box = (to_px(cx - hw), to_px(cy - hh), to_px(cx + hw), to_px(cy + hh))
        return shape, box

    def circ(cx, cy, r):
        shape = lambda px, py: sd_circle(px, py, to_px(cx), to_px(cy),
                                         r * scale)
        box = (to_px(cx - r), to_px(cy - r), to_px(cx + r), to_px(cy + r))
        return shape, box

    shapes = {
        'body': rrect(*BODY_BOX),
        'panel': rrect(*PANEL_BOX),
        'lens': circ(*LENS_C),
        'glass': circ(*GLASS_C),
        'glint': circ(*GLINT_C),
    }
    hw, hh, r = STRIPE_BOX
    for i in range(len(STRIPES)):
        shapes['stripe%d' % i] = rrect(
            STRIPE_X0 + i * STRIPE_GAP, STRIPE_Y, hw, hh, r)
    return shapes


def paint_art(canvas, scale, offset):
    s = art_shapes(scale, offset)
    panel = s['panel'][0]
    canvas.draw(s['body'][0], BODY, bbox=s['body'][1])
    canvas.draw(panel, PANEL, bbox=s['panel'][1])
    # 렌즈는 판 안쪽으로만. 판 모서리를 넘어가면 몸체 위에 떠 보입니다.
    canvas.draw(s['lens'][0], LENS, clip=panel, bbox=s['lens'][1])
    canvas.draw(s['glass'][0], GLASS, clip=panel, bbox=s['glass'][1])
    canvas.draw(s['glint'][0], GLINT, clip=panel, bbox=s['glint'][1])
    for i, color in enumerate(STRIPES):
        shape, box = s['stripe%d' % i]
        canvas.draw(shape, color, bbox=box)


def render_foreground(px):
    """적응형 앞면. 108dp 캔버스 한가운데에 72 단위 그림을 놓습니다."""
    canvas = Canvas(px)
    scale = px / 108.0
    paint_art(canvas, scale, offset=18.0 * scale)
    return canvas


def render_legacy(px):
    """옛 아이콘. 마스크가 없으므로 배경까지 직접 그리고 여백을 줄입니다.

    적응형 쪽은 보이는 영역이 108 중 가운데 72 라 몸체가 그 안에서 69% 를
    차지합니다. 옛 아이콘도 비슷하게 보이도록 그림을 키웁니다.
    """
    canvas = Canvas(px)
    canvas.fill_rect_gradient(BG_TOP, BG_BOTTOM, radius=px * 0.22)
    scale = px * 0.95 / ART
    paint_art(canvas, scale, offset=px * 0.025)
    return canvas


def render_monochrome(px):
    """테마 아이콘. 시스템이 한 가지 색으로 칠하므로 실루엣만 남깁니다.

    색을 못 쓰니 겹쳐 그리는 방식이 통하지 않습니다. 흰 몸체 위에 어두운 판을
    얹던 것을 그대로 흰색으로 바꾸면 판까지 흰색이 되어 그냥 둥근 사각형
    덩어리가 됩니다. 그래서 몸체를 통으로 칠하고 렌즈와 색 띠 자리를 **뚫습니다.**
    뚫린 자리로 배경색이 비쳐 카메라로 읽힙니다.
    """
    canvas = Canvas(px)
    scale = px / 108.0
    s = art_shapes(scale, 18.0 * scale)

    body, body_box = s['body']
    holes = [s['lens'][0]]
    holes += [s['stripe%d' % i][0] for i in range(len(STRIPES))]

    def silhouette(x, y):
        d = body(x, y)
        for hole in holes:
            d = max(d, -hole(x, y))
        return d

    canvas.draw(silhouette, (0xFF, 0xFF, 0xFF), bbox=body_box)
    return canvas


ADAPTIVE_XML = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
'''

# 옛 아이콘과 같은 그라데이션을 뒷면에도 씁니다. 단색으로 두면 안드로이드 8 이상
# 에서만 배경이 밋밋해져 같은 앱인데 기기마다 달라 보입니다.
BACKGROUND_XML = '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:angle="270"
        android:startColor="#%02X%02X%02X"
        android:endColor="#%02X%02X%02X"
        android:type="linear"/>
</shape>
''' % (BG_TOP + BG_BOTTOM)


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

    drawable_dir = os.path.join(root, 'drawable')
    os.makedirs(drawable_dir, exist_ok=True)
    with open(os.path.join(drawable_dir, 'ic_launcher_background.xml'), 'w',
              encoding='utf-8') as f:
        f.write(BACKGROUND_XML)

    print('✅ 런처 아이콘 %d 개 + 적응형/테마 정의 생성' % made)
    return 0


if __name__ == '__main__':
    sys.exit(main())
