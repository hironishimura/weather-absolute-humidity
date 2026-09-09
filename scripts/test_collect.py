#!/usr/bin/env python3
"""collect.py の読み取り処理を確かめる。

実際のページは取りに行かない。よくある形の時系列表を組み立てて、
そこから気温と湿度を拾えるかどうかだけを見る。

    python3 scripts/weather/test_collect.py
"""

import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import collect  # noqa: E402
import collect_browser  # noqa: E402

JST = timezone(timedelta(hours=9))
NOW = datetime(2026, 9, 8, 14, 30, tzinfo=JST)

# 見出しが左端にある形（Yahoo!天気の時系列表に近い）
ROW_HTML = """
<html><body>
<table class="yjw_table">
  <tr><td>時刻</td><td>15時</td><td>16時</td><td>17時</td></tr>
  <tr><td>天気</td><td>晴れ</td><td>くもり</td><td>くもり</td></tr>
  <tr><td>気温（℃）</td><td>25.0</td><td>24.4</td><td>23.8</td></tr>
  <tr><td>湿度（％）</td><td>64</td><td>68</td><td>72</td></tr>
  <tr><td>降水量（mm/h）</td><td>0.0</td><td>0.0</td><td>0.5</td></tr>
</table>
</body></html>
"""

# 見出しが1行目にある形
COL_HTML = """
<html><body>
<table>
  <thead><tr><th>時刻</th><th>天気</th><th>気温</th><th>湿度</th></tr></thead>
  <tbody>
    <tr><td>15:00</td><td>晴</td><td>25.0℃</td><td>64%</td></tr>
    <tr><td>16:00</td><td>曇</td><td>24.4℃</td><td>68%</td></tr>
    <tr><td>17:00</td><td>曇</td><td>23.8℃</td><td>72%</td></tr>
  </tbody>
</table>
</body></html>
"""

# ウェザーニュースの実況欄に近い形
OBS_HTML = """
<html><body>
<ul class="list">
  <li class="obs_block"><p class="title">気温</p><div class="obs_content">
    <div class="inner"><p class="value">26.7</p></div><p class="unit">\u2103</p></div></li>
  <li class="obs_block"><p class="title">湿度</p><div class="obs_content">
    <div class="inner"><p class="value">94</p></div><p class="unit">%</p></div></li>
  <li class="obs_block"><p class="title">気圧</p><div class="obs_content">
    <div class="inner"><p class="value">988</p></div><p class="unit">hPa</p></div></li>
  <li class="obs_block"><p class="title">風</p><div class="obs_content">
    <div class="inner"><p class="value">1.6</p></div><p class="unit">m/s</p></div></li>
</ul>
</body></html>
"""

# Yahoo!天気のように、同じ形の表が「今日」「明日」と2つ並ぶ形
TWO_TABLE_HTML = ROW_HTML + """\n<table class="yjw_table">\n  <tr><td>時刻</td><td>15時</td><td>18時</td></tr>\n  <tr><td>気温（℃）</td><td>18.0</td><td>17.0</td></tr>\n  <tr><td>湿度（％）</td><td>90</td><td>92</td></tr>\n</table>\n"""

JSON_HTML = """
<html><body>
<script type="application/json">
{"page":{"forecast":[
  {"datetime":"2026-09-08T15:00","temperature":25.0,"humidity":64},
  {"datetime":"2026-09-08T16:00","temperature":24.4,"humidity":68},
  {"datetime":"2026-09-08T17:00","temperature":23.8,"humidity":72}
]}}
</script>
</body></html>
"""


class 表の読み取り(unittest.TestCase):

    def test_見出しが左端の表(self):
        got = collect.series_from_html(ROW_HTML)
        self.assertIsNotNone(got)
        times, temps, hums = got
        self.assertEqual(times, ["15時", "16時", "17時"])
        self.assertEqual(temps, ["25.0", "24.4", "23.8"])
        self.assertEqual(hums, ["64", "68", "72"])

    def test_見出しが1行目の表(self):
        got = collect.series_from_html(COL_HTML)
        self.assertIsNotNone(got)
        times, temps, hums = got
        self.assertEqual(times, ["15:00", "16:00", "17:00"])
        self.assertEqual(temps, ["25.0℃", "24.4℃", "23.8℃"])

    def test_湿度がない表は使わない(self):
        html = "<table><tr><td>時刻</td><td>15時</td></tr><tr><td>気温</td><td>25</td></tr></table>"
        self.assertIsNone(collect.series_from_html(html))

    def test_表がなければNone(self):
        self.assertIsNone(collect.series_from_html("<html><body><p>なにもない</p></body></html>"))

    def test_scriptの中身は拾わない(self):
        html = ROW_HTML.replace("<table", "<script>var x='湿度';</script><table")
        got = collect.series_from_html(html)
        self.assertEqual(got[2], ["64", "68", "72"])


class 実況の読み取り(unittest.TestCase):

    def test_見出しと値の組から読む(self):
        got = collect.current_from_blocks(OBS_HTML)
        self.assertEqual(got["temp"], 26.7)
        self.assertEqual(got["humidity"], 94.0)
        self.assertEqual(got["pressure"], 988.0)

    def test_風は拾わない(self):
        self.assertNotIn("wind", collect.current_from_blocks(OBS_HTML))

    def test_湿度がなければNone(self):
        html = OBS_HTML.replace("湿度", "降水量")
        self.assertIsNone(collect.current_from_blocks(html))

    def test_実況として扱う(self):
        r = collect.collect_one("wni", {"enabled": True, "url": "http://example.test/"},
                                html=OBS_HTML, now=NOW)
        self.assertTrue(r["ok"])
        self.assertFalse(r["current_is_forecast"])
        self.assertEqual(r["current"]["temp"], 26.7)
        self.assertEqual(r["current"]["pressure"], 988.0)
        self.assertIn("実況", r["strategy"])


class 表が2つ並ぶ形(unittest.TestCase):

    def test_両方読んでつなげる(self):
        r = collect.collect_one("yahoo", {"enabled": True, "url": "http://example.test/"},
                                html=TWO_TABLE_HTML, now=NOW)
        self.assertTrue(r["ok"])
        self.assertEqual(len(r["hourly"]), 5)
        self.assertIn("table×2", r["strategy"])

    def test_2つめは翌日になる(self):
        r = collect.collect_one("yahoo", {"enabled": True, "url": "http://example.test/"},
                                html=TWO_TABLE_HTML, now=NOW)
        times = [x["time"] for x in r["hourly"]]
        self.assertEqual(times[0], "2026-09-08T15:00:00+09:00")
        self.assertEqual(times[2], "2026-09-08T17:00:00+09:00")
        self.assertEqual(times[3], "2026-09-09T15:00:00+09:00")
        self.assertEqual(times[4], "2026-09-09T18:00:00+09:00")

    def test_読める表を全部返す(self):
        got = collect.series_all_from_html(TWO_TABLE_HTML)
        self.assertEqual(len(got), 2)
        self.assertEqual(got[1][1], ["18.0", "17.0"])


class 埋め込みJSONの読み取り(unittest.TestCase):

    def test_配列から拾う(self):
        got = collect.series_from_json(JSON_HTML)
        self.assertIsNotNone(got)
        self.assertEqual(got[1], [25.0, 24.4, 23.8])
        self.assertEqual(got[2], [64, 68, 72])


class 時刻の組み立て(unittest.TestCase):

    def test_時刻と値がそろう(self):
        rows = collect.build_hourly(["15時", "16時", "17時"], ["25.0", "24.4", "23.8"],
                                    ["64", "68", "72"], now=NOW)
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]["time"], "2026-09-08T15:00:00+09:00")
        self.assertEqual(rows[0]["temp"], 25.0)
        self.assertEqual(rows[2]["humidity"], 72.0)

    def test_日付をまたぐ(self):
        rows = collect.build_hourly(["23時", "0時", "1時"], ["20", "19", "18"],
                                    ["80", "82", "85"], now=NOW)
        self.assertEqual(rows[0]["time"], "2026-09-08T23:00:00+09:00")
        self.assertEqual(rows[1]["time"], "2026-09-09T00:00:00+09:00")
        self.assertEqual(rows[2]["time"], "2026-09-09T01:00:00+09:00")

    def test_ISO形式の時刻(self):
        rows = collect.build_hourly(["2026-09-08T15:00"], ["25.0"], ["64"], now=NOW)
        self.assertEqual(rows[0]["time"], "2026-09-08T15:00:00+09:00")

    def test_ありえない値は捨てる(self):
        rows = collect.build_hourly(["15時", "16時", "17時"], ["25.0", "999", "23.8"],
                                    ["64", "68", "180"], now=NOW)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["temp"], 25.0)

    def test_値が読めない欄は飛ばす(self):
        rows = collect.build_hourly(["15時", "16時"], ["25.0", "---"], ["64", "68"], now=NOW)
        self.assertEqual(len(rows), 1)

    def test_時刻がなくても現在から並べる(self):
        rows = collect.build_hourly(None, ["25.0", "24.4"], ["64", "68"], now=NOW)
        self.assertEqual(rows[0]["time"], "2026-09-08T14:00:00+09:00")
        self.assertEqual(rows[1]["time"], "2026-09-08T15:00:00+09:00")


class いまに一番近い値(unittest.TestCase):

    def test_近い1点を選ぶ(self):
        rows = collect.build_hourly(["14時", "15時", "16時"], ["24", "25", "24"],
                                    ["66", "64", "68"], now=NOW)
        cur = collect.nearest_now(rows, now=NOW)
        self.assertEqual(cur["time"], "2026-09-08T14:00:00+09:00")

    def test_離れすぎていたら使わない(self):
        rows = collect.build_hourly(["20時"], ["22"], ["75"], now=NOW)
        self.assertIsNone(collect.nearest_now(rows, now=NOW))


class 提供元ごとの処理(unittest.TestCase):

    def test_使わない設定なら理由を返す(self):
        r = collect.collect_one("yahoo", {"enabled": False})
        self.assertFalse(r["ok"])
        self.assertIn("enabled", r["error"])

    def test_読めたら中身が入る(self):
        r = collect.collect_one("yahoo", {"enabled": True, "url": "http://example.test/",
                                          "label": "宇都宮"}, html=ROW_HTML, now=NOW)
        self.assertTrue(r["ok"])
        self.assertEqual(r["strategy"], "table×1")
        self.assertEqual(len(r["hourly"]), 3)
        self.assertEqual(r["label"], "宇都宮")
        self.assertTrue(r["current_is_forecast"])

    def test_表がなければJSONを試す(self):
        r = collect.collect_one("wni", {"enabled": True, "url": "http://example.test/"},
                                html=JSON_HTML, now=NOW)
        self.assertTrue(r["ok"])
        self.assertEqual(r["strategy"], "json")

    def test_nowを渡さなくても動く(self):
        r = collect.collect_one("wni", {"enabled": True, "url": "http://example.test/"},
                                html=OBS_HTML)
        self.assertTrue(r["ok"])
        self.assertEqual(r["current"]["temp"], 26.7)

    def test_読めないページは理由を残す(self):
        r = collect.collect_one("yahoo", {"enabled": True, "url": "http://example.test/"},
                                html="<html><body>売り切れ</body></html>", now=NOW)
        self.assertFalse(r["ok"])
        self.assertIn("読み取れませんでした", r["error"])


WN_TEXT = """最新見解
日
時
天気
降水
気温
風
9日(水)
9
1ミリ
26℃
7m/s
10
0ミリ
28℃
5m/s
10日(木)
0
1ミリ
19℃
1m/s
"""


class 画面テキストからの読み取り(unittest.TestCase):

    def test_時刻と気温を拾う(self):
        rows = collect.hourly_from_text(WN_TEXT, NOW)
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]["time"], "2026-09-09T09:00:00+09:00")
        self.assertEqual(rows[0]["temp"], 26.0)
        self.assertEqual(rows[2]["time"], "2026-09-10T00:00:00+09:00")

    def test_湿度は入らない(self):
        rows = collect.hourly_from_text(WN_TEXT, NOW)
        self.assertNotIn("humidity", rows[0])

    def test_日付の見出しがなければ何も拾わない(self):
        text = WN_TEXT.replace("9日(水)", "").replace("10日(木)", "")
        self.assertEqual(collect.hourly_from_text(text, NOW), [])

    def test_月をまたぐ(self):
        text = "1日(木)\n9\n0ミリ\n15℃\n2m/s\n"
        rows = collect.hourly_from_text(text, datetime(2026, 9, 29, 12, 0, tzinfo=JST))
        self.assertEqual(rows[0]["time"], "2026-10-01T09:00:00+09:00")

    def test_ありえない気温は捨てる(self):
        text = "9日(水)\n9\n0ミリ\n999℃\n2m/s\n"
        self.assertEqual(collect.hourly_from_text(text, NOW), [])


class ブラウザで読んだ結果の扱い(unittest.TestCase):

    def test_画面テキストの並びを足す(self):
        base = {"ok": True, "hourly": [{"time": "2026-09-09T09:00:00+09:00",
                                        "temp": 27.0, "humidity": 88.0}], "strategy": "実況"}
        extra = [{"time": "2026-09-09T09:00:00+09:00", "temp": 26.0},
                 {"time": "2026-09-09T10:00:00+09:00", "temp": 28.0}]
        got = collect_browser.add_hourly(base, extra)
        self.assertEqual(len(got["hourly"]), 2)
        self.assertEqual(got["hourly"][0]["temp"], 27.0)   # もとの値を上書きしない
        self.assertEqual(got["hourly"][0]["humidity"], 88.0)
        self.assertEqual(got["hourly"][1]["temp"], 28.0)
        self.assertIn("画面テキスト", got["strategy"])

    def test_前が失敗でも並びだけで作る(self):
        base = {"ok": False, "url": "http://example.test/", "error": "読めません"}
        extra = [{"time": "2026-09-09T09:00:00+09:00", "temp": 26.0}]
        got = collect_browser.add_hourly(base, extra, {"label": "宇都宮"})
        self.assertTrue(got["ok"])
        self.assertEqual(got["label"], "宇都宮")
        self.assertEqual(len(got["hourly"]), 1)

    def test_足すものがなければそのまま(self):
        base = {"ok": True, "hourly": [], "strategy": "実況"}
        self.assertEqual(collect_browser.add_hourly(base, []), base)


    def test_増えていれば入れ替える(self):
        old = {"ok": True, "hourly": [1, 2]}
        new = {"ok": True, "hourly": [1, 2, 3], "strategy": "table×1"}
        got = collect_browser.pick_better(old, new)
        self.assertEqual(len(got["hourly"]), 3)
        self.assertIn("ブラウザ", got["strategy"])

    def test_増えていなければ触らない(self):
        old = {"ok": True, "hourly": [1, 2, 3]}
        new = {"ok": True, "hourly": [1, 2]}
        self.assertIsNone(collect_browser.pick_better(old, new))

    def test_前が失敗なら入れ替える(self):
        old = {"ok": False, "error": "読めません"}
        new = {"ok": True, "hourly": [], "strategy": "実況"}
        self.assertIsNotNone(collect_browser.pick_better(old, new))

    def test_実況の現在値は残す(self):
        old = {"ok": True, "hourly": [], "current": {"temp": 26.7, "humidity": 94},
               "current_is_forecast": False}
        new = {"ok": True, "hourly": [1, 2], "current": {"temp": 25, "humidity": 80},
               "current_is_forecast": True, "strategy": "table×1"}
        got = collect_browser.pick_better(old, new)
        self.assertEqual(got["current"]["temp"], 26.7)
        self.assertFalse(got["current_is_forecast"])
        self.assertEqual(len(got["hourly"]), 2)

    def test_もとの結果は書き換えない(self):
        old = {"ok": True, "hourly": []}
        new = {"ok": True, "hourly": [1], "strategy": "実況"}
        collect_browser.pick_better(old, new)
        self.assertEqual(new["strategy"], "実況")


if __name__ == "__main__":
    unittest.main(verbosity=2)
