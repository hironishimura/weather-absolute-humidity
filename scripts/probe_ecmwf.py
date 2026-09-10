#!/usr/bin/env python3
"""ECMWF を足せるかを確かめる。

先に「頼んだ項目が本当に返るか」を見る。
Open-Meteo は、モデルによっては空（null）で返すことがある。
気象庁モデルの降水確率がまさにそれだった。
"""

import json
import urllib.request

BASE = "https://api.open-meteo.com/v1/forecast"
LAT, LON = 36.5551, 139.8828
FIELDS = "temperature_2m,relative_humidity_2m,surface_pressure,precipitation,dew_point_2m"


def ask(models):
    q = ("?latitude=%.4f&longitude=%.4f&hourly=%s"
         "&current=temperature_2m,relative_humidity_2m,surface_pressure"
         "&timezone=Asia%%2FTokyo&forecast_days=10&past_days=1" % (LAT, LON, FIELDS))
    if models:
        q += "&models=" + models
    url = BASE + q
    try:
        with urllib.request.urlopen(url, timeout=25) as r:
            d = json.load(r)
    except Exception as e:  # noqa: BLE001
        return url, {"エラー": str(e)}
    h = d.get("hourly") or {}
    n = len(h.get("time") or [])
    out = {"時刻の数": n}
    for k in FIELDS.split(","):
        vals = h.get(k)
        if vals is None:
            out[k] = "項目そのものがない"
        else:
            got = sum(1 for v in vals if v is not None)
            out[k] = "%d/%d" % (got, n)
    c = d.get("current") or {}
    out["現在値"] = {k: c.get(k) for k in
                  ("temperature_2m", "relative_humidity_2m", "surface_pressure")}
    out["解像度m"] = d.get("hourly_units") and d.get("generationtime_ms")
    for k in ("model_elevation", "elevation", "utc_offset_seconds"):
        if k in d:
            out[k] = d[k]
    return url, out


for models in ["ecmwf_ifs025", "ecmwf_aifs025", "ecmwf_ifs04", "jma_seamless", ""]:
    url, res = ask(models)
    print("=" * 60)
    print("models =", models or "(指定なし)")
    print(url)
    for k, v in res.items():
        print("   %-22s %s" % (k, v))
