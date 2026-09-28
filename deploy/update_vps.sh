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
# docs/data と backup は VPS 側が書くので、こちらから上書きしません。
# backup を外さないと、--delete で配るたびに控えが消えます。
rsync -az --delete \
  --exclude '.git' --exclude '.github' --exclude '__pycache__' --exclude '*.pyc' \
  --exclude '.DS_Store' --exclude 'apple' --exclude 'dist' --exclude 'test' \
  --exclude 'docs/data' --exclude 'venv' --exclude '.playwright' \
  --exclude 'backup' \
  ./ "$HOST":"$APP_DIR"/

if [ "$SETUP" = yes ]; then
  # 初回だけ、手元にある取り込み済みの値も持っていきます(向こうに無いものだけ使われます)
  rsync -az docs/data/ "$HOST":"$APP_DIR"/docs/data/
  ssh "$HOST" "bash $APP_DIR/deploy/setup_vps.sh"
else
  # 公開設定も毎回入れ直します。これをしないと deploy/weather.caddy を
  # 直しても VPS 側は古いままで、直したつもりが反映されません。
  # 合言葉(/etc/caddy/weather-auth.d/)は VPS のものが正なので触りません。
  ssh "$HOST" "set -e
    chown -R weather:weather $APP_DIR
    chmod 755 $APP_DIR $APP_DIR/docs
    mkdir -p /etc/caddy/weather-auth.d
    chmod 750 /etc/caddy/weather-auth.d
    chgrp caddy /etc/caddy/weather-auth.d 2>/dev/null || true
    install -m 644 $APP_DIR/deploy/weather.caddy /etc/caddy/conf.d/weather.caddy
    caddy validate --config /etc/caddy/Caddyfile >/dev/null
    systemctl reload caddy
    systemctl is-active weather-collect.timer"
fi
