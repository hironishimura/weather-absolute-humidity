//  降水確率の当たり具合
//
//  scripts/verify.py が、予報の降水確率と気象庁アメダスの実際の雨量を
//  つき合わせて書き出した accuracy.json を読みます。
//  数え方（期間の切り方や「雨が降った」の基準）はあちら側で決めています。

import Foundation

public struct AccuracyFile: Decodable, Sendable {
    public struct Score: Decodable, Sendable {
        public var n: Int
        public var hit: Int
        public var rate: Double
        public var brier: Double
    }
    public struct Period: Decodable, Sendable {
        public var start: String
        public var hours: Int
        public var mm: Double
        public var rain: Bool
        public var pops: [String: Double]
    }
    public struct PlaceEntry: Decodable, Sendable {
        public var id: String?
        public var label: String?
        public var lat: Double?
        public var lon: Double?
        public var station: String?
        public var periods: [Period]?
        public var scores: [String: Score]?
    }
    public var updated_at: String?
    public var rain_mm: Double?
    public var say_rain: Double?
    public var places: [PlaceEntry]?
}

public struct AccuracyPeriod: Sendable, Identifiable {
    public var start: Date
    public var hours: Int
    public var mm: Double
    public var rain: Bool
    public var pops: [SourceKey: Double]

    public var id: String { "\(start.timeIntervalSince1970)-\(hours)" }

    /// 「9/5(土)」または「9/6 午前」
    public var label: String {
        if hours >= 24 { return Format.date(start) }
        let hour = JST.parts(start).hour ?? 0
        return Format.shortDate(start) + (hour < 12 ? " 午前" : " 午後")
    }
}

public struct AccuracyScore: Sendable {
    public var n: Int
    public var hit: Int
    public var rate: Double
    public var brier: Double
}

public struct AccuracyResult: Sendable {
    public var updatedAt: Date?
    public var placeLabel: String
    public var station: String?
    public var rainMM: Double
    public var sayRain: Double
    public var periods: [AccuracyPeriod]
    public var scores: [SourceKey: AccuracyScore]
    /// この地点の集計がまだないとき
    public var missing: Bool
}

public struct AccuracyClient: Sendable {
    let fetcher: Fetching
    public init(fetcher: Fetching) { self.fetcher = fetcher }

    public func load(place: Place) async throws -> AccuracyResult {
        let file = try await fetcher.decode(AccuracyFile.self,
                                            from: Endpoints.url("\(Endpoints.snapshotBase)/accuracy.json"))
        return Self.build(file, place: place)
    }

    public static func build(_ file: AccuracyFile, place: Place) -> AccuracyResult {
        let updatedAt = file.updated_at.flatMap(JST.parseISO)
        let rainMM = file.rain_mm ?? 1
        let sayRain = file.say_rain ?? 50

        var hit: AccuracyFile.PlaceEntry?
        // まず id で、なければ一番近い地点で
        for p in file.places ?? [] where p.id == place.id { hit = p }
        if hit == nil {
            var nearest: (km: Double, entry: AccuracyFile.PlaceEntry)?
            for p in file.places ?? [] {
                guard let la = p.lat, let lo = p.lon else { continue }
                let km = Geo.distanceKm(place.lat, place.lon, la, lo)
                if nearest == nil || km < nearest!.km { nearest = (km, p) }
            }
            if let n = nearest, n.km <= SnapshotClient.maxKm { hit = n.entry }
        }

        guard let entry = hit else {
            return AccuracyResult(updatedAt: updatedAt, placeLabel: "", station: nil,
                                  rainMM: rainMM, sayRain: sayRain,
                                  periods: [], scores: [:], missing: true)
        }

        var periods: [AccuracyPeriod] = []
        for p in entry.periods ?? [] {
            guard let start = JST.parseISO(p.start) else { continue }
            var pops: [SourceKey: Double] = [:]
            for (k, v) in p.pops {
                if let key = SourceKey(rawValue: k) { pops[key] = v }
            }
            periods.append(AccuracyPeriod(start: start, hours: p.hours, mm: p.mm,
                                          rain: p.rain, pops: pops))
        }
        periods.sort { $0.start < $1.start }

        var scores: [SourceKey: AccuracyScore] = [:]
        for (k, v) in entry.scores ?? [:] {
            if let key = SourceKey(rawValue: k) {
                scores[key] = AccuracyScore(n: v.n, hit: v.hit, rate: v.rate, brier: v.brier)
            }
        }

        return AccuracyResult(updatedAt: updatedAt,
                              placeLabel: entry.label ?? "",
                              station: entry.station,
                              rainMM: rainMM, sayRain: sayRain,
                              periods: periods, scores: scores, missing: false)
    }
}

extension AccuracyResult {
    /// その期間で、その提供元が当てたかどうか。予報がなければ nil。
    public func isHit(_ period: AccuracyPeriod, _ key: SourceKey) -> Bool? {
        guard let pop = period.pops[key] else { return nil }
        return (pop >= sayRain) == period.rain
    }
}
