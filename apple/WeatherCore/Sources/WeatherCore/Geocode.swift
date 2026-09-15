//  地名から緯度経度を引く
//
//  まず国土地理院の住所検索にあたります。日本の町名まで引けるためです。
//  返ってこない／見つからないときだけ Open-Meteo の地名検索に回ります。
//  こちらは市までしか引けませんが、控えとしては十分です。
//
//  Web版（docs/assets/app.js）と同じ順番・同じ絞り込みにしてあります。

import Foundation

/// 地名検索の当たり
public struct GeoCandidate: Identifiable, Equatable, Sendable {
    public var title: String
    public var lat: Double
    public var lon: Double

    public var id: String { "\(title)|\(lat)|\(lon)" }

    public init(title: String, lat: Double, lon: Double) {
        self.title = title
        self.lat = lat
        self.lon = lon
    }
}

public struct Geocoder: Sendable {
    private let fetcher: Fetching

    public init(fetcher: Fetching = URLSessionFetcher(timeout: 15)) {
        self.fetcher = fetcher
    }

    /// いちどに出す数。多すぎると選べません
    public static let limit = 8

    /// 空白を落とします。全角の空白も。
    public static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func search(_ query: String) async -> [GeoCandidate] {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }

        // 国土地理院は応答が遅いことがあるので、いちどだけ取り直します
        for _ in 0..<2 {
            if let hits = try? await gsi(q), !hits.isEmpty { return hits }
        }
        return (try? await openMeteo(q)) ?? []
    }

    // MARK: - 国土地理院

    struct GSIFeature: Decodable {
        struct Geometry: Decodable { var coordinates: [Double]? }
        struct Props: Decodable { var title: String? }
        var geometry: Geometry?
        var properties: Props?
    }

    func gsiURL(_ q: String) -> URL {
        Endpoints.url("\(Self.gsiBase)?q=\(Self.escape(q))")
    }

    static let gsiBase = "https://msearch.gsi.go.jp/address-search/AddressSearch"

    private func gsi(_ q: String) async throws -> [GeoCandidate] {
        let data = try await fetcher.data(from: gsiURL(q))
        let list = try JSONDecoder().decode([GSIFeature].self, from: data)
        return Self.pick(list, query: q)
    }

    /// 問い合わせた字が住所に入っているものだけ残します。
    /// 残さないと「東京駅」で北海道の地名が並びます（実際にそうなりました）。
    static func pick(_ list: [GSIFeature], query: String) -> [GeoCandidate] {
        var out: [GeoCandidate] = []
        for f in list {
            guard let title = f.properties?.title,
                  let c = f.geometry?.coordinates, c.count >= 2 else { continue }
            guard normalize(title).contains(query) else { continue }
            out.append(GeoCandidate(title: title, lat: c[1], lon: c[0]))
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Open-Meteo（控え）

    private struct OMResponse: Decodable {
        struct Hit: Decodable {
            var name: String?
            var latitude: Double?
            var longitude: Double?
            var admin1: String?
            var admin2: String?
        }
        var results: [Hit]?
    }

    func openMeteoURL(_ q: String) -> URL {
        Endpoints.url("\(Self.openMeteoBase)?name=\(Self.escape(q))"
                      + "&count=\(Self.limit)&language=ja&format=json")
    }

    static let openMeteoBase = "https://geocoding-api.open-meteo.com/v1/search"

    private func openMeteo(_ q: String) async throws -> [GeoCandidate] {
        let data = try await fetcher.data(from: openMeteoURL(q))
        let res = try JSONDecoder().decode(OMResponse.self, from: data)
        return (res.results ?? []).compactMap { hit in
            guard let name = hit.name, let lat = hit.latitude, let lon = hit.longitude else {
                return nil
            }
            let head = hit.admin1 ?? ""
            return GeoCandidate(title: head.isEmpty ? name : head + name, lat: lat, lon: lon)
        }
    }

    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }
}
