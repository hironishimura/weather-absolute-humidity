#!/usr/bin/env python3
"""ブラウザで実際に描画させてから読み取る（任意・外せます）。

ウェザーニュースの1時間ごとの予報は、ページを開いてから画面側で組み立てられます。
そのためページのHTMLを取ってくるだけでは読めません。
このスクリプトは Playwright で本物のブラウザにページを開かせ、描画が終わってから
そのHTMLを取り出して、collect.py と同じ読み取り処理にかけます。

    python3 scripts/collect_browser.py --dump    # 描画後に何があるか見るだけ
    python3 scripts/collect_browser.py           # latest.json に上書き（増えたぶんだけ）

【外し方】
  - settings.json の sources.<名前>.browser.enabled を false にする
  - あるいはワークフローのこのステップを消す
どちらでも、collect.py だけの動きに戻ります。このスクリプトは
「読めたら足す」だけで、失敗しても latest.json を壊しません。
Playwright が入っていない場合も、何もせずに正常終了します。
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import collect  # noqa: E402

SETTINGS = os.path.join(HERE, "settings.json")


def load_playwright():
    """Playwright がなければ None を返す（入れていなくても動くようにする）。"""
    try:
        from playwright.sync_api import sync_playwright
        return sync_playwright
    except ImportError:
        return None


# 広告や計測は読み込まない。ページが「静か」にならず待てなくなるため。
BLOCK_HOSTS = (
    "googletagmanager", "google-analytics", "doubleclick", "googlesyndication",
    "adservice", "amazon-adsystem", "criteo", "rubiconproject", "scorecardresearch",
    "yieldmo", "taboola", "outbrain", "facebook.net", "connect.facebook",
)
BLOCK_TYPES = ("image", "media", "font")


def render(sync_playwright, url, conf):
    """ページを開いて、描画が落ち着いてからHTMLを返す。"""
    wait_ms = int(conf.get("wait_ms", 4000))
    wait_for = conf.get("wait_for")
    scroll = bool(conf.get("scroll", True))
    # networkidle は広告のせいで永久に来ないことがあるので既定にしない
    wait_until = conf.get("wait_until", "domcontentloaded")

    with sync_playwright() as p:
        browser = p.chromium.launch()
        try:
            page = browser.new_context(
                locale="ja-JP",
                timezone_id="Asia/Tokyo",
                viewport={"width": 1280, "height": 2000},
                user_agent=collect.USER_AGENT,
            ).new_page()

            def gate(route):
                r = route.request
                if r.resource_type in BLOCK_TYPES or any(h in r.url for h in BLOCK_HOSTS):
                    return route.abort()
                return route.continue_()

            page.route("**/*", gate)
            page.goto(url, wait_until=wait_until, timeout=45000)
            try:
                page.wait_for_load_state("load", timeout=15000)
            except Exception:                       # noqa: BLE001  待てなくても先へ進む
                print("   （読み込み完了を待てませんでしたが、そのまま続けます）")
            if wait_for:
                try:
                    page.wait_for_selector(wait_for, timeout=15000)
                except Exception as e:              # noqa: BLE001
                    print("   （%s を待てませんでした: %s）" % (wait_for, type(e).__name__))
            if scroll:
                # 画面に入ってから読み込む作りのページがあるので、一度下まで送る
                page.mouse.wheel(0, 6000)
                page.wait_for_timeout(1200)
                page.mouse.wheel(0, -6000)
            page.wait_for_timeout(wait_ms)
            try:
                text = page.inner_text("body")
            except Exception:                       # noqa: BLE001
                text = ""
            return {"html": page.content(), "text": text}
        finally:
            browser.close()


def dump_text(text, keywords):
    """描画後に画面へ出ている文字を、手がかりの前後だけ見る。"""
    if not text:
        print("  （表示テキストを取れませんでした）")
        return
    flat = text.replace("\n", " / ")
    print("  表示テキスト: %d 文字" % len(text))
    import re as _re
    for kw in keywords:
        hits = list(_re.finditer(_re.escape(kw), flat))
        print("  ── 「%s」 %d 箇所" % (kw, len(hits)))
        for m in hits[:2]:
            s0 = max(0, m.start() - 150)
            print("     …%s…" % flat[s0:m.start() + 700])


def dump(html, name):
    print("=" * 70)
    print("■ %s（描画後）" % name)
    print("  長さ: %d 文字" % len(html))
    tables = collect.read_tables(html)
    print("  表の数: %d" % len(tables))
    for i, t in enumerate(tables[:20]):
        if not t:
            continue
        labels = [r[0] for r in t if r]
        head = " | ".join(x[:10] for x in t[0][:12])
        left = " | ".join(x[:10] for x in labels[:12])
        print("   [%2d] %d行 × 最大%d列" % (i, len(t), max(len(r) for r in t)))
        print("        1行目 : %s" % head)
        print("        左端列 : %s" % left)
        if any(("湿度" in x or "気温" in x or "降水" in x) for x in labels + list(t[0])):
            print("        ★ 気温・湿度・降水のどれかを含みます")
    got = collect.series_all_from_html(html)
    print("  読めた表: %d 個" % len(got))
    for g in got:
        print("     時刻: %s" % " | ".join(str(x) for x in (g[0] or [])[:10]))
        print("     気温: %s" % " | ".join(str(x) for x in g[1][:10]))
        print("     湿度: %s" % " | ".join(str(x) for x in g[2][:10]))


def main():
    ap = argparse.ArgumentParser(description="ブラウザで描画してから読み取る")
    ap.add_argument("--dump", action="store_true", help="読み取らず、何があるかだけ見る")
    ap.add_argument("--source", default=None, help="ひとつの提供元だけ処理する")
    args = ap.parse_args()

    sync_playwright = load_playwright()
    if sync_playwright is None:
        print("Playwright が入っていないため、ブラウザでの取り込みは行いません。")
        print("（collect.py だけの結果をそのまま使います）")
        return 0

    with open(SETTINGS, encoding="utf-8") as f:
        settings = json.load(f)

    targets = []
    for name, conf in (settings.get("sources") or {}).items():
        if args.source and name != args.source:
            continue
        b = conf.get("browser") or {}
        if not b.get("enabled"):
            print("%-12s ブラウザでの取り込みは無効です" % name)
            continue
        if not conf.get("url"):
            continue
        targets.append((name, conf, b))

    if not targets:
        print("ブラウザで取り込む対象がありません。")
        return 0

    results = {}
    for name, conf, b in targets:
        print("%-12s 開いています… %s" % (name, conf["url"]))
        try:
            rendered = render(sync_playwright, conf["url"], b)
        except Exception as e:                      # noqa: BLE001  何が起きても続ける
            print("%-12s 開けませんでした（%s: %s）" % (name, type(e).__name__, e))
            continue
        html = rendered["html"]
        if args.dump:
            dump(html, name)
            dump_text(rendered.get("text"), ["1時間ごと", "湿度", "時間ごとの", "気温"])
            continue
        r = collect.collect_one(name, dict(conf, enabled=True), html=html)
        r = add_hourly(r, collect.hourly_from_text(rendered.get("text")), conf)
        if r.get("ok"):
            print("%-12s 読めました（%s・%d時間ぶん）" % (name, r.get("strategy"), len(r.get("hourly", []))))
            results[name] = r
        else:
            print("%-12s 読めませんでした（%s）" % (name, r.get("error")))

    if args.dump or not results:
        return 0
    return merge(settings, results)


def add_hourly(result, extra, conf=None):
    """画面テキストから拾った並びを、いまの結果に足す。

    同じ時刻があれば、欠けている項目だけ埋めます。
    """
    if not extra:
        return result
    conf = conf or {}
    out = dict(result)
    if not out.get("ok"):
        out = {
            "ok": True, "url": result.get("url"), "label": conf.get("label", ""),
            "strategy": "", "hourly": [],
        }
    by = {}
    for r in (out.get("hourly") or []):
        by[r["time"]] = dict(r)
    for r in extra:
        cur = by.get(r["time"])
        if cur is None:
            by[r["time"]] = dict(r)
        else:
            for k, v in r.items():
                if k != "time" and cur.get(k) is None:
                    cur[k] = v
    out["hourly"] = [by[k] for k in sorted(by)]
    st = out.get("strategy", "")
    if "画面テキスト" not in st:
        out["strategy"] = (st + "＋画面テキスト") if st else "画面テキスト"
    return out


def pick_better(old, new):
    """すでにある結果と、ブラウザで読んだ結果のどちらを使うか決める。

    増えていなければ None を返す（そのまま置いておく）。
    実況が取れているほうの現在値は残す。
    """
    old = old or {}
    old_n = len(old.get("hourly") or [])
    new_n = len(new.get("hourly") or [])
    if old.get("ok") and new_n <= old_n:
        return None
    out = dict(new)
    if old.get("current") and old.get("current_is_forecast") is False and \
            out.get("current_is_forecast") is not False:
        out["current"] = old["current"]
        out["current_is_forecast"] = False
    out["strategy"] = (out.get("strategy", "") + "（ブラウザ）").strip()
    return out


def merge(settings, results):
    """latest.json に、増えたぶんだけ上書きする。"""
    outs = settings.get("outputs") or []
    if not outs:
        print("書き出し先がありません。")
        return 0

    path = outs[0] if os.path.isabs(outs[0]) else os.path.join(ROOT, outs[0])
    if not os.path.exists(path):
        print("%s がまだありません。先に collect.py を動かしてください。" % path)
        return 0

    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    changed = []
    for name, r in results.items():
        old = (data.get("sources") or {}).get(name) or {}
        better = pick_better(old, r)
        if better:
            data.setdefault("sources", {})[name] = better
            changed.append("%s %d→%d時間" % (name, len(old.get("hourly") or []),
                                            len(better.get("hourly") or [])))

    if not changed:
        print("増えるものがなかったので、そのままにします。")
        return 0

    body = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    for out in outs:
        p2 = out if os.path.isabs(out) else os.path.join(ROOT, out)
        with open(p2, "w", encoding="utf-8") as f:
            f.write(body)
    print("上書きしました：%s" % " / ".join(changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
