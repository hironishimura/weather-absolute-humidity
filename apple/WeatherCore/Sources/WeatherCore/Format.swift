//  表示のための文字づくり（すべて日本時間）

import Foundation

public enum Format {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = JST.zone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let timeF = formatter("Hmm")
    private static let dateTimeF = formatter("MdHmm")
    private static let dateF = formatter("MdEEE")

    /// 21:05
    public static func time(_ d: Date) -> String { timeF.string(from: d) }

    /// 9/9 21:05
    public static func dateTime(_ d: Date) -> String { dateTimeF.string(from: d) }

    /// 9/9(水)
    public static func date(_ d: Date) -> String { dateF.string(from: d) }

    /// 9/9
    public static func shortDate(_ d: Date) -> String {
        let p = JST.parts(d)
        return "\(p.month ?? 0)/\(p.day ?? 0)"
    }

    /// 数値。値がなければ「--」
    public static func number(_ v: Double?, _ digits: Int = 1) -> String {
        guard let v, v.isFinite else { return "--" }
        return String(format: "%.\(digits)f", v)
    }

    /// 「1.3 km」のような距離
    public static func km(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f km", v) : String(format: "%.0f km", v)
    }
}
