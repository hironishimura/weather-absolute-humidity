//  気象庁：府県天気予報（3日先 + 週間）
//
//  返ってくる JSON は入れ子が深いので、Web版と同じ順で拾っています。
//    timeSeries[0] 天気　timeSeries[1] 降水確率（6時間ごと）　timeSeries[2] 気温
//  週間のほうは [1] に入っていて、天気コードと降水確率、最高／最低気温が並びます。

import Foundation

public struct ForecastResult: Sendable {
    public var officeCode: String
    public var officeName: String
    public var daily: [DailyForecast]
    public var pops: [PopBlock]
    public var overview: String
}

public struct ForecastClient: Sendable {
    let fetcher: Fetching
    public init(fetcher: Fetching) { self.fetcher = fetcher }

    /// 予報区の一覧（コード → 名前）
    public func offices() async throws -> [String: String] {
        let any = try await fetcher.json(Endpoints.url("\(Endpoints.jma)/common/const/area.json"))
        guard let root = any as? [String: Any], let src = root["offices"] as? [String: Any] else {
            return [:]
        }
        var out: [String: String] = [:]
        for (code, v) in src {
            out[code] = J.string((v as? [String: Any])?["name"]) ?? code
        }
        return out
    }

    public func load(place: Place, officeNames: [String: String],
                     stations: [StationInfo]) async throws -> ForecastResult {
        let office = place.office?.isEmpty == false
            ? place.office!
            : JMATables.resolveOffice(lat: place.lat, lon: place.lon, officeNames: officeNames)

        async let dataTask = fetcher.json(
            Endpoints.url("\(Endpoints.jma)/forecast/data/forecast/\(office).json"))
        // 気象概況は読めなくても困らないので、失敗はそのまま流します
        async let overviewTask: Any? = try? await fetcher.json(
            Endpoints.url("\(Endpoints.jma)/forecast/data/overview_forecast/\(office).json"))

        let overviewAny = await overviewTask
        let raw = try await dataTask
        let overview = J.string(J.dict(overviewAny)?["text"]) ?? ""

        var parsed = Self.parse(raw, place: place, stations: stations)
        parsed.officeCode = office
        parsed.officeName = officeNames[office] ?? office
        parsed.overview = overview
        return parsed
    }

    /// 取得と切り離してあるので、保存した JSON でも確かめられます
    public static func parse(_ raw: Any, place: Place, stations: [StationInfo]) -> ForecastResult {
        var days: [String: DailyForecast] = [:]
        var pops: [PopBlock] = []

        func slot(_ iso: String) -> String? {
            guard let d = JST.parseISO(iso) else { return nil }
            let key = JST.dayKey(d)
            if days[key] == nil {
                days[key] = DailyForecast(key: key, date: JST.startOfDay(d))
            }
            return key
        }

        let list = J.array(raw) ?? []

        // ---- 直近3日 ----
        if let near = J.dict(J.at(list, 0)), let ts = J.array(near["timeSeries"]) {
            if let ts0 = J.dict(J.at(ts, 0)), let a0 = J.dict(J.at(J.array(ts0["areas"]), 0)) {
                let weathers = J.array(a0["weathers"]) ?? []
                let codes = J.array(a0["weatherCodes"]) ?? []
                for (i, iso) in (J.array(ts0["timeDefines"]) ?? []).enumerated() {
                    guard let key = slot(J.string(iso) ?? "") else { continue }
                    if let w = J.string(J.at(weathers, i)) {
                        days[key]?.weather = w.replacingOccurrences(
                            of: "[　\\s]+", with: "", options: .regularExpression)
                    }
                    if let c = J.string(J.at(codes, i)) { days[key]?.code = c }
                }
            }
            if let ts1 = J.dict(J.at(ts, 1)), let a1 = J.dict(J.at(J.array(ts1["areas"]), 0)) {
                let values = J.array(a1["pops"]) ?? []
                for (i, iso) in (J.array(ts1["timeDefines"]) ?? []).enumerated() {
                    guard let v = J.number(J.at(values, i)),
                          let text = J.string(iso), let t0 = JST.parseISO(text) else { continue }
                    if let key = slot(text) {
                        let current = days[key]?.pop
                        days[key]?.pop = Swift.max(current ?? v, v)
                    }
                    pops.append(PopBlock(time: t0, hours: 6, pop: v))
                }
            }
            if let ts2 = J.dict(J.at(ts, 2)), let areas = J.array(ts2["areas"]), !areas.isEmpty {
                let index = pickTempArea(areas, place: place, stations: stations)
                if let a2 = J.dict(J.at(areas, index)) {
                    let temps = J.array(a2["temps"]) ?? []
                    for (i, iso) in (J.array(ts2["timeDefines"]) ?? []).enumerated() {
                        guard let v = J.number(J.at(temps, i)),
                              let text = J.string(iso), let d = JST.parseISO(text),
                              let key = slot(text) else { continue }
                        // 気象庁は00時を最低気温、09時を最高気温として出しています
                        let hour = JST.parts(d).hour ?? 0
                        if hour < 6 {
                            if days[key]?.min == nil { days[key]?.min = v }
                        } else if days[key]?.max == nil {
                            days[key]?.max = v
                        }
                    }
                }
            }
        }

        // ---- 週間 ----
        if let week = J.dict(J.at(list, 1)), let wts = J.array(week["timeSeries"]) {
            if let w0 = J.dict(J.at(wts, 0)), let b0 = J.dict(J.at(J.array(w0["areas"]), 0)) {
                let codes = J.array(b0["weatherCodes"]) ?? []
                let wpops = J.array(b0["pops"]) ?? []
                for (i, iso) in (J.array(w0["timeDefines"]) ?? []).enumerated() {
                    guard let key = slot(J.string(iso) ?? "") else { continue }
                    if days[key]?.code.isEmpty ?? false, let c = J.string(J.at(codes, i)) {
                        days[key]?.code = c
                    }
                    if days[key]?.pop == nil, let p = J.number(J.at(wpops, i)) {
                        days[key]?.pop = p
                    }
                }
            }
            if let w1 = J.dict(J.at(wts, 1)), let areas = J.array(w1["areas"]), !areas.isEmpty {
                let index = pickTempArea(areas, place: place, stations: stations)
                if let b1 = J.dict(J.at(areas, index)) {
                    let mins = J.array(b1["tempsMin"]) ?? []
                    let maxs = J.array(b1["tempsMax"]) ?? []
                    for (i, iso) in (J.array(w1["timeDefines"]) ?? []).enumerated() {
                        guard let key = slot(J.string(iso) ?? "") else { continue }
                        if days[key]?.min == nil, let v = J.number(J.at(mins, i)) { days[key]?.min = v }
                        if days[key]?.max == nil, let v = J.number(J.at(maxs, i)) { days[key]?.max = v }
                    }
                }
            }
        }

        // 文言がない日は天気コードから補います
        var out = days.values.map { day -> DailyForecast in
            var d = day
            if d.weather.isEmpty { d.weather = JMATables.weatherName(code: d.code) }
            return d
        }
        out.sort { $0.key < $1.key }
        pops.sort { $0.time < $1.time }

        return ForecastResult(officeCode: "", officeName: "", daily: out, pops: pops, overview: "")
    }

    /// 気温予報地点のうち、いまの地点に一番近いものを選ぶ
    static func pickTempArea(_ areas: [Any], place: Place, stations: [StationInfo]) -> Int {
        guard !stations.isEmpty else { return 0 }
        var byCode: [String: StationInfo] = [:]
        for s in stations { byCode[s.code] = s }

        var best = 0
        var bestKm = Double.infinity
        for (i, a) in areas.enumerated() {
            guard let code = J.string(J.dict(J.dict(a)?["area"])?["code"]),
                  let st = byCode[code] else { continue }
            let km = Geo.distanceKm(place.lat, place.lon, st.lat, st.lon)
            if km < bestKm { bestKm = km; best = i }
        }
        return best
    }
}
