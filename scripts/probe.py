#!/usr/bin/env python3
"""Yahoo!天気・ウェザーニュースのページが実際どう作られているかを調べる。

手元からは外に出られないことがあるので、GitHub Actions から動かして
その出力（ログ）を見ながら collect.py の読み取りを直すための道具。

    python3 scripts/probe.py                          # settings.json のURLを調べる
    python3 scripts/probe.py --url https://…          # 指定したURLを調べる
    python3 scripts/probe.py --links https://… --keyword 宇都宮
                                                      # ページ内のリンクを探す
"""

import argparse
import json
import os
import re
import sys
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import collect  # noqa: E402

SETTINGS = os.path.join(HERE, "settings.json")
MAX_TABLES = 12
MAX_CELLS = 14


class LinkParser(HTMLParser):
    """<a href> と文字を拾う。"""

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
        if tag == "a" and self._href:
            self.links.append((self._href, " ".join("".join(self._text).split())))
            self._href = None

    def handle_data(self, data):
        if self._href is not None:
            self._text.append(data)


def title_of(html):
    m = re.search(r"<title[^>]*>(.*?)</title>", html, re.S | re.I)
    return " ".join(m.group(1).split()) if m else "(タイトルなし)"


def short(cells, n=MAX_CELLS):
    out = [c if len(c) <= 12 else c[:12] + "…" for c in cells[:n]]
    if len(cells) > n:
        out.append("…(全%d列)" % len(cells))
    return " | ".join(out)


def probe(name, url):
    print("=" * 70)
    print("■ %s" % name)
    print("  URL: %s" % url)
    try:
        html = collect.fetch(url)
    except Exception as e:                       # noqa: BLE001  何が来ても続ける
        print("  取得できませんでした: %s" % e)
        return
    print("  タイトル: %s" % title_of(html))
    print("  長さ: %d 文字" % len(html))

    tables = collect.read_tables(html)
    print("  表の数: %d" % len(tables))
    for i, t in enumerate(tables[:MAX_TABLES]):
        labels = [r[0] for r in t if r]
        print("   [%2d] %d行 × 最大%d列" % (i, len(t), max((len(r) for r in t), default=0)))
        print("        1行目 : %s" % (short(t[0]) if t else "(空)"))
        print("        左端列 : %s" % short(labels))
        hit = [x for x in labels + list(t[0]) if "湿度" in x or "気温" in x]
        if hit:
            print("        ★ 気温／湿度らしい見出し: %s" % " , ".join(hit[:6]))
    if len(tables) > MAX_TABLES:
        print("   …ほか %d 個" % (len(tables) - MAX_TABLES))

    got = collect.series_from_html(html)
    if got:
        print("  → 表から読めました")
        print("     時刻: %s" % short([str(x) for x in (got[0] or [])], 10))
        print("     気温: %s" % short([str(x) for x in got[1]], 10))
        print("     湿度: %s" % short([str(x) for x in got[2]], 10))
    else:
        print("  → 表からは読めませんでした")
        got = collect.series_from_json(html)
        if got:
            print("  → 埋め込みJSONから読めました")
            print("     気温: %s" % short([str(x) for x in got[1]], 10))
            print("     湿度: %s" % short([str(x) for x in got[2]], 10))
        else:
            print("  → 埋め込みJSONからも読めませんでした")
            for key in ("湿度", "気温"):
                for m in list(re.finditer(key, html))[:3]:
                    s = max(0, m.start() - 120)
                    around = " ".join(html[s:m.start() + 160].split())
                    print("     「%s」の周辺: …%s…" % (key, around[:240]))


def probe_scripts(url, keyword):
    """<script> の中に気温・湿度がどう入っているかを見る。"""
    print("=" * 70)
    print("■ script 調べ: %s（手がかり: %s）" % (url, keyword))
    try:
        html = collect.fetch(url)
    except Exception as e:                       # noqa: BLE001
        print("  取得できませんでした: %s" % e)
        return

    blocks = list(re.finditer(r"<script([^>]*)>(.*?)</script>", html, re.S | re.I))
    print("  script の数: %d" % len(blocks))
    for i, m in enumerate(blocks):
        attrs, body = m.group(1), m.group(2)
        src = re.search(r'src=["\']([^"\']+)', attrs)
        mark = []
        for k in ("humid", "HUMID", "湿度", "AIRTMP", "temperature", "hourly"):
            if k in body:
                mark.append(k)
        if src:
            print("   [%2d] 外部: %s" % (i, src.group(1)[:100]))
        elif mark:
            print("   [%2d] 中身 %d文字  含む: %s" % (i, len(body), " ".join(mark)))
        elif len(body) > 2000:
            print("   [%2d] 中身 %d文字" % (i, len(body)))

    for key in (keyword, "humid", "HUMID"):
        hits = list(re.finditer(key, html))
        if not hits:
            continue
        print("  ── 「%s」 %d 箇所（先頭5件の前後）" % (key, len(hits)))
        for m in hits[:5]:
            s0 = max(0, m.start() - 200)
            around = " ".join(html[s0:m.start() + 300].split())
            print("     …%s…" % around[:420])


def probe_urls(url):
    """ページの中に書かれているURLらしきものを並べる。"""
    print("=" * 70)
    print("■ URL 調べ: %s" % url)
    try:
        html = collect.fetch(url)
    except Exception as e:                       # noqa: BLE001
        print("  取得できませんでした: %s" % e)
        return
    found = set()
    for m in re.finditer(r"""['\"(]([a-zA-Z0-9_./:-]*(?:api|\.json|/json)[a-zA-Z0-9_./?=&:%-]*)""", html):
        u = m.group(1)
        if len(u) > 8 and not u.endswith(".js"):
            found.add(u)
    print("  api / json を含むURLらしきもの: %d 件（先頭40件）" % len(found))
    for u in sorted(found)[:40]:
        print("   %s" % u[:150])


def probe_links(url, keyword):
    print("=" * 70)
    print("■ リンク探し: %s（含む文字: %s）" % (url, keyword))
    try:
        html = collect.fetch(url)
    except Exception as e:                       # noqa: BLE001
        print("  取得できませんでした: %s" % e)
        return
    p = LinkParser()
    p.feed(html)
    hits = [(h, t) for h, t in p.links if keyword in t or keyword in (h or "")]
    print("  一致 %d 件（先頭30件）" % len(hits))
    for h, t in hits[:30]:
        print("   %-60s %s" % (h[:60], t[:24]))


def main():
    ap = argparse.ArgumentParser(description="ページの作りを調べる")
    ap.add_argument("--url", action="append", default=[], help="調べるURL（複数可）")
    ap.add_argument("--links", default=None, help="リンクを探すページ")
    ap.add_argument("--scripts", default=None, help="script の中身を見るページ")
    ap.add_argument("--urls", default=None, help="ページ内のURLを並べる")
    ap.add_argument("--keyword", default="宇都宮", help="リンク探しの手がかり")
    args = ap.parse_args()

    if args.scripts:
        probe_scripts(args.scripts, args.keyword)
        return 0

    if args.urls:
        probe_urls(args.urls)
        return 0

    if args.links:
        probe_links(args.links, args.keyword)
        return 0

    if args.url:
        for u in args.url:
            probe(u, u)
        return 0

    with open(SETTINGS, encoding="utf-8") as f:
        settings = json.load(f)
    for name, conf in (settings.get("sources") or {}).items():
        if conf.get("url"):
            probe(name, conf["url"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
