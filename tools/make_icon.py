"""앱 아이콘 1024px 만들기 — ecom 표식(SVG)을 흰색으로, 바탕은 ecom 초록(#005034) 꽉 채움.

iOS 앱 아이콘은 투명 부분이 없어야 한다(둥근 모서리는 iOS 가 깎는다).
쓰는 법: python -I -X utf8 tools/make_icon.py <economic-site 의 ecom-mark.svg 경로>
"""
import pathlib
import subprocess
import sys
import tempfile

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

svg = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
html = f"""<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;width:1024px;height:1024px;background:#005034;overflow:hidden}}
.m{{position:absolute;left:50%;top:48%;height:47%;transform:translate(-50%,-50%);color:#fff}}
.m svg{{height:100%;width:auto;display:block}}
</style></head><body><div class="m">{svg}</div></body></html>"""

with tempfile.TemporaryDirectory() as tmp:
    page = pathlib.Path(tmp) / "icon.html"
    page.write_text(html, encoding="utf-8")
    shot = pathlib.Path(tmp) / "shot.png"
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--window-size=1024,1024",
                    f"--screenshot={shot}", page.as_uri()], check=True, timeout=60)
    from PIL import Image
    im = Image.open(shot).convert("RGB")
    assert im.size == (1024, 1024), im.size
    im.save(OUT)
print(OUT)
