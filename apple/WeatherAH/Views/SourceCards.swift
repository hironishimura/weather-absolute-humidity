//  提供元ごとの値

import SwiftUI
import WeatherCore

struct SourceCards: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("提供元ごとの値")
            LazyVGrid(columns: [.cards(minimum: 240)], spacing: 14) {
                ForEach(SourceKey.allCases) { key in
                    Card(key: key,
                         color: Color(hex: settings.hex(for: key)),
                         now: weather.nows[key])
                }
            }
        }
    }

    private struct Card: View {
        var key: SourceKey
        var color: Color
        var now: NowValue?

        var body: some View {
            CardBox(accent: color) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(key.name).font(.subheadline.bold())
                        Spacer()
                        badge
                    }
                    if let now {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            value(Format.number(now.values.temp, 1), "℃")
                            value(Format.number(now.values.rh, 0), "%")
                            value(Format.number(now.values.mr, 1), "g/kg(DA)")
                        }
                        if let t = now.time {
                            Text("\(Format.dateTime(t)) の値")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("取得できていません")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                }
            }
        }

        private var badge: some View {
            let text: String
            let tint: Color
            if now == nil { text = "未取得"; tint = .secondary }
            else if now!.isForecast { text = "予報値"; tint = .accentColor }
            else { text = "実況値"; tint = .green }
            return Text(text)
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(tint.opacity(0.14), in: Capsule())
                .foregroundStyle(tint)
        }

        private func value(_ v: String, _ unit: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(v).font(.title3.weight(.semibold)).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
