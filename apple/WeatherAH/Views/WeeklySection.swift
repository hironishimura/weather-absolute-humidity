//  1週間の予報（提供元ごと）

import SwiftUI
import WeatherCore

struct WeeklySection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("1週間の予報（提供元ごと）")
                Spacer()
                if !weather.officeName.isEmpty {
                    Text("\(weather.officeName)の予報です。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            let days = weather.weeklyDays
            if days.isEmpty {
                Text("予報を取得できませんでした。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        header
                        ForEach(days, id: \.self) { day in
                            Divider()
                            row(day)
                        }
                    }
                }
                .scrollIndicators(.visible)
            }

            Text("気温は日ごとの最高／最低です。気象庁は発表値、気象庁MSM/GSMは1時間ごとの予報からまとめた計算値です。"
                 + "降水確率は日ごとの発表値があればその値、なければ時間帯ごとの値のうちその日のいちばん高いものです。"
                 + "気象庁MSM/GSMの降水確率だけは、気象庁のモデルに含まれていないため Open-Meteo の総合予報の値です。")
                .font(.caption2).foregroundStyle(.secondary)

            if !weather.overview.isEmpty {
                DisclosureGroup("気象概況（気象庁）") {
                    Text(weather.overview)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.footnote)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("日付").font(.caption.bold()).frame(width: 90, alignment: .leading)
            ForEach(SourceKey.allCases) { key in
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: settings.hex(for: key))).frame(width: 8, height: 8)
                    Text(key.name).font(.caption.bold()).lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
    }

    private func row(_ day: String) -> some View {
        let today = JST.dayKey(Date())
        return HStack(alignment: .top, spacing: 0) {
            Text(dateLabel(day))
                .font(.caption.monospacedDigit())
                .foregroundStyle(day == today ? Color.accentColor : .secondary)
                .fontWeight(day == today ? .bold : .regular)
                .frame(width: 90, alignment: .leading)
            ForEach(SourceKey.allCases) { key in
                cell(weather.weekly[key]?[day])
                    .frame(width: 150, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
    }

    private func dateLabel(_ key: String) -> String {
        guard let d = JST.parseISO(key + "T00:00:00+09:00") else { return key }
        return Format.date(d)
    }

    @ViewBuilder
    private func cell(_ day: DailyForecast?) -> some View {
        if let day {
            VStack(alignment: .leading, spacing: 2) {
                if !day.weather.isEmpty {
                    Text(day.weather).font(.caption).lineLimit(2)
                }
                if day.max != nil || day.min != nil {
                    HStack(spacing: 3) {
                        Text(Format.number(day.max, 1)).foregroundStyle(.orange).bold()
                        Text("/").foregroundStyle(.secondary)
                        Text(Format.number(day.min, 1)).foregroundStyle(.blue)
                        Text("℃").font(.caption2).foregroundStyle(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                }
                if let pop = day.pop {
                    Text("降水 \(Format.number(pop, 0))%")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let lo = day.ahMin, let hi = day.ahMax {
                    Text("絶対湿度 \(Format.number(lo, 1))〜\(Format.number(hi, 1)) g/kg(DA)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("—").font(.caption).foregroundStyle(.tertiary)
        }
    }
}
