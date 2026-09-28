#!/bin/bash
# =========================================================
# 取り込んだ値の控えを日ごとに残す（VPS 上・取り込みのたびに呼ばれる）
#
# なぜ要るか:
#   history.json は降水確率の当たり具合を数えるための書きためです。
#   過去の予報はあとから取り寄せられないので、これが壊れたり消えたり
#   すると、数字がそろうまでまた1週間ほどかかります。
#
# 残すもの: /opt/weather-ah/backup/YYYY-MM-DD/*.json （既定で30日ぶん）
# 手元へ取り寄せる: Mac で bash deploy/fetch_data.sh
# =========================================================
set -euo pipefail

APP_DIR=${WEATHER_APP_DIR:-/opt/weather-ah}
DATA="$APP_DIR/docs/data"
BACKUP="$APP_DIR/backup"
KEEP=${WEATHER_BACKUP_KEEP:-30}

PY=python3
[ -x "$APP_DIR/venv/bin/python3" ] && PY="$APP_DIR/venv/bin/python3"

DAY=$(date +%Y-%m-%d)
DEST="$BACKUP/$DAY"
mkdir -p "$DEST"

n=0
for f in latest.json history.json accuracy.json; do
  # JSON として読めるものだけ控えます。壊れたものを控えに混ぜると、
  # 戻すときにどれが無事なのか分からなくなるためです。
  if [ -s "$DATA/$f" ] \
     && "$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$DATA/$f" 2>/dev/null; then
    cp "$DATA/$f" "$DEST/$f"
    n=$((n + 1))
  else
    echo "  $f は控えませんでした（空か、JSONとして読めません）" >&2
  fi
done
# ひとつも控えられなかった日は残しません
[ "$n" -eq 0 ] && rmdir "$DEST" 2>/dev/null

# 古いものから片付けます
ls -1d "$BACKUP"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] 2>/dev/null \
  | sort | head -n "-$KEEP" | while read -r d; do rm -rf "$d"; done

echo "控え: $DEST（$n 件） / 残している日数 $(ls -1d "$BACKUP"/[0-9]*-[0-9]*-[0-9]* 2>/dev/null | wc -l)"
