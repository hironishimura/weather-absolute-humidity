#!/bin/bash
# =========================================================
# 気温・湿度・絶対湿度 VPS 初期設定スクリプト (Ubuntu 24.04 / root で実行)
#
#   使い方:  Mac から  bash deploy/update_vps.sh --setup
#            (VPS へ送ったあと、ここが VPS 側で走ります)
#
# 行うこと:
#   1. 必要なものを入れる・タイムゾーン(Asia/Tokyo)
#   2. 実行ユーザー weather 作成、/opt/weather-ah へ配置
#   3. Python の置き場(venv)と Playwright の chromium
#   4. systemd 登録(3時間おきの取り込み)
#   5. Caddy に公開設定を足す
#   6. 初回の取り込みを1回走らせる
#
# 土地サーチ(/opt/tochi-search)と同じサーバーに相乗りします。
# 向こうの設定には触りません。ufw も向こうで 22/80/443 が開いています。
# =========================================================
set -euo pipefail

APP_DIR=/opt/weather-ah
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOMAIN=weather.shome.co.jp

echo "== 1. 必要なもの"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3-venv rsync curl
timedatectl set-timezone Asia/Tokyo
python3 --version

echo "== 2. アプリ配置"
id weather >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin weather
mkdir -p "$APP_DIR"
if [ "$SRC_DIR" != "$APP_DIR" ]; then
  rsync -a --delete \
    --exclude '.git' --exclude '.github' --exclude '__pycache__' --exclude '*.pyc' \
    --exclude '.DS_Store' --exclude 'apple' --exclude 'dist' --exclude 'test' \
    --exclude 'docs/data' --exclude 'venv' --exclude '.playwright' \
    "$SRC_DIR"/ "$APP_DIR"/
fi
mkdir -p "$APP_DIR/docs/data"
# 取り込んだ値は VPS のものが正です。まだ無いものだけ手元から引き継ぎます。
for f in latest.json history.json accuracy.json; do
  if [ ! -f "$APP_DIR/docs/data/$f" ] && [ -f "$SRC_DIR/docs/data/$f" ]; then
    cp "$SRC_DIR/docs/data/$f" "$APP_DIR/docs/data/$f"
  fi
done

echo "== 3. Python と Playwright"
# 取り込みのうち collect.py と verify.py は Python だけで動きますが、
# ウェザーニュースの1時間ごと予報は画面側で組み立てられるため
# collect_browser.py がブラウザ(chromium)を使います。
[ -x "$APP_DIR/venv/bin/python3" ] || python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --quiet --upgrade pip
"$APP_DIR/venv/bin/pip" install --quiet playwright
PLAYWRIGHT_BROWSERS_PATH="$APP_DIR/.playwright" \
  "$APP_DIR/venv/bin/playwright" install --with-deps chromium

# Caddy(別の利用者)が docs/ を読めるように、通り道は開けておきます
chown -R weather:weather "$APP_DIR"
chmod 755 "$APP_DIR" "$APP_DIR/docs"

echo "== 4. systemd"
install -m 644 "$APP_DIR/deploy/weather-collect.service" /etc/systemd/system/weather-collect.service
install -m 644 "$APP_DIR/deploy/weather-collect.timer"   /etc/systemd/system/weather-collect.timer
systemctl daemon-reload
systemctl enable --now weather-collect.timer
systemctl --no-pager list-timers weather-collect.timer || true

echo "== 5. Caddy"
# 土地サーチの /etc/caddy/Caddyfile を書き換えずに相乗りするため、
# 各アプリの設定は /etc/caddy/conf.d/ に置いて import させます。
if ! command -v caddy >/dev/null; then
  echo "  Caddy が入っていません。土地サーチの setup_vps.sh を先に走らせてください。" >&2
  exit 1
fi
mkdir -p /etc/caddy/conf.d
install -m 644 "$APP_DIR/deploy/weather.caddy" /etc/caddy/conf.d/weather.caddy
if ! grep -q '/etc/caddy/conf.d' /etc/caddy/Caddyfile; then
  printf '\n# 各アプリの公開設定はここから読みます\nimport /etc/caddy/conf.d/*.caddy\n' \
    >> /etc/caddy/Caddyfile
  echo "  /etc/caddy/Caddyfile に import を足しました"
fi
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy

echo "== 6. 初回の取り込み"
systemctl start weather-collect.service || true
systemctl --no-pager --lines=10 status weather-collect.service || true

echo
echo "== 完了"
echo "  取り込み: systemctl list-timers weather-collect.timer"
echo "  すぐ動かす: systemctl start weather-collect.service"
echo "  ログ    : journalctl -u weather-collect -f"
echo "  URL     : https://$DOMAIN  (DNSのAレコード設定後に有効)"
