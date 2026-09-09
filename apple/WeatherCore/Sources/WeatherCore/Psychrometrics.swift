//  湿り空気の計算
//
//  Web版（docs/assets/app.js）と同じ式を使っています。
//  数字が食い違わないよう、係数もそのまま合わせてあります。

import Foundation

public enum Psychrometrics {

    /// 飽和水蒸気圧 [hPa]（Tetens の式・水面上）
    public static func saturationVaporPressure(_ t: Double) -> Double {
        6.1078 * pow(10, (7.5 * t) / (t + 237.3))
    }

    /// 水蒸気圧 [hPa]
    public static func vaporPressure(_ t: Double, _ rh: Double) -> Double {
        saturationVaporPressure(t) * (rh / 100)
    }

    /// 容積絶対湿度 [g/m³]　空気1立方メートルに含まれる水蒸気の重さ
    public static func volumetricHumidity(_ t: Double, _ rh: Double) -> Double {
        (216.68 * vaporPressure(t, rh)) / (t + 273.15)
    }

    /// 重量絶対湿度 [g/kg(DA)]　乾き空気1kgあたりの水蒸気の重さ
    public static func mixingRatio(_ t: Double, _ rh: Double, pressure: Double? = nil) -> Double? {
        let p = pressure ?? 1013.25
        let e = vaporPressure(t, rh)
        guard p - e > 0 else { return nil }
        return (621.945 * e) / (p - e)
    }

    /// 露点温度 [℃]（Magnus の式）
    public static func dewPoint(_ t: Double, _ rh: Double) -> Double {
        let a = 17.625, b = 243.04
        let r = min(max(rh, 0.1), 100)
        let g = log(r / 100) + (a * t) / (b + t)
        return (b * g) / (a - g)
    }

    /// 不快指数
    public static func discomfortIndex(_ t: Double, _ rh: Double) -> Double {
        0.81 * t + 0.01 * rh * (0.99 * t - 14.3) + 46.3
    }

    /// 標高から気圧を推定 [hPa]（観測値がないときの控え）
    public static func pressureFromAltitude(_ alt: Double, temperature t: Double? = nil) -> Double {
        let temp = t ?? 15
        return 1013.25 * pow(1 - (0.0065 * alt) / (temp + 273.15 + 0.0065 * alt), 5.257)
    }
}

/// 気温と相対湿度から、画面に出す値をまとめて作ったもの
public struct Reading: Equatable, Sendable {
    public var temp: Double
    public var rh: Double
    public var vh: Double
    public var mr: Double?
    public var dp: Double
    public var di: Double
    public var pressure: Double?

    public init?(temp: Double?, rh: Double?, pressure: Double? = nil) {
        guard let t = temp, let h = rh, t.isFinite, h.isFinite else { return nil }
        self.temp = t
        self.rh = h
        self.vh = Psychrometrics.volumetricHumidity(t, h)
        self.mr = Psychrometrics.mixingRatio(t, h, pressure: pressure)
        self.dp = Psychrometrics.dewPoint(t, h)
        self.di = Psychrometrics.discomfortIndex(t, h)
        self.pressure = pressure
    }
}
