#!/usr/bin/env python3
"""地名検索の詰め。確かめるのは3つ。

1. CORSの見方が正しいか（すでにブラウザから読めている先で対照をとる）
2. 国土地理院が遅いことがあるのか（取り直しで通るか）
3. 「問い合わせの字がtitleに入っているか」で絞れば、的外れを落とせるか
"""

import json
import time
import urllib.error
import urllib.parse
import urllib.request

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
GSI = "https://msearch.gsi.go.jp/address-search/AddressSearch?q="


def get(url, tries=3):
    for i in range(tries):
        req = urllib.request.Request(url, headers={
            "User-Agent": UA, "Accept": "application/json,*/*",
            "Origin": "https://hironishimura.github.io"})
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                return r.status, dict(r.headers), r.read().decode("utf-8", "replace"), i + 1
        except Exception as e:  # noqa: BLE001
            last = str(e)
            time.sleep(1.5)
    return None, {}, "取れませんでした: %s" % last, tries


print("=" * 64)
print("1. CORSの見方の対照（すでにブラウザから読めている先）")
print("=" * 64)
for name, url in [
    ("api.open-meteo.com（実績あり）",
     "https://api.open-meteo.com/v1/forecast?latitude=36.55&longitude=139.88&current=temperature_2m"),
    ("www.jma.go.jp（実績あり）",
     "https://www.jma.go.jp/bosai/common/const/area.json"),
    ("geocoding-api.open-meteo.com",
     "https://geocoding-api.open-meteo.com/v1/search?name=%E9%B9%BF%E6%B2%BC%E5%B8%82&count=3&language=ja&format=json"),
    ("msearch.gsi.go.jp",
     GSI + urllib.parse.quote("鹿沼市")),
]:
    code, h, body, tried = get(url, tries=2)
    print("%-34s 状態 %-5s CORS: %s" % (name, code, h.get("Access-Control-Allow-Origin") or "なし"))

print()
print("=" * 64)
print("2. 国土地理院は取り直せば通るか")
print("=" * 64)
for q in ["宇都宮市", "宇都宮市", "日光市"]:
    code, h, body, tried = get(GSI + urllib.parse.quote(q))
    n = "?"
    try:
        n = len(json.loads(body))
    except Exception:  # noqa: BLE001
        pass
    print("%-10s 状態 %-5s %s回目で成功 件数 %s" % (q, code, tried, n))

print()
print("=" * 64)
print("3. titleに問い合わせの字が入っているかで絞る")
print("=" * 64)
for q in ["東京駅", "鹿沼市", "栃木県宇都宮市平出町", "東京都千代田区丸の内",
          "日光市今市", "宇都宮市平出工業団地", "あああ"]:
    code, h, body, tried = get(GSI + urllib.parse.quote(q))
    try:
        d = json.loads(body)
    except Exception:  # noqa: BLE001
        print("%-18s 読めません" % q)
        continue
    hit = [x for x in d if q in (x.get("properties", {}).get("title") or "")]
    print("-" * 64)
    print("%s … 全%d件 → 字が入っているもの %d件" % (q, len(d), len(hit)))
    for x in (hit or d)[:4]:
        g = x.get("geometry", {}).get("coordinates", [])
        mark = "○" if x in hit else "×"
        print("   %s %-26s lat=%s lon=%s"
              % (mark, x.get("properties", {}).get("title"),
                 g[1] if len(g) > 1 else "?", g[0] if g else "?"))
