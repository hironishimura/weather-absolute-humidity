#!/bin/bash
# Mac側で実行: 最新のコードをVPSへ反映する(取り込んだ値は触らない)
#
#   bash deploy/update_vps.sh           反映だけ
#   bash deploy/update_vps.sh --setup   反映したあと、VPS上で初期設定も走らせる(初回)
#
# 土地サーチと同じサーバーです。SSHは鍵認証のみ。
set -euo pipefail
cd "$(dirname "$0")/.."

HOST=root@153.115.38.1
APP_DIR=/opt/weather-ah

SETUP=no
[ "${1:-}" = "--setup" ] && SETUP=yes

# apple/ は Mac・iPhone 用、dist/ は1ファイル版、test/ は手元の確認用なので送りません。
# docs/data は VPS 側が書くので、こちらから上書きしません。
rsync -az --delete \
  --exclude '.git' --exclude '.github' --exclude '__pycache__' --exclude '*.pyc' \
  --exclude '.DS_Store' --exclude 'apple' --exclude 'dist' --exclude 'test' \
  --exclude 'docs/data' --exclude 'venv' --exclude '.playwright' \
  ./ "$HOST":"$APP_DIR"/

if [ "$SETUP" = yes ]; then
  # 初回だけ、手元にある取り込み済みの値も持っていきます(向こうに無いものだけ使われます)
  rsync -az docs/data/ "$HOST":"$APP_DIR"/docs/data/
  ssh "$HOST" "bash $APP_DIR/deploy/setup_vps.sh"
else
  ssh "$HOST" "chown -R weather:weather $APP_DIR \
    && chmod 755 $APP_DIR $APP_DIR/docs \
    && systemctl reload caddy \
    && systemctl is-active weather-collect.timer"
fi
