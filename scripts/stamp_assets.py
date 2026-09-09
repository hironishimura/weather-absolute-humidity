#!/usr/bin/env python3
"""読み込むCSS・JavaScriptに、中身から作った印をつける。

ブラウザは同じURLのファイルをしばらく使い回します。中身を直しても
URLが同じだと古いままになり、画面と動きが食い違うことがあります。
そこで中身が変わったらURLも変わるように「?v=…」を付け替えます。

    python3 scripts/stamp_assets.py

docs/index.html を書き換えます。build_single.py からも呼ばれます。
"""

import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
INDEX = os.path.join(ROOT, "docs/index.html")
ASSETS = os.path.join(ROOT, "docs/assets")


def short_hash(path):
    with open(path, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()[:8]


def stamp():
    if not os.path.exists(INDEX):
        print("%s がありません" % INDEX)
        return 1
    with open(INDEX, encoding="utf-8") as f:
        html = f.read()

    changed = []
    for name in ("app.css", "app.js"):
        path = os.path.join(ASSETS, name)
        if not os.path.exists(path):
            continue
        v = short_hash(path)
        pattern = re.compile(r'(\./assets/' + re.escape(name) + r')(\?v=[0-9a-f]+)?')
        html, n = pattern.subn(lambda m: m.group(1) + "?v=" + v, html)
        if n:
            changed.append("%s → ?v=%s" % (name, v))

    with open(INDEX, "w", encoding="utf-8") as f:
        f.write(html)
    print("印をつけました：%s" % " / ".join(changed) if changed else "対象がありませんでした")
    return 0


if __name__ == "__main__":
    sys.exit(stamp())
