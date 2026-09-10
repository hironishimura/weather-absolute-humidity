import XCTest
@testable import WeatherCore

final class 平均: XCTestCase {

    func nows() -> [SourceKey: NowValue] {
        [
            .jma: NowValue(time: nil, values: Reading(temp: 24.0, rh: 70, pressure: 1002)!),
            .model: NowValue(time: nil, values: Reading(temp: 26.0, rh: 60)!),
            .yahoo: NowValue(time: nil, values: Reading(temp: 25.0, rh: 65)!)
        ]
    }

    func test_取れているぶんだけで平均する() {
        let a = Aggregate.average(nows())
        XCTAssertEqual(a.temp ?? 0, 25.0, accuracy: 0.001)
        XCTAssertEqual(a.rh ?? 0, 65.0, accuracy: 0.001)
        XCTAssertEqual(a.counts["temp"], 3)
        XCTAssertEqual(a.used.count, 3)
    }

    func test_気圧は持っている提供元だけ() {
        let a = Aggregate.average(nows())
        XCTAssertEqual(a.counts["pressure"], 1)
        XCTAssertEqual(a.pressure ?? 0, 1002, accuracy: 0.001)
    }

    func test_ひとつもなければ空() {
        let a = Aggregate.average([:])
        XCTAssertNil(a.temp)
        XCTAssertTrue(a.used.isEmpty)
    }

    func test_絶対湿度も平均される() {
        let a = Aggregate.average(nows())
        XCTAssertNotNil(a.vh)
        XCTAssertGreaterThan(a.vh ?? 0, 10)
    }
}

final class 日ごとにまとめる: XCTestCase {

    var rows: [HourlyRow] {
        [
            HourlyRow.make(time: JST.date(2026, 9, 9, 3), temp: 18, rh: 90)!,
            HourlyRow.make(time: JST.date(2026, 9, 9, 14), temp: 29, rh: 50)!,
            HourlyRow.make(time: JST.date(2026, 9, 9, 23), temp: 21, rh: 80)!,
            HourlyRow.make(time: JST.date(2026, 9, 10, 5), temp: 17, rh: 95)!
        ]
    }

    func test_最高と最低() {
        let d = Aggregate.daily(fromHourly: rows)
        XCTAssertEqual(d["2026-09-09"]?.max, 29)
        XCTAssertEqual(d["2026-09-09"]?.min, 18)
        XCTAssertEqual(d["2026-09-10"]?.max, 17)
    }

    func test_絶対湿度の幅も出る() {
        let d = Aggregate.daily(fromHourly: rows)["2026-09-09"]
        XCTAssertNotNil(d?.ahMin)
        XCTAssertNotNil(d?.ahMax)
        XCTAssertLessThan(d!.ahMin!, d!.ahMax!)
    }

    func test_時間帯の降水確率を日ごとに直す() {
        let blocks = [
            PopBlock(time: JST.date(2026, 9, 9, 0), hours: 6, pop: 10),
            PopBlock(time: JST.date(2026, 9, 9, 6), hours: 6, pop: 70),
            PopBlock(time: JST.date(2026, 9, 9, 12), hours: 12, pop: 30)
        ]
        let byDay = Aggregate.dailyPops(fromBlocks: blocks)
        XCTAssertEqual(byDay["2026-09-09"], 70)     // その日のいちばん高い値
    }

    func test_日をまたぐ区切りは両方の日に入る() {
        let blocks = [PopBlock(time: JST.date(2026, 9, 9, 18), hours: 12, pop: 60)]
        let byDay = Aggregate.dailyPops(fromBlocks: blocks)
        XCTAssertEqual(byDay["2026-09-09"], 60)
        XCTAssertEqual(byDay["2026-09-10"], 60)
    }

    func test_降水確率が空いている日を埋める() {
        let jma = [DailyForecast(key: "2026-09-09", date: JST.date(2026, 9, 9), weather: "くもり")]
        let table = Aggregate.weekly(
            jmaDaily: jma, modelRows: [], snapshot: [],
            popBlocks: [.jma: [PopBlock(time: JST.date(2026, 9, 9, 6), hours: 6, pop: 40)]])
        XCTAssertEqual(table[.jma]?["2026-09-09"]?.pop, 40)
        XCTAssertEqual(table[.jma]?["2026-09-09"]?.weather, "くもり")
    }

    func test_発表値があれば上書きしない() {
        let jma = [DailyForecast(key: "2026-09-09", date: JST.date(2026, 9, 9), pop: 80)]
        let table = Aggregate.weekly(
            jmaDaily: jma, modelRows: [], snapshot: [],
            popBlocks: [.jma: [PopBlock(time: JST.date(2026, 9, 9, 6), hours: 6, pop: 40)]])
        XCTAssertEqual(table[.jma]?["2026-09-09"]?.pop, 80)
    }

    func test_週間表があるほうを優先する() {
        let src = SnapshotSource(
            key: .yahoo, ok: true, label: "宇都宮", error: nil, now: nil,
            rows: rows,
            weekly: [DailyForecast(key: "2026-09-09", date: JST.date(2026, 9, 9),
                                   weather: "雨", pop: 90, min: 19, max: 25)],
            pops: [])
        let table = Aggregate.weekly(jmaDaily: [], modelRows: [], snapshot: [src], popBlocks: [:])
        let day = table[.yahoo]?["2026-09-09"]
        XCTAssertEqual(day?.weather, "雨")
        XCTAssertEqual(day?.max, 25)          // 週間表の値
        XCTAssertNotNil(day?.ahMax)           // 時間ごとから出した絶対湿度は残る
    }

    func test_降水確率の階段() {
        let steps = Aggregate.popSteps([PopBlock(time: JST.date(2026, 9, 9, 6), hours: 6, pop: 40)])
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].pop, 40)
        XCTAssertEqual(steps[1].time, JST.date(2026, 9, 9, 11, 59))
    }
}

final class グラフの目盛り: XCTestCase {

    // 表示範囲は「過去24時間＋先N日」なので 1日=48h・2日=72h・3日=96h・7日=192h
    func test_広い画面() {
        XCTAssertEqual(AxisTicks.hours(span: 48, usable: 1006).step, 3)
        XCTAssertEqual(AxisTicks.hours(span: 72, usable: 1006).step, 3)
        XCTAssertEqual(AxisTicks.hours(span: 96, usable: 1006).step, 6)
        XCTAssertEqual(AxisTicks.hours(span: 192, usable: 1006).step, 24)
    }

    func test_せまい画面() {
        XCTAssertEqual(AxisTicks.hours(span: 48, usable: 298).step, 6)
        XCTAssertEqual(AxisTicks.hours(span: 72, usable: 298).step, 6)
        XCTAssertEqual(AxisTicks.hours(span: 96, usable: 298).step, 12)
    }

    func test_せまいときは時を省く() {
        XCTAssertTrue(AxisTicks.hours(span: 48, usable: 1006).withUnit)
        XCTAssertFalse(AxisTicks.hours(span: 72, usable: 298).withUnit)
    }

    func test_どんなに狭くても24時間より粗くしない() {
        XCTAssertEqual(AxisTicks.hours(span: 192, usable: 40).step, 24)
    }

    func test_刻みは決まった値だけ() {
        for span in [8.0, 24, 48, 72, 96, 192] {
            for w in [40.0, 100, 298, 658, 1006, 1400] {
                XCTAssertTrue([1, 2, 3, 6, 12, 24].contains(AxisTicks.hours(span: span, usable: w).step))
            }
        }
    }

    func test_目盛りの時刻は刻みの倍数() {
        let from = JST.date(2026, 9, 9, 13, 20)
        let marks = AxisTicks.hourMarks(from: from, to: from.addingTimeInterval(48 * 3600), step: 6)
        XCTAssertFalse(marks.isEmpty)
        for m in marks {
            XCTAssertEqual((JST.parts(m).hour ?? 1) % 6, 0)
            XCTAssertGreaterThanOrEqual(m, from)
        }
    }

    func test_縦軸はキリのよい数字() {
        let s = AxisTicks.nice(min: 17.3, max: 29.4)
        XCTAssertLessThanOrEqual(s.min, 17.3)
        XCTAssertGreaterThanOrEqual(s.max, 29.4)
        XCTAssertTrue([1.0, 2.0, 2.5, 5.0, 10.0].contains(s.step))
    }

    func test_同じ値ばかりでも軸が潰れない() {
        let s = AxisTicks.nice(min: 20, max: 20)
        XCTAssertLessThan(s.min, s.max)
    }

    func test_日の切れ目() {
        let from = JST.date(2026, 9, 9, 13)
        let starts = AxisTicks.dayStarts(from: from, to: from.addingTimeInterval(48 * 3600))
        XCTAssertEqual(starts, [JST.date(2026, 9, 10), JST.date(2026, 9, 11)])
    }
}


final class 雨量とグラフの範囲: XCTestCase {

    func test_雨量の項目が増えている() {
        XCTAssertTrue(ChartField.allCases.contains(.precip))
        XCTAssertEqual(ChartField.precip.title, "雨量")
        XCTAssertEqual(ChartField.precip.unit, "mm/h")
        XCTAssertTrue(ChartField.precip.startsAtZero)
        // 折れ線で出します。刻みの違う提供元があるので点も見せます
        XCTAssertTrue(ChartField.precip.showsPoints)
        XCTAssertEqual(ChartField.precip.interpolation, .straight)
        XCTAssertEqual(ChartField.pop.interpolation, .stepEnd)
        XCTAssertEqual(ChartField.temp.interpolation, .smooth)
        XCTAssertFalse(ChartField.temp.showsPoints)
    }

    func test_雨量だけの点も並びに入る() {
        // 気温も湿度もなくても、雨量があれば1点として残します
        let row = HourlyRow.make(time: JST.date(2026, 9, 10, 3), temp: nil, rh: nil, precip: 2.5)
        XCTAssertEqual(row?.precip, 2.5)
    }

    func test_なにもなければ点にしない() {
        XCTAssertNil(HourlyRow.make(time: JST.date(2026, 9, 10, 3),
                                    temp: nil, rh: nil, pop: nil, precip: nil))
    }

    func test_グラフの過去は1時間() {
        XCTAssertEqual(ChartWindow.pastHours, 1)
        XCTAssertEqual(ChartWindow.span(days: 1), 25)
        XCTAssertEqual(ChartWindow.span(days: 7), 169)
    }

    func test_目盛りは過去1時間ぶんでも決められる() {
        // 1日表示（25時間）と7日表示（169時間）
        XCTAssertTrue([1, 2, 3, 6, 12, 24].contains(
            AxisTicks.hours(span: ChartWindow.span(days: 1), usable: 1006).step))
        XCTAssertEqual(AxisTicks.hours(span: ChartWindow.span(days: 7), usable: 1006).step, 24)
    }

    func test_ECMWFが提供元に入っている() {
        XCTAssertTrue(SourceKey.allCases.contains(.ecmwf))
        XCTAssertEqual(SourceKey.ecmwf.name, "ECMWF")
        XCTAssertEqual(SourceKey.ecmwf.defaultHex, "#7B3FA0")
        // 色は提供元ごとに別であること（同じだと線の見分けがつきません）
        let hexes = SourceKey.allCases.map(\.defaultHex)
        XCTAssertEqual(Set(hexes).count, hexes.count)
    }

    func test_ECMWFは降水確率を数えない() {
        // Open-Meteo はモデル指定つきだと降水確率を返しません（実測で確認）
        XCTAssertFalse(SourceKey.withPop.contains(.ecmwf))
        XCTAssertTrue(SourceKey.withPop.contains(.model))
        XCTAssertEqual(SourceKey.withPop.count, SourceKey.allCases.count - 1)
    }

    func test_ECMWFのURLにモデル名が入る() {
        let c = OpenMeteoClient(fetcher: URLSessionFetcher())
        let url = c.valuesURL(.宇都宮, withModel: true, models: "ecmwf_ifs025")
        XCTAssertTrue(url.absoluteString.contains("models=ecmwf_ifs025"), url.absoluteString)
        // 雨量を頼み忘れると雨量のグラフが消えます
        XCTAssertTrue(url.absoluteString.contains("precipitation"), url.absoluteString)
    }

    func test_絶対湿度は重量で出す() {
        XCTAssertEqual(ChartField.ah.title, "絶対湿度")
        XCTAssertEqual(ChartField.ah.unit, "g/kg(DA)")
        // 22℃70% なら 12前後（g/m³ なら14前後）。取り違えるとここで落ちます
        let row = HourlyRow.make(time: JST.date(2026, 9, 10, 3), temp: 22, rh: 70)!
        let v = ChartField.ah.value(row)!
        XCTAssertEqual(v, 11.6, accuracy: 0.6)
        XCTAssertNotEqual(v, row.vh!, accuracy: 0.5)
    }

    func test_3時間ごとの雨量は1時間あたりに直す() {
        // Yahoo!天気は3時間ぶんの合計で出しています
        let pts = [0, 3, 6, 9].map {
            ChartPoint(time: JST.date(2026, 9, 10, $0), value: 6)
        }
        let per = ChartField.perHour(pts)
        XCTAssertEqual(per.map(\.value), [2, 2, 2, 2])
        XCTAssertEqual(per.map(\.time), pts.map(\.time))
    }

    func test_1時間ごとの雨量はそのまま() {
        let pts = [0, 1, 2].map { ChartPoint(time: JST.date(2026, 9, 10, $0), value: 4) }
        XCTAssertEqual(ChartField.perHour(pts).map(\.value), [4, 4, 4])
    }

    func test_点がひとつなら割らない() {
        let pts = [ChartPoint(time: JST.date(2026, 9, 10, 0), value: 6)]
        XCTAssertEqual(ChartField.perHour(pts).map(\.value), [6])
    }

    /// 0が続く区間に線を引くと、わずかに降る予報と見分けがつきません
    private func rain(_ values: [Double]) -> [ChartSeries] {
        let pts = values.enumerated().map {
            ChartPoint(time: JST.date(2026, 9, 10, 0).addingTimeInterval(Double($0.offset) * 3600),
                       value: $0.element)
        }
        return ChartField.rainSegments(ChartSeries(key: .model, points: pts))
    }

    func test_降っていない区間は線にしない() {
        let segs = rain([0, 0, 0, 2, 3, 0, 0, 0, 1, 0, 0])
        XCTAssertEqual(segs.count, 2)
        // 山の足元（前後ひとつずつの0）は残します
        XCTAssertEqual(segs[0].points.map(\.value), [0, 2, 3, 0])
        XCTAssertEqual(segs[1].points.map(\.value), [0, 1, 0])
    }

    func test_ずっと降らなければ線はない() {
        XCTAssertTrue(rain([0, 0, 0, 0]).isEmpty)
    }

    func test_ずっと降るなら1本のまま() {
        let segs = rain([1, 2, 3])
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].points.map(\.value), [1, 2, 3])
    }

    func test_山ごとに別のidになる() {
        // 山の足元を残すので、0が2つ以上あいて初めて線が切れます
        let segs = rain([0, 1, 0, 0, 0, 2, 0])
        XCTAssertEqual(segs.count, 2)
        guard segs.count == 2 else { return }
        XCTAssertNotEqual(segs[0].id, segs[1].id)
        // 色分けは提供元で決めるので、key は同じままです
        XCTAssertEqual(segs[0].key, segs[1].key)
    }

    func test_0がひとつだけなら線はつながったまま() {
        // 足元の0が隣り合うため、切りません
        let segs = rain([0, 1, 0, 2, 0])
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs.first?.points.map(\.value), [0, 1, 0, 2, 0])
    }
}
