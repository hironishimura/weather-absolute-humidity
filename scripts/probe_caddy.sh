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
export WEATHER_AUTH_FILE=$T/weather-auth.conf
sed -e 's|^weather\.shome\.co\.jp {|http://localhost:8080 {|' \
    -e "s|/etc/caddy/weather-auth\.conf|$WEATHER_AUTH_FILE|" \
    deploy/weather.caddy > $T/conf.d/weather.caddy
printf 'import %s/conf.d/*.caddy\n' "$T" > $T/Caddyfile
grep -q "$WEATHER_AUTH_FILE" $T/conf.d/weather.caddy \
  || { echo "読み込み先の差し替えに失敗しました" >&2; exit 1; }

export WEATHER_CADDYFILE=$T/Caddyfile
export WEATHER_RELOAD=no

# 読み込む先を、setup_vps.sh と同じ初期状態にする
printf '# 合言葉はかけていません（set_password.sh で決められます）\n' > "$WEATHER_AUTH_FILE"

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

say "⑨ 合言葉をやめられる"
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

# ---- 読み込み先が消えたときどうなるか ----
# 土地サーチと同じ Caddyfile なので、ここで全体が読めなくなると困る。
say "⑫ 読み込み先が消えると設定が読めない（確認）"
mv "$WEATHER_AUTH_FILE" $T/away
if caddy validate --config $T/Caddyfile >$T/o 2>&1; then
  echo "消えても通った（そのほうが安全）"
else
  echo "やはり通らない → 消さない工夫が要る"
fi
mv $T/away "$WEATHER_AUTH_FILE"

say "⑬ 見つからなくても平気な書き方（*.conf）"
mkdir -p $T/authdir
sed "s|import $WEATHER_AUTH_FILE|import $T/authdir/*.conf|" $T/conf.d/weather.caddy \
  > $T/conf.d2.caddy
mkdir -p $T/c2 && cp $T/conf.d2.caddy $T/c2/weather.caddy
printf 'import %s/c2/*.caddy\n' "$T" > $T/Caddyfile2
if caddy validate --config $T/Caddyfile2 >$T/o 2>&1; then
  pass
else
  fail $T/o
fi

say "⑭ そこに合言葉を置いても通る"
printf 'basic_auth @locked {\n\thiro %s\n}\n' \
  "$(caddy hash-password --plaintext 'tochigi-2026!')" > $T/authdir/auth.conf
caddy validate --config $T/Caddyfile2 >$T/o 2>&1 && pass || fail $T/o

echo
echo "できあがった合言葉ファイル:"
sed 's/^/    /' "$WEATHER_AUTH_FILE"
echo "caddy version: $(caddy version)"
[ $ng -eq 0 ] && echo "すべて確認できました" || echo "落ちたものがあります"
exit $ng
