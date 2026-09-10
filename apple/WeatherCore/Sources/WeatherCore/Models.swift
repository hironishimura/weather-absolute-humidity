//  画面と取得処理でやりとりする型

import Foundation

// MARK: - 提供元

public enum SourceKey: String, CaseIterable, Codable, Sendable, Identifiable {
    case jma
    case model
    case ecmwf
    case yahoo
    case weathernews

    public var id: String { rawValue }

    /// 画面に出す名前
    public var name: String {
        switch self {
        case .jma: return "気象庁"
        case .model: return "気象庁MSM/GSM"
        case .ecmwf: return "ECMWF"
        case .yahoo: return "Yahoo!天気"
        case .weathernews: return "ウェザーニュース"
        }
    }

    /// 凡例などで使う短い名前
    public var short: String {
        switch self {
        case .jma: return "気象庁 実況"
        case .model: return "MSM/GSM"
        case .ecmwf: return "ECMWF"
        case .yahoo: return "Yahoo!天気"
        case .weathernews: return "ウェザーニュース"
        }
    }

    public var about: String {
        switch self {
        case .jma:
            return "近隣アメダスの観測値です。"
        case .model:
            return "気象庁の数値予報を Open-Meteo 経由で取得。実測値ではありません。"
                + "降水確率だけは気象庁モデルに入っていないため、Open-Meteo の総合予報の値です。"
        case .ecmwf:
            return "欧州中期予報センターの全球モデル（IFS 0.25°）を Open-Meteo 経由で取得。"
                + "気象庁とは別の計算なので、両者が一致していれば見通しが立ち、"
                + "割れていれば難しい状況だと分かります。降水確率は出ません。"
        case .yahoo:
            return "3時間ごとの予報値です。"
        case .weathernews:
            return "公開ページの実況天気・観測値です。"
        }
    }

    /// 降水確率を出す提供元。ECMWF は降水確率を持たないので当たり具合も数えません
    public static var withPop: [SourceKey] { allCases.filter { $0 != .ecmwf } }

    /// 既定の色（Web版と同じ）
    public var defaultHex: String {
        switch self {
        case .jma: return "#C77B1E"
        case .model: return "#1F6FEB"
        case .ecmwf: return "#7B3FA0"
        case .yahoo: return "#C0392B"
        case .weathernews: return "#1F7A55"
        }
    }
}

// MARK: - 地点

public struct Place: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var lat: Double
    public var lon: Double
    /// 気象庁の府県予報区。空なら緯度経度から自動で選びます。
    public var office: String?

    public init(id: String = Place.newID(), label: String, lat: Double, lon: Double, office: String? = nil) {
        self.id = id
        self.label = label
        self.lat = lat
        self.lon = lon
        self.office = office
    }

    public static func newID() -> String {
        "p" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
            + String(Int.random(in: 0..<1296), radix: 36)
    }

    public static let 宇都宮 = Place(id: "utsunomiya", label: "栃木県宇都宮市", lat: 36.5551, lon: 139.8828)
}

// MARK: - 観測所

public struct Station: Equatable, Sendable {
    public var code: String
    public var name: String
    public var lat: Double
    public var lon: Double
    public var alt: Double
    public var km: Double
}

// MARK: - 値

/// いまの値（実況または予報）
public struct NowValue: Equatable, Sendable {
    public var time: Date?
    public var values: Reading
    /// 実況ではなく予報の値のとき true
    public var isForecast: Bool
    public var stationName: String?
    public var fetchedAt: Date?
    /// アメダスの生データ（風や降水量の表示に使います）
    public var wind: Double?
    public var windDirection: Int?
    public var precipitation1h: Double?

    public init(time: Date?, values: Reading, isForecast: Bool = false, stationName: String? = nil,
                fetchedAt: Date? = nil, wind: Double? = nil, windDirection: Int? = nil,
                precipitation1h: Double? = nil) {
        self.time = time
        self.values = values
        self.isForecast = isForecast
        self.stationName = stationName
        self.fetchedAt = fetchedAt
        self.wind = wind
        self.windDirection = windDirection
        self.precipitation1h = precipitation1h
    }
}

/// 時系列の1点。提供元によって取れる項目が違うので、ないものは nil です。
public struct HourlyRow: Equatable, Sendable, Identifiable {
    public var time: Date
    public var temp: Double?
    public var rh: Double?
    public var vh: Double?
    public var mr: Double?
    public var pop: Double?
    /// 雨量 [mm/h]
    public var precip: Double?

    public var id: Date { time }

    public init(time: Date, temp: Double? = nil, rh: Double? = nil,
                vh: Double? = nil, mr: Double? = nil,
                pop: Double? = nil, precip: Double? = nil) {
        self.time = time
        self.temp = temp
        self.rh = rh
        self.vh = vh
        self.mr = mr
        self.pop = pop
        self.precip = precip
    }

    /// 気温と湿度がそろっていれば絶対湿度も入れて作ります
    public static func make(time: Date, temp: Double?, rh: Double?,
                            pressure: Double? = nil, pop: Double? = nil,
                            precip: Double? = nil) -> HourlyRow? {
        var row = HourlyRow(time: time, temp: temp, rh: rh, pop: pop, precip: precip)
        if let t = temp, let h = rh {
            row.vh = Psychrometrics.volumetricHumidity(t, h)
            row.mr = Psychrometrics.mixingRatio(t, h, pressure: pressure)
        }
        if row.temp == nil && row.rh == nil && row.pop == nil && row.precip == nil { return nil }
        return row
    }
}

/// 時間帯ごとの降水確率
public struct PopBlock: Equatable, Sendable {
    public var time: Date
    public var hours: Int
    public var pop: Double

    public init(time: Date, hours: Int, pop: Double) {
        self.time = time
        self.hours = hours
        self.pop = pop
    }
}

/// 日ごとの予報
public struct DailyForecast: Equatable, Sendable, Identifiable {
    /// 日本時間の日付キー（2026-09-09）
    public var key: String
    public var date: Date
    public var weather: String
    public var code: String
    public var pop: Double?
    public var min: Double?
    public var max: Double?
    /// その日の絶対湿度 [g/kg(DA)]
    public var ahMin: Double?
    public var ahMax: Double?

    public var id: String { key }

    public init(key: String, date: Date, weather: String = "", code: String = "",
                pop: Double? = nil, min: Double? = nil, max: Double? = nil,
                ahMin: Double? = nil, ahMax: Double? = nil) {
        self.key = key
        self.date = date
        self.weather = weather
        self.code = code
        self.pop = pop
        self.min = min
        self.max = max
        self.ahMin = ahMin
        self.ahMax = ahMax
    }
}

// MARK: - 取得状況

public struct StatusLine: Identifiable, Equatable, Sendable {
    public enum State: Sendable { case ok, failed, notFetched }
    public var key: String
    public var name: String
    public var state: State
    public var message: String

    public var id: String { key }

    public init(key: String, name: String, state: State, message: String) {
        self.key = key
        self.name = name
        self.state = state
        self.message = message
    }
}
