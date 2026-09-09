//  地点の一覧と編集
//
//  ここで足した地点は iCloud を通って、他の端末にも出てきます。

import SwiftUI
import CoreLocation
import WeatherCore

struct PlaceListView: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var editing: Place?
    @Binding var addingNew: Bool

    var body: some View {
        @Bindable var settings = settings
        List(selection: Binding(
            get: { settings.active.id },
            set: { settings.select($0 ?? settings.active.id) }
        )) {
            Section {
                ForEach(settings.places) { place in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.label.isEmpty ? "名前のない地点" : place.label)
                            Text(String(format: "%.4f, %.4f", place.lat, place.lon))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            editing = place
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    .tag(place.id)
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
    }
}

struct PlaceEditor: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Place
    @State private var locating = false
    @State private var locateError: String?
    @State private var locator = Locator()

    private let isNew: Bool

    init(place: Place, isNew: Bool) {
        _draft = State(initialValue: place)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("宇都宮 事務所", text: $draft.label)
                }
                Section("場所") {
                    LabeledContent("緯度") {
                        TextField("36.5551", value: $draft.lat, format: .number.precision(.fractionLength(0...5)))
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                    }
                    LabeledContent("経度") {
                        TextField("139.8828", value: $draft.lon, format: .number.precision(.fractionLength(0...5)))
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
                    Text("緯度・経度は地図アプリで長押しすると出てきます。"
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
