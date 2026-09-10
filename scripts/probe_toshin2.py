#!/usr/bin/env python3
"""東進の天気が 403 になる理由を突き止める。

- 403 の中身は何か（Cloudflare の門前払いか、サイト自身の拒否か）
- ヘッダを変えれば通るのか
- 本物のブラウザ（Chromium）なら通るのか
"""

import gzip
import io
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://www.toshin.com"
CITY = BASE + "/weather/city?pref=" + urllib.parse.quote("栃木県")
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")


def get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            raw = res.read()
            if res.headers.get("Content-Encoding") == "gzip":
                raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
            return res.status, dict(res.headers), raw.decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        raw = e.read() or b""
        try:
            if (e.headers or {}).get("Content-Encoding") == "gzip":
                raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
        except Exception:
            pass
        return e.code, dict(e.headers or {}), raw.decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        return None, {}, "取れませんでした: %s" % e


print("=" * 60)
print("1. 403 の中身とヘッダ")
print("=" * 60)
code, headers, body = get(CITY, {"User-Agent": UA, "Accept-Encoding": "gzip"})
print("状態:", code)
for k, v in headers.items():
    print("  %-22s %s" % (k, str(v)[:110]))
print("-" * 60)
print(body[:1200])

print()
print("=" * 60)
print("2. ほかのページはどうか")
print("=" * 60)
for path in ["/", "/weather/", "/weather/city", "/robots.txt", "/sitemap.xml"]:
    c, h, b = get(BASE + path, {"User-Agent": UA})
    print("%-16s %s  cf-mitigated=%s  %d文字" %
          (path, c, h.get("cf-mitigated"), len(b)))

print()
print("=" * 60)
print("3. ヘッダを変えたら通るか")
print("=" * 60)
tries = {
    "素のPython": {},
    "UAだけ": {"User-Agent": UA},
    "ブラウザ風一式": {
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "ja,en-US;q=0.9,en;q=0.8",
        "Referer": BASE + "/weather/",
        "sec-ch-ua": '"Chromium";v="124", "Not:A-Brand";v="24"',
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": '"macOS"',
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "same-origin",
        "Upgrade-Insecure-Requests": "1",
    },
    "検索エンジン風": {"User-Agent": "Mozilla/5.0 (compatible; Googlebot/2.1; "
                                "+http://www.google.com/bot.html)"},
}
for name, h in tries.items():
    c, hh, b = get(CITY, h)
    print("%-14s %s  %d文字  cf-mitigated=%s" % (name, c, len(b), hh.get("cf-mitigated")))
