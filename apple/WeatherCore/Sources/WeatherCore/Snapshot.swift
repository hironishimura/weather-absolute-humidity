//  Yahoo!天気・ウェザーニュース（取り込みファイル）
//
//  どちらも公開APIがなく、端末から直接は読めません。
//  GitHub Actions が3時間おきにページを読み、latest.json に書き出しています。
//  ここではそのファイルを読み、いま見ている地点に一番近い取り込み地点を使います。

import Foundation

public struct SnapshotFile: Decodable, Sendable {
    public struct Current: Decodable, Sendable {
        public var time: String?
        public var temp: Double?
        public var humidity: Double?
        public var pressure: Double?
    }
    public struct Hourly: Decodable, Sendable {
        public var time: String
        public var temp: Double?
        public var humidity: Double?
        public var pressure: Double?
        public var pop: Double?
        public var precip: Double?
    }
    public struct Weekly: Decodable, Sendable {
        public var date: String
        public var weather: String?
        public var temp_max: Double?
        public var temp_min: Double?
        public var pop: Double?
    }
    public struct Pop: Decodable, Sendable {
        public var time: String
        public var hours: Int?
        public var pop: Double?
    }
    public struct Source: Decodable, Sendable {
        public var ok: Bool?
        public var label: String?
        public var error: String?
        public var current: Current?
        public var current_is_forecast: Bool?
        public var hourly: [Hourly]?
        public var weekly: [Weekly]?
        public var pops: [Pop]?
    }
    public struct PlaceEntry: Decodable, Sendable {
        public var id: String?
        public var label: String?
        public var lat: Double?
        public var lon: Double?
        public var sources: [String: Source]?
    }
    public var generated_at: String?
    public var places: [PlaceEntry]?
    /// 1地点だけだった古い形
    public var label: String?
    public var sources: [String: Source]?
}

/// 取り込みファイルから読み取った、ひとつの提供元ぶんの中身
public struct SnapshotSource: Sendable {
    public var key: SourceKey
    public var ok: Bool
    public var label: String
    public var error: String?
    public var now: NowValue?
    public var rows: [HourlyRow]
    public var weekly: [DailyForecast]
    public var pops: [PopBlock]
}

public struct SnapshotResult: Sendable {
    public var generatedAt: Date?
    /// 使った取り込み地点の名前
    public var placeLabel: String
    /// いま見ている地点からの距離 [km]
    public var km: Double?
    public var sources: [SnapshotSource]
    /// 近い取り込みがなかったときの理由
    public var missReason: String?
}

public struct SnapshotClient: Sendable {
    let fetcher: Fetching
    /// これより離れた取り込みは使いません
    public static let maxKm: Double = 40

    public init(fetcher: Fetching) { self.fetcher = fetcher }

    public func load(place: Place) async throws -> SnapshotResult {
        let file = try await fetcher.decodeFirst(SnapshotFile.self,
                                                 from: Endpoints.snapshotURLs("latest.json"))
        return Self.build(file, place: place)
    }

    public static func build(_ file: SnapshotFile, place: Place) -> SnapshotResult {
        let generatedAt = file.generated_at.flatMap(JST.parseISO)

        var entry: SnapshotFile.PlaceEntry?
        var km: Double?
        if let list = file.places, !list.isEmpty {
            var nearest: (km: Double, entry: SnapshotFile.PlaceEntry)?
            for p in list {
                guard let la = p.lat, let lo = p.lon else { continue }
                let d = Geo.distanceKm(place.lat, place.lon, la, lo)
                if nearest == nil || d < nearest!.km { nearest = (d, p) }
            }
            if let hit = nearest {
                if hit.km > maxKm {
                    let label = hit.entry.label ?? hit.entry.id ?? ""
                    return SnapshotResult(
                        generatedAt: generatedAt, placeLabel: label, km: hit.km, sources: [],
                        missReason: "この地点の取り込みがありません"
                            + "（一番近い取り込みは\(label)で約\(Int(hit.km.rounded()))km離れています）")
                }
                entry = hit.entry
                km = hit.km
            } else {
                entry = list.first
            }
        } else if let sources = file.sources {
            entry = SnapshotFile.PlaceEntry(id: nil, label: file.label, lat: nil, lon: nil,
                                            sources: sources)
            km = 0
        }

        guard let entry else {
            return SnapshotResult(generatedAt: generatedAt, placeLabel: "", km: nil, sources: [],
                                  missReason: "取り込みファイルに地点が入っていません")
        }

        var out: [SnapshotSource] = []
        for key in [SourceKey.yahoo, .weathernews] {
            guard let src = entry.sources?[key.rawValue] else { continue }
            out.append(parse(src, key: key, generatedAt: generatedAt))
        }
        return SnapshotResult(generatedAt: generatedAt,
                              placeLabel: entry.label ?? entry.id ?? "",
                              km: km, sources: out, missReason: nil)
    }

    static func parse(_ src: SnapshotFile.Source, key: SourceKey, generatedAt: Date?) -> SnapshotSource {
        guard src.ok == true else {
            return SnapshotSource(key: key, ok: false, label: src.label ?? "",
                                  error: src.error ?? "取得に失敗しています",
                                  now: nil, rows: [], weekly: [], pops: [])
        }

        var now: NowValue?
        if let c = src.current, let reading = Reading(temp: c.temp, rh: c.humidity, pressure: c.pressure) {
            now = NowValue(time: c.time.flatMap(JST.parseISO),
                           values: reading,
                           isForecast: src.current_is_forecast != false,
                           fetchedAt: generatedAt)
        }

        var rows: [HourlyRow] = []
        for r in src.hourly ?? [] {
            guard let t = JST.parseISO(r.time) else { continue }
            // 気温だけ・湿度だけの提供元もあるので、あるものだけ入れます
            if let row = HourlyRow.make(time: t, temp: r.temp, rh: r.humidity,
                                        pressure: r.pressure, pop: r.pop, precip: r.precip) {
                rows.append(row)
            }
        }
        rows.sort { $0.time < $1.time }

        var weekly: [DailyForecast] = []
        for d in src.weekly ?? [] {
            let key = String(d.date.prefix(10))
            guard let date = JST.parseISO(key + "T00:00:00+09:00") else { continue }
            weekly.append(DailyForecast(key: key, date: date, weather: d.weather ?? "",
                                        pop: d.pop, min: d.temp_min, max: d.temp_max))
        }
        weekly.sort { $0.key < $1.key }

        var pops: [PopBlock] = []
        for p in src.pops ?? [] {
            guard let t = JST.parseISO(p.time), let v = p.pop else { continue }
            pops.append(PopBlock(time: t, hours: p.hours ?? 6, pop: v))
        }
        pops.sort { $0.time < $1.time }

        return SnapshotSource(key: key, ok: true, label: src.label ?? "", error: nil,
                              now: now, rows: rows, weekly: weekly, pops: pops)
    }
}
