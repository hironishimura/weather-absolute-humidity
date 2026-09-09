#!/usr/bin/env python3
"""Yahoo!天気とウェザーニュースから気温・湿度を取り込む。

どちらも公開APIがなく、ブラウザから直接読むことはできない（CORS）。
そこでサーバ側（GitHub Actions など）でページを取得し、
docs/data/latest.json に書き出しておく。
アプリはそのファイルを読んで、気象庁の値と並べて表示する。

外部ライブラリは使わない（GitHub Actions でそのまま動かすため）。

    python3 scripts/collect.py --dry-run          # 書き出さず中身だけ確認
    python3 scripts/collect.py                    # latest.json を書き出す
    python3 scripts/collect.py --html yahoo=a.html --dry-run
                                                          # 保存したページで読み取りを試す

ページの作りが変わると読めなくなる。そのときは latest.json の
sources.<名前>.error に理由が入り、アプリ側は「失敗」と表示する。
気象庁の実況と予報だけは常に動くので、アプリ全体が止まることはない。
"""

import argparse
import gzip
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # リポジトリの一番上
SETTINGS_JSON = os.path.join(HERE, "settings.json")
DEFAULT_OUT = os.path.join(ROOT, "docs/data/latest.json")

JST = timezone(timedelta(hours=9), "JST")
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)
TIMEOUT = 20


# =========================================================
# 取得
# =========================================================
def fetch(url):
    """ページを取ってきて文字列で返す。"""
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "ja,en;q=0.8",
            "Accept-Encoding": "gzip",
        },
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
        raw = res.read()
        if res.headers.get("Content-Encoding") == "gzip":
            raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
        charset = res.headers.get_content_charset()
    for enc in [charset, "utf-8", "cp932", "euc-jp"]:
        if not enc:
            continue
        try:
            return raw.decode(enc)
        except (UnicodeDecodeError, LookupError):
            continue
    return raw.decode("utf-8", "replace")


# =========================================================
# 表の読み取り
# =========================================================
class TableParser(HTMLParser):
    """<table> を「行 × セル」の文字列にほどく。"""

    SKIP = ("script", "style", "noscript")

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tables = []
        self._open = []      # 入れ子の table
        self._cell = None
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self._skip += 1
        elif tag == "table":
            self._open.append([])
        elif tag == "tr" and self._open:
            self._open[-1].append([])
        elif tag in ("td", "th") and self._open:
            if not self._open[-1]:
                self._open[-1].append([])
            self._cell = []
        elif tag == "br" and self._cell is not None:
            self._cell.append(" ")

    def handle_endtag(self, tag):
        if tag in self.SKIP:
            self._skip = max(0, self._skip - 1)
        elif tag in ("td", "th") and self._cell is not None and self._open:
            self._open[-1][-1].append(" ".join("".join(self._cell).split()))
            self._cell = None
        elif tag == "table" and self._open:
            done = self._open.pop()
            if done:
                self.tables.append([r for r in done if r])

    def handle_data(self, data):
        if self._skip == 0 and self._cell is not None:
            self._cell.append(data)


def read_tables(html):
    p = TableParser()
    try:
        p.feed(html)
    except Exception:  # 壊れたHTMLでも途中まで使う
        pass
    p.close()
    return p.tables


NUM_RE = re.compile(r"-?\d+(?:\.\d+)?")
HOUR_RE = re.compile(r"(\d{1,2})\s*(?:時|:)")


def to_number(text):
    if text is None:
        return None
    m = NUM_RE.search(text.replace("−", "-").replace("－", "-"))
    return float(m.group()) if m else None


def to_hour(text):
    if text is None:
        return None
    m = HOUR_RE.search(text)
    if not m:
        m = re.fullmatch(r"\s*(\d{1,2})\s*", text)
    if not m:
        return None
    h = int(m.group(1))
    return h if 0 <= h <= 24 else None


def label_kind(text):
    """行や列の見出しが何を指しているかを返す。"""
    if not text:
        return None
    t = text.replace(" ", "")
    if "湿度" in t:
        return "humidity"
    if "気温" in t or re.search(r"温度", t):
        return "temp"
    if "時刻" in t or "時間" in t or t in ("時", "日時"):
        return "time"
    return None


def series_from_rows(table):
    """見出しが左端にある表（Yahoo!天気の時系列表など）から読む。"""
    found = {}
    for row in table:
        if len(row) < 3:
            continue
        kind = label_kind(row[0])
        if kind and kind not in found:
            found[kind] = row[1:]
    if "temp" in found and "humidity" in found:
        return found.get("time"), found["temp"], found["humidity"]
    return None


def series_from_cols(table):
    """見出しが1行目にある表から読む。"""
    if len(table) < 3:
        return None
    head = table[0]
    idx = {}
    for i, cell in enumerate(head):
        kind = label_kind(cell)
        if kind and kind not in idx:
            idx[kind] = i
    if "temp" not in idx or "humidity" not in idx:
        return None
    need = max(idx.values())
    times, temps, hums = [], [], []
    for row in table[1:]:
        if len(row) <= need:
            continue
        times.append(row[idx["time"]] if "time" in idx else None)
        temps.append(row[idx["temp"]])
        hums.append(row[idx["humidity"]])
    if not temps:
        return None
    return (times if "time" in idx else None), temps, hums


def series_from_html(html):
    """表から（時刻・気温・湿度）を取り出す。読めなければ None。"""
    got = series_all_from_html(html)
    return got[0] if got else None


def series_all_from_html(html):
    """読める表を全部返す。

    Yahoo!天気は「今日」と「明日」で同じ形の表が2つ並ぶので、
    どちらも読んでつなげられるようにしておく。
    """
    out = []
    for table in read_tables(html):
        for reader in (series_from_rows, series_from_cols):
            got = reader(table)
            if got:
                out.append(got)
                break
    return out


# =========================================================
# 実況の読み取り
# ---------------------------------------------------------
# ウェザーニュースは1時間ごとの湿度を画面側で組み立てているため
# HTMLからは読めないが、実況（いまの気温・湿度・気圧）は
# 「見出しと値」の組で素直に書かれている。そこを読む。
# =========================================================
OBS_BLOCK_RE = re.compile(r'<li[^>]*class="[^"]*obs_block[^"]*"[^>]*>(.*?)</li>', re.S | re.I)
OBS_TITLE_RE = re.compile(r'class="title"[^>]*>\s*([^<]{1,12})', re.S)
OBS_VALUE_RE = re.compile(r'class="value"[^>]*>\s*(-?\d+(?:\.\d+)?)', re.S)

OBS_FIELDS = (
    ("湿度", "humidity", 0, 100),
    ("気温", "temp", -60, 60),
    ("気圧", "pressure", 800, 1100),
)


def current_from_blocks(html):
    """「見出し＋値」が組になっている実況欄から読む。"""
    found = {}
    for m in OBS_BLOCK_RE.finditer(html):
        block = m.group(1)
        t = OBS_TITLE_RE.search(block)
        v = OBS_VALUE_RE.search(block)
        if not t or not v:
            continue
        title = t.group(1).strip()
        for label, key, lo, hi in OBS_FIELDS:
            if label in title and key not in found:
                val = float(v.group(1))
                if lo <= val <= hi:
                    found[key] = val
    if "temp" in found and "humidity" in found:
        return found
    return None


def current_from_labels(html):
    """見出しの近くに値と単位が並んでいる作りから読む（控え）。"""
    found = {}
    for label, key, unit, lo, hi in (
        ("湿度", "humidity", "%", 0, 100),
        ("気温", "temp", "℃", -60, 60),
    ):
        for m in re.finditer(label, html):
            seg = html[m.end():m.end() + 400]
            v = re.search(r">\s*(-?\d+(?:\.\d+)?)\s*<", seg)
            if not v:
                continue
            after = seg[v.end():v.end() + 150]
            if unit not in after:
                continue
            val = float(v.group(1))
            if lo <= val <= hi:
                found[key] = val
                break
    if "temp" in found and "humidity" in found:
        return found
    return None


# =========================================================
# 埋め込みJSONからの読み取り（表で読めなかったときの控え）
# =========================================================
TEMP_KEYS = ("temp", "temperature", "airtemperature", "tmp")
HUM_KEYS = ("humidity", "humid", "rh")
TIME_KEYS = ("time", "datetime", "date", "hour", "timestamp")


def _pick(d, keys):
    for k, v in d.items():
        kl = re.sub(r"[^a-z]", "", k.lower())
        if kl in keys and isinstance(v, (int, float, str)):
            return v
    return None


def series_from_json(html):
    """<script> の中のJSONに、気温と湿度が並ぶ配列があれば拾う。"""
    best = None
    for m in re.finditer(r"<script[^>]*>(.*?)</script>", html, re.S | re.I):
        body = m.group(1).strip()
        start = body.find("{")
        if start < 0:
            continue
        try:
            data = json.loads(body[start:])
        except ValueError:
            continue

        stack = [data]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                stack.extend(node.values())
            elif isinstance(node, list):
                rows = [x for x in node if isinstance(x, dict)]
                if len(rows) >= 3:
                    t = [_pick(r, TEMP_KEYS) for r in rows]
                    h = [_pick(r, HUM_KEYS) for r in rows]
                    if all(x is not None for x in t) and all(x is not None for x in h):
                        cand = ([_pick(r, TIME_KEYS) for r in rows], t, h)
                        if best is None or len(cand[1]) > len(best[1]):
                            best = cand
                stack.extend(x for x in node if isinstance(x, (dict, list)))
    return best


# =========================================================
# 画面に出ている文字からの読み取り
# ---------------------------------------------------------
# ウェザーニュースの1時間ごと予報は表ではなく、画面側で組み立てられる
# 並びで出ています。単位（ミリ・℃・m/s）を手がかりに拾います。
# この並びに湿度は入っていないので、取れるのは気温だけです。
# =========================================================
DAY_LINE_RE = re.compile(r"^(\d{1,2})日\s*[（(][月火水木金土日][）)]$")
HOUR_LINE_RE = re.compile(r"^(\d{1,2})$")
MM_LINE_RE = re.compile(r"^(-?\d+(?:\.\d+)?)\s*ミリ$")
TEMP_LINE_RE = re.compile(r"^(-?\d+(?:\.\d+)?)\s*[℃度]$")


def _date_for_day(day, now):
    """「9日」から日付を組み立てる。月をまたいでいたら前後の月にずらす。"""
    base = now.replace(hour=0, minute=0, second=0, microsecond=0)
    for shift in (0, 1, -1):
        month = base.month + shift
        year = base.year
        if month > 12:
            month, year = 1, year + 1
        elif month < 1:
            month, year = 12, year - 1
        try:
            d = base.replace(year=year, month=month, day=day)
        except ValueError:
            continue
        if abs((d - base).days) <= 16:
            return d
    return None


def hourly_from_text(text, now=None):
    """画面に出ている文字から「時・降水量・気温」の並びを拾う。

    ウェザーニュースの1時間ごと予報は
        7日(月) / 9 / 1ミリ / 22℃ / 7m/s / 10 / 1ミリ / 23℃ / …
    という並びで出ています。日付の見出しと、時・ミリ・℃ の3つ組を探します。
    """
    if not text:
        return []
    now = now or datetime.now(JST)
    lines = [x.strip() for x in text.split("\n")]
    lines = [x for x in lines if x]

    out = []
    day = None
    i = 0
    while i < len(lines):
        m = DAY_LINE_RE.match(lines[i])
        if m:
            day = _date_for_day(int(m.group(1)), now)
            i += 1
            continue
        if day is not None and i + 2 < len(lines):
            h = HOUR_LINE_RE.match(lines[i])
            mm = MM_LINE_RE.match(lines[i + 1])
            tp = TEMP_LINE_RE.match(lines[i + 2])
            if h and mm and tp:
                hour = int(h.group(1))
                temp = float(tp.group(1))
                if 0 <= hour <= 23 and -60 <= temp <= 60:
                    out.append({
                        "time": (day + timedelta(hours=hour)).isoformat(),
                        "temp": round(temp, 1),
                    })
                    i += 3
                    continue
        i += 1

    # 同じ時刻が二度出てきたら後のほうを残す
    seen = {}
    for r in out:
        seen[r["time"]] = r
    return [seen[k] for k in sorted(seen)]


# =========================================================
# 時刻の組み立て
# =========================================================
def build_hourly(times, temps, hums, now=None, start=None):
    """読み取った文字列を {time, temp, humidity} の並びにする。

    start に前の表の最後の時刻を渡すと、その続きとして日付を進める。
    （Yahoo!天気は「今日」「明日」で表が分かれていて、どちらも 0時 から始まる）
    """
    now = now or datetime.now(JST)
    out = []
    day = now.replace(minute=0, second=0, microsecond=0)
    prev_hour = None
    if start:
        try:
            prev = datetime.fromisoformat(start)
            day = prev.replace(minute=0, second=0, microsecond=0)
            prev_hour = prev.hour
        except ValueError:
            pass

    n = min(len(temps), len(hums))
    for i in range(n):
        temp = to_number(str(temps[i])) if temps[i] is not None else None
        hum = to_number(str(hums[i])) if hums[i] is not None else None
        if temp is None or hum is None:
            continue
        if not (-60 <= temp <= 60) or not (0 <= hum <= 100):
            continue

        stamp = None
        raw = times[i] if times and i < len(times) else None
        if raw is not None:
            iso = parse_iso(str(raw))
            if iso:
                stamp = iso
            else:
                hour = to_hour(str(raw))
                if hour is not None:
                    if prev_hour is not None and hour < prev_hour:
                        day = day + timedelta(days=1)
                    prev_hour = hour
                    stamp = day.replace(hour=hour % 24)
                    if hour == 24:
                        stamp = stamp + timedelta(days=1)
        if stamp is None:
            stamp = now.replace(minute=0, second=0, microsecond=0) + timedelta(hours=i)

        out.append({
            "time": stamp.isoformat(),
            "temp": round(temp, 1),
            "humidity": round(hum, 1),
        })

    out.sort(key=lambda r: r["time"])
    return out


def parse_iso(text):
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})", text)
    if m:
        return datetime(*[int(x) for x in m.groups()], tzinfo=JST)
    if re.fullmatch(r"\d{10,13}", text):
        v = int(text)
        if v > 10 ** 12:
            v //= 1000
        return datetime.fromtimestamp(v, JST)
    return None


def nearest_now(hourly, now=None):
    """いまの時刻に一番近い1点を返す（実況の代わりに使う）。"""
    if not hourly:
        return None
    now = now or datetime.now(JST)
    best, best_gap = None, None
    for row in hourly:
        try:
            t = datetime.fromisoformat(row["time"])
        except ValueError:
            continue
        gap = abs((t - now).total_seconds())
        if best_gap is None or gap < best_gap:
            best, best_gap = row, gap
    if best is None or best_gap > 5400:      # 90分より離れていたら使わない
        return None
    return best


# =========================================================
# 1つの提供元を処理する
# =========================================================
def collect_one(name, conf, html=None, now=None):
    if not conf.get("enabled"):
        return {"ok": False, "error": "settings.json で enabled が false です"}
    url = conf.get("url")
    if html is None:
        if not url:
            return {"ok": False, "error": "settings.json に url がありません"}
        try:
            html = fetch(url)
        except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
            return {"ok": False, "url": url, "error": "取得できませんでした（%s）" % e}

    ways = []

    # 1時間（3時間）ごとの並び
    tables = series_all_from_html(html)
    hourly = []
    if tables:
        ways.append("table×%d" % len(tables))
        for got in tables:
            hourly += build_hourly(got[0], got[1], got[2], now=now,
                                   start=hourly[-1]["time"] if hourly else None)
    else:
        got = series_from_json(html)
        if got:
            ways.append("json")
            hourly = build_hourly(got[0], got[1], got[2], now=now)

    # いまの観測値
    obs = current_from_blocks(html) or current_from_labels(html)
    if obs:
        ways.append("実況")

    if not hourly and not obs:
        return {
            "ok": False,
            "url": url,
            "error": "ページから気温と湿度を読み取れませんでした（作りが変わった可能性があります）",
        }

    out = {
        "ok": True,
        "url": url,
        "label": conf.get("label", ""),
        "strategy": "＋".join(ways),
        "hourly": hourly,
    }
    if obs:
        out["current"] = {
            "time": now.replace(second=0, microsecond=0).isoformat(),
            "temp": obs["temp"],
            "humidity": obs["humidity"],
        }
        if "pressure" in obs:
            out["current"]["pressure"] = obs["pressure"]
        out["current_is_forecast"] = False
        return out

    cur = nearest_now(hourly, now=now)
    if cur:
        out["current"] = dict(cur)
        out["current_is_forecast"] = True
    return out


# =========================================================
# 実行
# =========================================================
def load_settings():
    with open(SETTINGS_JSON, encoding="utf-8") as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser(description="Yahoo!天気・ウェザーニュースから気温と湿度を取り込む")
    ap.add_argument("--dry-run", action="store_true", help="書き出さずに中身を表示する")
    ap.add_argument("--out", default=None,
                    help="書き出し先を1つだけ指定する（既定は settings.json の outputs）")
    ap.add_argument("--html", action="append", default=[],
                    help="保存したページで試す（例 --html yahoo=saved.html）")
    args = ap.parse_args()

    settings = load_settings()
    local = {}
    for item in args.html:
        if "=" not in item:
            print("--html は 名前=ファイル の形で指定してください", file=sys.stderr)
            return 2
        key, path = item.split("=", 1)
        with open(path, encoding="utf-8", errors="replace") as f:
            local[key] = f.read()

    now = datetime.now(JST)
    result = {
        "generated_at": now.isoformat(),
        "label": settings.get("label", ""),
        "sources": {},
    }
    for name, conf in (settings.get("sources") or {}).items():
        if name in local:
            conf = dict(conf, enabled=True)
        result["sources"][name] = collect_one(name, conf, html=local.get(name), now=now)

    for name, r in result["sources"].items():
        if r.get("ok"):
            print("%-12s 取得 %d時間ぶん（%s）" % (name, len(r.get("hourly", [])), r.get("strategy")))
        else:
            print("%-12s 未取得 %s" % (name, r.get("error", "")))

    if args.dry_run:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    if args.out:
        outs = [args.out]
    else:
        outs = settings.get("outputs") or [settings.get("output") or DEFAULT_OUT]
    body = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    for out in outs:
        path = out if os.path.isabs(out) else os.path.join(ROOT, out)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(body)
        print("書き出しました → %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
