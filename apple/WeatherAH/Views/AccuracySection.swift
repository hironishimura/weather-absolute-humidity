//  降水確率の当たり具合

import SwiftUI
import WeatherCore

struct AccuracySection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("降水確率の当たり具合")
                Spacer()
                Text(lead).font(.caption).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                ForEach(SourceKey.allCases) { key in
                    Card(key: key,
                         color: Color(hex: settings.hex(for: key)),
                         score: weather.accuracy?.scores[key])
                }
            }

            if let acc = weather.accuracy, !acc.periods.isEmpty {
                DisclosureGroup("期間ごとの内訳") {
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            ForEach(acc.periods.reversed()) { p in
                                Divider()
                                row(p, acc)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.footnote)
            }

            Text(note)
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var lead: String {
        guard let acc = weather.accuracy, !acc.missing else { return "この地点の集計はまだありません。" }
        var s = acc.placeLabel
        if let st = acc.station { s += "（実際の雨量はアメダス\(st)観測所）" }
        if let t = acc.updatedAt { s += "／集計 \(Format.dateTime(t))" }
        return s
    }

    private var note: String {
        let acc = weather.accuracy
        let mm = Format.number(acc?.rainMM ?? 1, 0)
        let say = Format.number(acc?.sayRain ?? 50, 0)
        return "7日前〜4日前は1日ごと、直近3日は半日ごと（午前・午後）に数えています。"
            + "実際に降ったかどうかは気象庁アメダスの雨量が\(mm)mm以上かどうか、"
            + "予報は降水確率\(say)%以上を「降る予報」とみなしています。"
            + "ブライアスコアは確率そのもののずれで、0に近いほど的確です。"
            + "過去の予報はあとから取り寄せられないため、取り込みを続けるほど数がそろいます。"
    }

    private func row(_ p: AccuracyPeriod, _ acc: AccuracyResult) -> some View {
        HStack(spacing: 0) {
            Text(p.label)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text("\(Format.number(p.mm, 1)) mm")
                .font(.caption.monospacedDigit())
                .foregroundStyle(p.rain ? Color.accentColor : .primary)
                .fontWeight(p.rain ? .bold : .regular)
                .frame(width: 80, alignment: .leading)
            ForEach(SourceKey.allCases) { key in
                Group {
                    if let pop = p.pops[key], let hit = acc.isHit(p, key) {
                        Text("\(Format.number(pop, 0))% \(hit ? "○" : "×")")
                            .foregroundStyle(hit ? Color.green : Color.orange)
                            .fontWeight(hit ? .bold : .regular)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .font(.caption.monospacedDigit())
                .frame(width: 90, alignment: .leading)
            }
        }
        .padding(.vertical, 7)
    }

    private struct Card: View {
        var key: SourceKey
        var color: Color
        var score: AccuracyScore?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(key.name).font(.caption.bold())
                if let score {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(Format.number(score.rate, 1))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%").font(.caption2).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max(score.rate, 0), 100), total: 100)
                        .tint(color)
                    Text("\(score.n)期間のうち\(score.hit)回あたり／ブライアスコア \(Format.number(score.brier, 3))")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("まだ数えられません").font(.subheadline).foregroundStyle(.secondary)
                    Text("終わった期間の予報がまだ足りません。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .top) {
                Rectangle().fill(color).frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }
}
