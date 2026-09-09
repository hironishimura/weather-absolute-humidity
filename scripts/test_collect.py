#!/usr/bin/env python3
"""collect.py の読み取り処理を確かめる。

実際のページは取りに行かない。よくある形の時系列表を組み立てて、
そこから気温と湿度を拾えるかどうかだけを見る。

    python3 scripts/weather/test_collect.py
"""

import os
import re
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import collect  # noqa: E402
import collect_browser  # noqa: E402
import verify  # noqa: E402

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


WEEK_HTML = """
<table>
 <tr><td>日付</td><td>9月11日 (金)</td><td>9月12日 (土)</td><td>9月13日 (日)</td></tr>
 <tr><td>天気</td><td>くもり</td><td>雨</td><td>晴れ</td></tr>
 <tr><td>気温（℃）</td><td>28 19</td><td>26 20</td><td>29</td></tr>
 <tr><td>降水 確率（％）</td><td>40</td><td>70</td><td>---</td></tr>
</table>
"""


POP6_HTML = """
<table><tr><td>時間</td><td>0-6</td><td>6-12</td><td>12-18</td><td>18-24</td></tr>
<tr><td>降水</td><td>10%</td><td>20%</td><td>70%</td><td>80%</td></tr></table>
<table><tr><td>時間</td><td>0-6</td><td>6-12</td><td>12-18</td><td>18-24</td></tr>
<tr><td>降水</td><td>60%</td><td>60%</td><td>20%</td><td>20%</td></tr></table>
"""

POP12_HTML = """
<table><tr><td>時間</td><td>午前</td><td>午後</td></tr>
<tr><td>降水確率</td><td>90%</td><td>80%</td></tr></table>
"""


class 時間帯ごとの降水確率(unittest.TestCase):

    def test_6時間ごと(self):
        got = collect.pops_from_html(POP6_HTML, NOW)
        self.assertEqual(len(got), 8)
        self.assertEqual(got[0]["time"], "2026-09-08T00:00:00+09:00")
        self.assertEqual(got[0]["hours"], 6)
        self.assertEqual(got[0]["pop"], 10.0)

    def test_2枚目は翌日(self):
        got = collect.pops_from_html(POP6_HTML, NOW)
        self.assertEqual(got[4]["time"], "2026-09-09T00:00:00+09:00")
        self.assertEqual(got[4]["pop"], 60.0)

    def test_午前午後(self):
        got = collect.pops_from_html(POP12_HTML, NOW)
        self.assertEqual(len(got), 2)
        self.assertEqual(got[0]["hours"], 12)
        self.assertEqual(got[1]["time"], "2026-09-08T12:00:00+09:00")
        self.assertEqual(got[1]["pop"], 80.0)

    def test_降水量の表は使わない(self):
        html = POP6_HTML.replace("降水", "降水量")
        self.assertEqual(collect.pops_from_html(html, NOW), [])

    def test_時刻の見出しが範囲でなければ使わない(self):
        html = POP6_HTML.replace("0-6", "0時").replace("6-12", "3時")
        self.assertEqual(collect.pops_from_html(html, NOW), [])

    def test_結果に入る(self):
        r = collect.collect_one("yahoo", {"enabled": True, "url": "http://example.test/"},
                                html=POP6_HTML, now=NOW)
        self.assertTrue(r["ok"])
        self.assertEqual(len(r["pops"]), 8)
        self.assertIn("降水確率", r["strategy"])


class 週間予報の読み取り(unittest.TestCase):

    def test_日付と気温と降水確率(self):
        got = collect.weekly_from_html(WEEK_HTML, NOW)
        self.assertEqual(len(got), 3)
        self.assertEqual(got[0]["date"], "2026-09-11")
        self.assertEqual(got[0]["weather"], "くもり")
        self.assertEqual(got[0]["temp_max"], 28.0)
        self.assertEqual(got[0]["temp_min"], 19.0)
        self.assertEqual(got[0]["pop"], 40.0)

    def test_片方しかない気温(self):
        got = collect.weekly_from_html(WEEK_HTML, NOW)
        self.assertEqual(got[2]["temp_max"], 29.0)
        self.assertNotIn("temp_min", got[2])

    def test_読めない降水確率は入れない(self):
        got = collect.weekly_from_html(WEEK_HTML, NOW)
        self.assertNotIn("pop", got[2])

    def test_年をまたぐ(self):
        html = WEEK_HTML.replace("9月11日 (金)", "1月5日 (月)")
        got = collect.weekly_from_html(html, datetime(2026, 12, 28, 12, 0, tzinfo=JST))
        self.assertEqual(got[0]["date"], "2027-01-05")

    def test_日付の行がなければ空(self):
        html = WEEK_HTML.replace("日付", "見出し")
        self.assertEqual(collect.weekly_from_html(html, NOW), [])

    def test_結果に入る(self):
        r = collect.collect_one("yahoo", {"enabled": True, "url": "http://example.test/"},
                                html=WEEK_HTML, now=NOW)
        self.assertTrue(r["ok"])
        self.assertEqual(len(r["weekly"]), 3)
        self.assertIn("週間", r["strategy"])


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


# =========================================================
# verify.py（降水確率の当たり具合）
# =========================================================
NOW_V = datetime(2026, 9, 9, 15, 0, tzinfo=JST)


class 期間の切り方(unittest.TestCase):
    def test_7日前から3日前は1日ごと(self):
        got = verify.periods(NOW_V)
        day = [(s, h) for (s, h) in got if h == 24]
        self.assertEqual(len(day), 4)
        self.assertEqual(day[0][0], datetime(2026, 9, 2, 0, 0, tzinfo=JST))
        self.assertEqual(day[-1][0], datetime(2026, 9, 5, 0, 0, tzinfo=JST))

    def test_直近3日は半日ごと(self):
        got = verify.periods(NOW_V)
        half = [(s, h) for (s, h) in got if h == 12]
        # 6日〜8日の午前午後で6つ、9日は午前だけ終わっている
        self.assertEqual(len(half), 7)
        self.assertEqual(half[0][0], datetime(2026, 9, 6, 0, 0, tzinfo=JST))
        self.assertEqual(half[-1][0], datetime(2026, 9, 9, 0, 0, tzinfo=JST))

    def test_終わっていない期間は返さない(self):
        for start, hours in verify.periods(NOW_V):
            self.assertLessEqual(start + timedelta(hours=hours), NOW_V)

    def test_順番は古いものから(self):
        got = verify.periods(NOW_V)
        self.assertEqual(got, sorted(got))


class 予報の書きため(unittest.TestCase):
    LATEST = {
        "places": [{
            "id": "utsunomiya", "label": "栃木県宇都宮市",
            "sources": {
                "jma": {"ok": True,
                        "pops": [{"time": "2026-09-10T06:00:00+09:00", "hours": 6, "pop": 30}],
                        "weekly": [{"date": "2026-09-11", "pop": 60}]},
                "yahoo": {"ok": False, "pops": [{"time": "2026-09-10T06:00:00+09:00",
                                                 "hours": 6, "pop": 10}]},
            },
        }],
    }

    def test_取り出せる(self):
        got = verify.forecasts_in(self.LATEST)
        self.assertIn(("utsunomiya", "jma", "2026-09-10T06:00:00+09:00", 6, 30.0), got)
        self.assertIn(("utsunomiya", "jma", "2026-09-11T00:00:00+09:00", 24, 60.0), got)

    def test_失敗した提供元は使わない(self):
        got = verify.forecasts_in(self.LATEST)
        self.assertFalse([g for g in got if g[1] == "yahoo"])

    def test_降水確率がないものは飛ばす(self):
        latest = {"places": [{"id": "a", "sources": {"jma": {"ok": True, "pops": [
            {"time": "2026-09-10T06:00:00+09:00", "hours": 6, "pop": None},
            {"time": "2026-09-10T12:00:00+09:00", "hours": 6, "pop": "--"},
        ]}}}]}
        self.assertEqual(verify.forecasts_in(latest), [])

    def test_書きためて始まる前の予報を残す(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            verify.HISTORY = os.path.join(d, "history.json")
            added, total = verify.record(self.LATEST, NOW_V)
            self.assertEqual(added, 2)
            self.assertEqual(total, 2)
            # もう一度やっても増えない（同じ期間は上書き）
            added, total = verify.record(self.LATEST, NOW_V)
            self.assertEqual(total, 2)

    def test_もう始まっている期間は記録しない(self):
        import tempfile
        latest = {"places": [{"id": "a", "sources": {"jma": {"ok": True, "pops": [
            {"time": "2026-09-09T06:00:00+09:00", "hours": 6, "pop": 40},
        ]}}}]}
        with tempfile.TemporaryDirectory() as d:
            verify.HISTORY = os.path.join(d, "history.json")
            added, total = verify.record(latest, NOW_V)
            self.assertEqual(added, 0)


class 予報の取り出し(unittest.TestCase):
    ENTRIES = {
        "a|jma|2026-09-08T00:00:00+09:00|6": {"pop": 10},
        "a|jma|2026-09-08T06:00:00+09:00|6": {"pop": 70},
        "a|jma|2026-09-08T12:00:00+09:00|6": {"pop": 20},
        "a|yahoo|2026-09-08T00:00:00+09:00|24": {"pop": 50},
        "b|jma|2026-09-08T00:00:00+09:00|6": {"pop": 90},
    }

    def test_重なる区切りの最大値をとる(self):
        got = verify.pop_for(self.ENTRIES, "a", "jma",
                             datetime(2026, 9, 8, 0, 0, tzinfo=JST), 12)
        self.assertEqual(got, 70)

    def test_地点と提供元がちがえば使わない(self):
        got = verify.pop_for(self.ENTRIES, "a", "weathernews",
                             datetime(2026, 9, 8, 0, 0, tzinfo=JST), 12)
        self.assertIsNone(got)
        got = verify.pop_for(self.ENTRIES, "b", "jma",
                             datetime(2026, 9, 8, 0, 0, tzinfo=JST), 12)
        self.assertEqual(got, 90)

    def test_重なっていなければ使わない(self):
        got = verify.pop_for(self.ENTRIES, "a", "jma",
                             datetime(2026, 9, 9, 0, 0, tzinfo=JST), 12)
        self.assertIsNone(got)

    def test_1日の予報は半日にも使える(self):
        got = verify.pop_for(self.ENTRIES, "a", "yahoo",
                             datetime(2026, 9, 8, 12, 0, tzinfo=JST), 12)
        self.assertEqual(got, 50)


class 正解率(unittest.TestCase):
    def setUp(self):
        self.entries = {}
        self.cache = {}
        for i, (pop_jma, pop_yahoo, mm) in enumerate([
            (80, 20, 5.0),    # 降った → 気象庁は当たり、Yahoo!ははずれ
            (10, 10, 0.0),    # 降らない → どちらも当たり
            (60, 70, 0.0),    # 降らない → どちらもはずれ
            (0, 90, 3.0),     # 降った → 気象庁はずれ、Yahoo!当たり
        ]):
            start = datetime(2026, 9, 2, 0, 0, tzinfo=JST) + timedelta(days=i)
            self.entries["a|jma|%s|24" % start.isoformat()] = {"pop": pop_jma}
            self.entries["a|yahoo|%s|24" % start.isoformat()] = {"pop": pop_yahoo}
            self.cache["%s|24" % start.isoformat()] = {"mm": mm, "rain": mm >= 1.0}

    def test_当たった数を数える(self):
        rows, scores = verify.score("a", None, self.entries, self.cache,
                                    now=NOW_V, fetch=False)
        self.assertEqual(scores["jma"]["n"], 4)
        self.assertEqual(scores["jma"]["hit"], 2)
        self.assertEqual(scores["jma"]["rate"], 50.0)
        self.assertEqual(scores["yahoo"]["hit"], 2)

    def test_ブライアスコア(self):
        rows, scores = verify.score("a", None, self.entries, self.cache,
                                    now=NOW_V, fetch=False)
        # ((0.8-1)^2 + (0.1-0)^2 + (0.6-0)^2 + (0.0-1)^2) / 4 = 1.41 / 4
        self.assertEqual(scores["jma"]["brier"], 0.352)   # 1.41 / 4 = 0.3525 を小数3桁に

    def test_記録がなければ出さない(self):
        rows, scores = verify.score("a", None, {}, self.cache, now=NOW_V, fetch=False)
        self.assertEqual(scores, {})
        self.assertEqual(rows, [])

    def test_実際の雨がわからない期間は飛ばす(self):
        rows, scores = verify.score("a", None, self.entries, {}, now=NOW_V, fetch=False)
        self.assertEqual(rows, [])

    def test_予報のない期間は雨量を見に行かない(self):
        calls = []
        orig = verify.rain_mm
        verify.rain_mm = lambda st, s, h: (calls.append(s), 0.0)[1]
        try:
            verify.score("a", "41277", self.entries, {}, now=NOW_V, fetch=True)
        finally:
            verify.rain_mm = orig
        # 予報を入れた4期間だけ（半日の期間には予報がない）
        self.assertEqual(len(calls), 4)

    def test_期間の中身(self):
        rows, _ = verify.score("a", None, self.entries, self.cache,
                               now=NOW_V, fetch=False)
        self.assertEqual(len(rows), 4)
        self.assertEqual(rows[0]["hours"], 24)
        self.assertTrue(rows[0]["rain"])
        self.assertEqual(rows[0]["pops"]["jma"], 80)


class 予報区の選び方(unittest.TestCase):
    def test_近い予報区を選ぶ(self):
        self.assertEqual(verify.resolve_office(36.5551, 139.8828), "090000")   # 栃木県
        self.assertEqual(verify.resolve_office(35.6812, 139.7671), "130000")   # 東京都

    def test_アプリ側の表と中身が同じ(self):
        here = os.path.dirname(os.path.abspath(__file__))
        js = os.path.join(os.path.dirname(here), "docs/assets/app.js")
        with open(js, encoding="utf-8") as f:
            src = f.read()
        body = re.search(r"var OFFICES = \[(.*?)\n\];", src, re.S).group(1)
        found = re.findall(r"\['[^']+','(\d+)',([\d.]+),([\d.]+)\]", body)
        self.assertEqual(len(found), len(verify.OFFICES))
        for (code, la, lo), (c2, la2, lo2) in zip(found, verify.OFFICES):
            self.assertEqual(code, c2)
            self.assertAlmostEqual(float(la), la2, places=2)
            self.assertAlmostEqual(float(lo), lo2, places=2)


class 気象庁の降水確率(unittest.TestCase):
    FORECAST = [
        {"timeSeries": [
            {"timeDefines": ["2026-09-09T17:00:00+09:00"],
             "areas": [{"area": {"code": "090010"}, "weathers": ["くもり"]}]},
            {"timeDefines": ["2026-09-09T18:00:00+09:00", "2026-09-10T00:00:00+09:00",
                             "2026-09-10T06:00:00+09:00"],
             "areas": [{"area": {"code": "090010"}, "pops": ["20", "", "60"]}]},
        ]},
        {"timeSeries": [
            {"timeDefines": ["2026-09-11T00:00:00+09:00", "2026-09-12T00:00:00+09:00"],
             "areas": [{"area": {"code": "090000"}, "pops": ["", "30"]}]},
        ]},
    ]

    def setUp(self):
        self.calls = []
        self.orig = verify.get_json
        verify.get_json = lambda url: (self.calls.append(url), self.FORECAST)[1]

    def tearDown(self):
        verify.get_json = self.orig

    def test_6時間ごとと1日ごとを取り出す(self):
        got = verify.jma_pops({"lat": 36.5551, "lon": 139.8828})
        self.assertEqual(len(got), 3)
        self.assertEqual(got[0], (datetime(2026, 9, 9, 18, 0, tzinfo=JST), 6, 20.0))
        self.assertEqual(got[1], (datetime(2026, 9, 10, 6, 0, tzinfo=JST), 6, 60.0))
        self.assertEqual(got[2], (datetime(2026, 9, 12, 0, 0, tzinfo=JST), 24, 30.0))

    def test_空欄は飛ばす(self):
        got = verify.jma_pops({"lat": 36.5551, "lon": 139.8828})
        self.assertNotIn(datetime(2026, 9, 10, 0, 0, tzinfo=JST), [g[0] for g in got])

    def test_予報区を指定できる(self):
        verify.jma_pops({"lat": 0, "lon": 0, "office": "130000"})
        self.assertIn("130000", self.calls[0])


class 数値予報の降水確率(unittest.TestCase):
    METEO = {"hourly": {
        "time": ["2026-09-09T18:00", "2026-09-09T19:00", "2026-09-09T20:00"],
        "precipitation_probability": [10, None, 40],
    }}

    def setUp(self):
        self.calls = []
        self.orig = verify.get_json
        verify.get_json = lambda url: (self.calls.append(url), self.METEO)[1]

    def tearDown(self):
        verify.get_json = self.orig

    def test_1時間ごとに取り出す(self):
        got = verify.model_pops({"lat": 36.5551, "lon": 139.8828})
        self.assertEqual(len(got), 2)
        self.assertEqual(got[0], (datetime(2026, 9, 9, 18, 0, tzinfo=JST), 1, 10.0))
        self.assertEqual(got[1], (datetime(2026, 9, 9, 20, 0, tzinfo=JST), 1, 40.0))

    def test_モデルは指定しない(self):
        # 気象庁のモデルを指定すると降水確率が空で返るため、指定しません
        verify.model_pops({"lat": 36.5551, "lon": 139.8828})
        self.assertNotIn("models=", self.calls[0])
        self.assertIn("precipitation_probability", self.calls[0])


class 直接読む予報(unittest.TestCase):
    def test_読めなくても止まらない(self):
        orig = verify.get_json

        def boom(url):
            raise OSError("つながりません")
        verify.get_json = boom
        try:
            got = verify.direct_forecasts([{"id": "a", "lat": 36.5, "lon": 139.8}])
        finally:
            verify.get_json = orig
        self.assertEqual(got, [])

    def test_緯度経度がなければ飛ばす(self):
        self.assertEqual(verify.direct_forecasts([{"id": "a"}]), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
