#!/usr/bin/env python3
"""アプリを1つのHTMLファイルにまとめる。

CSSとJavaScriptを本体に埋め込むので、できたファイルをダブルクリックするだけで
使える。サーバもインターネット上の置き場所も要らない。

    python3 scripts/build_single.py

ただし file:// で開くと、ブラウザの決まりで現在地の取得（Geolocation）が
使えない。地点は画面の「地点を手で設定する」から入れる（既定は宇都宮）。
取り込みファイル（data/latest.json）も読めないので、Yahoo!天気と
ウェザーニュースの欄は「未取得」になる。
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # リポジトリの一番上
PUBLIC = os.path.join(ROOT, "docs")
DEFAULT_OUT = os.path.join(ROOT, "dist/weather-app.html")


def read(*parts):
    with open(os.path.join(PUBLIC, *parts), encoding="utf-8") as f:
        return f.read()


def build():
    html = read("index.html")
    css = read("assets", "app.css")
    js = read("assets", "app.js")

    for name, body in (("app.css", css), ("app.js", js)):
        if "</script" in body.lower():
            raise SystemExit("%s に </script> が含まれていて埋め込めません" % name)

    html = html.replace(
        '<link rel="stylesheet" href="./assets/app.css">',
        "<style>\n" + css + "\n</style>",
    )
    html = html.replace(
        '<script src="./assets/app.js" defer></script>',
        "<script>\n" + js + "\n</script>",
    )
    if "./assets/" in html:
        raise SystemExit("埋め込めていない参照が残っています")

    # 1ファイルで配る版だとわかるようにしておく
    html = html.replace(
        "<title>気温・湿度・絶対湿度 ｜ 現在地の実況と予報</title>",
        "<title>気温・湿度・絶対湿度 ｜ 現在地の実況と予報（1ファイル版）</title>",
    )
    return html


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    os.makedirs(os.path.dirname(out), exist_ok=True)
    body = build()
    with open(out, "w", encoding="utf-8") as f:
        f.write(body)
    print("書き出しました → %s（%.0f KB）" % (out, len(body.encode("utf-8")) / 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
