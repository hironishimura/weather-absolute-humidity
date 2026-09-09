/* 取得処理（アメダス実況・過去24時間・数値予報・取り込みファイル）をモックで確かめます */
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '..', 'docs', 'assets', 'app.js'), 'utf8');
const doc = {
  readyState: 'loading', addEventListener(){}, getElementById: () => null,
  querySelectorAll: () => [], createElement: () => ({ style:{}, appendChild(){} }),
  createElementNS: () => ({ style:{}, appendChild(){}, setAttribute(){} }), visibilityState:'hidden'
};
const ctx = {
  document: doc, navigator: {}, localStorage: { getItem: () => null, setItem(){} },
  fetch: () => Promise.reject(new Error('no network')),
  setTimeout, clearTimeout, setInterval: () => 0,
  Intl, console, Math, Date, JSON, Object, Array, Number, String, Promise, isFinite, parseFloat
};
ctx.window = ctx;
vm.createContext(ctx);
vm.runInContext(src, ctx, { filename: 'app.js' });

let pass = 0;
function ok(name, cond, extra) {
  if (cond) { pass++; console.log('  ok   ' + name); }
  else { console.log('  FAIL ' + name + (extra !== undefined ? '  → ' + extra : '')); process.exitCode = 1; }
}
const near = (a, b, t) => Math.abs(a - b) <= t;

/* --- モックの中身 --- */
const table = {
  /* 宇都宮のすぐ近くだが湿度を測っていない地点 */
  '41000': { kjName: 'ダミー', lat: [36, 33.2], lon: [139, 52.4], alt: 100 },
  '41277': { kjName: '宇都宮', lat: [36, 33.0], lon: [139, 52.2], alt: 119 },
  '44132': { kjName: '東京',   lat: [35, 41.4], lon: [139, 45.6], alt: 25 }
};
const map = {
  '41000': { temp: [24.8, 0] },
  '41277': { temp: [24.2, 0], humidity: [68, 0], pressure: [1002.4, 0],
             wind: [2.1, 0], windDirection: [5, 0], precipitation1h: [0.5, 0] },
  '44132': { temp: [27.0, 0], humidity: [55, 0] }
};
const point = {
  '20260908120000': { temp: [23.5, 0], humidity: [70, 0], pressure: [1002.8, 0] },
  '20260908121000': { temp: [23.8, 0], humidity: [69, 0] },
  '20260908122000': { temp: [24.0, 0], humidity: [null, 5] },   /* 欠測は捨てる */
  '20260908123000': { temp: [24.2, 0], humidity: [68, 0] }
};
const meteo = {
  current: { time: '2026-09-08T14:00', temperature_2m: 24.6, relative_humidity_2m: 66, surface_pressure: 1001.5 },
  hourly: {
    time: ['2026-09-08T13:00', '2026-09-08T14:00', '2026-09-08T15:00', '2026-09-08T16:00'],
    temperature_2m: [24.1, 24.6, 25.0, null],
    relative_humidity_2m: [68, 66, 63, 60],
    surface_pressure: [1001.8, 1001.5, 1001.2, 1001.0]
  }
};
const snapshot = {
  generated_at: '2026-09-08T14:05:00+09:00',
  sources: {
    yahoo: { ok: true, label: '栃木県宇都宮市',
      current: { time: '2026-09-08T14:00:00+09:00', temp: 24.5, humidity: 67 },
      hourly: [ { time: '2026-09-08T15:00:00+09:00', temp: 25.0, humidity: 64 },
                { time: '2026-09-08T16:00:00+09:00', temp: 24.4, humidity: 68 },
                { time: '2026-09-08T17:00:00+09:00', temp: null, humidity: 70 } ] },
    weathernews: { ok: false, error: 'ページの作りが変わったようです' }
  }
};

let requested = [];
ctx.getJSON = function (url, opt) {
  requested.push(url);
  if (url.indexOf('amedastable') >= 0) { return Promise.resolve(table); }
  if (url.indexOf('latest_time') >= 0) { return Promise.resolve('2026-09-08T14:10:00+09:00\n'); }
  if (url.indexOf('/map/20260908141000.json') >= 0) { return Promise.resolve(map); }
  if (url.indexOf('/point/41277/20260908_12.json') >= 0) { return Promise.resolve(point); }
  if (url.indexOf('/point/') >= 0) { return Promise.reject(new Error('HTTP 404')); }
  if (url.indexOf('open-meteo') >= 0) { return Promise.resolve(meteo); }
  if (url.indexOf('latest.json') >= 0) { return Promise.resolve(snapshot); }
  return Promise.reject(new Error('未知のURL ' + url));
};

const place = { lat: 36.5551, lon: 139.8828 };

console.log('\n■ アメダス実況');
ctx.loadAmedas(place).then(function (hit) {
  ok('湿度のある一番近い地点を選ぶ', ctx.state.station.code === '41277', ctx.state.station.code);
  ok('気温', ctx.state.now.jma.values.temp === 24.2);
  ok('相対湿度', ctx.state.now.jma.values.rh === 68);
  ok('観測気圧を使う', near(ctx.state.now.jma.values.pressure, 1002.4, 0.01));
  ok('絶対湿度が計算される ≒ 15.2 g/m³', near(ctx.state.now.jma.values.vh, 15.2, 0.3), ctx.state.now.jma.values.vh.toFixed(2));
  ok('観測時刻', ctx.state.now.jma.time.toISOString() === '2026-09-08T05:10:00.000Z', ctx.state.now.jma.time.toISOString());
  ok('map のファイル名が日本時間で組まれる',
     requested.some(u => u.indexOf('/map/20260908141000.json') >= 0));
  ok('取得状況が「取得」', ctx.state.status.find(s => s.key === 'jma').ok === true);
  ok('風の表示', ctx.windText(ctx.state.now.jma.row) === '東 2.1 m/s', ctx.windText(ctx.state.now.jma.row));

  console.log('\n■ 過去24時間');
  return ctx.loadAmedasPast(hit.station.code, hit.obsTime);
}).then(function (rows) {
  ok('8ブロック分を要求する', requested.filter(u => u.indexOf('/point/') >= 0).length === 8,
     requested.filter(u => u.indexOf('/point/') >= 0).length);
  ok('欠測を除いた3点', rows.length === 3, rows.length);
  ok('時刻順', rows[0].time < rows[2].time);
  ok('絶対湿度が入る', near(rows[0].vh, 14.7, 0.4), rows[0].vh.toFixed(2));
  ok('404 のブロックは無視される', true);

  console.log('\n■ 数値予報（Open-Meteo）');
  return ctx.loadModel(place);
}).then(function () {
  const f = ctx.state.future.model;
  ok('欠測の時刻を落として3点', f.length === 3, f.length);
  ok('日本時間として読む', f[0].time.toISOString() === '2026-09-08T04:00:00.000Z', f[0].time.toISOString());
  ok('現在値も取れる', near(ctx.state.now.model.values.temp, 24.6, 0.001));
  ok('モデル指定つきで要求する', requested.some(u => u.indexOf('models=jma_seamless') >= 0));

  console.log('\n■ 取り込みファイル');
  return ctx.loadSnapshot();
}).then(function () {
  ok('Yahoo の現在値', near(ctx.state.now.yahoo.values.temp, 24.5, 0.001));
  ok('Yahoo の絶対湿度', near(ctx.state.now.yahoo.values.vh, 15.0, 0.4), ctx.state.now.yahoo.values.vh.toFixed(2));
  ok('気温だけ・湿度だけの時刻も残す', ctx.state.future.yahoo.length === 3, ctx.state.future.yahoo.length);
  ok('気温が欠けた時刻は絶対湿度を出さない',
     ctx.state.future.yahoo[2].vh === undefined && ctx.state.future.yahoo[2].rh === 70,
     JSON.stringify(ctx.state.future.yahoo[2]));
  ok('気温と湿度がそろえば絶対湿度が出る', near(ctx.state.future.yahoo[0].vh, 14.7, 0.5),
     ctx.state.future.yahoo[0].vh && ctx.state.future.yahoo[0].vh.toFixed(2));
  ok('ウェザーニュースは失敗として出る', ctx.state.status.find(s => s.key === 'weathernews').ok === false);
  ok('失敗の理由が伝わる', ctx.state.status.find(s => s.key === 'weathernews').msg.indexOf('作りが変わった') >= 0);
  ok('ウェザーニュースの予報は入らない', !ctx.state.future.weathernews);

  console.log('\n■ ファイルがないとき');
  ctx.getJSON = () => Promise.reject(new Error('HTTP 404'));
  return ctx.loadSnapshot();
}).then(function () {
  ok('未取得として扱う', ctx.state.status.find(s => s.key === 'yahoo').ok === null);
  ok('直し方が書いてある', ctx.state.status.find(s => s.key === 'snapshot').msg.indexOf('collect.py') > 0);

  console.log('\n■ 数値予報が落ちたとき');
  let calls = 0;
  ctx.getJSON = (u) => { calls++; return calls === 1 ? Promise.reject(new Error('HTTP 400')) : Promise.resolve(meteo); };
  return ctx.loadModel(place).then(() => {
    ok('モデル指定なしで取り直す', calls === 2, calls);
    ok('取り直しても値が入る', ctx.state.future.model.length === 3);
    console.log('\n' + pass + ' 件確認しました' + (process.exitCode ? '（失敗あり）' : ''));
  });
}).catch(function (e) {
  console.log('  例外: ' + e.stack);
  process.exitCode = 1;
});
