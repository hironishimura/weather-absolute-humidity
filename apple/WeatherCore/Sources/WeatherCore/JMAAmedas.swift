//  気象庁：アメダスの実況と過去24時間

import Foundation

public struct AmedasNow: Sendable {
    public var station: Station
    public var observedAt: Date
    public var now: NowValue
    public var hasHumidity: Bool
}

/// アメダス一覧の1行
public struct StationInfo: Sendable, Equatable {
    public var code: String
    public var name: String
    public var lat: Double
    public var lon: Double
    public var alt: Double
}

public struct AmedasClient: Sendable {
    let fetcher: Fetching
    public init(fetcher: Fetching) { self.fetcher = fetcher }

    /// 観測所の一覧。1回読んだら使い回せるよう、呼ぶ側で持っておきます。
    public func table() async throws -> [StationInfo] {
        let any = try await fetcher.json(Endpoints.url("\(Endpoints.jma)/amedas/const/amedastable.json"))
        guard let d = any as? [String: Any] else { throw FetchError.badBody }
        return Self.parseTable(d)
    }

    static func parseTable(_ d: [String: Any]) -> [StationInfo] {
        var out: [StationInfo] = []
        for (code, v) in d {
            guard let s = v as? [String: Any],
                  let lat = Geo.degrees(fromDegreeMinute: s["lat"] as? [Double]),
                  let lon = Geo.degrees(fromDegreeMinute: s["lon"] as? [Double]) else { continue }
            out.append(StationInfo(code: code,
                                   name: J.string(s["kjName"]) ?? code,
                                   lat: lat, lon: lon,
                                   alt: J.number(s["alt"]) ?? 0))
        }
        return out.sorted { $0.code < $1.code }
    }

    /// 緯度経度に近い順に観測所を並べる
    public static func nearest(_ table: [StationInfo],
                               lat: Double, lon: Double, limit: Int = 120) -> [Station] {
        table.map {
            Station(code: $0.code, name: $0.name, lat: $0.lat, lon: $0.lon, alt: $0.alt,
                    km: Geo.distanceKm(lat, lon, $0.lat, $0.lon))
        }
        .sorted { $0.km < $1.km }
        .prefix(limit)
        .map { $0 }
    }

    /// いまの実況。気温と湿度がそろっている一番近い観測所を選びます。
    public func current(place: Place, table: [StationInfo]) async throws -> AmedasNow {
        let near = Self.nearest(table, lat: place.lat, lon: place.lon)
        let stamp = try await latestTime()
        let map = try await fetcher.json(
            Endpoints.url("\(Endpoints.jma)/amedas/data/map/\(JST.stamp(stamp)).json"))
        guard let rows = map as? [String: Any] else { throw FetchError.badBody }

        var withBoth: (Station, [String: Any])?
        var withTemp: (Station, [String: Any])?
        for st in near {
            guard let row = rows[st.code] as? [String: Any] else { continue }
            let t = J.amedas(row, "temp")
            let h = J.amedas(row, "humidity")
            if withTemp == nil, t != nil { withTemp = (st, row) }
            if t != nil, h != nil { withBoth = (st, row); break }
        }
        guard let hit = withBoth ?? withTemp else {
            throw FetchError.noValue("近くに観測値のある地点がありませんでした")
        }

        let t = J.amedas(hit.1, "temp")
        let h = J.amedas(hit.1, "humidity")
        let p = J.amedas(hit.1, "pressure")
            ?? Psychrometrics.pressureFromAltitude(hit.0.alt, temperature: t)
        guard let values = Reading(temp: t, rh: h, pressure: p) else {
            throw FetchError.noValue("気温か湿度を読めませんでした")
        }

        let now = NowValue(time: stamp, values: values, isForecast: false,
                           stationName: hit.0.name,
                           wind: J.amedas(hit.1, "wind"),
                           windDirection: J.amedas(hit.1, "windDirection").map { Int($0) },
                           precipitation1h: J.amedas(hit.1, "precipitation1h"))
        return AmedasNow(station: hit.0, observedAt: stamp, now: now, hasHumidity: h != nil)
    }

    func latestTime() async throws -> Date {
        let txt = try await fetcher.text(Endpoints.url("\(Endpoints.jma)/amedas/data/latest_time.txt"))
        guard let d = JST.parseISO(txt) else { throw FetchError.noValue("観測時刻を読めませんでした") }
        return d
    }

    /// 直近の10分値。3時間ごとのファイルを新しいほうから blocks 個つなぎます。
    /// グラフに出すのは直近1時間ぶんなので、既定では2個で足ります。
    public func recentPast(stationCode: String, observedAt: Date,
                           blocks: Int = 2) async throws -> [HourlyRow] {
        let p = JST.parts(observedAt)
        let blockHour = ((p.hour ?? 0) / 3) * 3
        let base = JST.date(p.year ?? 2000, p.month ?? 1, p.day ?? 1, blockHour)

        var rows: [HourlyRow] = []
        await withTaskGroup(of: [HourlyRow].self) { group in
            for i in stride(from: Swift.max(blocks - 1, 0), through: 0, by: -1) {
                let block = base.addingTimeInterval(TimeInterval(-i * 3 * 3600))
                group.addTask {
                    (try? await self.block(stationCode: stationCode, at: block)) ?? []
                }
            }
            for await part in group { rows.append(contentsOf: part) }
        }
        rows.sort { $0.time < $1.time }
        return rows
    }

    func block(stationCode: String, at block: Date) async throws -> [HourlyRow] {
        let p = JST.parts(block)
        let name = String(format: "%04d%02d%02d_%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0, p.hour ?? 0)
        let any = try await fetcher.json(
            Endpoints.url("\(Endpoints.jma)/amedas/data/point/\(stationCode)/\(name).json"))
        guard let dict = any as? [String: Any] else { return [] }

        var out: [HourlyRow] = []
        for stamp in dict.keys.sorted() {
            guard let time = JST.date(fromStamp: stamp),
                  let row = dict[stamp] as? [String: Any] else { continue }
            let t = J.amedas(row, "temp")
            let h = J.amedas(row, "humidity")
            guard t != nil, h != nil else { continue }   // 欠測は捨てます
            let pr = J.amedas(row, "pressure")
            if let made = HourlyRow.make(time: time, temp: t, rh: h, pressure: pr,
                                         precip: J.amedas(row, "precipitation1h")) {
                out.append(made)
            }
        }
        return out
    }
}

public enum Wind {
    static let names = ["北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
                        "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西"]

    /// 風向（1〜16）と風速から「東 2.1 m/s」を作る
    public static func text(direction: Int?, speed: Double?) -> String {
        guard let speed else { return "--" }
        var head = ""
        if let d = direction {
            if d == 0 { head = "静穏 " }
            else if (1...16).contains(d) { head = names[d - 1] + " " }
        }
        return head + String(format: "%.1f m/s", speed)
    }
}
