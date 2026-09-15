//  地点の一覧と編集
//
//  ここで足した地点は iCloud を通って、他の端末にも出てきます。

import SwiftUI
import CoreLocation
import WeatherCore

struct PlaceListView: View {
    @Environment(SettingsStore.self) private var settings
    /// iPhone では選んだら閉じます
    var onSelect: (() -> Void)?

    // 編集画面はこの一覧が自分で開きます。
    // iPhone では一覧じたいがシートの中に出るので、外側から開こうとすると
    // 「シートの上にシート」になり、何も出てきません。
    @State private var editing: Place?
    @State private var addingNew = false

    var body: some View {
        List {
            Section {
                ForEach(settings.places) { place in
                    HStack {
                        // 行そのものが「この地点にする」ボタン
                        Button {
                            settings.select(place.id)
                            onSelect?()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: place.id == settings.active.id
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(place.id == settings.active.id
                                                     ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.label.isEmpty ? "名前のない地点" : place.label)
                                        .foregroundStyle(.primary)
                                    Text(String(format: "%.4f, %.4f", place.lat, place.lon))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)

                        Button {
                            editing = place
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for i in offsets where settings.places.indices.contains(i) {
                        settings.remove(id: settings.places[i].id)
                    }
                }
                .onMove { from, to in
                    settings.move(from: from, to: to)
                }
            } footer: {
                Label(settings.usingCloud ? "iCloud で同期しています" : "この端末の中だけに保存しています",
                      systemImage: settings.usingCloud ? "icloud.fill" : "iphone")
                    .font(.caption2)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addingNew = true
                } label: {
                    Label("地点を追加", systemImage: "plus")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            #endif
        }
        .sheet(item: $editing) { place in
            PlaceEditor(place: place, isNew: false)
        }
        .sheet(isPresented: $addingNew) {
            PlaceEditor(place: Place(label: "", lat: 35.6812, lon: 139.7671), isNew: true)
        }
    }
}

struct PlaceEditor: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Place
    @State private var locating = false
    @State private var locateError: String?
    @State private var locator = Locator()

    @State private var searching = false
    @State private var candidates: [GeoCandidate] = []
    @State private var geoMessage: String?

    private let isNew: Bool

    init(place: Place, isNew: Bool) {
        _draft = State(initialValue: place)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("地名") {
                    // 第1引数は「見出し」です。Mac では箱の左に並ぶので、
                    // 長い例を渡すと箱が押しつぶされます。例は prompt に渡します。
                    TextField("地名", text: $draft.label,
                              prompt: Text("栃木県宇都宮市平出町"))
                        .labelsHidden()
                        .onSubmit { Task { await lookUp() } }
                    Button {
                        Task { await lookUp() }
                    } label: {
                        Label(searching ? "探しています…" : "地名から緯度経度を入れる",
                              systemImage: "magnifyingglass")
                    }
                    .disabled(searching)

                    if let geoMessage {
                        Text(geoMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    // 候補は選ばせます。黙って先頭を入れると、
                    // 「東京駅」で北海道の座標が静かに入るような事故が起きます。
                    ForEach(candidates) { c in
                        Button {
                            fill(with: c)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title)
                                Text(String(format: "%.4f° N, %.4f° E", c.lat, c.lon))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("場所") {
                    LabeledContent("緯度") {
                        TextField("緯度", value: $draft.lat,
                                  format: .number.precision(.fractionLength(0...5)),
                                  prompt: Text("36.5551"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                    }
                    LabeledContent("経度") {
                        TextField("経度", value: $draft.lon,
                                  format: .number.precision(.fractionLength(0...5)),
                                  prompt: Text("139.8828"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                    }
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        Label(locating ? "現在地を探しています…" : "現在地を入れる",
                              systemImage: "location")
                    }
                    .disabled(locating)
                    if let locateError {
                        Text(locateError).font(.caption).foregroundStyle(.red)
                    }
                }
                Section {
                    Text("地名は住所のほうがよく見つかります（駅や施設の名前でも引けることがあります）。"
                         + "出どころは国土地理院の住所検索です。"
                         + "緯度・経度は地図アプリで長押しすると出てきます。"
                         + "気象庁と数値予報は、どこを入れてもそのまま動きます。"
                         + "Yahoo!天気とウェザーニュースは取り込み地点から40km以内のときだけ出ます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !isNew && settings.places.count > 1 {
                    Section {
                        Button("この地点を削除", role: .destructive) {
                            settings.remove(id: draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "地点を追加" : "地点を編集")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var v = draft
                        if v.label.trimmingCharacters(in: .whitespaces).isEmpty {
                            v.label = String(format: "%.3f, %.3f", v.lat, v.lon)
                        }
                        if isNew { settings.add(v) } else { settings.update(v) }
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    /// 地名から緯度経度を引きます。
    /// 押されたときだけ問い合わせます（1文字ごとに投げると相手に負担がかかります）。
    private func lookUp() async {
        let q = draft.label
        guard !searching else { return }
        guard !Geocoder.normalize(q).isEmpty else {
            candidates = []
            geoMessage = "地名を入れてください"
            return
        }
        searching = true
        candidates = []
        geoMessage = "探しています…"
        defer { searching = false }

        let hits = await Geocoder().search(q)
        if hits.isEmpty {
            geoMessage = "見つかりませんでした。住所で入れるか、緯度・経度を直接入れてください"
            return
        }
        if hits.count == 1 {
            fill(with: hits[0])
            return
        }
        candidates = hits
        geoMessage = "\(hits.count)件見つかりました。選んでください"
    }

    private func fill(with c: GeoCandidate) {
        draft.label = c.title
        draft.lat = (c.lat * 10000).rounded() / 10000
        draft.lon = (c.lon * 10000).rounded() / 10000
        // 場所が変わったので、予報区は選び直させます
        draft.office = nil
        candidates = []
        geoMessage = "入れました：\(c.title)"
    }

    private func useCurrentLocation() async {
        locating = true
        locateError = nil
        defer { locating = false }
        do {
            let c = try await locator.current()
            draft.lat = (c.latitude * 10000).rounded() / 10000
            draft.lon = (c.longitude * 10000).rounded() / 10000
        } catch {
            locateError = "現在地を取得できませんでした（設定でこのアプリに位置情報を許可してください）"
        }
    }
}

/// 現在地をひとつだけ取る小さな入れもの
@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocationCoordinate2D, Error>?

    enum Failure: Error { case denied, unavailable }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current() async throws -> CLLocationCoordinate2D {
        manager.requestWhenInUseAuthorization()
        return try await withCheckedThrowingContinuation { c in
            waiting = c
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            guard let c = self.waiting else { return }
            self.waiting = nil
            if let coordinate { c.resume(returning: coordinate) }
            else { c.resume(throwing: Failure.unavailable) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let c = self.waiting else { return }
            self.waiting = nil
            c.resume(throwing: error)
        }
    }
}
