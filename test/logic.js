/* app.js の計算とパース処理を、DOMとネットワークを差し替えて確かめます */
const fs = require('fs');
const vm = require('vm');
const path = require('path');


const src = fs.readFileSync(path.join(__dirname, '..', 'docs', 'assets', 'app.js'), 'utf8');

const listeners = {};
const doc = {
  readyState: 'loading',
  addEventListener: (k, f) => { listeners[k] = f; },
  getElementById: () => null,
  querySelectorAll: () => [],
  createElement: () => ({ style:{}, appendChild(){}, setAttribute(){} }),
  createElementNS: () => ({ style:{}, appendChild(){}, setAttribute(){} }),
  visibilityState: 'hidden'
};
const ctx = {
  document: doc,
  navigator: {},
  localStorage: { getItem: () => null, setItem: () => {} },
  fetch: () => Promise.reject(new Error('no network')),
  setTimeout, clearTimeout, setInterval: () => 0,
  Intl, console, Math, Date, JSON, Object, Array, Number, String, Promise, isFinite, parseFloat,
  AbortController: undefined
};
ctx.window = ctx;
vm.createContext(ctx);
vm.runInContext(src, ctx, { filename: 'app.js' });

let pass = 0;
function ok(name, cond, extra) {
  if (cond) { pass++; console.log('  ok   ' + name); }
  else { console.log('  FAIL ' + name + (extra ? '  → ' + extra : '')); process.exitCode = 1; }
}
function near(a, b, tol) { return Math.abs(a - b) <= tol; }

console.log('\n■ 湿り空気の計算');
const vh20 = ctx.volumetricHumidity(20, 60);
ok('20℃60% の容積絶対湿度 ≒ 10.4 g/m³', near(vh20, 10.4, 0.15), vh20.toFixed(3));
const vhSat25 = ctx.volumetricHumidity(25, 100);
ok('25℃100% の容積絶対湿度 ≒ 23.0 g/m³', near(vhSat25, 23.0, 0.2), vhSat25.toFixed(3));
const vhSat0 = ctx.volumetricHumidity(0, 100);
ok('0℃100% の容積絶対湿度 ≒ 4.85 g/m³', near(vhSat0, 4.85, 0.1), vhSat0.toFixed(3));
const mr20 = ctx.mixingRatio(20, 60, 1013.25);
ok('20℃60% の重量絶対湿度 ≒ 8.7 g/kg(DA)', near(mr20, 8.73, 0.15), mr20.toFixed(3));
const dp20 = ctx.dewPoint(20, 60);
ok('20℃60% の露点 ≒ 12.0℃', near(dp20, 12.0, 0.2), dp20.toFixed(3));
const dp25 = ctx.dewPoint(25, 40);
ok('25℃40% の露点 ≒ 10.5℃', near(dp25, 10.5, 0.3), dp25.toFixed(3));
ok('100%のとき露点＝気温', near(ctx.dewPoint(18, 100), 18, 0.05), ctx.dewPoint(18,100).toFixed(3));
ok('湿度0%でもNaNを返さない', isFinite(ctx.dewPoint(20, 0)));
const di = ctx.discomfortIndex(28, 70);
ok('28℃70% の不快指数 ≒ 78.4', near(di, 78.4, 0.2), di.toFixed(2));
ok('標高0mの推定気圧 ≒ 1013hPa', near(ctx.pressureFromAltitude(0, 15), 1013.25, 0.5));
ok('標高が上がると気圧が下がる', ctx.pressureFromAltitude(1000, 15) < 1000);
ok('derive は気温が数値でないと null', ctx.derive(null, 50) === null);

console.log('\n■ 補助関数');
ok('dm2deg([35,41.4]) ≒ 35.69', near(ctx.dm2deg([35, 41.4]), 35.69, 0.01), ctx.dm2deg([35,41.4]).toFixed(4));
ok('amedasValue が [値,フラグ] を読む', ctx.amedasValue({ temp: [25.3, 0] }, 'temp') === 25.3);
ok('amedasValue は欠測で NaN', Number.isNaN(ctx.amedasValue({ temp: [null, 5] }, 'temp')));
ok('amedasValue は項目なしで NaN', Number.isNaN(ctx.amedasValue({}, 'humidity')));
const d1 = ctx.parseJmaStamp('20260908141000');
ok('parseJmaStamp が日本時間として解釈する', d1.toISOString() === '2026-09-08T05:10:00.000Z', d1 && d1.toISOString());
ok('宇都宮〜東京の距離 ≒ 100km', near(ctx.distanceKm(36.5551, 139.8828, 35.6895, 139.6917), 99, 6),
   ctx.distanceKm(36.5551,139.8828,35.6895,139.6917).toFixed(1));
ok('風向16方位', ctx.windText({ wind: [3.2, 0], windDirection: [1, 0] }) === '北 3.2 m/s', ctx.windText({wind:[3.2,0],windDirection:[1,0]}));
ok('静穏', ctx.windText({ wind: [0, 0], windDirection: [0, 0] }) === '静穏 0.0 m/s', ctx.windText({wind:[0,0],windDirection:[0,0]}));

console.log('\n■ 予報区の自動判定');
ctx.state.offices = { '090000': '栃木県', '130000': '東京都', '016000': '石狩・空知・後志地方' };
ok('宇都宮 → 栃木県', ctx.resolveOffice({ lat: 36.5551, lon: 139.8828 }) === '090000');
ok('東京駅 → 東京都', ctx.resolveOffice({ lat: 35.6812, lon: 139.7671 }) === '130000');
ok('札幌 → 石狩・空知・後志地方', ctx.resolveOffice({ lat: 43.0618, lon: 141.3545 }) === '016000');
ok('手で指定したらそれを使う', ctx.resolveOffice({ lat: 36.5, lon: 139.8, office: '110000' }) === '110000');
ok('area.json に名前がなければ控えのコード', ctx.resolveOffice({ lat: 34.6937, lon: 135.5023 }) === '270000');

console.log('\n■ 最寄り観測所の並べ替え');
const table = {
  '41277': { kjName: '宇都宮', lat: [36, 33.0], lon: [139, 52.2], alt: 119 },
  '44132': { kjName: '東京',   lat: [35, 41.4], lon: [139, 45.6], alt: 25 },
  '99999': { kjName: '壊れた地点' }
};
const near3 = ctx.nearestStations(table, 36.5551, 139.8828, 10);
ok('近い順に並ぶ', near3[0].code === '41277' && near3[1].code === '44132');
ok('緯度経度のない地点は除く', near3.length === 2);
ok('距離が入る', near3[0].km < 5, near3[0].km.toFixed(2));

console.log('\n■ 天気コード');
ok('100 → 晴れ', ctx.TELOP['100'] === '晴れ');
ok('218 → くもり後雨か雪', ctx.TELOP['218'] === 'くもり後雨か雪');
ok('コード数', Object.keys(ctx.TELOP).length > 90, Object.keys(ctx.TELOP).length);

console.log('\n■ 予報JSONの読み取り');
ctx.cache.amedasTable = table;
const forecast = [
  {
    reportDatetime: '2026-09-08T17:00:00+09:00',
    timeSeries: [
      {
        timeDefines: ['2026-09-08T17:00:00+09:00', '2026-09-09T00:00:00+09:00', '2026-09-10T00:00:00+09:00'],
        areas: [{ area: { name: '南部', code: '090010' },
          weatherCodes: ['200', '101', '206'],
          weathers: ['くもり', '晴れ　時々　くもり', 'くもり　一時　雨'] }]
      },
      {
        timeDefines: ['2026-09-08T18:00:00+09:00', '2026-09-09T00:00:00+09:00', '2026-09-09T06:00:00+09:00', '2026-09-09T12:00:00+09:00', '2026-09-09T18:00:00+09:00'],
        areas: [{ area: { name: '南部', code: '090010' }, pops: ['10', '0', '10', '30', '20'] }]
      },
      {
        timeDefines: ['2026-09-09T00:00:00+09:00', '2026-09-09T09:00:00+09:00', '2026-09-10T00:00:00+09:00', '2026-09-10T09:00:00+09:00'],
        areas: [{ area: { name: '宇都宮', code: '41277' }, temps: ['21', '29', '20', '27'] },
                { area: { name: '東京', code: '44132' }, temps: ['24', '31', '23', '30'] }]
      }
    ]
  },
  {
    timeSeries: [
      {
        timeDefines: ['2026-09-09T00:00:00+09:00', '2026-09-10T00:00:00+09:00', '2026-09-11T00:00:00+09:00'],
        areas: [{ area: { name: '宇都宮', code: '090000' },
          weatherCodes: ['101', '206', '300'], pops: ['20', '40', '70'], reliabilities: ['', 'A', 'B'] }]
      },
      {
        timeDefines: ['2026-09-09T00:00:00+09:00', '2026-09-10T00:00:00+09:00', '2026-09-11T00:00:00+09:00'],
        areas: [{ area: { name: '宇都宮', code: '41277' },
          tempsMin: ['', '20', '19'], tempsMax: ['', '28', '26'] }]
      }
    ]
  }
];
const overview = { text: '栃木県は、高気圧に覆われています。' };

ctx.getJSON = (url) => Promise.resolve(url.indexOf('overview') >= 0 ? overview : forecast);
ctx.state.offices = { '090000': '栃木県' };

ctx.loadForecast({ lat: 36.5551, lon: 139.8828 }).then(() => {
  const d = ctx.state.daily;
  ok('3日＋週間がまとまる', d.length === 4, d.length);
  ok('9/8 の天気', d[0].weather === 'くもり', d[0].weather);
  ok('9/9 の天気（空白を詰める）', d[1].weather === '晴れ時々くもり', d[1].weather);
  ok('9/9 の降水確率は最大値', d[1].pop === 30, d[1].pop);
  ok('9/9 の最低気温', d[1].min === 21, d[1].min);
  ok('9/9 の最高気温', d[1].max === 29, d[1].max);
  ok('近い方の気温予報地点（宇都宮）を選ぶ', d[2].min === 20 && d[2].max === 27, JSON.stringify([d[2].min, d[2].max]));
  ok('9/11 は週間予報から', d[3].min === 19 && d[3].max === 26 && d[3].weather === '雨', JSON.stringify(d[3]));
  ok('コードから天気名', d[2].weather === 'くもり一時雨', d[2].weather);
  ok('気象概況', ctx.state.overview.indexOf('高気圧') > 0);
  ok('予報区名', ctx.state.officeName === '栃木県');
  const st = ctx.state.status.find(s => s.key === 'jma_forecast');
  ok('取得状況に名前が出る', st && st.name === '気象庁（府県天気予報）', st && st.name);

  console.log('\n' + pass + ' 件確認しました' + (process.exitCode ? '（失敗あり）' : ''));
});
