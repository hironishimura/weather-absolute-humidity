#!/usr/bin/env python3
"""降水確率が当たったかどうかを数える。

やっていること
  1. いまの予報（latest.json）の降水確率を history.json に書きためる。
     同じ期間の予報は上書きし、**その期間が始まる前の最後の予報**を残す。
  2. すでに終わった期間について、気象庁アメダスの実際の降水量を見る。
  3. 予報と実際をつき合わせて、提供元ごとの正解率を accuracy.json に書く。

期間の切り方（ご指定どおり）
  - 7日前〜3日前 … 1日ごと
  - 直近3日      … 半日ごと（0〜12時 / 12〜24時）

「雨が降った」の基準は 1mm 以上です。気象庁の降水確率が
「1mm以上の雨が降る確率」なので、それに合わせています。

正解の数え方は 降水確率50%以上を「降る予報」とみなし、実際と合っていれば正解。
あわせてブライアスコア（確率予報のずれ。0に近いほどよい）も出します。

    python3 scripts/verify.py            # 記録して照合する
    python3 scripts/verify.py --no-fetch # 記録だけ（外に出ない）
"""

import argparse
import json
import math
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import collect  # noqa: E402

JST = collect.JST
JMA = "https://www.jma.go.jp/bosai"
OPEN_METEO = "https://api.open-meteo.com/v1/forecast"
DATA = os.path.join(ROOT, "docs/data")
HISTORY = os.path.join(DATA, "history.json")
ACCURACY = os.path.join(DATA, "accuracy.json")
LATEST = os.path.join(DATA, "latest.json")

RAIN_MM = 1.0          # これ以上で「雨が降った」
SAY_RAIN = 50.0        # これ以上の降水確率を「降る予報」とみなす
KEEP_DAYS = 30         # 記録を残す日数


# =========================================================
# 記録
# =========================================================
def load_json(path, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (ValueError, OSError):
        return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def forecasts_in(latest):
    """latest.json から（地点, 提供元, 期間の開始, 何時間, 降水確率）を取り出す。"""
    out = []
    places = latest.get("places")
    if not places:
        places = [{"id": "default", "label": latest.get("label", ""),
                   "sources": latest.get("sources") or {}}]
    for place in places:
        pid = place.get("id", "default")
        for name, r in (place.get("sources") or {}).items():
            if not r.get("ok"):
                continue
            for p in (r.get("pops") or []):
                if collect.to_number(str(p.get("pop"))) is None:
                    continue
                out.append((pid, name, p["time"], int(p.get("hours", 6)), float(p["pop"])))
            for d in (r.get("weekly") or []):
                if not isinstance(d.get("pop"), (int, float)):
                    continue
                out.append((pid, name, d["date"] + "T00:00:00+09:00", 24, float(d["pop"])))
    return out


# 予報区（気象庁の府県予報区）のだいたいの位置。
# docs/assets/app.js の OFFICES と同じ中身です（test_collect.py で見比べています）。
OFFICES = [
    ("011000", 45.20, 142.10), ("012000", 44.00, 142.20), ("013000", 43.90, 143.90), ("014100", 43.30, 144.80),
    ("014030", 42.92, 143.20), ("015000", 42.60, 142.20), ("016000", 43.15, 141.45), ("017000", 41.90, 140.50),
    ("020000", 40.75, 140.80), ("030000", 39.60, 141.30), ("040000", 38.40, 140.90), ("050000", 39.80, 140.40),
    ("060000", 38.40, 140.20), ("070000", 37.40, 140.30), ("080000", 36.30, 140.30), ("090000", 36.70, 139.85),
    ("100000", 36.50, 138.95), ("110000", 36.00, 139.40), ("120000", 35.50, 140.20), ("130000", 35.69, 139.69),
    ("140000", 35.40, 139.35), ("150000", 37.50, 138.90), ("160000", 36.70, 137.20), ("170000", 36.70, 136.80),
    ("180000", 35.90, 136.30), ("190000", 35.60, 138.60), ("200000", 36.20, 138.10), ("210000", 35.80, 137.00),
    ("220000", 34.95, 138.40), ("230000", 35.10, 137.10), ("240000", 34.60, 136.40), ("250000", 35.20, 136.15),
    ("260000", 35.20, 135.50), ("270000", 34.65, 135.50), ("280000", 35.00, 134.90), ("290000", 34.40, 135.90),
    ("300000", 33.90, 135.50), ("310000", 35.40, 133.90), ("320000", 35.05, 132.60), ("330000", 34.85, 133.80),
    ("340000", 34.60, 132.80), ("350000", 34.20, 131.50), ("360000", 33.90, 134.30), ("370000", 34.20, 134.00),
    ("380000", 33.75, 132.90), ("390000", 33.50, 133.40), ("400000", 33.60, 130.60), ("410000", 33.30, 130.10),
    ("420000", 33.00, 129.70), ("430000", 32.70, 130.80), ("440000", 33.20, 131.50), ("450000", 32.20, 131.30),
    ("460100", 31.70, 130.60), ("460040", 28.40, 129.50), ("471000", 26.50, 127.90), ("472000", 25.83, 131.23),
    ("473000", 24.80, 125.30), ("474000", 24.40, 124.20),
]


def resolve_office(lat, lon):
    """一番近い府県予報区を選ぶ。"""
    best = None
    for code, la, lo in OFFICES:
        d = (la - lat) ** 2 + ((lo - lon) * math.cos(math.radians(lat))) ** 2
        if best is None or d < best[0]:
            best = (d, code)
    return best[1] if best else None


def jma_pops(place):
    """気象庁の府県天気予報から降水確率を取り出す。[(開始, 何時間, %), ...]"""
    office = place.get("office") or resolve_office(place["lat"], place["lon"])
    data = get_json("%s/forecast/data/forecast/%s.json" % (JMA, office))
    out = []

    near = data[0] if data else None
    ts = (near or {}).get("timeSeries") or []
    if len(ts) > 1 and ts[1].get("areas"):
        a = ts[1]["areas"][0]
        for i, iso in enumerate(ts[1].get("timeDefines") or []):
            v = (a.get("pops") or [None])[i] if i < len(a.get("pops") or []) else None
            if v in ("", None):
                continue
            t = datetime.fromisoformat(iso)
            out.append((t, 6, float(v)))

    week = data[1] if len(data) > 1 else None
    wts = (week or {}).get("timeSeries") or []
    if wts and wts[0].get("areas"):
        b = wts[0]["areas"][0]
        for i, iso in enumerate(wts[0].get("timeDefines") or []):
            v = (b.get("pops") or [None])[i] if i < len(b.get("pops") or []) else None
            if v in ("", None):
                continue
            t = datetime.fromisoformat(iso)
            out.append((t.replace(hour=0, minute=0, second=0, microsecond=0), 24, float(v)))
    return out


def model_pops(place):
    """Open-Meteo の1時間ごとの降水確率。

    気象庁のモデル（MSM/GSM）そのものには降水確率が入っておらず、
    models=jma_seamless を付けると中身が全部からになります。
    そのため、Open-Meteo が各社のモデルをまとめて出している値をもらいます。
    アプリの表示（docs/assets/app.js の loadModel）と同じ扱いです。
    """
    url = ("%s?latitude=%.4f&longitude=%.4f&hourly=precipitation_probability"
           "&forecast_days=10&timezone=Asia%%2FTokyo"
           % (OPEN_METEO, place["lat"], place["lon"]))
    data = get_json(url)
    h = data.get("hourly") or {}
    times = h.get("time") or []
    vals = h.get("precipitation_probability") or []
    out = []
    for i, iso in enumerate(times):
        v = vals[i] if i < len(vals) else None
        if v is None:
            continue
        t = datetime.fromisoformat(iso)
        if t.tzinfo is None:
            t = t.replace(tzinfo=JST)
        out.append((t, 1, float(v)))
    return out


def direct_forecasts(places):
    """気象庁とOpen-Meteoは取り込みファイルを通さず、ここで直接読みます。"""
    out = []
    for place in places:
        pid = place.get("id", "default")
        if place.get("lat") is None or place.get("lon") is None:
            continue
        for src, fn in (("jma", jma_pops), ("model", model_pops)):
            try:
                for t, hours, pop in fn(place):
                    out.append((pid, src, t.isoformat(), hours, pop))
            except (urllib.error.URLError, urllib.error.HTTPError, OSError,
                    ValueError, KeyError, IndexError, TypeError) as e:
                print("   %s の予報を読めませんでした（%s）" % (src, e))
    return out


def record(latest, now=None, extra=None):
    """いまの予報を書きためる。期間が始まる前の最後の予報だけを残す。"""
    now = now or datetime.now(JST)
    hist = load_json(HISTORY, {"entries": {}})
    entries = hist.get("entries") or {}

    added = 0
    for pid, src, target, hours, pop in forecasts_in(latest) + list(extra or []):
        try:
            t0 = datetime.fromisoformat(target)
        except ValueError:
            continue
        if t0.tzinfo is None:
            t0 = t0.replace(tzinfo=JST)
        if t0 <= now:
            continue                      # もう始まっている期間の予報は使わない
        key = "%s|%s|%s|%d" % (pid, src, t0.isoformat(), hours)
        entries[key] = {"pop": pop, "captured": now.isoformat()}
        added += 1

    # 古い記録を捨てる
    limit = now - timedelta(days=KEEP_DAYS)
    for key in list(entries.keys()):
        try:
            t0 = datetime.fromisoformat(key.split("|")[2])
        except (ValueError, IndexError):
            del entries[key]
            continue
        if t0 < limit:
            del entries[key]

    hist["entries"] = entries
    hist["updated_at"] = now.isoformat()
    save_json(HISTORY, hist)
    return added, len(entries)


# =========================================================
# 実際に降ったかどうか
# =========================================================
def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": collect.USER_AGENT})
    with urllib.request.urlopen(req, timeout=collect.TIMEOUT) as res:
        return json.loads(res.read().decode("utf-8"))


_TABLE = {}


def amedas_table():
    """アメダスの一覧。一度読んだら使い回す。"""
    if not _TABLE:
        _TABLE.update(get_json(JMA + "/amedas/const/amedastable.json"))
    return _TABLE


def nearest_stations(lat, lon, count=6):
    """近い順にアメダス観測所を並べる。[(番号, 名前), ...]"""
    near = []
    for code, s in amedas_table().items():
        la, lo = s.get("lat"), s.get("lon")
        if not la or not lo:
            continue
        y = la[0] + la[1] / 60.0
        x = lo[0] + lo[1] / 60.0
        d = (y - lat) ** 2 + ((x - lon) * math.cos(math.radians(lat))) ** 2
        near.append((d, code, s.get("kjName", code)))
    near.sort()
    return [(c, n) for (_, c, n) in near[:count]]


def pick_station(lat, lon, start, hours):
    """近い順にためして、降水量が実際に読める観測所を選ぶ。

    雨だけを測る観測所もあれば、風だけの観測所もあるので、
    「近い」だけでなく「読める」ことを確かめる。
    """
    for code, name in nearest_stations(lat, lon):
        if rain_mm(code, start, hours) is not None:
            return code, name
    return None, None


def rain_mm(station, start, hours):
    """その期間にどれだけ降ったかを足す。読めなければ None。"""
    total = 0.0
    got = False
    block = start.replace(minute=0, second=0, microsecond=0)
    block = block - timedelta(hours=block.hour % 3)
    end = start + timedelta(hours=hours)

    while block <= end:      # 終わりの時刻ちょうどの値は次のファイルに入っている
        name = "%04d%02d%02d_%02d" % (block.year, block.month, block.day, block.hour)
        try:
            data = get_json("%s/amedas/data/point/%s/%s.json" % (JMA, station, name))
        except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError):
            block += timedelta(hours=3)
            continue
        for stamp, row in data.items():
            try:
                t = datetime(int(stamp[0:4]), int(stamp[4:6]), int(stamp[6:8]),
                             int(stamp[8:10]), int(stamp[10:12]), tzinfo=JST)
            except (ValueError, IndexError):
                continue
            if not (start < t <= end):
                continue
            v = row.get("precipitation10m")
            if isinstance(v, list) and isinstance(v[0], (int, float)):
                total += float(v[0])
                got = True
        block += timedelta(hours=3)

    return round(total, 1) if got else None


# =========================================================
# 期間の切り方
# =========================================================
def periods(now=None):
    """7日前〜3日前は1日ごと、直近3日は半日ごと。終わった期間だけ返す。"""
    now = now or datetime.now(JST)
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    out = []

    for i in range(7, 3, -1):                      # 7,6,5,4日前
        out.append((midnight - timedelta(days=i), 24))

    for i in range(3, -1, -1):                     # 3,2,1,0日前
        day = midnight - timedelta(days=i)
        for h in (0, 12):
            out.append((day + timedelta(hours=h), 12))

    return [(s, h) for (s, h) in out if s + timedelta(hours=h) <= now]


# =========================================================
# 照合
# =========================================================
def score(place_id, station, hist_entries, cache, now=None, fetch=True):
    now = now or datetime.now(JST)
    rows = []
    for start, hours in periods(now):
        pops = {}
        for src in ("jma", "model", "yahoo", "weathernews"):
            p = pop_for(hist_entries, place_id, src, start, hours)
            if p is not None:
                pops[src] = p
        if not pops:
            continue                   # 予報が残っていない期間は雨量も見に行かない

        key = "%s|%d" % (start.isoformat(), hours)
        actual = cache.get(key)
        if actual is None and fetch and station:
            mm = rain_mm(station, start, hours)
            if mm is not None:
                actual = {"mm": mm, "rain": mm >= RAIN_MM}
                cache[key] = actual
        if actual is None:
            continue

        rows.append({"start": start.isoformat(), "hours": hours,
                     "mm": actual["mm"], "rain": actual["rain"], "pops": pops})

    scores = {}
    for src in ("jma", "model", "yahoo", "weathernews"):
        n = hit = 0
        brier = 0.0
        for r in rows:
            if src not in r["pops"]:
                continue
            n += 1
            said = r["pops"][src] >= SAY_RAIN
            if said == r["rain"]:
                hit += 1
            brier += (r["pops"][src] / 100.0 - (1.0 if r["rain"] else 0.0)) ** 2
        if n:
            scores[src] = {"n": n, "hit": hit,
                           "rate": round(hit * 100.0 / n, 1),
                           "brier": round(brier / n, 3)}
    return rows, scores


def pop_for(entries, place_id, src, start, hours):
    """その期間をおおう予報を探す。ぴったりの区切りがなければ、重なる区切りの最大値。"""
    end = start + timedelta(hours=hours)
    best = None
    for key, v in entries.items():
        parts = key.split("|")
        if len(parts) != 4 or parts[0] != place_id or parts[1] != src:
            continue
        try:
            t0 = datetime.fromisoformat(parts[2])
        except ValueError:
            continue
        t1 = t0 + timedelta(hours=int(parts[3]))
        if t1 <= start or t0 >= end:
            continue                       # 重なっていない
        p = v.get("pop")
        if not isinstance(p, (int, float)):
            continue
        best = p if best is None else max(best, p)
    return best


def main():
    ap = argparse.ArgumentParser(description="降水確率の当たり具合を数える")
    ap.add_argument("--no-fetch", action="store_true", help="実際の降水量を取りに行かない")
    args = ap.parse_args()

    now = datetime.now(JST)
    latest = load_json(LATEST, {})
    if not latest:
        print("latest.json がありません。先に collect.py を動かしてください。")
        return 0

    places = latest.get("places") or []
    extra = [] if args.no_fetch else direct_forecasts(places)
    added, total = record(latest, now, extra)
    print("予報を記録しました：今回 %d 件 / 保存中 %d 件" % (added, total))

    hist = load_json(HISTORY, {"entries": {}})
    acc = load_json(ACCURACY, {"places": []})
    cache_all = acc.get("actuals") or {}

    out_places = []
    for place in places:
        pid = place.get("id", "default")
        lat, lon = place.get("lat"), place.get("lon")
        station = name = None
        done = periods(now)
        if lat is not None and lon is not None and not args.no_fetch and done:
            try:
                station, name = pick_station(lat, lon, done[-1][0], done[-1][1])
            except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError) as e:
                print("   観測所を選べませんでした（%s）" % e)

        cache = cache_all.setdefault(pid, {})
        rows, scores = score(pid, station, hist.get("entries") or {}, cache,
                             now=now, fetch=not args.no_fetch)
        out_places.append({
            "id": pid, "label": place.get("label", ""),
            "lat": lat, "lon": lon,
            "station": name, "periods": rows, "scores": scores,
        })
        print("── %s（観測所 %s）" % (place.get("label") or pid, name or "不明"))
        if not scores:
            print("   まだ照合できる記録がありません（予報の書きためが始まったところです）")
        for src, sc in scores.items():
            print("   %-12s 正解 %d/%d（%.1f%%）ブライア %.3f"
                  % (src, sc["hit"], sc["n"], sc["rate"], sc["brier"]))

    save_json(ACCURACY, {
        "updated_at": now.isoformat(),
        "rain_mm": RAIN_MM,
        "say_rain": SAY_RAIN,
        "places": out_places,
        "actuals": cache_all,
    })
    print("書き出しました → %s" % ACCURACY)
    return 0


if __name__ == "__main__":
    sys.exit(main())
