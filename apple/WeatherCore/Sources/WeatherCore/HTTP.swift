//  取得まわり
//
//  取りに行く先は気象庁・Open-Meteo・GitHub Pages（取り込みファイル）の3つだけです。

import Foundation

public enum FetchError: LocalizedError, Equatable {
    case http(Int)
    case badBody
    case noValue(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP \(code)"
        case .badBody: return "中身を読めませんでした"
        case .noValue(let why): return why
        }
    }
}

/// 取りに行く相手。差し替えられるようにしておくと、確認のときに助かります。
public protocol Fetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionFetcher: Fetching {
    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.http(http.statusCode)
        }
        return data
    }
}

extension Fetching {
    /// JSON をそのまま辞書・配列として受け取る（気象庁の予報は形が入り組んでいるため）
    func json(_ url: URL) async throws -> Any {
        let data = try await data(from: url)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    func decode<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let data = try await data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func text(_ url: URL) async throws -> String {
        let data = try await data(from: url)
        guard let s = String(data: data, encoding: .utf8) else { throw FetchError.badBody }
        return s
    }
}

public enum Endpoints {
    public static let jma = "https://www.jma.go.jp/bosai"
    public static let openMeteo = "https://api.open-meteo.com/v1/forecast"
    /// GitHub Actions が書き出している取り込みファイルの置き場所
    public static let snapshotBase = "https://hironishimura.github.io/weather-absolute-humidity/data"

    public static func url(_ s: String) -> URL {
        URL(string: s) ?? URL(string: "https://www.jma.go.jp/")!
    }
}

/// JSON の中から値を取り出すための小さな道具
enum J {
    static func dict(_ any: Any?) -> [String: Any]? { any as? [String: Any] }
    static func array(_ any: Any?) -> [Any]? { any as? [Any] }
    static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }
    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d.isFinite ? d : nil }
        if let n = any as? NSNumber { return n.doubleValue.isFinite ? n.doubleValue : nil }
        if let s = any as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
    /// アメダスの値は [値, 品質情報] の形で入っています
    static func amedas(_ row: [String: Any]?, _ key: String) -> Double? {
        guard let pair = row?[key] as? [Any], let first = pair.first else { return nil }
        return number(first)
    }
    static func at(_ list: [Any]?, _ i: Int) -> Any? {
        guard let list, i >= 0, i < list.count else { return nil }
        return list[i]
    }
}
