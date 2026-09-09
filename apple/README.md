# iPhone・iPad・Mac のアプリ

Web版と同じ中身を、Apple の端末で動くアプリにしたものです。
**ひとつのプロジェクトで iPhone・iPad・Mac の3つに入ります。**

登録した地点と提供元の色は **iCloud** で行き来するので、
iPhone で地点を足すと iPad と Mac にも出てきます。

```
apple/
  WeatherAH.xcodeproj      ← Xcode で開くのはこれ
  WeatherAH/               ← 画面（SwiftUI）
  WeatherCore/             ← 計算と取得（Swift パッケージ・単体テスト付き）
```

## 使うのに要るもの

| | 要るもの |
|---|---|
| Mac で動かす | Mac と Xcode 16 以降。**Apple ID だけでよく、お金はかかりません** |
| iPhone・iPad で動かす | 同上。ただし無料の Apple ID だと **7日ごとに入れ直し**が要ります |
| iCloud で同期する | **Apple Developer Program（年 12,800円ほど）** が要ります |
| 7日ごとの入れ直しをなくす | 同上 |

iCloud を使わない場合でもアプリはそのまま動きます。
そのときは地点や色が**その端末の中だけ**に残り、画面下の「取得状況」に
「この端末の中だけに保存しています」と出ます。

## 入れ方

### 1. Xcode で開く

```bash
open apple/WeatherAH.xcodeproj
```

### 2. 署名を自分のものにする

1. 左の一覧でいちばん上の **WeatherAH** を選ぶ
2. **TARGETS → WeatherAH → Signing & Capabilities**
3. **Team** を自分の Apple ID にする
4. **Bundle Identifier** を自分のものに変える
   （例：`jp.example.weather` など。世界でひとつの名前が要ります）

Apple ID を Xcode に入れていないときは
**Xcode → Settings → Accounts → ＋ → Apple ID** から足してください。

### 3. 動かす

画面上の実行先を選んで ▶ を押すだけです。

- **Mac** … 「My Mac」を選ぶ
- **iPhone・iPad** … ケーブルでつなぐか、同じ Wi-Fi にいる端末を選ぶ
  （はじめて入れたときは、端末側で
  **設定 → 一般 → VPNとデバイス管理** から自分の Apple ID を「信頼」してください）

## iCloud 同期を入れる

**Apple Developer Program に入っている場合だけ**できます。

1. **TARGETS → WeatherAH → Signing & Capabilities**
2. **＋ Capability** → **iCloud**
3. **Key-value storage** にチェックを入れる

これだけです。Xcode が権限ファイルを作ってくれます。
アプリ側は入っていれば自動で使い、入っていなければ端末内保存に落ちます。

同期しているのは次の3つです。**天気のデータは同期しません**
（それぞれの端末が気象庁などから直接取るためです）。

- 登録した地点（名前・緯度経度・並び順）
- いま選んでいる地点
- 提供元ごとの色

置き場所は iCloud のキーバリューストア（`NSUbiquitousKeyValueStore`）です。
1MB まで置けるので、地点の一覧には十分足ります。
端末どうしで食い違ったときは、**あとから書いたほうを採ります**。

> **同期されないときは**
> iCloud にサインインしているか、
> 設定 →〈自分の名前〉→ iCloud →「このアプリ」がオンかを確かめてください。
> どちらの端末も同じ Apple ID である必要があります。

## 中身

| ファイル | 何をするか |
|---|---|
| `WeatherCore/Psychrometrics.swift` | 絶対湿度・露点・不快指数などの計算 |
| `WeatherCore/JMAAmedas.swift` | 気象庁アメダスの実況と過去24時間 |
| `WeatherCore/JMAForecast.swift` | 気象庁の府県天気予報（3日＋週間） |
| `WeatherCore/OpenMeteo.swift` | 気象庁 MSM/GSM の1時間ごと予報 |
| `WeatherCore/Snapshot.swift` | Yahoo!天気・ウェザーニュース（取り込みファイル） |
| `WeatherCore/Accuracy.swift` | 降水確率の当たり具合 |
| `WeatherCore/Settings.swift` | 地点と色。iCloud との行き来もここ |
| `WeatherCore/AxisTicks.swift` | グラフの目盛りの決め方 |
| `WeatherAH/Views/` | 画面（SwiftUI） |

計算式も取得の仕方も **Web版とまったく同じ**です。
数字が食い違わないよう、Web版のテストと同じ値で確かめています。

### Yahoo!天気とウェザーニュースについて

この2社は公開APIがなく、端末から直接は読めません。
GitHub Actions が3時間おきにページを読んで
`docs/data/latest.json` に書き出したものを、アプリが読んでいます。

そのため**取り込み地点から40km以内の地点でだけ**この2社の値が出ます。
地点を増やすときは、リポジトリの `scripts/settings.json` に足してください
（詳しくは一番上の README にあります）。

気象庁と数値予報は、どこの地点を入れてもそのまま動きます。

## 確認

手元では Linux で作っているため Swift を動かせません。
そのかわり **GitHub Actions の macOS** で毎回確かめています
（`.github/workflows/apple-build.yml`）。

```bash
# 計算と読み取りの確認（Mac で）
swift test --package-path apple/WeatherCore

# iPhone / iPad / Mac それぞれのビルド
xcodebuild build -project apple/WeatherAH.xcodeproj -scheme WeatherAH \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild build -project apple/WeatherAH.xcodeproj -scheme WeatherAH \
  -destination 'platform=macOS'
```

## App Store には出していません

自分の端末で使うためのものです。
人に配るときは Apple Developer Program と、各社の利用規約の確認が要ります。
とくに Yahoo!天気とウェザーニュースはページを読んでいるので、
配布の前に必ず各社の規約をご確認ください。
