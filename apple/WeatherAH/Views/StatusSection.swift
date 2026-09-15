//  取得状況と、絶対湿度についての説明

import SwiftUI
import WeatherCore

struct StatusSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("取得状況")
            ForEach(weather.statusOrdered) { line in
                HStack(alignment: .top, spacing: 10) {
                    Text(label(line.state))
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(tint(line.state).opacity(0.14), in: Capsule())
                        .foregroundStyle(tint(line.state))
                        .frame(width: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name).font(.caption.bold())
                        Text(line.message).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        // 提供元の説明もここに出します（カードを短くするため）
                        if let about = SourceKey(rawValue: line.key)?.about {
                            Text(about).font(.caption2).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Divider().padding(.vertical, 4)

            HStack(spacing: 6) {
                Image(systemName: settings.usingCloud ? "icloud.fill" : "iphone")
                Text(settings.usingCloud
                     ? "登録した地点と色は iCloud で iPhone・iPad・Mac に行き来します。"
                     : "iCloud が使えないため、この端末の中だけに保存しています。")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("絶対湿度とは").font(.caption.bold())
                Text("乾き空気1kgあたりに含まれる水蒸気の重さ［g/kg(DA)］です。空気線図と同じ量で、"
                     + "暖めても冷やしても値が変わらないため、換気量や結露を考えるときに扱いやすい指標です。"
                     + "同じ提供元・同じ時刻の気温と相対湿度から計算しています。"
                     + "空気1m³あたりの重さ［g/m³］（容積絶対湿度）も「そのほかの値」に出しています。")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("表示する値は目安です。設計や気密測定の判断に使うときは実測値と照らし合わせてください。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private func label(_ s: StatusLine.State) -> String {
        switch s {
        case .ok: return "取得"
        case .failed: return "失敗"
        case .notFetched: return "未取得"
        }
    }

    private func tint(_ s: StatusLine.State) -> Color {
        switch s {
        case .ok: return .green
        case .failed: return .red
        case .notFetched: return .secondary
        }
    }
}
