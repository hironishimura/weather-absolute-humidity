import XCTest
@testable import WeatherCore

/// Web版（test/logic.js）と同じ値になることを確かめます
final class 湿り空気の計算: XCTestCase {

    func test_飽和水蒸気圧() {
        XCTAssertEqual(Psychrometrics.saturationVaporPressure(0), 6.11, accuracy: 0.02)
        XCTAssertEqual(Psychrometrics.saturationVaporPressure(20), 23.4, accuracy: 0.2)
        XCTAssertEqual(Psychrometrics.saturationVaporPressure(30), 42.4, accuracy: 0.4)
    }

    func test_容積絶対湿度() {
        // 20℃ 60% でおよそ 10.4 g/m³
        XCTAssertEqual(Psychrometrics.volumetricHumidity(20, 60), 10.4, accuracy: 0.3)
        // 30℃ 80% でおよそ 24.2 g/m³
        XCTAssertEqual(Psychrometrics.volumetricHumidity(30, 80), 24.2, accuracy: 0.6)
    }

    func test_湿度0なら絶対湿度も0() {
        XCTAssertEqual(Psychrometrics.volumetricHumidity(25, 0), 0, accuracy: 1e-9)
    }

    func test_重量絶対湿度() {
        // 20℃ 60% 1013.25hPa でおよそ 8.8 g/kg(DA)
        XCTAssertEqual(Psychrometrics.mixingRatio(20, 60) ?? 0, 8.8, accuracy: 0.3)
    }

    func test_気圧が低いほど重量絶対湿度は大きい() {
        let high = Psychrometrics.mixingRatio(20, 60, pressure: 1013.25) ?? 0
        let low = Psychrometrics.mixingRatio(20, 60, pressure: 950) ?? 0
        XCTAssertGreaterThan(low, high)
    }

    func test_露点温度() {
        XCTAssertEqual(Psychrometrics.dewPoint(20, 60), 12.0, accuracy: 0.4)
        // 湿度100%なら露点は気温と同じ
        XCTAssertEqual(Psychrometrics.dewPoint(25, 100), 25, accuracy: 0.1)
    }

    func test_不快指数() {
        XCTAssertEqual(Psychrometrics.discomfortIndex(30, 70), 82.7, accuracy: 0.3)
    }

    func test_標高が高いほど気圧は低い() {
        let sea = Psychrometrics.pressureFromAltitude(0)
        let high = Psychrometrics.pressureFromAltitude(1000)
        XCTAssertEqual(sea, 1013.25, accuracy: 0.1)
        XCTAssertLessThan(high, sea)
    }

    func test_まとめて作る() {
        let r = Reading(temp: 24.2, rh: 68, pressure: 1002.4)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.vh, 15.2, accuracy: 0.3)
        XCTAssertEqual(r!.pressure, 1002.4)
    }

    func test_値が欠けていれば作らない() {
        XCTAssertNil(Reading(temp: nil, rh: 60))
        XCTAssertNil(Reading(temp: 20, rh: nil))
    }
}

final class 距離と時刻: XCTestCase {

    func test_距離() {
        // 宇都宮 → 東京 はおよそ 100km
        let km = Geo.distanceKm(36.5551, 139.8828, 35.6812, 139.7671)
        XCTAssertEqual(km, 98, accuracy: 5)
    }

    func test_同じ場所なら0() {
        XCTAssertEqual(Geo.distanceKm(36.5, 139.8, 36.5, 139.8), 0, accuracy: 1e-9)
    }

    func test_度分を度に() {
        XCTAssertEqual(Geo.degrees(fromDegreeMinute: [36, 33.0]) ?? 0, 36.55, accuracy: 0.001)
        XCTAssertNil(Geo.degrees(fromDegreeMinute: nil))
        XCTAssertNil(Geo.degrees(fromDegreeMinute: [36]))
    }

    func test_気象庁の時刻表記を読む() {
        let d = JST.date(fromStamp: "20260908141000")
        XCTAssertEqual(d, JST.date(2026, 9, 8, 14, 10))
    }

    func test_読めない時刻はnil() {
        XCTAssertNil(JST.date(fromStamp: "こんにちは"))
        XCTAssertNil(JST.date(fromStamp: "2026"))
    }

    func test_日付キー() {
        XCTAssertEqual(JST.dayKey(JST.date(2026, 9, 9, 23, 30)), "2026-09-09")
        // 日本時間の0時ちょうどはその日
        XCTAssertEqual(JST.dayKey(JST.date(2026, 9, 10, 0, 0)), "2026-09-10")
    }

    func test_ISO文字列を読む() {
        XCTAssertEqual(JST.parseISO("2026-09-09T18:00:00+09:00"), JST.date(2026, 9, 9, 18))
        // タイムゾーンがなければ日本時間として読む（Open-Meteo がこの形）
        XCTAssertEqual(JST.parseISO("2026-09-09T18:00"), JST.date(2026, 9, 9, 18))
        XCTAssertNil(JST.parseISO(""))
    }

    func test_予報区を選ぶ() {
        XCTAssertEqual(JMATables.resolveOffice(lat: 36.5551, lon: 139.8828), "090000")   // 栃木県
        XCTAssertEqual(JMATables.resolveOffice(lat: 35.6812, lon: 139.7671), "130000")   // 東京都
        XCTAssertEqual(JMATables.resolveOffice(lat: 26.2124, lon: 127.6809), "471000")   // 沖縄本島
    }

    func test_予報区の数はWeb版と同じ() {
        XCTAssertEqual(JMATables.offices.count, 58)
    }

    func test_天気コードから文言() {
        XCTAssertEqual(JMATables.weatherName(code: "101"), "晴れ時々くもり")
        XCTAssertEqual(JMATables.weatherName(code: "999"), "")
        XCTAssertEqual(JMATables.weatherName(code: nil), "")
    }
}
