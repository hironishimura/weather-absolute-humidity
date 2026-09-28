#!/bin/bash
# =========================================================
# VPS の取り込み結果と、その控えを手元に取ってくる（Mac で実行）
#
#   bash deploy/fetch_data.sh
#
# なぜ要るか:
#   VPS を作り直すと、降水確率の当たり具合の書きため(history.json)が
#   消えます。過去の予報はあとから取り寄せられないので、ときどき
#   これを走らせて手元にも置いておきます。
#
# 取ってきたものは backup/ に入ります（git には入れません）。
# 戻すときは、そのファイルを VPS の /opt/weather-ah/docs/data/ へ
# 置いてから systemctl start weather-collect.service。
# =========================================================
set -euo pipefail
cd "$(dirname "$0")/.."

HOST=${WEATHER_HOST:-root@153.115.38.1}
APP_DIR=/opt/weather-ah
OUT=backup/vps

mkdir -p "$OUT/data" "$OUT/snapshots"

# いまの値
rsync -az "$HOST":"$APP_DIR"/docs/data/ "$OUT"/data/
# 日ごとの控え。--delete は付けません。向こうで消えた古い日も、
# 手元には残しておきたいからです。
rsync -az "$HOST":"$APP_DIR"/backup/ "$OUT"/snapshots/ 2>/dev/null || true

echo
echo "手元に置きました: $OUT"
ls -1d "$OUT"/snapshots/*/ 2>/dev/null | wc -l | xargs echo "  控えの日数:"
if [ -f "$OUT/data/history.json" ]; then
  python3 - "$OUT/data/history.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
n = len(d) if isinstance(d, list) else len(d.get('records', d))
print('  予報の書きため: %d 件' % n)
PY
fi
