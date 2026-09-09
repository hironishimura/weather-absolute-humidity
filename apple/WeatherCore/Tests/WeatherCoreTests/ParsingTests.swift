import XCTest
@testable import WeatherCore

/// ネットには出ず、作ったデータで読み取りを確かめます
final class 取得の差し替え: Fetching, @unchecked Sendable {
    var bodies: [String: Data] = [:]
    var requested: [String] = []

    func data(from url: URL) async throws -> Data {
        requested.append(url.absoluteString)
        for (needle, body) in bodies where url.absoluteString.contains(needle) {
            return body
        }
        throw FetchError.http(404)
    }

    func put(_ needle: String, json: Any) {
        bodies[needle] = try! JSONSerialization.data(withJSONObject: json)
    }
    func put(_ needle: String, text: String) {
        bodies[needle] = Data(text.utf8)
    }
}

final class 気象庁の予報を読む: XCTestCase {

    let stations: [StationInfo] = [
        StationInfo(code: "41277", name: "宇都宮", lat: 36.55, lon: 139.87, alt: 119),
        StationInfo(code: "41166", name: "真岡", lat: 36.44, lon: 140.01, alt: 66)
    ]

    var forecastJSON: [Any] {
        [
            ["timeSeries": [
                ["timeDefines": ["2026-09-09T05:00:00+09:00", "2026-09-10T00:00:00+09:00"],
                 "areas": [["area": ["name": "南部", "code": "090010"],
                            "weatherCodes": ["200", "101"],
                            "weathers": ["くもり", "晴れ　時々　くもり"]]]],
                ["timeDefines": ["2026-09-09T06:00:00+09:00", "2026-09-09T12:00:00+09:00",
                                 "2026-09-10T00:00:00+09:00"],
                 "areas": [["area": ["code": "090010"], "pops": ["10", "30", ""]]]],
                ["timeDefines": ["2026-09-10T00:00:00+09:00", "2026-09-10T09:00:00+09:00"],
                 "areas": [["area": ["code": "41166"], "temps": ["19", "31"]],
                           ["area": ["code": "41277"], "temps": ["21", "29"]]]]
            ]],
            ["timeSeries": [
                ["timeDefines": ["2026-09-11T00:00:00+09:00", "2026-09-12T00:00:00+09:00"],
                 "areas": [["area": ["code": "090000"],
                            "weatherCodes": ["300", "201"], "pops": ["70", "20"]]]],
                ["timeDefines": ["2026-09-11T00:00:00+09:00", "2026-09-12T00:00:00+09:00"],
                 "areas": [["area": ["code": "41277"],
                            "tempsMin": ["19", "18"], "tempsMax": ["26", "25"]]]]
            ]]
        ]
    }

    func 読む() -> ForecastResult {
        ForecastClient.parse(forecastJSON, place: .宇都宮, stations: stations)
    }

    func test_日ごとにまとまる() {
        let r = 読む()
        XCTAssertEqual(r.daily.map(\.key), ["2026-09-09", "2026-09-10", "2026-09-11", "2026-09-12"])
    }

    func test_天気の空白を詰める() {
        XCTAssertEqual(読む().daily[1].weather, "晴れ時々くもり")
    }

    func test_降水確率はその日の最大() {
        XCTAssertEqual(読む().daily[0].pop, 30)
    }

    func test_空欄の降水確率は飛ばす() {
        let pops = 読む().pops
        XCTAssertEqual(pops.count, 2)
        XCTAssertEqual(pops.map(\.pop), [10, 30])
        XCTAssertEqual(pops[0].hours, 6)
    }

    func test_近い気温予報地点を選ぶ() {
        // 宇都宮（41277）のほうが近いので 21/29 を使う
        let d = 読む().daily[1]
        XCTAssertEqual(d.min, 21)
        XCTAssertEqual(d.max, 29)
    }

    func test_週間予報から埋める() {
        let d = 読む().daily[2]
        XCTAssertEqual(d.min, 19)
        XCTAssertEqual(d.max, 26)
        XCTAssertEqual(d.pop, 70)
        XCTAssertEqual(d.weather, "雨")     // 文言がないのでコードから
    }

    func test_取得までまとめて() async throws {
        let fake = 取得の差し替え()
        fake.put("/forecast/data/forecast/", json: forecastJSON)
        fake.put("overview_forecast", json: ["text": "高気圧に覆われています。"])
        let client = ForecastClient(fetcher: fake)
        let r = try await client.load(place: .宇都宮, officeNames: ["090000": "栃木県"],
                                      stations: stations)
        XCTAssertEqual(r.officeCode, "090000")
        XCTAssertEqual(r.officeName, "栃木県")
        XCTAssertEqual(r.overview, "高気圧に覆われています。")
    }

    func test_気象概況が読めなくても止まらない() async throws {
        let fake = 取得の差し替え()
        fake.put("/forecast/data/forecast/", json: forecastJSON)
        let client = ForecastClient(fetcher: fake)
        let r = try await client.load(place: .宇都宮, officeNames: [:], stations: stations)
        XCTAssertEqual(r.overview, "")
        XCTAssertFalse(r.daily.isEmpty)
    }
}

final class アメダスを読む: XCTestCase {

    let table: [String: Any] = [
        "41000": ["kjName": "ダミー", "lat": [36, 33.2], "lon": [139, 52.4], "alt": 100],
        "41277": ["kjName": "宇都宮", "lat": [36, 33.0], "lon": [139, 52.2], "alt": 119],
        "44132": ["kjName": "東京", "lat": [35, 41.4], "lon": [139, 45.6], "alt": 25]
    ]

    func fake() -> 取得の差し替え {
        let f = 取得の差し替え()
        f.put("amedastable", json: table)
        f.put("latest_time", text: "2026-09-08T14:10:00+09:00")
        f.put("/map/20260908141000.json", json: [
            "41000": ["temp": [24.8, 0]],                                   // 湿度なし
            "41277": ["temp": [24.2, 0], "humidity": [68, 0], "pressure": [1002.4, 0],
                      "wind": [2.1, 0], "windDirection": [5, 0], "precipitation1h": [0.5, 0]],
            "44132": ["temp": [27.0, 0], "humidity": [55, 0]]
        ])
        f.put("/point/41277/20260908_12.json", json: [
            "20260908120000": ["temp": [23.5, 0], "humidity": [70, 0], "pressure": [1002.8, 0]],
            "20260908121000": ["temp": [23.8, 0], "humidity": [69, 0]],
            "20260908122000": ["temp": [24.0, 0], "humidity": [NSNull(), 5]],   // 欠測
            "20260908123000": ["temp": [24.2, 0], "humidity": [68, 0]]
        ])
        return f
    }

    func test_湿度のある一番近い観測所を選ぶ() async throws {
        let f = fake()
        let client = AmedasClient(fetcher: f)
        let list = try await client.table()
        let hit = try await client.current(place: .宇都宮, table: list)
        XCTAssertEqual(hit.station.code, "41277")
        XCTAssertEqual(hit.now.values.temp, 24.2)
        XCTAssertEqual(hit.now.values.rh, 68)
        XCTAssertEqual(hit.now.values.pressure ?? 0, 1002.4, accuracy: 0.01)
        XCTAssertEqual(hit.now.values.vh, 15.2, accuracy: 0.3)
        XCTAssertTrue(hit.hasHumidity)
        XCTAssertEqual(hit.observedAt, JST.date(2026, 9, 8, 14, 10))
    }

    func test_風の表示() async throws {
        let f = fake()
        let client = AmedasClient(fetcher: f)
        let hit = try await client.current(place: .宇都宮, table: try await client.table())
        XCTAssertEqual(Wind.text(direction: hit.now.windDirection, speed: hit.now.wind), "東 2.1 m/s")
        XCTAssertEqual(Wind.text(direction: 0, speed: 1.0), "静穏 1.0 m/s")
        XCTAssertEqual(Wind.text(direction: nil, speed: nil), "--")
    }

    func test_日本時間でファイル名を組む() async throws {
        let f = fake()
        let client = AmedasClient(fetcher: f)
        _ = try await client.current(place: .宇都宮, table: try await client.table())
        XCTAssertTrue(f.requested.contains { $0.contains("/map/20260908141000.json") })
    }

    func test_過去24時間は欠測を除く() async throws {
        let f = fake()
        let client = AmedasClient(fetcher: f)
        let rows = try await client.past24h(stationCode: "41277",
                                            observedAt: JST.date(2026, 9, 8, 14, 10))
        XCTAssertEqual(rows.count, 3)                 // 欠測の1点を除く
        XCTAssertLessThan(rows[0].time, rows[2].time) // 時刻順
        XCTAssertEqual(rows[0].vh ?? 0, 14.7, accuracy: 0.5)
    }

    func test_近い順に並ぶ() {
        let list = AmedasClient.parseTable(table)
        let near = AmedasClient.nearest(list, lat: 36.5551, lon: 139.8828, limit: 2)
        XCTAssertEqual(near.count, 2)
        XCTAssertLessThan(near[0].km, near[1].km)
        XCTAssertEqual(near[0].alt, 100)              // 一番近いのはダミー地点
    }
}
