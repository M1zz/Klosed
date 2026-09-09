#!/usr/bin/env python3
"""앱스토어 마케팅 스크린샷 생성: HTML 생성 → 헤드리스 Chrome 렌더링.

원본 캡처(docs/screenshots/raw/<locale>/)를 목업 위에 얹고 헤드라인을 붙여
App Store Connect 제출 규격(1242x2688)으로 바로 렌더링한다.

다음 릴리즈 때는 원본 스크린샷만 다시 찍고 이 스크립트를 재실행하면 된다.

사용법:
    python3 scripts/make_marketing_screenshots.py          # ko, en 전부
    python3 scripts/make_marketing_screenshots.py ko       # 특정 로케일만
"""
import subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"
OUT = ROOT / "docs" / "screenshots" / "marketing"
WORK = ROOT / "docs" / "screenshots" / ".html"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# App Store Connect 제출 규격. 원본(1320x2868)을 리사이즈하지 않고
# 캔버스 자체를 이 크기로 잡아 렌더링해야 화질이 유지된다.
W, H = 1242, 2688

# (파일명, 레이아웃, 헤드라인, 서브카피) — 로케일별로 따로 쓴다(기계번역 금지)
SHOTS = {
    "ko": [
        ("01-main.png",     "hero-bleed",  "마트 가기 전,<br>딱 3초",   "오늘 여는지 한눈에 확인하세요"),
        ("02-calendar.png", "left-text",   "이번 달 휴무일을<br>한눈에", "달력에서 쉬는 날만 콕 집어드려요"),
        ("03-marts.png",    "text-bottom", "내가 가는 마트만 골라서",    "대형마트·코스트코·명절 휴무까지"),
        ("04-pattern.png",  "flat-rotate", "동네 마트도<br>직접 등록",   "2·4주 화요일 같은 패턴 그대로"),
        ("05-share.png",    "dark",        "휴무 소식,<br>카드 한 장으로", "가족과 이웃에게 바로 알려주세요"),
    ],
    "en": [
        ("01-main.png",     "hero-bleed",  "Check before<br>you go",      "See at a glance if the store is open"),
        ("02-calendar.png", "left-text",   "This month's<br>closings",    "Every closed day, right on the calendar"),
        ("03-marts.png",    "text-bottom", "Track only your stores",      "Supermarkets, Costco, holiday closings"),
        ("04-pattern.png",  "flat-rotate", "Add your<br>local store",     "Patterns like 2nd and 4th Tuesday"),
        ("05-share.png",    "dark",        "Share a closing<br>in one card", "Let family and neighbors know"),
    ],
}

BASE_CSS = f"""
* {{ margin:0; padding:0; box-sizing:border-box; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
body {{ background:#f6f5f3; font-family:-apple-system, "Apple SD Gothic Neo", "Helvetica Neue", sans-serif;
  position:relative; }}
.headline {{ font-size:96px; font-weight:800; color:#141416; letter-spacing:-2px; line-height:1.22; }}
.sub {{ font-size:48px; font-weight:500; color:#9a9aa0; letter-spacing:-1px; }}
.phone {{ background:#17171a; border-radius:112px; border:3px solid #3a3a3e; padding:24px;
  box-shadow: 58px 86px 116px rgba(0,0,0,.28), 20px 30px 50px rgba(0,0,0,.18); }}
.phone img {{ width:100%; display:block; border-radius:89px; }}
"""

LAYOUTS = {
    # 1) 정면 대형, 하단 블리드
    "hero-bleed": """
.headline { text-align:center; margin-top:230px; padding:0 70px; }
.sub { text-align:center; margin-top:48px; }
.wrap { display:flex; justify-content:center; margin-top:150px; }
.phone { width:930px; }
""",
    # 2) 좌측 정렬 텍스트 + 오른쪽으로 기운 폰
    "left-text": """
.headline { text-align:left; margin:250px 0 0 100px; }
.sub { text-align:left; margin:44px 0 0 104px; }
.wrap { perspective:2600px; perspective-origin:30% 30%; position:absolute; left:250px; top:790px; }
.phone { width:880px; transform:rotateY(16deg) rotateX(2deg); }
""",
    # 3) 폰 상단, 텍스트 하단
    "text-bottom": """
.wrap { perspective:2800px; perspective-origin:50% 40%; display:flex; justify-content:center; margin-top:150px; }
.phone { width:830px; transform:rotateY(-10deg) rotateX(2deg); }
.headline { text-align:center; margin-top:110px; padding:0 70px; }
.sub { text-align:center; margin-top:44px; }
""",
    # 4) 평면 회전 + 하단 블리드
    "flat-rotate": """
.headline { text-align:center; margin-top:220px; padding:0 70px; }
.sub { text-align:center; margin-top:48px; }
.wrap { position:absolute; left:100px; top:880px; }
.phone { width:980px; transform:rotate(-6deg); }
""",
    # 5) 다크 배경 반전 (마지막 장 포인트)
    "dark": """
body { background:#131316; }
.headline { color:#f5f5f7; text-align:center; margin-top:230px; padding:0 70px; }
.sub { color:#77777d; text-align:center; margin-top:48px; }
.wrap { display:flex; justify-content:center; margin-top:140px; }
.phone { width:880px; border-color:#48484e;
  box-shadow: 0 0 160px rgba(255,90,120,.22), 40px 70px 110px rgba(0,0,0,.55); }
""",
}

BODY_TEXT_FIRST = ('<div class="headline">{headline}</div><div class="sub">{sub}</div>'
                   '<div class="wrap"><div class="phone"><img src="{img}"></div></div>')
BODY_PHONE_FIRST = ('<div class="wrap"><div class="phone"><img src="{img}"></div></div>'
                    '<div class="headline">{headline}</div><div class="sub">{sub}</div>')

HTML = """<!doctype html><html><head><meta charset="utf-8"><style>
{base}{layout}
</style></head><body>{body}</body></html>"""


def render(locale):
    out_dir = OUT / locale
    out_dir.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    for fname, layout, headline, sub in SHOTS[locale]:
        src = RAW / locale / fname
        if not src.exists():
            raise SystemExit(f"원본 스크린샷이 없습니다: {src}")
        body_tpl = BODY_PHONE_FIRST if layout == "text-bottom" else BODY_TEXT_FIRST
        body = body_tpl.format(headline=headline, sub=sub, img=src.as_uri())
        html_path = WORK / f"{locale}-{fname.replace('.png', '.html')}"
        html_path.write_text(HTML.format(base=BASE_CSS, layout=LAYOUTS[layout], body=body), encoding="utf-8")
        out_png = out_dir / fname
        subprocess.run([CHROME, "--headless=new", f"--screenshot={out_png}",
                        f"--window-size={W},{H}", "--force-device-scale-factor=1",
                        "--hide-scrollbars", "--disable-gpu", html_path.as_uri()],
                       check=True, capture_output=True)
        print(f"rendered {out_png}")


if __name__ == "__main__":
    targets = sys.argv[1:] or list(SHOTS)
    for loc in targets:
        render(loc)
