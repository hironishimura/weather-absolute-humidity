#!/usr/bin/env python3
"""本物のブラウザ（Chromium）なら東進の天気が見られるかを確かめる。

見られるなら、止めているのは「機械らしさ」であって回線ではない、と分かる。
中身の作り（表の形・刻み・湿度の有無）もここで見る。
"""

import re
import urllib.parse

from playwright.sync_api import sync_playwright

URL = "https://www.toshin.com/weather/city?pref=" + urllib.parse.quote("栃木県")


def main():
    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context(locale="ja-JP", timezone_id="Asia/Tokyo",
                            viewport={"width": 1280, "height": 900})
        page = ctx.new_page()
        res = page.goto(URL, wait_until="domcontentloaded", timeout=45000)
        print("状態     :", res.status if res else "(応答なし)")
        print("最終URL  :", page.url)
        page.wait_for_timeout(2500)
        html = page.content()
        print("大きさ   :", len(html), "文字")
        print("題名     :", page.title())

        for key in ("湿度", "気温", "降水", "体感", "風速"):
            print("  「%s」の字 %s" % (key, "あり" if key in html else "なし"))

        tables = page.locator("table")
        print("表の数   :", tables.count())
        for i in range(min(tables.count(), 4)):
            rows = tables.nth(i).locator("tr")
            print("-- 表%d（%d行）" % (i, rows.count()))
            for j in range(min(rows.count(), 8)):
                txt = rows.nth(j).inner_text().replace("\n", " | ")
                print("   ", txt[:180])

        links = page.locator("a")
        n = links.count()
        print("リンク数 :", n)
        seen = 0
        for i in range(n):
            href = links.nth(i).get_attribute("href") or ""
            if "city" in href or "point" in href:
                print("   ", href[:90], "|", (links.nth(i).inner_text() or "")[:20])
                seen += 1
                if seen >= 15:
                    break

        # 1時間ごとの表がありそうな市のページも見る
        cand = [l for l in
                [links.nth(i).get_attribute("href") or "" for i in range(n)]
                if "city" in l and "pref" in l]
        if cand:
            nxt = urllib.parse.urljoin(page.url, cand[0])
            print("\n== 市のページ:", nxt)
            page.goto(nxt, wait_until="domcontentloaded", timeout=45000)
            page.wait_for_timeout(2500)
            h2 = page.content()
            print("大きさ:", len(h2), "文字　題名:", page.title())
            for key in ("湿度", "気温", "降水量", "体感", "風"):
                print("  「%s」の字 %s" % (key, "あり" if key in h2 else "なし"))
            t2 = page.locator("table")
            print("表の数:", t2.count())
            for i in range(min(t2.count(), 5)):
                rows = t2.nth(i).locator("tr")
                print("-- 表%d（%d行）" % (i, rows.count()))
                for j in range(min(rows.count(), 10)):
                    print("   ", rows.nth(j).inner_text().replace("\n", " | ")[:200])
            # 湿度らしき数字の並びを拾ってみる
            m = re.findall(r"(\d{1,3})\s*%", h2)
            print("%%つきの数字（先頭20）:", m[:20])

        b.close()


if __name__ == "__main__":
    main()
