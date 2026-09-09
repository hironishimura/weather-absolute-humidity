//  全体の入れもの
//
//  iPad と Mac は「左に地点・右に天気」の2画面。
//  iPhone は画面がせまいので、天気を最初に出して、
//  地点は左上のボタンから開くようにしています。

import SwiftUI
import WeatherCore

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WeatherStore.self) private var weather

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var columns = NavigationSplitViewVisibility.automatic
    @State private var editing: Place?
    @State private var addingNew = false
    @State private var showColors = false
    @State private var showPlaces = false

    var body: some View {
        content
            .task(id: settings.active.id) {
                await weather.refresh(place: settings.active)
            }
            .sheet(item: $editing) { place in
                PlaceEditor(place: place, isNew: false)
            }
            .sheet(isPresented: $addingNew) {
                PlaceEditor(place: Place(label: "", lat: 35.6812, lon: 139.7671), isNew: true)
            }
            .sheet(isPresented: $showColors) {
                ColorSettingsView()
            }
            .sheet(isPresented: $showPlaces) {
                NavigationStack {
                    PlaceListView(editing: $editing, addingNew: $addingNew,
                                  onSelect: { showPlaces = false })
                        .navigationTitle("地点")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("閉じる") { showPlaces = false }
                            }
                        }
                }
            }
    }

    /// せまい画面（iPhone）は1枚、広い画面（iPad・Mac）は2画面
    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if sizeClass == .compact {
            NavigationStack {
                DetailView(showColors: $showColors, showPlaces: $showPlaces, compact: true)
            }
        } else {
            splitView
        }
        #else
        splitView
        #endif
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columns) {
            PlaceListView(editing: $editing, addingNew: $addingNew, onSelect: nil)
                .navigationTitle("地点")
        } detail: {
            DetailView(showColors: $showColors, showPlaces: $showPlaces, compact: false)
        }
    }
}

private struct DetailView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WeatherStore.self) private var weather
    @Binding var showColors: Bool
    @Binding var showPlaces: Bool
    var compact: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PlaceHeader()
                NowTiles()
                SubValues()
                SourceCards()
                ChartsSection(showColors: $showColors)
                WeeklySection()
                AccuracySection()
                DewCheckSection()
                StatusSection()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(settings.active.label.isEmpty ? "気温・湿度・絶対湿度" : settings.active.label)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            if compact {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showPlaces = true
                    } label: {
                        Label("地点", systemImage: "list.bullet")
                    }
                }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await weather.refresh(place: settings.active) }
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
                .disabled(weather.isLoading)
            }
        }
        .refreshable {
            await weather.refresh(place: settings.active)
        }
        .overlay(alignment: .top) {
            if weather.isLoading {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 6)
            }
        }
    }
}

/// 地点名と、いつの値かを出す
private struct PlaceHeader: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settings.active.label.isEmpty ? "名前のない地点" : settings.active.label)
                .font(.title2.bold())
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let st = weather.station {
                Text("気象庁の観測地点：\(st.name)（指定地点から約 \(Format.km(st.km))・標高 \(Format.number(st.alt, 0)) m）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        let p = settings.active
        var s = String(format: "%.4f° N, %.4f° E", p.lat, p.lon)
        if let t = weather.updatedAt { s += "　・　\(Format.dateTime(t)) 取得" }
        return s
    }
}
