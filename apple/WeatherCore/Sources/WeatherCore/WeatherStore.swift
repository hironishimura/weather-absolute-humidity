//  取得したものをぜんぶ持っておく入れもの
//
//  画面はここを見て描くだけにしてあります。

import Foundation
import Observation

@MainActor
@Observable
public final class WeatherStore {

    // MARK: - 取ってきたもの

    public private(set) var nows: [SourceKey: NowValue] = [:]
    public private(set) var past: [HourlyRow] = []
    public private(set) var future: [SourceKey: [HourlyRow]] = [:]
    public private(set) var popBlocks: [SourceKey: [PopBlock]] = [:]
    public private(set) var weekly: [SourceKey: [String: DailyForecast]] = [:]
    public private(set) var jmaDaily: [DailyForecast] = []
    public private(set) var station: Station?
    public private(set) var officeName: String = ""
    public private(set) var overview: String = ""
    public private(set) var accuracy: AccuracyResult?
    public private(set) var status: [StatusLine] = []
    public private(set) var updatedAt: Date?

    public private(set) var isLoading = false
    public private(set) var place: Place?

    // MARK: - 取りに行く相手

    private let amedas: AmedasClient
    private let forecast: ForecastClient
    private let model: OpenMeteoClient
    private let snapshot: SnapshotClient
    private let accuracyClient: AccuracyClient

    private var stationTable: [StationInfo] = []
    private var officeNames: [String: String] = [:]

    public init(fetcher: Fetching = URLSessionFetcher()) {
        self.amedas = AmedasClient(fetcher: fetcher)
        self.forecast = ForecastClient(fetcher: fetcher)
        self.model = OpenMeteoClient(fetcher: fetcher)
        self.snapshot = SnapshotClient(fetcher: fetcher)
        self.accuracyClient = AccuracyClient(fetcher: fetcher)
    }

    // MARK: - まとめて読み直す

    public func refresh(place: Place) async {
        guard !isLoading else { return }
        isLoading = true
        self.place = place
        nows = [:]
        past = []
        future = [:]
        popBlocks = [:]
        weekly = [:]
        jmaDaily = []
        station = nil
        overview = ""
        accuracy = nil
        status = []

        if stationTable.isEmpty {
            stationTable = (try? await amedas.table()) ?? []
        }
        if officeNames.isEmpty {
            officeNames = (try? await forecast.offices()) ?? [:]
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadAmedas(place) }
            group.addTask { await self.loadForecast(place) }
            group.addTask { await self.loadModel(place) }
            group.addTask { await self.loadECMWF(place) }
            group.addTask { await self.loadSnapshot(place) }
            group.addTask { await self.loadAccuracy(place) }
        }

        weekly = Aggregate.weekly(jmaDaily: jmaDaily,
                                  modelRows: future[.model] ?? [],
                                  ecmwfRows: future[.ecmwf] ?? [],
                                  snapshot: snapshotSources,
                                  popBlocks: popBlocks)
        updatedAt = Date()
        isLoading = false
    }

    private var snapshotSources: [SnapshotSource] = []

    // MARK: - それぞれ

    private func loadAmedas(_ place: Place) async {
        do {
            let hit = try await amedas.current(place: place, table: stationTable)
            station = hit.station
            nows[.jma] = hit.now
            setStatus("jma", SourceKey.jma.name, .ok,
                      "\(hit.station.name)アメダス（約\(Format.km(hit.station.km))）／"
                      + "\(Format.dateTime(hit.observedAt)) 現在"
                      + (hit.hasHumidity ? "" : "　※この地点は湿度を観測していません"))
            past = (try? await amedas.recentPast(stationCode: hit.station.code,
                                                 observedAt: hit.observedAt)) ?? []
        } catch {
            setStatus("jma", SourceKey.jma.name, .failed,
                      "取得できませんでした（\(error.localizedDescription)）")
        }
    }

    private func loadForecast(_ place: Place) async {
        do {
            let r = try await forecast.load(place: place, officeNames: officeNames,
                                            stations: stationTable)
            jmaDaily = r.daily
            popBlocks[.jma] = r.pops
            officeName = r.officeName
            overview = r.overview
            setStatus("jma_forecast", "気象庁（府県天気予報）", .ok,
                      "\(r.officeName)（\(r.officeCode)）の予報を読み込みました")
        } catch {
            setStatus("jma_forecast", "気象庁（府県天気予報）", .failed,
                      "取得できませんでした（\(error.localizedDescription)）")
        }
    }

    private func loadModel(_ place: Place) async {
        do {
            let r = try await model.load(place: place)
            future[.model] = r.rows
            if let now = r.now { nows[.model] = now }
            setStatus("model", SourceKey.model.name, .ok,
                      "\(r.rows.count)時間ぶんの予報を読み込みました"
                      + (r.hasPop ? "（降水確率は Open-Meteo の総合予報）"
                                  : "（降水確率は取れませんでした）"))
        } catch {
            setStatus("model", SourceKey.model.name, .failed,
                      "取得できませんでした（\(error.localizedDescription)）")
        }
    }

    /// ECMWF（欧州中期予報センター）の全球モデル。
    /// 気象庁とは別の計算なので、見通しが立つかどうかの手がかりになります。
    private func loadECMWF(_ place: Place) async {
        do {
            let r = try await model.load(place: place, models: "ecmwf_ifs025", wantsPop: false)
            future[.ecmwf] = r.rows
            if let now = r.now { nows[.ecmwf] = now }
            setStatus("ecmwf", SourceKey.ecmwf.name, .ok,
                      "\(r.rows.count)時間ぶんの予報を読み込みました（このモデルに降水確率はありません）")
        } catch {
            setStatus("ecmwf", SourceKey.ecmwf.name, .failed,
                      "取得できませんでした（\(error.localizedDescription)）")
        }
    }

    private func loadSnapshot(_ place: Place) async {
        do {
            let r = try await snapshot.load(place: place)
            if let why = r.missReason {
                for key in [SourceKey.yahoo, .weathernews] {
                    setStatus(key.rawValue, key.name, .notFetched, why)
                }
                setStatus("snapshot", "Yahoo!天気・ウェザーニュース（取り込みファイル）", .notFetched, why)
                return
            }
            snapshotSources = r.sources
            var got: [String] = []
            for src in r.sources {
                if !src.ok {
                    setStatus(src.key.rawValue, src.key.name, .failed, src.error ?? "取得に失敗しています")
                    continue
                }
                if let now = src.now { nows[src.key] = now }
                if !src.rows.isEmpty { future[src.key] = src.rows }
                if !src.pops.isEmpty { popBlocks[src.key] = src.pops }
                got.append(src.key.name)

                var kinds: [String] = []
                if src.rows.contains(where: { $0.temp != nil }) { kinds.append("気温") }
                if src.rows.contains(where: { $0.vh != nil }) { kinds.append("湿度") }
                if src.rows.contains(where: { $0.pop != nil }) { kinds.append("降水確率") }
                let body = src.rows.isEmpty
                    ? "現在値のみ"
                    : "\(src.rows.count)時間ぶんの予報（\(kinds.joined(separator: "・"))）"
                let when = r.generatedAt.map { "（取得 \(Format.dateTime($0))）" } ?? ""
                setStatus(src.key.rawValue, src.key.name, .ok,
                          (src.label.isEmpty ? "" : src.label + "／") + body + when)
            }
            let near = (r.km ?? 0) > 0.5 ? "（約\(Format.km(r.km ?? 0))離れた取り込み地点）" : ""
            setStatus("snapshot", "Yahoo!天気・ウェザーニュース（取り込みファイル）",
                      got.isEmpty ? .notFetched : .ok,
                      got.isEmpty
                        ? "latest.json はありますが中身が空です"
                        : (r.placeLabel.isEmpty ? "" : r.placeLabel + " の")
                          + got.joined(separator: "・") + " を読み込みました" + near)
        } catch {
            for key in [SourceKey.yahoo, .weathernews] {
                setStatus(key.rawValue, key.name, .notFetched, "未取得（サーバ側での取り込みが必要です）")
            }
            setStatus("snapshot", "Yahoo!天気・ウェザーニュース（取り込みファイル）", .notFetched,
                      "取り込みファイルを読めませんでした（\(error.localizedDescription)）")
        }
    }

    private func loadAccuracy(_ place: Place) async {
        accuracy = try? await accuracyClient.load(place: place)
    }

    private func setStatus(_ key: String, _ name: String, _ state: StatusLine.State, _ message: String) {
        let line = StatusLine(key: key, name: name, state: state, message: message)
        if let i = status.firstIndex(where: { $0.key == key }) {
            status[i] = line
        } else {
            status.append(line)
        }
    }

    // MARK: - 画面から使うもの

    public var average: AverageNow { Aggregate.average(nows) }

    public var statusOrdered: [StatusLine] {
        let order = ["jma", "jma_forecast", "model", "ecmwf", "yahoo", "weathernews", "snapshot"]
        return status.sorted {
            (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99)
        }
    }

    /// 1週間の表に出す日付。過ぎた日は出しません。
    public var weeklyDays: [String] {
        let today = JST.dayKey(Date())
        return Aggregate.days(in: weekly).filter { $0 >= today }
    }

    /// グラフに出す線。過去の実況（気象庁）と、これからの予報（各社）です。
    /// 雨量は降っている山ごとに分けて返します。
    public func series(for field: ChartField, days: Int) -> [ChartSeries] {
        let raw = rawSeries(for: field, days: days)
        guard field == .precip else { return raw }
        return raw.flatMap { ChartField.rainSegments($0) }
    }

    /// 気温グラフに重ねる、日ごとの最高・最低と天気（気象庁の予報）。
    /// Web版と同じで、日の真ん中に縦棒と丸で置きます。
    public func dailyMarks(days: Int) -> [DayMark] {
        let now = Date()
        let from = now.addingTimeInterval(-ChartWindow.pastSeconds)
        let to = now.addingTimeInterval(TimeInterval(days * 24 * 3600))
        guard let jma = weekly[.jma] else { return [] }

        var out: [DayMark] = []
        var day = JST.startOfDay(from)
        while day < to {
            let end = day.addingTimeInterval(24 * 3600)
            if let d = jma[JST.dayKey(day)],
               d.max != nil || d.min != nil || !d.weather.isEmpty {
                out.append(DayMark(dayKey: JST.dayKey(day), start: day, end: end,
                                   high: d.max, low: d.min, weather: d.weather))
            }
            day = end
        }
        return out
    }

    /// その項目に出せる値がひとつでもあるか。
    /// 雨量が全部0のときに「出せる提供元がありません」と出さないために使います。
    public func hasAnyValue(for field: ChartField, days: Int) -> Bool {
        !rawSeries(for: field, days: days).isEmpty
    }

    private func rawSeries(for field: ChartField, days: Int) -> [ChartSeries] {
        let now = Date()
        let from = now.addingTimeInterval(-ChartWindow.pastSeconds)
        let to = now.addingTimeInterval(TimeInterval(days * 24 * 3600))

        var out: [ChartSeries] = []
        for key in SourceKey.allCases {
            var rows: [HourlyRow] = []
            if key == .jma {
                rows = field == .pop ? Aggregate.popSteps(popBlocks[.jma] ?? []) : past
            } else {
                rows = future[key] ?? []
                if field == .pop {
                    let blocks = popBlocks[key] ?? []
                    if !blocks.isEmpty { rows = Aggregate.popSteps(blocks) }
                }
            }
            // 雨量は「予報が出ていない＝0」ではないので、値のある点だけを線にします
            let points = rows
                .filter { $0.time >= from && $0.time <= to }
                .compactMap { row -> ChartPoint? in
                    guard let v = field.value(row) else { return nil }
                    return ChartPoint(time: row.time, value: v)
                }
            if !points.isEmpty {
                out.append(ChartSeries(key: key, points: field == .precip
                                       ? ChartField.perHour(points) : points))
            }
        }
        return out
    }
}

// MARK: - グラフに渡す形

/// グラフに出す時間の幅
public enum ChartWindow {
    /// 過去はここまで（実況の直近ぶんだけ出します）
    public static let pastHours: Double = 1
    public static let pastSeconds: TimeInterval = pastHours * 3600

    /// 「N日」表示のときの全体の幅（時間）
    public static func span(days: Int) -> Double {
        Double(days) * 24 + pastHours
    }
}

public enum ChartField: String, CaseIterable, Sendable, Identifiable {
    case temp, rh, ah, pop, precip

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .temp: return "気温"
        case .rh: return "相対湿度"
        case .ah: return "絶対湿度"
        case .pop: return "降水確率"
        case .precip: return "雨量"
        }
    }
    public var unit: String {
        switch self {
        case .temp: return "℃"
        case .rh: return "%"
        case .ah: return "g/kg(DA)"
        case .pop: return "%"
        case .precip: return "mm/h"
        }
    }
    public var digits: Int {
        switch self {
        case .temp, .ah, .precip: return 1
        case .rh, .pop: return 0
        }
    }
    public var fixedRange: ClosedRange<Double>? { self == .pop ? 0...100 : nil }
    /// 雨量は刻みが提供元で違うので、値のある時刻を小さな丸で示します
    public var showsPoints: Bool { self == .precip }
    /// 線のつなぎ方。降水確率は階段、雨量はまっすぐ、ほかはなめらかに
    public var interpolation: LineShape {
        switch self {
        case .pop: return .stepEnd
        case .precip: return .straight
        default: return .smooth
        }
    }
    /// 0を下回らない項目
    public var startsAtZero: Bool { self == .pop || self == .precip }

    /// 雨量を「降っている山」だけに切り分けます。
    /// 0が続く区間は線にしません。平らな0の線は、わずかに降る予報と
    /// 見分けがつかないためです。山の足元（前後ひとつずつの0）は残して、
    /// どこから降り出してどこで止むかが分かるようにしています。
    static func rainSegments(_ s: ChartSeries) -> [ChartSeries] {
        let pts = s.points
        guard !pts.isEmpty else { return [] }
        var keep = [Bool](repeating: false, count: pts.count)
        for i in pts.indices where pts[i].value > 0 {
            keep[i] = true
            if i > 0 { keep[i - 1] = true }
            if i + 1 < pts.count { keep[i + 1] = true }
        }
        var out: [ChartSeries] = []
        var run: [ChartPoint] = []
        func flush() {
            guard !run.isEmpty else { return }
            out.append(ChartSeries(key: s.key, segment: out.count, points: run))
            run = []
        }
        for i in pts.indices {
            if keep[i] { run.append(pts[i]) } else { flush() }
        }
        flush()
        return out
    }

    /// 雨量を1時間あたりに直します。
    /// Yahoo!天気は3時間ごとの合計で出しているため、そのまま並べると3倍に見えます。
    static func perHour(_ points: [ChartPoint]) -> [ChartPoint] {
        guard points.count > 1 else { return points }
        var gaps: [Double] = []
        for i in 1..<points.count {
            gaps.append(points[i].time.timeIntervalSince(points[i - 1].time) / 3600)
        }
        gaps.sort()
        let step = gaps[gaps.count / 2]
        guard step > 1.01 else { return points }
        return points.map { ChartPoint(time: $0.time, value: $0.value / step) }
    }

    func value(_ row: HourlyRow) -> Double? {
        switch self {
        case .temp: return row.temp
        case .rh: return row.rh
        // 絶対湿度は重量絶対湿度［g/kg(DA)］。空気線図と同じ量です
        case .ah: return row.mr
        case .pop: return row.pop
        case .precip: return row.precip
        }
    }
}

/// 線のつなぎ方。Charts に依らずここで決めておきます
public enum LineShape: Sendable {
    case smooth, straight, stepEnd
}

/// 気温グラフに重ねる、1日ぶんの最高・最低と天気
public struct DayMark: Identifiable, Sendable {
    public var dayKey: String
    public var start: Date
    public var end: Date
    public var high: Double?
    public var low: Double?
    public var weather: String

    public var id: String { dayKey }

    /// 画面に見えている部分の真ん中。端の日は切れたぶんを除いて置きます
    public func mid(from: Date, to: Date) -> Date {
        let a = Swift.max(start, from), b = Swift.min(end, to)
        return Date(timeIntervalSince1970:
                        (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2)
    }

    /// 画面に見えている幅［時間］。せまい日は数字を出しません
    public func visibleHours(from: Date, to: Date) -> Double {
        let a = Swift.max(start, from), b = Swift.min(end, to)
        return Swift.max(b.timeIntervalSince(a) / 3600, 0)
    }
}

public struct ChartPoint: Identifiable, Sendable {
    public var time: Date
    public var value: Double
    public var id: Date { time }
}

public struct ChartSeries: Identifiable, Sendable {
    public var key: SourceKey
    /// 同じ提供元で線が分かれるときの通し番号（雨量の山ごと）
    public var segment: Int = 0
    public var points: [ChartPoint]
    public var id: String { "\(key.rawValue)#\(segment)" }
}
