//  グラフの目盛り
//
//  Web版の hourTicks() / niceScale() と同じ考え方です。

import Foundation

public enum AxisTicks {

    public struct Hour: Equatable, Sendable {
        /// 何時間おきか
        public var step: Int
        /// 「時」を付けるかどうか（せまいときは数字だけ）
        public var withUnit: Bool
        /// 目盛りの間隔 [pt]
        public var gap: Double
    }

    static let hourSteps = [1, 2, 3, 6, 12, 24]

    /// 時刻の目盛りを何時間おきにするか決める。
    /// 表示範囲がせまいほど細かく刻み、入りきらないときは順に粗くします。
    ///   span   表示している時間の幅（時間）
    ///   usable 目盛りに使える横幅（pt）
    public static func hours(span: Double, usable: Double) -> Hour {
        guard span > 0, usable > 0 else { return Hour(step: 24, withUnit: true, gap: usable) }
        var i = span > 120 ? 5 : (span > 80 ? 3 : (span > 30 ? 2 : 1))
        while i < hourSteps.count - 1 && usable / (span / Double(hourSteps[i])) < 24 { i += 1 }
        let gap = usable / (span / Double(hourSteps[i]))
        return Hour(step: hourSteps[i], withUnit: gap >= 34, gap: gap)
    }

    /// 目盛りにする時刻を並べる
    public static func hourMarks(from start: Date, to end: Date, step: Int) -> [Date] {
        guard step > 0, end > start else { return [] }
        let p = JST.parts(start)
        var t = JST.date(p.year ?? 2000, p.month ?? 1, p.day ?? 1, p.hour ?? 0)
        while (JST.parts(t).hour ?? 0) % step != 0 { t = t.addingTimeInterval(3600) }
        if t < start { t = t.addingTimeInterval(TimeInterval(step * 3600)) }

        var out: [Date] = []
        while t <= end && out.count < 400 {
            out.append(t)
            t = t.addingTimeInterval(TimeInterval(step * 3600))
        }
        return out
    }

    /// 縦軸をキリのよい数字で刻む
    public static func nice(min: Double, max: Double, want: Int = 4) -> (min: Double, max: Double, step: Double) {
        guard min.isFinite, max.isFinite else { return (0, 1, 1) }
        var lo = min, hi = max
        if hi - lo < 1e-6 { lo -= 0.5; hi += 0.5 }
        let raw = (hi - lo) / Double(Swift.max(want, 1))
        let step = niceStep(raw)
        let start = (lo / step).rounded(.down) * step
        let stop = (hi / step).rounded(.up) * step
        return (start, stop, step)
    }

    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let exp = pow(10, (log10(raw)).rounded(.down))
        let f = raw / exp
        let nice: Double = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5 : 10)))
        return nice * exp
    }

    /// 縦軸に並べる値
    public static func values(min: Double, max: Double, step: Double) -> [Double] {
        guard step > 0, max > min else { return [min] }
        var out: [Double] = []
        var v = min
        while v <= max + step / 1000 && out.count < 40 {
            out.append(v)
            v += step
        }
        return out
    }

    /// 表示範囲に入っている日の切れ目（日本時間の0時）
    public static func dayStarts(from start: Date, to end: Date) -> [Date] {
        var t = JST.startOfDay(start)
        var out: [Date] = []
        while t <= end && out.count < 40 {
            if t > start { out.append(t) }
            t = JST.calendar.date(byAdding: .day, value: 1, to: t) ?? t.addingTimeInterval(86400)
        }
        return out
    }

    /// 表示範囲に入っている日（帯の中央に日付を出すために使います）
    public static func days(from start: Date, to end: Date) -> [(start: Date, end: Date, date: Date)] {
        var out: [(Date, Date, Date)] = []
        var t = JST.startOfDay(start)
        while t < end && out.count < 40 {
            let next = JST.calendar.date(byAdding: .day, value: 1, to: t) ?? t.addingTimeInterval(86400)
            if next > start { out.append((t, next, t)) }
            t = next
        }
        return out
    }
}
