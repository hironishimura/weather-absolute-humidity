import XCTest
@testable import WeatherCore

final class 地名から緯度経度: XCTestCase {

    private func feature(_ title: String, lat: Double, lon: Double) -> Geocoder.GSIFeature {
        Geocoder.GSIFeature(geometry: .init(coordinates: [lon, lat]),
                            properties: .init(title: title))
    }

    func test_空白を落とす() {
        XCTAssertEqual(Geocoder.normalize(" 栃木県 　宇都宮市 "), "栃木県宇都宮市")
        XCTAssertEqual(Geocoder.normalize("   "), "")
    }

    func test_字が入っていないものを落とす() {
        // 「東京駅」で北海道が並んだ実例です
        let list = [
            feature("北海道札幌市東区", lat: 43.076111, lon: 141.363617),
            feature("北海道東神楽町東", lat: 43.681801, lon: 142.432129),
            feature("東京駅", lat: 35.681259, lon: 139.766217),
        ]
        let hits = Geocoder.pick(list, query: "東京駅")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.title, "東京駅")
    }

    func test_緯度と経度を取り違えない() {
        // 国土地理院は [経度, 緯度] の順で返します。逆に読むと日本から出ます
        let hits = Geocoder.pick([feature("栃木県宇都宮市平出町",
                                          lat: 36.57386, lon: 139.945251)],
                                 query: "宇都宮市平出町")
        XCTAssertEqual(hits.first?.lat ?? 0, 36.57386, accuracy: 0.0001)
        XCTAssertEqual(hits.first?.lon ?? 0, 139.945251, accuracy: 0.0001)
        XCTAssertLessThan(hits.first?.lat ?? 0, hits.first?.lon ?? 0)
    }

    func test_多すぎるときは8件まで() {
        let many = (0..<20).map { _ in feature("鹿沼市", lat: 36.5, lon: 139.7) }
        XCTAssertEqual(Geocoder.pick(many, query: "鹿沼市").count, Geocoder.limit)
    }

    func test_座標のないものは捨てる() {
        let broken = Geocoder.GSIFeature(geometry: nil, properties: .init(title: "鹿沼市"))
        XCTAssertTrue(Geocoder.pick([broken], query: "鹿沼市").isEmpty)
    }

    func test_問い合わせの字がURLに入る() {
        let c = Geocoder(fetcher: URLSessionFetcher())
        let url = c.gsiURL("宇都宮市").absoluteString
        XCTAssertTrue(url.hasPrefix(Geocoder.gsiBase), url)
        XCTAssertTrue(url.contains("q="), url)
        // 日本語はそのまま載せられないので、必ず変換されている必要があります
        XCTAssertFalse(url.contains("宇都宮"), url)
        XCTAssertTrue(url.contains("%E5%AE%87%E9%83%BD%E5%AE%AE%E5%B8%82"), url)
    }

    func test_控えのURLも組める() {
        let c = Geocoder(fetcher: URLSessionFetcher())
        let url = c.openMeteoURL("鹿沼市").absoluteString
        XCTAssertTrue(url.contains("language=ja"), url)
        XCTAssertTrue(url.contains("count=\(Geocoder.limit)"), url)
    }
}
