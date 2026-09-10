#!/usr/bin/env python3
"""東進の天気（toshin.com/weather）が取り込めるかどうかを調べる。

実装する前の下調べのための道具。取り込みは一切せず、
「どう作られているか」「取ってよいか」をログに出すだけ。

    python3 scripts/probe_toshin.py

手元からは外に出られないので、GitHub Actions から動かして出力を読む。
"""

import gzip
import io
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)
TIMEOUT = 20
BASE = "https://www.toshin.com"


def get(url):
    """取ってきて (最終URL, 状態, ヘッダ, 本文) を返す。落ちても例外にしない。"""
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,*/*",
            "Accept-Language": "ja,en;q=0.8",
            "Accept-Encoding": "gzip",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            raw = res.read()
            if res.headers.get("Content-Encoding") == "gzip":
                raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
            charset = res.headers.get_content_charset()
            final, code, headers = res.geturl(), res.status, dict(res.headers)
    except urllib.error.HTTPError as e:
        raw = e.read() or b""
        charset = None
        final, code, headers = url, e.code, dict(e.headers or {})
    except Exception as e:  # noqa: BLE001
        return url, None, {}, "取得できませんでした: %s" % e

    for enc in [charset, "utf-8", "cp932", "euc-jp"]:
        if not enc:
            continue
        try:
            return final, code, headers, raw.decode(enc)
        except (UnicodeDecodeError, LookupError):
            continue
    return final, code, headers, raw.decode("utf-8", "replace")


class Tables(HTMLParser):
    """表を行と列に落とす。中身の作りを見るため。"""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tables = []
        self._t = None
        self._row = None
        self._cell = None

    def handle_starttag(self, tag, attrs):
        if tag == "table":
            self._t = []
        elif tag == "tr" and self._t is not None:
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []

    def handle_endtag(self, tag):
        if tag == "table" and self._t is not None:
            self.tables.append(self._t)
            self._t = None
        elif tag == "tr" and self._row is not None:
            self._t.append(self._row)
            self._row = None
        elif tag in ("td", "th") and self._cell is not None:
            self._row.append(" ".join("".join(self._cell).split()))
            self._cell = None

    def handle_data(self, data):
        if self._cell is not None:
            self._cell.append(data)


class Links(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links = []
        self._href = None
        self._text = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self._href = dict(attrs).get("href")
            self._text = []

    def handle_endtag(self, tag):
        if tag == "a" and self._href is not None:
            self.links.append((self._href, " ".join("".join(self._text).split())))
            self._href = None

    def handle_data(self, data):
        if self._href is not None:
            self._text.append(data)


def head(title):
    print("\n" + "=" * 60)
    print(title)
    print("=" * 60)


def show_response(url):
    final, code, headers, body = get(url)
    print("URL      :", url)
    print("最終URL  :", final)
    print("状態     :", code)
    print("種類     :", headers.get("Content-Type"))
    print("大きさ   :", "%d 文字" % len(body))
    for k in ("X-Robots-Tag", "Set-Cookie", "Cache-Control", "Server"):
        if headers.get(k):
            print("%-9s: %s" % (k, headers[k][:120]))
    return body


def looks_rendered(body):
    """気温や湿度の数字が、そのままHTMLに入っているかを見る。"""
    marks = {
        "「湿度」の字": "湿度" in body,
        "「気温」の字": "気温" in body,
        "「降水」の字": "降水" in body,
        "「体感」の字": "体感" in body,
        "℃つきの数字": bool(re.search(r"-?\d+(\.\d+)?\s*(℃|&#8451;|度)", body)),
        "%つきの数字": bool(re.search(r"\d+\s*%", body)),
        "mmつきの数字": bool(re.search(r"\d+(\.\d+)?\s*mm", body)),
    }
    for k, v in marks.items():
        print("  %-12s %s" % (k, "あり" if v else "なし"))
    return marks


def main():
    head("1. robots.txt（取ってよいか）")
    body = show_response(BASE + "/robots.txt")
    print("-" * 60)
    print(body[:1500] if body else "(空)")

    head("2. 都道府県のページ")
    url = BASE + "/weather/city?pref=" + urllib.parse.quote("栃木県")
    body = show_response(url)
    print("-- HTMLに数字が入っているか --")
    looks_rendered(body)

    print("-- <script src> --")
    for m in re.findall(r'<script[^>]+src="([^"]+)"', body)[:15]:
        print("  ", m)
    print("-- 画面を組み立てていそうな仕掛け --")
    for key in ("__NEXT_DATA__", "window.__", "Vue", "React", "ng-app", "data-react"):
        if key in body:
            print("   あり:", key)

    print("-- 表の数 --")
    tp = Tables()
    tp.feed(body)
    print("  ", len(tp.tables), "個")
    for i, t in enumerate(tp.tables[:6]):
        print("   表%d: %d行" % (i, len(t)))
        for row in t[:4]:
            print("      ", " | ".join(row[:12]))

    print("-- 市区町村へのリンク --")
    lp = Links()
    lp.feed(body)
    city = [(h, t) for h, t in lp.links if "city" in (h or "") or "宇都宮" in (t or "")]
    for h, t in city[:20]:
        print("   %-50s %s" % (h[:50], t))
    print("   リンク総数:", len(lp.links))

    head("3. 市のページ（宇都宮）")
    for cand in [
        BASE + "/weather/city?pref=" + urllib.parse.quote("栃木県")
        + "&city=" + urllib.parse.quote("宇都宮市"),
        BASE + "/weather/city/" + urllib.parse.quote("宇都宮市"),
    ]:
        b = show_response(cand)
        if b and "取得できませんでした" not in b[:40]:
            looks_rendered(b)
            tp2 = Tables()
            tp2.feed(b)
            print("  表の数:", len(tp2.tables))
            for i, t in enumerate(tp2.tables[:4]):
                print("   表%d: %d行" % (i, len(t)))
                for row in t[:6]:
                    print("      ", " | ".join(row[:14]))
        print("-" * 60)

    head("4. JSON を返す口がないか")
    for path in ["/weather/api", "/api/weather", "/weather/city.json"]:
        f, c, h, b = get(BASE + path)
        print("%-24s %s %s" % (path, c, (h.get("Content-Type") or "")[:40]))

    head("5. 利用規約のありか")
    for path in ["/policy/", "/rule/", "/terms/", "/weather/"]:
        f, c, h, b = get(BASE + path)
        print("%-14s %s  %s" % (path, c, f))


if __name__ == "__main__":
    main()
