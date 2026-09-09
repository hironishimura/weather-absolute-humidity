//  距離と時刻まわりの小さな道具

import Foundation

public enum Geo {
    /// 2地点の距離 [km]
    public static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let R = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// アメダス表の [度, 分] を度に直す
    public static func degrees(fromDegreeMinute dm: [Double]?) -> Double? {
        guard let dm, dm.count >= 2 else { return nil }
        return dm[0] + dm[1] / 60
    }
}

/// 日本時間まわり。気象庁のデータは日本時間が前提なので、一か所にまとめています。
public enum JST {
    public static let zone = TimeZone(secondsFromGMT: 9 * 3600)!

    public static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = Locale(identifier: "ja_JP")
        return c
    }()

    /// 日本時間での年月日時分
    public static func parts(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
    }

    /// 日本時間の日付キー（2026-09-09）
    public static func dayKey(_ date: Date) -> String {
        let p = parts(date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    /// その日の0時（日本時間）
    public static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 気象庁のファイル名に使う YYYYMMDDHHMM00
    public static func stamp(_ date: Date) -> String {
        let p = parts(date)
        return String(format: "%04d%02d%02d%02d%02d00",
                      p.year ?? 0, p.month ?? 0, p.day ?? 0, p.hour ?? 0, p.minute ?? 0)
    }

    /// 気象庁の 20260908141000 形式を Date に
    public static func date(fromStamp s: String) -> Date? {
        let digits = s.prefix(12)
        guard digits.count == 12, digits.allSatisfy(\.isNumber) else { return nil }
        func num(_ from: Int, _ len: Int) -> Int {
            let a = digits.index(digits.startIndex, offsetBy: from)
            let b = digits.index(a, offsetBy: len)
            return Int(digits[a..<b]) ?? 0
        }
        var c = DateComponents()
        c.year = num(0, 4); c.month = num(4, 2); c.day = num(6, 2)
        c.hour = num(8, 2); c.minute = num(10, 2)
        c.timeZone = zone
        return calendar.date(from: c)
    }

    /// 日本時間の年月日時分から Date を作る
    public static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        c.timeZone = zone
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// 2026-09-09T18:00:00+09:00 のような文字列を読む。
    /// タイムゾーンが書かれていなければ日本時間として読みます（Open-Meteo がこの形）。
    public static func parseISO(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let hasZone = t.hasSuffix("Z") || t.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        let full = hasZone ? t : t + (t.count == 16 ? ":00+09:00" : "+09:00")
        for options in [[ISO8601DateFormatter.Options.withInternetDateTime],
                        [.withInternetDateTime, .withFractionalSeconds]] {
            let f = ISO8601DateFormatter()
            f.formatOptions = options
            if let d = f.date(from: full) { return d }
        }
        return nil
    }
}
