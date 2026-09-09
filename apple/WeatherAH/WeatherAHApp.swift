//  気温・湿度・絶対湿度
//
//  iPhone・iPad・Mac で同じ中身が動きます。
//  登録した地点と提供元の色は iCloud で行き来します。

import SwiftUI
import WeatherCore

@main
struct WeatherAHApp: App {
    @State private var settings = SettingsStore.makeDefault()
    @State private var weather = WeatherStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(weather)
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 820)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("更新") {
                    Task { await weather.refresh(place: settings.active) }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }
}
