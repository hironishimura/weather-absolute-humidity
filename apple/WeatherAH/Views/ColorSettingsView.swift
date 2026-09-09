//  提供元ごとの色を変える
//
//  変えた色は iCloud に入るので、iPhone で変えれば Mac にも出ます。

import SwiftUI
import WeatherCore

struct ColorSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("提供元の色") {
                    ForEach(SourceKey.allCases) { key in
                        ColorPicker(selection: Binding(
                            get: { Color(hex: settings.hex(for: key)) },
                            set: { settings.setHex($0.hexString, for: key) }
                        ), supportsOpacity: false) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(key.name)
                                Text(settings.hex(for: key))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button("元の色に戻す") { settings.resetColors() }
                } footer: {
                    Text("グラフ・提供元カード・1週間の表・当たり具合、すべてに使われます。")
                        .font(.caption2)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("色を変える")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
    }
}
