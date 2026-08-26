#!/usr/bin/env python3
"""런처 아이콘을 코드로 그려 android/app/src/main/res 에 써 넣습니다.

카메라를 든 감자 캐릭터. 오른쪽 머리에 연필을 꽂아 "사진 + 메모"를 함께
말합니다. 초록 바탕에 크림빛 몸, 굵고 들쭉날쭉한 검정 테두리.

**그림을 파일이 아니라 코드로 두는 이유.** 이 저장소에는 android/ 폴더가 없고
빌드할 때마다 `flutter create` 로 새로 만듭니다. 그래서 아이콘도 매번 다시
넣어야 하는데, PNG 를 커밋해 두면 무엇이 어떻게 바뀌었는지 diff 로 볼 수 없고
크기별로 열 몇 개를 손으로 맞춰야 합니다. 코드로 그리면 색이나 자세를 한 줄
고쳐 모든 밀도를 다시 뽑을 수 있습니다.

표준 라이브러리만 씁니다. Pillow 나 ImageMagick 을 CI 에 더 얹지 않으려고
PNG 인코더와 래스터라이저를 직접 두었습니다. 도형마다 부호 있는 거리(SDF)로
픽셀 덮임을 계산하므로 밀도마다 제 해상도에서 바로 그려도 경계가 매끈합니다.

만드는 것:
  mipmap-<밀도>/ic_launcher.png             옛 방식(안드로이드 7 이하) 아이콘
  mipmap-<밀도>/ic_launcher_foreground.png  적응형 아이콘 앞면
  mipmap-<밀도>/ic_launcher_monochrome.png  테마 아이콘(안드로이드 13+)
  mipmap-anydpi-v26/ic_launcher.xml         적응형 아이콘 정의
  drawable/ic_launcher_background.xml       적응형 아이콘 뒷면(단색)
"""

import math
import os
import struct
import sys
import zlib

RES = 'android/app/src/main/res'

DENSITIES = {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
}

# --- 색 -------------------------------------------------------------------
BACKDROP = (0x54, 0xE0, 0x45)
INK = (0x14, 0x14, 0x12)          # 완전한 검정보다 살짝 눅인 먹색
CREAM = (0xFD, 0xF8, 0xE9)
SLATE = (0x7E, 0x94, 0xAE)
MINT = (0xBF, 0xE8, 0xDE)
CORAL = (0xF4, 0xA2, 0x8C)
PENCIL = (0xE9, 0xB9, 0x5C)
WHITE = (0xFF, 0xFF, 0xFF)

# --- 배치 (72 단위 정사각형 안에서 정의) ----------------------------------
ART = 72.0
FAT = 1.10                        # 가로로 통통하게

# 적응형 아이콘의 뒷면은 108dp 인데 런처는 가운데 72dp 만 오려 씁니다.
#
# 한 번은 스퀘어클(둥근 사각형) 마스크를 가정하고 1.22 까지 키웠다가 실제
# 갤럭시에서 연필 끝이 잘렸습니다. One UI 의 아이콘 모양은 제가 근사한 둥근
# 사각형보다 모서리를 더 많이 깎습니다. 어느 런처에서도 안전한 기준은 결국
# 안드로이드가 정한 **지름 72dp 원**이라, 그 원에 맞춰 다시 잡았습니다.
ZOOM = 0.98
# 감자는 아래가 불룩해서 먹이 칠해진 무게중심이 캔버스 한가운데보다 아래에
# 놓입니다. 상자가 아니라 **무게중심**을 재서 맞춘 값입니다.
SHIFT = -3.65

BODY = [(36.0, 41.0, 21.0 * FAT, 23.0),
        (26.0 - (FAT - 1) * 10, 30.0, 12.0 * FAT, 10.5),
        (48.0 + (FAT - 1) * 10, 35.0, 11.0 * FAT, 10.0),
        (41.0 + (FAT - 1) * 6, 56.0, 11.5 * FAT, 8.5)]

# 카메라를 눈높이까지 올려 오른쪽 눈을 가립니다. 왼쪽 뜬 눈만 보입니다.
CAM = (41.5, 41.0, 10.6, 9.6)     # cx, cy, 반너비, 반높이
PEN = dict(tipx=59.11, tipy=14.36, length=22.0, angle_deg=140.0, w=3.0)


def widen(x, pull):
    """몸이 불어난 만큼 바깥으로 밀어냅니다. 안 밀면 손이 몸통에 삼켜집니다."""
    return x + (1.0 if x >= 36 else -1.0) * (FAT - 1.0) * pull


# --- 도형의 부호 있는 거리 -------------------------------------------------

def sd_round_rect(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def sd_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sd_ellipse(px, py, cx, cy, rx, ry):
    return (math.hypot((px - cx) / rx, (py - cy) / ry) - 1.0) * min(rx, ry)


def sd_triangle(px, py, tri):
    """세 반평면의 교집합. 안쪽이 음수가 되도록 방향을 맞춰 넘겨야 합니다."""
    worst = -1e9
    for i in range(3):
        ax, ay = tri[i]
        bx, by = tri[(i + 1) % 3]
        ex, ey = bx - ax, by - ay
        length = math.hypot(ex, ey) or 1e-9
        worst = max(worst, ((px - ax) * ey - (py - ay) * ex) / length)
    return worst


def orient(tri):
    """감는 방향을 코드가 직접 확인합니다.

    화면 좌표는 y 가 아래로 커져서 손으로 따지면 부호를 틀리기 쉽습니다
    (예전에 틀려서 도형이 통째로 사라진 적이 있습니다).
    """
    cx = sum(p[0] for p in tri) / 3.0
    cy = sum(p[1] for p in tri) / 3.0
    out = list(tri) if sd_triangle(cx, cy, tri) < 0 else [tri[0], tri[2], tri[1]]
    assert sd_triangle(cx, cy, out) < 0, '삼각형 방향을 잡지 못했습니다.'
    return out


def smin(a, b, k):
    """부드러운 합집합. 타원 여러 개를 감자처럼 이어 붙일 때 씁니다."""
    h = max(0.0, min(1.0, 0.5 + 0.5 * (b - a) / k))
    return b * (1 - h) + a * h - k * h * (1 - h)


def coverage(d):
    return min(1.0, max(0.0, 0.5 - d))


# --- 손그림 잡음 -----------------------------------------------------------

def _hash2(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 1274126177) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def value_noise(x, y, seed):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    ux = fx * fx * (3 - 2 * fx)
    uy = fy * fy * (3 - 2 * fy)
    a = _hash2(ix, iy, seed)
    b = _hash2(ix + 1, iy, seed)
    c = _hash2(ix, iy + 1, seed)
    d = _hash2(ix + 1, iy + 1, seed)
    return (a * (1 - ux) + b * ux) * (1 - uy) + (c * (1 - ux) + d * ux) * uy


# --- 캔버스 ---------------------------------------------------------------

class Canvas:
    """스트레이트 알파 RGBA 버퍼."""

    def __init__(self, size):
        self.size = size
        self.buf = [0.0] * (size * size * 4)

    def fill(self, color):
        base = [v / 255.0 for v in color]
        for i in range(0, self.size * self.size * 4, 4):
            self.buf[i] = base[0]
            self.buf[i + 1] = base[1]
            self.buf[i + 2] = base[2]
            self.buf[i + 3] = 1.0

    def draw(self, shape, color, bbox):
        n = self.size
        x0 = max(0, int(bbox[0]) - 2)
        y0 = max(0, int(bbox[1]) - 2)
        x1 = min(n, int(bbox[2]) + 2)
        y1 = min(n, int(bbox[3]) + 2)
        r, g, b = color[0] / 255.0, color[1] / 255.0, color[2] / 255.0
        for y in range(y0, y1):
            py = y + 0.5
            for x in range(x0, x1):
                a = coverage(shape(x + 0.5, py))
                if a > 0:
                    self.over(x, y, r, g, b, a)

    def over(self, x, y, r, g, b, a):
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
        return bytes(min(255, max(0, int(v * 255 + 0.5))) for v in self.buf)


def write_png(path, canvas):
    n = canvas.size
    data = canvas.to_bytes()
    raw = b''.join(b'\x00' + data[y * n * 4:(y + 1) * n * 4] for y in range(n))

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


# --- 그림 좌표계 -----------------------------------------------------------

class Art:
    """72 단위 그림 좌표 ↔ 픽셀. 모든 경계를 손으로 그린 것처럼 흔듭니다."""

    def __init__(self, canvas, scale, offset, zoom=ZOOM, shift=SHIFT):
        self.c, self.s, self.o, self.z = canvas, scale, offset, zoom
        self.dy = shift * zoom * scale

    def px(self, u):
        return self.o + (36.0 + (u - 36.0) * self.z) * self.s

    def py(self, u):
        return self.px(u) + self.dy

    def art(self, p):
        return 36.0 + ((p - self.o) / self.s - 36.0) / self.z

    def art_y(self, p):
        return self.art(p - self.dy)

    def _k(self, v):
        return v * self.z * self.s

    # -- 원시 도형 (경계상자는 그림 단위로 돌려줍니다) --
    def ell(self, cx, cy, rx, ry):
        f = lambda x, y: sd_ellipse(x, y, self.px(cx), self.py(cy),
                                    self._k(rx), self._k(ry))
        r = max(rx, ry)
        return f, (cx - r, cy - r, cx + r, cy + r)

    def circ(self, cx, cy, r):
        f = lambda x, y: sd_circle(x, y, self.px(cx), self.py(cy), self._k(r))
        return f, (cx - r, cy - r, cx + r, cy + r)

    def rrect(self, cx, cy, hw, hh, rr, rot=0.0):
        cxp, cyp = self.px(cx), self.py(cy)
        ca, sa = math.cos(-rot), math.sin(-rot)

        def f(x, y):
            dx, dy = x - cxp, y - cyp
            return sd_round_rect(dx * ca - dy * sa, dx * sa + dy * ca,
                                 0.0, 0.0, self._k(hw), self._k(hh),
                                 self._k(rr))
        rad = math.hypot(hw, hh)
        return f, (cx - rad, cy - rad, cx + rad, cy + rad)

    def tri(self, points):
        pts = orient(points)
        ppx = [(self.px(x), self.py(y)) for x, y in pts]
        f = lambda x, y: sd_triangle(x, y, ppx)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        return f, (min(xs), min(ys), max(xs), max(ys))

    def blob(self, parts, k=4.0):
        shapes = [self.ell(*p) for p in parts]

        def f(x, y):
            d = shapes[0][0](x, y)
            for sh, _ in shapes[1:]:
                d = smin(d, sh(x, y), self._k(k))
            return d
        xs = [b[0] for _, b in shapes] + [b[2] for _, b in shapes]
        ys = [b[1] for _, b in shapes] + [b[3] for _, b in shapes]
        return f, (min(xs) - k, min(ys) - k, max(xs) + k, max(ys) + k)

    # -- 붓질 --
    def _rough(self, f, seed, amp):
        """경계를 **그림 단위 좌표에서** 흔듭니다.

        픽셀 좌표에서 흔들면 큰 아이콘일수록 잔물결이 곱게 나와 기기마다 손맛이
        달라 보입니다. 좌표 해시라 난수 씨앗 없이도 매번 같은 선이 나옵니다.
        """
        unit = self._k(1.0)

        def g(x, y):
            ax, ay = self.art(x), self.art_y(y)
            n = (value_noise(ax * 0.26, ay * 0.26, seed) - 0.5) * 2
            n2 = (value_noise(ax * 0.95, ay * 0.95, seed + 13) - 0.5) * 2
            return f(x, y) + (n * amp + n2 * amp * 0.22) * unit
        return g

    def _box(self, bb, pad):
        x0, y0, x1, y1 = bb
        return (self.px(x0 - pad), self.py(y0 - pad),
                self.px(x1 + pad), self.py(y1 + pad))

    def ink(self, shape, color, seed, width=1.05, amp=0.55):
        """면을 칠하고 그 위에 굵기가 들쭉날쭉한 검정 테두리를 두릅니다."""
        f, bb = shape
        g = self._rough(f, seed, amp)
        unit = self._k(1.0)
        self.c.draw(g, color, self._box(bb, amp * 2 + 1))

        def band(x, y):
            ax, ay = self.art(x), self.art_y(y)
            w = width * (0.80 + 0.42 * value_noise(ax * 0.5, ay * 0.5,
                                                   seed + 31))
            return abs(g(x, y)) - w * unit
        self.c.draw(band, INK, self._box(bb, amp * 2 + width * 2 + 1))

    def flat(self, shape, color, seed, amp=0.4):
        """테두리 없이 면만. 눈·볼처럼 작은 요소용."""
        f, bb = shape
        self.c.draw(self._rough(f, seed, amp), color, self._box(bb, amp * 2 + 1))

    def stroke(self, cx, cy, length, angle, width, color, seed):
        self.flat(self.rrect(cx, cy, length / 2, width, width, angle),
                  color, seed, amp=0.3)

    def chevron(self, ax, ay, arm, width, color, seed, opening=45.0):
        """`<` 모양 감은 눈."""
        for i, sign in enumerate((-1, 1)):
            ang = math.radians(sign * opening)
            self.stroke(ax + math.cos(ang) * arm / 2,
                        ay + math.sin(ang) * arm / 2,
                        arm, ang, width, color, seed + i)


# --- 캐릭터 ---------------------------------------------------------------

def pencil(art, tipx, tipy, length, angle_deg, w):
    """연필 한 자루. 끝은 깎아 놓은 것처럼 뾰족한 원뿔로 냅니다.

    둥근 사각형으로 심을 그리면 끝이 뭉툭해서 성냥개비로 보입니다. 나무를 깎은
    삼각형 + 그 안의 흑연 삼각형, 두 겹이라야 연필로 읽힙니다.
    """
    ang = math.radians(angle_deg)
    dx, dy = math.cos(ang), math.sin(ang)
    nx, ny = -dy, dx
    cone = 3.4 * w / 2.1

    def at(along, across=0.0):
        return (tipx + dx * along + nx * across, tipy + dy * along + ny * across)

    b0, b1 = cone, length * 0.94
    bx, by = at((b0 + b1) / 2)
    art.ink(art.rrect(bx, by, (b1 - b0) / 2, w, 0.7, ang), PENCIL, 40,
            width=0.95, amp=0.32)
    art.ink(art.tri([at(0.0), at(cone, w), at(cone, -w)]), CREAM, 41,
            width=0.8, amp=0.22)
    art.flat(art.tri([at(0.0), at(cone * 0.45, w * 0.45),
                      at(cone * 0.45, -w * 0.45)]), INK, 43, amp=0.16)
    ex, ey = at(length * 0.97)
    art.ink(art.rrect(ex, ey, w * 0.75, w * 0.95, 0.7, ang), CORAL, 42,
            width=0.8, amp=0.28)


def draw(art):
    # 연필을 몸통보다 **먼저** 그립니다. 그래야 아래 절반이 머리에 가려져 뒤에
    # 꽂힌 것처럼 보입니다. 나중에 그리면 얼굴 위에 얹힌 막대가 됩니다.
    pencil(art, **PEN)

    art.ink(art.blob(BODY), CREAM, seed=1, width=1.30, amp=0.50)

    # 찡긋한 오른쪽 눈은 곧이어 카메라가 덮습니다. 그래도 그려 둡니다 —
    # 카메라를 조금만 옮겨도 눈이 사라지거나 반쯤 나오게 되는데, 그리지 않으면
    # 그 사실을 눈으로 확인할 방법이 없습니다.
    art.flat(art.circ(widen(26.5, 6), 35.5, 3.0), INK, 80, amp=0.28)
    art.flat(art.circ(widen(25.5, 6), 34.5, 1.05), CREAM, 81, amp=0.2)
    art.chevron(widen(44.0, 6), 35.5, 4.6, 0.9, INK, 82)
    art.flat(art.circ(widen(18.5, 16), 37.0, 2.9), CORAL, 84, amp=0.35)
    art.flat(art.circ(widen(53.5, 16), 37.0, 2.9), CORAL, 85, amp=0.35)

    cx, cy, hw, hh = CAM
    art.ink(art.rrect(cx, cy - hh - 1.6, 3.0, 2.0, 1.2), SLATE, 10,
            width=0.8, amp=0.3)
    art.ink(art.rrect(cx, cy, hw, hh, 2.6), SLATE, 11, width=1.05, amp=0.40)
    art.ink(art.circ(cx, cy, hh * 0.60), MINT, 12, width=0.85, amp=0.32)
    art.flat(art.circ(cx - hh * 0.18, cy - hh * 0.20, hh * 0.20), CREAM, 13,
             amp=0.22)
    art.ink(art.circ(cx - hw - 1.6, cy + 3.2, 3.7), CREAM, 50,
            width=1.0, amp=0.42)
    art.ink(art.circ(cx + hw + 1.6, cy + 3.2, 3.7), CREAM, 51,
            width=1.0, amp=0.42)


# --- 출력 -----------------------------------------------------------------

def render_foreground(px):
    """적응형 앞면. 108dp 캔버스 한가운데 72dp 안에 그림을 놓습니다."""
    canvas = Canvas(px)
    draw(Art(canvas, px / 108.0, 18.0 * px / 108.0))
    return canvas


def render_legacy(px, foreground):
    """옛 아이콘. 마스크가 없으므로 배경까지 직접 그립니다.

    모서리를 깎지 않고 정사각형을 꽉 채웁니다. 어느 안드로이드에서도 아이콘
    바탕이 초록으로 끝까지 차 있어야 같은 앱으로 보입니다.
    """
    canvas = Canvas(px)
    canvas.fill(BACKDROP)
    draw(Art(canvas, px / 72.0, 0.0))
    return canvas


def render_monochrome(px, foreground):
    """테마 아이콘. 시스템이 한 가지 색으로 칠합니다.

    색을 못 쓰니 겹쳐 그리는 방식이 통하지 않습니다. 앞면을 그대로 흰색으로
    바꾸면 몸도 카메라도 전부 흰색이 되어 덩어리가 됩니다. 그래서 **먹선 자리만
    비웁니다** — 흰 실루엣에 검은 선이 구멍으로 남아 배경색이 비칩니다.
    """
    canvas = Canvas(px)
    src = foreground.buf
    out = canvas.buf
    for i in range(0, px * px * 4, 4):
        a = src[i + 3]
        if a <= 0:
            continue
        lum = 0.299 * src[i] + 0.587 * src[i + 1] + 0.114 * src[i + 2]
        # 어두운 곳(먹선)일수록 0 에 가깝게. 0.25~0.45 사이에서 부드럽게.
        keep = min(1.0, max(0.0, (lum - 0.25) / 0.20))
        if keep <= 0:
            continue
        out[i] = out[i + 1] = out[i + 2] = 1.0
        out[i + 3] = a * keep
    return canvas


ADAPTIVE_XML = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
'''

BACKGROUND_XML = '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#%02X%02X%02X"/>
</shape>
''' % BACKDROP


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else RES
    if not os.path.isdir(os.path.dirname(root) or '.') and not os.path.isdir(root):
        print('❌ %s 가 없습니다. flutter create 를 먼저 실행하세요.' % root,
              file=sys.stderr)
        return 1

    made = 0
    for density, mult in DENSITIES.items():
        out = os.path.join(root, 'mipmap-' + density)
        # 앞면을 한 번만 그려 테마 아이콘까지 함께 씁니다.
        foreground = render_foreground(round(108 * mult))
        made += bool(write_png(os.path.join(out, 'ic_launcher_foreground.png'),
                               foreground))
        made += bool(write_png(os.path.join(out, 'ic_launcher_monochrome.png'),
                               render_monochrome(foreground.size, foreground)))
        made += bool(write_png(os.path.join(out, 'ic_launcher.png'),
                               render_legacy(round(48 * mult), foreground)))

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
