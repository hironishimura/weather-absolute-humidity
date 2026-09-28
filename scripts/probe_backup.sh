#!/bin/bash
# deploy/backup_data.sh の控えの残し方を確かめる。
# history.json は過去の予報の書きためで、あとから取り寄せられない。
# ここが静かに壊れると、失ってから気づくことになる。
set -u
cd "$(dirname "$0")/.."
T=/tmp/bk; rm -rf "${T:?}"; mkdir -p "$T/docs/data"
export WEATHER_APP_DIR=$T WEATHER_BACKUP_KEEP=3
D=$T/docs/data
TODAY=$(date +%Y-%m-%d)
ng=0
say () { printf '%-40s ' "$1"; }
pass () { echo "通った"; }
fail () { echo "★ 通らない${1:+  → $1}"; ng=1; }

good () {
  printf '{"a":1}\n'  > "$D/latest.json"
  printf '[1,2,3]\n'  > "$D/history.json"
  printf '{"b":2}\n'  > "$D/accuracy.json"
}

good; bash deploy/backup_data.sh >/dev/null 2>&1
say "① 3つとも控える"
[ "$(ls -1 "$T/backup/$TODAY" 2>/dev/null | wc -l)" -eq 3 ] && pass || fail

say "② 中身がそのまま残る"
[ "$(cat "$T/backup/$TODAY/history.json")" = "[1,2,3]" ] && pass || fail

rm -rf "${T:?}/backup/$TODAY"
printf '{"a":1' > "$D/latest.json"     # 閉じていない
bash deploy/backup_data.sh >/dev/null 2>&1
say "③ 壊れた JSON は控えない"
[ ! -f "$T/backup/$TODAY/latest.json" ] && pass || fail "壊れたものを控えてしまった"

say "④ 無事なものは控える"
[ -f "$T/backup/$TODAY/history.json" ] && pass || fail

good
for d in 2026-09-01 2026-09-02 2026-09-03 2026-09-04 2026-09-05; do
  mkdir -p "$T/backup/$d"; printf '{}' > "$T/backup/$d/latest.json"
done
bash deploy/backup_data.sh >/dev/null 2>&1
say "⑤ 決めた日数に収まる"
[ "$(ls -1 "$T/backup" | wc -l)" -eq 3 ] && pass || fail "$(ls -1 "$T/backup" | tr '\n' ' ')"

say "⑥ 消えるのは古いほうから"
[ ! -d "$T/backup/2026-09-01" ] && [ -d "$T/backup/2026-09-05" ] && pass || fail

rm -f "${D:?}"/*.json; rm -rf "${T:?}/backup/$TODAY"
bash deploy/backup_data.sh >/dev/null 2>&1
say "⑦ 値が無くても落ちない"
[ $? -eq 0 ] && pass || fail

say "⑧ 空の日は作らない"
[ ! -d "$T/backup/$TODAY" ] && pass || fail

# 配るたびに控えが消えないこと。--delete があるので取りこぼすと痛い。
say "⑨ 配布時に控えを消さない（除外してある）"
grep -q "exclude 'backup'" deploy/update_vps.sh && grep -q "exclude 'backup'" deploy/setup_vps.sh \
  && pass || fail "rsync --delete が backup を消します"

say "⑩ 取り込みの最後に控えが呼ばれる"
grep -q 'backup_data.sh' deploy/weather-collect.service && pass || fail

[ $ng -eq 0 ] && echo "すべて確認できました" || echo "落ちたものがあります"
exit $ng
