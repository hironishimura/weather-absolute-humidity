/* 計算と読み取りの確認をまとめて動かします
   　node app/weather/test/run.js                                        */
const { spawnSync } = require('child_process');
const path = require('path');

let failed = 0;
['logic.js', 'fetch.js'].forEach(function (f) {
  const r = spawnSync(process.execPath, [path.join(__dirname, f)], { stdio: 'inherit' });
  if (r.status !== 0) { failed++; }
});
if (failed) {
  console.log('\n' + failed + ' 個のファイルで失敗しました');
  process.exit(1);
}
console.log('\nすべて確認できました');
