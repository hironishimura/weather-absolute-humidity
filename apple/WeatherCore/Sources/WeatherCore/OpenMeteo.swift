//  気象庁の数値予報（MSM/GSM）を Open-Meteo 経由で
//
//  気象庁の公開予報には湿度が入っていないため、絶対湿度の「予報」はここから作ります。
//  降水確率だけは気象庁のモデルに含まれておらず、models=jma_seamless を付けると
//  中身が空で返ってきます。そのためモデル指定なしの総合予報から別に取ります。
//  （実際に問い合わせて確かめた挙動です。README にも書いてあります）

import Foundation

public struct ModelResult: Sendable {
    public var rows: [HourlyRow]
    public var now: NowValue?
    public var hasPop: Bool
}

public struct OpenMeteoClient: Sendable {
    let fetcher: Fetching
    public init(fetcher: Fetching) { self.fetcher = fetcher }

    struct Payload: Decodable {
        struct Current: Decodable {
            var time: String?
            var temperature_2m: Double?
            var relative_humidity_2m: Double?
            var surface_pressure: Double?
        }
        struct Hourly: Decodable {
            var time: [String]?
            var temperature_2m: [Double?]?
            var relative_humidity_2m: [Double?]?
            var surface_pressure: [Double?]?
            var precipitation_probability: [Double?]?
            var precipitation: [Double?]?
        }
        var current: Current?
        var hourly: Hourly?
    }

    func valuesURL(_ place: Place, withModel: Bool) -> URL {
        var s = "\(Endpoints.openMeteo)?latitude=\(String(format: "%.4f", place.lat))"
            + "&longitude=\(String(format: "%.4f", place.lon))"
            + "&hourly=temperature_2m,relative_humidity_2m,surface_pressure,precipitation"
            + "&current=temperature_2m,relative_humidity_2m,surface_pressure"
            + "&timezone=Asia%2FTokyo&forecast_days=10&past_days=1"
        if withModel { s += "&models=jma_seamless" }
        return Endpoints.url(s)
    }

    func popURL(_ place: Place) -> URL {
        Endpoints.url("\(Endpoints.openMeteo)?latitude=\(String(format: "%.4f", place.lat))"
            + "&longitude=\(String(format: "%.4f", place.lon))"
            + "&hourly=precipitation_probability"
            + "&timezone=Asia%2FTokyo&forecast_days=10&past_days=1")
    }

    public func load(place: Place) async throws -> ModelResult {
        async let popTask: Payload? = try? await fetcher.decode(Payload.self, from: popURL(place))

        var payload: Payload
        do {
            payload = try await fetcher.decode(Payload.self, from: valuesURL(place, withModel: true))
        } catch {
            // モデル指定が通らないときはモデルなしで取り直します
            payload = try await fetcher.decode(Payload.self, from: valuesURL(place, withModel: false))
        }
        let pops = await popTask
        return Self.build(values: payload, pops: pops)
    }

    static func build(values: Payload, pops: Payload?) -> ModelResult {
        var popByTime: [String: Double] = [:]
        if let h = pops?.hourly, let times = h.time, let list = h.precipitation_probability {
            for (i, t) in times.enumerated() where list.indices.contains(i) {
                if let v = list[i] { popByTime[t] = v }
            }
        }

        var rows: [HourlyRow] = []
        if let h = values.hourly, let times = h.time {
            for (i, text) in times.enumerated() {
                func pick(_ list: [Double?]?) -> Double? {
                    guard let list, list.indices.contains(i) else { return nil }
                    return list[i]
                }
                guard let t = pick(h.temperature_2m), let rh = pick(h.relative_humidity_2m),
                      let time = JST.parseISO(text) else { continue }
                if let row = HourlyRow.make(time: time, temp: t, rh: rh,
                                            pressure: pick(h.surface_pressure),
                                            pop: popByTime[text],
                                            precip: pick(h.precipitation)) {
                    rows.append(row)
                }
            }
        }
        rows.sort { $0.time < $1.time }

        var now: NowValue?
        if let c = values.current,
           let reading = Reading(temp: c.temperature_2m, rh: c.relative_humidity_2m,
                                 pressure: c.surface_pressure) {
            now = NowValue(time: c.time.flatMap(JST.parseISO) ?? Date(),
                           values: reading, isForecast: true)
        }
        return ModelResult(rows: rows, now: now, hasPop: !popByTime.isEmpty)
    }
}
