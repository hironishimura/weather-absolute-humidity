#!/usr/bin/env python3
"""地名から緯度経度を引く取得先を確かめる。

見るのは3つ:
  1. 応答があるか（状態・中身の形）
  2. ブラウザから直接読めるか（CORSの許可ヘッダがあるか）
  3. 日本の地名をどこまで細かく引けるか
"""

import json
import urllib.error
import urllib.parse
import urllib.request

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")

QUERIES = ["宇都宮市", "栃木県宇都宮市平出町", "東京駅", "札幌市中央区", "鹿沼市"]


def get(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "application/json,*/*",
        "Origin": "https://hironishimura.github.io",
    })
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, dict(r.headers), r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers or {}), (e.read() or b"").decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        return None, {}, "取れませんでした: %s" % e


def cors(headers):
    v = headers.get("Access-Control-Allow-Origin")
    return v if v else "（許可ヘッダなし＝ブラウザから直接は読めない）"


print("=" * 64)
print("1. 国土地理院 住所検索")
print("=" * 64)
for q in QUERIES:
    url = "https://msearch.gsi.go.jp/address-search/AddressSearch?q=" + urllib.parse.quote(q)
    code, h, body = get(url)
    print("-" * 64)
    print("問い合わせ:", q, " 状態:", code, " CORS:", cors(h))
    try:
        d = json.loads(body)
        print("件数:", len(d))
        for item in d[:3]:
            g = item.get("geometry", {}).get("coordinates", [])
            p = item.get("properties", {})
            print("   %-28s lon=%s lat=%s  (%s)"
                  % (p.get("title"), g[0] if g else "?", g[1] if len(g) > 1 else "?",
                     p.get("addressCode")))
    except Exception as e:  # noqa: BLE001
        print("読めません:", e, body[:160])

print()
print("=" * 64)
print("2. Open-Meteo Geocoding")
print("=" * 64)
for q in QUERIES:
    url = ("https://geocoding-api.open-meteo.com/v1/search?name="
           + urllib.parse.quote(q) + "&count=5&language=ja&format=json")
    code, h, body = get(url)
    print("-" * 64)
    print("問い合わせ:", q, " 状態:", code, " CORS:", cors(h))
    try:
        d = json.loads(body)
        results = d.get("results") or []
        print("件数:", len(results))
        for r in results[:3]:
            print("   %-20s %-10s lat=%.4f lon=%.4f  %s / %s"
                  % (r.get("name"), r.get("country_code"), r.get("latitude"),
                     r.get("longitude"), r.get("admin1"), r.get("admin2")))
    except Exception as e:  # noqa: BLE001
        print("読めません:", e, body[:160])
