#!/bin/bash
# deploy/ の公開設定と合言葉まわりを、本物の Caddy で通しで確かめる。
# サーバーに触る前にここで落としたい。GitHub Actions から呼ばれる。
set -u
cd "$(dirname "$0")/.."
T=/tmp/ct; rm -rf $T; mkdir -p $T/conf.d
ng=0

say () { printf '%-44s ' "$1"; }
pass () { echo "通った"; }
fail () { echo "★ 通らない"; ng=1; [ -n "${1-}" ] && sed 's/^/      /' "$1" | tail -4; }

# 本番の設定をそのまま使う。証明書を取りに行かせたくないので宛先だけ差し替え、
# 合言葉の置き場も、ここで作れる場所へ向け直す。
export WEATHER_AUTH_DIR=$T/weather-auth.d
WEATHER_AUTH_FILE=$WEATHER_AUTH_DIR/auth.conf
sed -e 's|^weather\.shome\.co\.jp {|http://localhost:8080 {|' \
    -e "s|/etc/caddy/weather-auth\.d|$WEATHER_AUTH_DIR|" \
    deploy/weather.caddy > $T/conf.d/weather.caddy
printf 'import %s/conf.d/*.caddy\n' "$T" > $T/Caddyfile
grep -q "$WEATHER_AUTH_DIR" $T/conf.d/weather.caddy \
  || { echo "読み込み先の差し替えに失敗しました" >&2; exit 1; }
mkdir -p "$WEATHER_AUTH_DIR"

export WEATHER_CADDYFILE=$T/Caddyfile
export WEATHER_RELOAD=no

# 読み込む先を、setup_vps.sh と同じ初期状態（空のフォルダ）にする
rm -f "$WEATHER_AUTH_DIR"/*.conf

say "① 合言葉なしの初期状態で設定が通る"
caddy validate --config $T/Caddyfile >$T/o 2>&1 && pass || fail $T/o

say "② 合言葉を決められる"
if WEATHER_PASSWORD='tochigi-2026!' bash deploy/set_password.sh </dev/null >$T/o 2>&1; then
  pass
else
  fail $T/o
fi

say "③ 決めたあとも設定が通る"
caddy validate --config $T/Caddyfile >$T/o 2>&1 && pass || fail $T/o

say "④ 合言葉が平文で残っていない"
if grep -q 'tochigi-2026!' "$WEATHER_AUTH_FILE"; then fail; else pass; fi

say "⑤ bcrypt のハッシュになっている"
grep -qE '^\s*hiro\s+\$2[aby]\$' "$WEATHER_AUTH_FILE" && pass || fail "$WEATHER_AUTH_FILE"

say "⑥ /data/ は鍵の対象から外れている"
grep -q 'not path /data/\*' $T/conf.d/weather.caddy && pass || fail

say "⑦ 短い合言葉は断る"
if WEATHER_PASSWORD='短い' bash deploy/set_password.sh </dev/null >$T/o 2>&1; then
  fail $T/o
else
  pass
fi

say "⑧ 断られても前の合言葉が残っている"
grep -qE '^\s*hiro\s+\$2[aby]\$' "$WEATHER_AUTH_FILE" && pass || fail "$WEATHER_AUTH_FILE"

say "⑨ 合言葉をやめられる（ファイルごと消える）"
bash deploy/set_password.sh --off >$T/o 2>&1 && pass || fail $T/o

say "⑩ やめたあとも設定が通る"
caddy validate --config $T/Caddyfile >$T/o 2>&1 && pass || fail $T/o

say "⑪ 壊れた合言葉ファイルは元に戻す"
printf 'basic_auth @locked {\n\tこわれた\n' > "$WEATHER_AUTH_FILE"   # 閉じ括弧なし
cp "$WEATHER_AUTH_FILE" $T/broken
if WEATHER_PASSWORD='tochigi-2026!' bash deploy/set_password.sh </dev/null >$T/o 2>&1; then
  # 壊れていたファイルを正しいもので置き換えられたなら、それで良い
  caddy validate --config $T/Caddyfile >/dev/null 2>&1 && pass || fail $T/o
else
  fail $T/o
fi

# ---- 置き場が丸ごと消えたとき ----
# 土地サーチと同じ Caddyfile なので、ここで全体が読めなくなると巻き添えになる。
say "⑫ 合言葉の置き場が消えても設定は通る"
mv "$WEATHER_AUTH_DIR" $T/away
caddy validate --config $T/Caddyfile >$T/o 2>&1 && pass || fail $T/o
mv $T/away "$WEATHER_AUTH_DIR"

say "⑬ 消えた置き場は作り直せる"
WEATHER_PASSWORD='tochigi-2026!' bash deploy/set_password.sh </dev/null >$T/o 2>&1 \
  && pass || fail $T/o

say "⑭ 作り直したあとも設定が通る"
caddy validate --config $T/Caddyfile >$T/o 2>&1 && pass || fail $T/o

echo
echo "できあがった合言葉ファイル:"
sed 's/^/    /' "$WEATHER_AUTH_FILE" 2>/dev/null || echo "    （ありません）"
echo "caddy version: $(caddy version)"
[ $ng -eq 0 ] && echo "すべて確認できました" || echo "落ちたものがあります"
exit $ng
