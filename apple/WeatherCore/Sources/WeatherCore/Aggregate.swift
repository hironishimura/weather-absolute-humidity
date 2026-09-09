//  提供元をまたいでまとめる処理
//
//  Web版と同じ考え方です。
//    ・見出しの大きな数字は、取れている提供元の平均
//    ・1週間の表は、日ごとの発表値があればそれ、なければ時間ごとの予報からまとめた値
//    ・降水確率は刻みが違うので、その期間に重なる区切りのうち一番高い値

import Foundation

/// 見出しに出す平均値。項目ごとに、値のある提供元だけで平均します。
public struct AverageNow: Sendable {
    public var temp: Double?
    public var rh: Double?
    public var vh: Double?
    public var mr: Double?
    public var dp: Double?
    public var di: Double?
    public var pressure: Double?
    /// 項目ごとに何社ぶん使ったか
    public var counts: [String: Int]
    /// 使った提供元
    public var used: [SourceKey]
}

public enum Aggregate {

    public static func average(_ nows: [SourceKey: NowValue]) -> AverageNow {
        var sums: [String: Double] = [:]
        var counts: [String: Int] = [:]
        var used: [SourceKey] = []

        for key in SourceKey.allCases {
            guard let n = nows[key] else { continue }
            used.append(key)
            let v = n.values
            let pairs: [(String, Double?)] = [
                ("temp", v.temp), ("rh", v.rh), ("vh", v.vh), ("mr", v.mr),
                ("dp", v.dp), ("di", v.di), ("pressure", v.pressure)
            ]
            for (name, value) in pairs {
                guard let value, value.isFinite else { continue }
                sums[name, default: 0] += value
                counts[name, default: 0] += 1
            }
        }
        func mean(_ name: String) -> Double? {
            guard let c = counts[name], c > 0, let s = sums[name] else { return nil }
            return s / Double(c)
        }
        return AverageNow(temp: mean("temp"), rh: mean("rh"), vh: mean("vh"), mr: mean("mr"),
                          dp: mean("dp"), di: mean("di"), pressure: mean("pressure"),
                          counts: counts, used: used)
    }

    /// 時間ごとの予報から日ごとの最高・最低をまとめる
    public static func daily(fromHourly rows: [HourlyRow]) -> [String: DailyForecast] {
        var out: [String: DailyForecast] = [:]
        for r in rows {
            let key = JST.dayKey(r.time)
            var day = out[key] ?? DailyForecast(key: key, date: JST.startOfDay(r.time))
            if let t = r.temp {
                day.max = Swift.max(day.max ?? t, t)
                day.min = Swift.min(day.min ?? t, t)
            }
            if let v = r.vh {
                day.vhMax = Swift.max(day.vhMax ?? v, v)
                day.vhMin = Swift.min(day.vhMin ?? v, v)
            }
            if let p = r.pop {
                day.pop = Swift.max(day.pop ?? p, p)
            }
            out[key] = day
        }
        return out
    }

    /// 時間帯ごとの降水確率から、日ごとの値（その日のいちばん高い確率）を作る
    public static func dailyPops(fromBlocks blocks: [PopBlock]) -> [String: Double] {
        var out: [String: Double] = [:]
        for b in blocks {
            // 区切りが日をまたぐこともあるので、1時間ずつ見て入れます
            var t = b.time
            let end = b.time.addingTimeInterval(TimeInterval(b.hours * 3600))
            while t < end {
                let key = JST.dayKey(t)
                out[key] = Swift.max(out[key] ?? b.pop, b.pop)
                t = t.addingTimeInterval(3600)
            }
        }
        return out
    }

    /// 1週間の表。提供元ごとに、日付キー → その日の予報。
    public static func weekly(jmaDaily: [DailyForecast],
                              modelRows: [HourlyRow],
                              snapshot: [SnapshotSource],
                              popBlocks: [SourceKey: [PopBlock]]) -> [SourceKey: [String: DailyForecast]] {
        var out: [SourceKey: [String: DailyForecast]] = [:]

        var jma: [String: DailyForecast] = [:]
        for d in jmaDaily { jma[d.key] = d }
        out[.jma] = jma

        out[.model] = daily(fromHourly: modelRows)

        for src in snapshot where src.ok {
            var byKey = daily(fromHourly: src.rows)
            // 週間表がある日はそちらを優先します
            for d in src.weekly {
                var day = byKey[d.key] ?? d
                day.weather = d.weather.isEmpty ? day.weather : d.weather
                if let v = d.max { day.max = v }
                if let v = d.min { day.min = v }
                if let v = d.pop { day.pop = v }
                byKey[d.key] = day
            }
            out[src.key] = byKey
        }

        // 降水確率が空いている日を、時間帯ごとの値で埋めます
        for (key, blocks) in popBlocks {
            let byDay = dailyPops(fromBlocks: blocks)
            var table = out[key] ?? [:]
            for (dayKey, pop) in byDay {
                if var day = table[dayKey] {
                    if day.pop == nil {
                        day.pop = pop
                        table[dayKey] = day
                    }
                } else if let date = JST.parseISO(dayKey + "T00:00:00+09:00") {
                    table[dayKey] = DailyForecast(key: dayKey, date: date, pop: pop)
                }
            }
            out[key] = table
        }

        return out
    }

    /// 表に出す日付を、全提供元ぶん集めて並べる
    public static func days(in weekly: [SourceKey: [String: DailyForecast]]) -> [String] {
        var set = Set<String>()
        for (_, table) in weekly { set.formUnion(table.keys) }
        return set.sorted()
    }

    /// 降水確率の階段。区切りの始めと終わりに同じ値を置いて、階段状に描けるようにします。
    public static func popSteps(_ blocks: [PopBlock]) -> [HourlyRow] {
        var out: [HourlyRow] = []
        for b in blocks.sorted(by: { $0.time < $1.time }) {
            let span = TimeInterval(b.hours * 3600)
            out.append(HourlyRow(time: b.time, pop: b.pop))
            out.append(HourlyRow(time: b.time.addingTimeInterval(span - 60), pop: b.pop))
        }
        return out
    }
}
