//  登録地点・選んでいる地点・提供元の色
//
//  iCloud（NSUbiquitousKeyValueStore）に置くので、
//  iPhone・iPad・Mac のあいだで同じ内容になります。
//  iCloud が使えないときは、この端末の中だけに保存して動き続けます。

import Foundation
import Observation

/// 保存するときのキー。置き場所の側からも使うので、クラスの外に出しています。
public let settingsStorageKey = "dc-weather-settings"

/// 保存する中身。まるごと JSON にして置きます。
public struct SettingsData: Codable, Equatable, Sendable {
    public var places: [Place]
    public var activeID: String
    /// 提供元ごとの色（変えたものだけ）。値は #RRGGBB。
    public var colors: [String: String]
    /// 端末どうしで新しいほうを採るための目印
    public var updatedAt: Date

    public init(places: [Place] = [Place.宇都宮],
                activeID: String = Place.宇都宮.id,
                colors: [String: String] = [:],
                updatedAt: Date = Date()) {
        self.places = places
        self.activeID = activeID
        self.colors = colors
        self.updatedAt = updatedAt
    }

    public static let empty = SettingsData()

    /// 両方に中身があるときは、新しいほうを採ります。
    public static func newer(_ a: SettingsData?, _ b: SettingsData?) -> SettingsData? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (let x?, let y?): return x.updatedAt >= y.updatedAt ? x : y
        }
    }

    public func place(id: String) -> Place? { places.first { $0.id == id } }

    public var active: Place {
        place(id: activeID) ?? places.first ?? Place.宇都宮
    }
}

/// 置き場所。確認のときに差し替えられるようにしてあります。
public protocol SettingsBackend: AnyObject {
    var isCloud: Bool { get }
    func read() -> Data?
    func write(_ data: Data)
    /// 他の端末で変わったときに呼ばれます
    var onExternalChange: (() -> Void)? { get set }
}

public final class UserDefaultsBackend: SettingsBackend {
    private let defaults: UserDefaults
    private let key: String
    public var isCloud: Bool { false }
    public var onExternalChange: (() -> Void)?

    public init(defaults: UserDefaults = .standard, key: String = settingsStorageKey) {
        self.defaults = defaults
        self.key = key
    }
    public func read() -> Data? { defaults.data(forKey: key) }
    public func write(_ data: Data) { defaults.set(data, forKey: key) }
}

/// iCloud のキーバリューストア。1MBまで置けるので、地点の一覧には十分です。
public final class CloudBackend: SettingsBackend {
    private let store = NSUbiquitousKeyValueStore.default
    private let local = UserDefaults.standard
    private let key: String
    private var observer: NSObjectProtocol?

    public var onExternalChange: (() -> Void)?

    /// iCloud にサインインしていて、権限もあるとき true
    public var isCloud: Bool { FileManager.default.ubiquityIdentityToken != nil }

    public init(key: String = settingsStorageKey) {
        self.key = key
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] _ in
            self?.onExternalChange?()
        }
        store.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func read() -> Data? {
        // iCloud にあるものと、この端末に残したものの新しいほうを使います
        let cloud = store.data(forKey: key)
        let localData = local.data(forKey: key)
        let decoder = JSONDecoder()
        let a = cloud.flatMap { try? decoder.decode(SettingsData.self, from: $0) }
        let b = localData.flatMap { try? decoder.decode(SettingsData.self, from: $0) }
        guard let winner = SettingsData.newer(a, b) else { return cloud ?? localData }
        return try? JSONEncoder().encode(winner)
    }

    public func write(_ data: Data) {
        local.set(data, forKey: key)      // iCloud が止まっていても残るように
        store.set(data, forKey: key)
        store.synchronize()
    }
}

@MainActor
@Observable
public final class SettingsStore {
    public private(set) var data: SettingsData
    /// iCloud で同期できているか
    public private(set) var usingCloud: Bool

    private let backend: SettingsBackend

    public init(backend: SettingsBackend) {
        self.backend = backend
        self.usingCloud = backend.isCloud
        if let raw = backend.read(), let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            self.data = decoded.places.isEmpty ? .empty : decoded
        } else {
            self.data = .empty
        }
        backend.onExternalChange = {
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    public static func makeDefault() -> SettingsStore {
        SettingsStore(backend: CloudBackend())
    }

    /// 他の端末で変わったときに読み直す
    public func reload() {
        usingCloud = backend.isCloud
        guard let raw = backend.read(),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw),
              !decoded.places.isEmpty else { return }
        if decoded != data { data = decoded }
    }

    private func save(_ next: SettingsData) {
        var v = next
        v.updatedAt = Date()
        data = v
        if let raw = try? JSONEncoder().encode(v) { backend.write(raw) }
    }

    // MARK: - 地点

    public var places: [Place] { data.places }
    public var active: Place { data.active }

    public func select(_ id: String) {
        guard data.activeID != id, data.place(id: id) != nil else { return }
        var v = data
        v.activeID = id
        save(v)
    }

    public func add(_ place: Place) {
        var v = data
        v.places.append(place)
        v.activeID = place.id
        save(v)
    }

    public func update(_ place: Place) {
        var v = data
        guard let i = v.places.firstIndex(where: { $0.id == place.id }) else { return }
        v.places[i] = place
        save(v)
    }

    public func remove(id: String) {
        var v = data
        guard v.places.count > 1 else { return }   // 最後のひとつは残します
        v.places.removeAll { $0.id == id }
        if v.activeID == id { v.activeID = v.places.first?.id ?? "" }
        save(v)
    }

    public func move(from source: IndexSet, to destination: Int) {
        var v = data
        let picked = source.sorted().compactMap { v.places.indices.contains($0) ? v.places[$0] : nil }
        guard !picked.isEmpty else { return }
        // 抜いた数だけ行き先がずれるので、先に数えておきます
        let before = source.filter { $0 < destination }.count
        for i in source.sorted(by: >) where v.places.indices.contains(i) {
            v.places.remove(at: i)
        }
        let at = min(max(destination - before, 0), v.places.count)
        v.places.insert(contentsOf: picked, at: at)
        save(v)
    }

    // MARK: - 色

    public func hex(for key: SourceKey) -> String {
        data.colors[key.rawValue] ?? key.defaultHex
    }

    public func setHex(_ hex: String, for key: SourceKey) {
        var v = data
        if hex.caseInsensitiveCompare(key.defaultHex) == .orderedSame {
            v.colors.removeValue(forKey: key.rawValue)
        } else {
            v.colors[key.rawValue] = hex
        }
        save(v)
    }

    public func resetColors() {
        var v = data
        v.colors = [:]
        save(v)
    }
}
