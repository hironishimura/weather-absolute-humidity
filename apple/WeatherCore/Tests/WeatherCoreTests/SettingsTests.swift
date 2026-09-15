import XCTest
@testable import WeatherCore

/// iCloud の代わりに、記憶の中に置くだけの入れもの
final class 置き場所の差し替え: SettingsBackend {
    var stored: Data?
    var isCloud: Bool = true
    var onExternalChange: (() -> Void)?
    var writes = 0

    func read() -> Data? { stored }
    func write(_ data: Data) { stored = data; writes += 1 }

    /// 他の端末で書き換わったことにする
    func pretendOtherDeviceWrote(_ data: SettingsData) {
        stored = try! JSONEncoder().encode(data)
        onExternalChange?()
    }
}

@MainActor
final class 地点の保存: XCTestCase {

    func test_はじめは宇都宮ひとつ() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        XCTAssertEqual(store.places.count, 1)
        XCTAssertEqual(store.active.label, "栃木県宇都宮市")
    }

    func test_足すとそれが選ばれる() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        let tokyo = Place(label: "東京 現場", lat: 35.6812, lon: 139.7671)
        store.add(tokyo)
        XCTAssertEqual(store.places.count, 2)
        XCTAssertEqual(store.active.id, tokyo.id)
    }

    func test_現在地は先頭にひとつだけ増える() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        store.setHere(lat: 36.5551, lon: 139.8828)
        XCTAssertEqual(store.places.count, 2)
        XCTAssertEqual(store.places.first?.id, Place.hereID)
        XCTAssertEqual(store.active.label, "現在地")
        XCTAssertTrue(store.active.isHere)
    }

    func test_現在地は押すたび位置だけ入れ替わる() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        store.setHere(lat: 36.5551, lon: 139.8828)
        store.setHere(lat: 35.6812, lon: 139.7671)
        // 増えません。ひとつを使い回します
        XCTAssertEqual(store.places.count, 2)
        XCTAssertEqual(store.places.filter(\.isHere).count, 1)
        XCTAssertEqual(store.active.lat, 35.6812, accuracy: 0.0001)
        XCTAssertEqual(store.active.lon, 139.7671, accuracy: 0.0001)
    }

    func test_ほかの地点に移ってからでも現在地に戻れる() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        store.setHere(lat: 36.5551, lon: 139.8828)
        let tokyo = Place(label: "東京 現場", lat: 35.6812, lon: 139.7671)
        store.add(tokyo)
        XCTAssertFalse(store.active.isHere)
        store.setHere(lat: 34.6937, lon: 135.5023)
        XCTAssertTrue(store.active.isHere)
        XCTAssertEqual(store.places.count, 3)
    }

    func test_書き換えられる() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        var p = store.active
        p.label = "自宅"
        store.update(p)
        XCTAssertEqual(store.active.label, "自宅")
    }

    func test_最後のひとつは消せない() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        store.remove(id: store.active.id)
        XCTAssertEqual(store.places.count, 1)
    }

    func test_消すと別の地点に移る() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        let first = store.active.id
        store.add(Place(label: "東京", lat: 35.6812, lon: 139.7671))
        let second = store.active.id
        store.remove(id: second)
        XCTAssertEqual(store.active.id, first)
    }

    func test_並べ替え() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        store.add(Place(label: "東京", lat: 35.68, lon: 139.76))
        store.add(Place(label: "大阪", lat: 34.69, lon: 135.50))
        XCTAssertEqual(store.places.map(\.label), ["栃木県宇都宮市", "東京", "大阪"])
        store.move(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(store.places.map(\.label), ["大阪", "栃木県宇都宮市", "東京"])
    }

    func test_保存される() {
        let backend = 置き場所の差し替え()
        let store = SettingsStore(backend: backend)
        store.add(Place(label: "東京", lat: 35.68, lon: 139.76))
        XCTAssertGreaterThan(backend.writes, 0)

        // 読み直しても残っている
        let again = SettingsStore(backend: backend)
        XCTAssertEqual(again.places.count, 2)
    }

    func test_他の端末で変わったら追いつく() {
        let backend = 置き場所の差し替え()
        let store = SettingsStore(backend: backend)
        let other = SettingsData(places: [Place(id: "x", label: "神戸", lat: 34.69, lon: 135.19)],
                                 activeID: "x")
        backend.pretendOtherDeviceWrote(other)
        store.reload()
        XCTAssertEqual(store.places.map(\.label), ["神戸"])
    }

    func test_中身が空なら追いつかない() {
        let backend = 置き場所の差し替え()
        let store = SettingsStore(backend: backend)
        backend.pretendOtherDeviceWrote(SettingsData(places: [], activeID: ""))
        store.reload()
        XCTAssertEqual(store.places.count, 1)    // もとのまま
    }

    func test_新しいほうを採る() {
        let old = SettingsData(places: [Place(id: "a", label: "古い", lat: 0, lon: 0)],
                               activeID: "a", updatedAt: Date(timeIntervalSince1970: 100))
        let new = SettingsData(places: [Place(id: "b", label: "新しい", lat: 0, lon: 0)],
                               activeID: "b", updatedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(SettingsData.newer(old, new)?.activeID, "b")
        XCTAssertEqual(SettingsData.newer(new, old)?.activeID, "b")
        XCTAssertEqual(SettingsData.newer(old, nil)?.activeID, "a")
        XCTAssertNil(SettingsData.newer(nil, nil))
    }

    func test_色を変えて元に戻す() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        XCTAssertEqual(store.hex(for: .jma), SourceKey.jma.defaultHex)
        store.setHex("#7B1FA2", for: .jma)
        XCTAssertEqual(store.hex(for: .jma), "#7B1FA2")
        store.resetColors()
        XCTAssertEqual(store.hex(for: .jma), SourceKey.jma.defaultHex)
    }

    func test_既定と同じ色なら覚えない() {
        let store = SettingsStore(backend: 置き場所の差し替え())
        store.setHex(SourceKey.yahoo.defaultHex.lowercased(), for: .yahoo)
        XCTAssertTrue(store.data.colors.isEmpty)
    }

    func test_iCloudが使えるかどうかが分かる() {
        let backend = 置き場所の差し替え()
        backend.isCloud = false
        let store = SettingsStore(backend: backend)
        XCTAssertFalse(store.usingCloud)
    }
}
