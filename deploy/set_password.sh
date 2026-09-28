#!/bin/bash
# =========================================================
# 画面を開くときの合言葉を決める・変える・やめる（VPS 上で root で実行）
#
#   bash /opt/weather-ah/deploy/set_password.sh          決める・変える
#   bash /opt/weather-ah/deploy/set_password.sh --off     やめる（誰でも見られる状態へ）
#
# 合言葉はこのリポジトリに入れません。公開設定なので、bcrypt の
# ハッシュでも総当たりの的になるためです。VPS の中だけに置きます。
#
#   /etc/caddy/weather-auth.d/auth.conf
#
# フォルダ指定で読ませているので、この中が空のあいだは鍵なしで動きます。
# 決め忘れで画面が開かなくなることはありません。
#
# /data/ には鍵をかけません。iPhone・iPad・Mac のアプリが認証を持たずに
# 読みにくるためです（deploy/weather.caddy を参照）。
# =========================================================
set -euo pipefail

AUTH_DIR=${WEATHER_AUTH_DIR:-/etc/caddy/weather-auth.d}
AUTH="$AUTH_DIR/auth.conf"
CADDYFILE=${WEATHER_CADDYFILE:-/etc/caddy/Caddyfile}
RELOAD=${WEATHER_RELOAD:-yes}

command -v caddy >/dev/null || { echo "Caddy が見つかりません" >&2; exit 1; }
mkdir -p "$AUTH_DIR"

# 壊れた設定を残さないよう、書き換える前を控えておきます
BACKUP=$(mktemp)
HAD=no
if [ -f "$AUTH" ]; then cp "$AUTH" "$BACKUP"; HAD=yes; fi

restore () {
  echo "  設定が通らなかったので、元に戻しました。" >&2
  if [ "$HAD" = yes ]; then cp "$BACKUP" "$AUTH"; else rm -f "$AUTH"; fi
  rm -f "$BACKUP"
  exit 1
}

if [ "${1:-}" = "--off" ]; then
  rm -f "$AUTH"
  echo "合言葉をやめました。誰でも見られる状態です。"
else
  # いまの利用者名を控えておき、そのまま Enter で使えるようにします
  WAS=$(grep -oE '^[[:space:]]*[A-Za-z0-9._-]+[[:space:]]+\$2[aby]\$' "$AUTH" 2>/dev/null \
        | head -1 | awk '{print $1}' || true)
  DEFAULT=${WAS:-hiro}

  read -r -p "利用者名 [$DEFAULT]: " USER_NAME || true
  USER_NAME=${USER_NAME:-$DEFAULT}
  case "$USER_NAME" in
    *[!A-Za-z0-9._-]*|'') echo "利用者名は英数字と . _ - だけにしてください" >&2; exit 1 ;;
  esac

  # 自動化のため環境変数からも受け取れるようにしています（ふだんは対話で）
  if [ -n "${WEATHER_PASSWORD:-}" ]; then
    PW=$WEATHER_PASSWORD
  else
    read -r -s -p "合言葉: " PW; echo
    read -r -s -p "もう一度: " PW2; echo
    [ "$PW" = "$PW2" ] || { echo "一致しません" >&2; exit 1; }
  fi
  [ ${#PW} -ge 8 ] || { echo "合言葉は8文字以上にしてください" >&2; exit 1; }

  HASH=$(caddy hash-password --plaintext "$PW")
  umask 077
  printf 'basic_auth @locked {\n\t%s %s\n}\n' "$USER_NAME" "$HASH" > "$AUTH"
  chmod 640 "$AUTH"
  chgrp caddy "$AUTH" 2>/dev/null || true
fi

caddy validate --config "$CADDYFILE" >/dev/null 2>&1 || restore
rm -f "$BACKUP"

if [ "$RELOAD" = yes ]; then
  systemctl reload caddy
  echo "反映しました。https://weather.shome.co.jp/ で確かめてください。"
  echo "  画面 … 合言葉を聞かれる（かけている場合）"
  echo "  /data/latest.json … 合言葉なしで開ける（アプリ用。こちらは常に開けます）"
fi
