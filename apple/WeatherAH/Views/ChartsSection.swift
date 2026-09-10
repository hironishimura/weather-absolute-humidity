//  時系列グラフ（各社を重ねて表示）
//
//  横軸の時刻の刻みは WeatherCore の AxisTicks が決めます。
//  Web版と同じ考え方で、せまいときは自動で粗くなります。

import SwiftUI
import Charts
import WeatherCore

struct ChartsSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WeatherStore.self) private var weather
    @Binding var showColors: Bool

    @State private var days = 2

    private let ranges = [1, 2, 3, 7]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("時系列（各社を重ねて表示）")
                Spacer()
                Button {
                    showColors = true
                } label: {
                    Label("色を変える", systemImage: "paintpalette")
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }

            Picker("表示範囲", selection: $days) {
                ForEach(ranges, id: \.self) { d in
                    Text("\(d)日").tag(d)
                }
            }
            .pickerStyle(.segmented)

            Legend()

            ForEach(ChartField.allCases) { field in
                FieldChart(field: field, days: days)
            }

            Text("実況は直近1時間ぶん、あとはこれからの予報です。"
                 + "降水確率は刻みが提供元で違うため、階段の幅が変わります"
                 + "（気象庁6時間・Yahoo!天気6時間・ウェザーニュース午前午後・数値予報1時間）。"
                 + "雨量は棒で出しています。気象庁は前1時間の実測、ほかは予報です。"
                 + "Yahoo!天気は3時間ごとの合計で出しているため、1時間あたりに割って並べています。"
                 + "絶対湿度は重量絶対湿度［g/kg(DA)］です。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private struct Legend: View {
        @Environment(SettingsStore.self) private var settings
        var body: some View {
            FlowRow(spacing: 12) {
                ForEach(SourceKey.allCases) { key in
                    HStack(spacing: 5) {
                        Capsule()
                            .fill(Color(hex: settings.hex(for: key)))
                            .frame(width: 16, height: 3)
                        Text(key.short + (key == .jma ? "" : "（予報）"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private struct FieldChart: View {
        @Environment(SettingsStore.self) private var settings
        @Environment(WeatherStore.self) private var weather
        var field: ChartField
        var days: Int

        var body: some View {
            let series = weather.series(for: field, days: days)
            let now = Date()
            let from = now.addingTimeInterval(-ChartWindow.pastSeconds)
            let to = now.addingTimeInterval(TimeInterval(days * 24 * 3600))

            VStack(alignment: .leading, spacing: 6) {
                Text("\(field.title)（\(field.unit)）")
                    .font(.subheadline.weight(.semibold))

                if series.isEmpty {
                    Text("この項目を出せる提供元がありません。")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    GeometryReader { geo in
                        let tick = AxisTicks.hours(span: ChartWindow.span(days: days),
                                                   usable: max(geo.size.width - 60, 60))
                        chart(series: series, from: from, to: to, now: now, tick: tick)
                    }
                    .frame(height: field == .temp ? 210 : 160)
                }
            }
            .padding(.vertical, 2)
        }

        @ViewBuilder
        private func chart(series: [ChartSeries], from: Date, to: Date, now: Date,
                           tick: AxisTicks.Hour) -> some View {
            Chart {
                ForEach(series) { s in
                    ForEach(s.points) { p in
                        // 提供元の分け方は foregroundStyle(by:) に任せます。
                        // 色を直に指定すると、線は分かれても全部同じ色になります。
                        if field.drawsBars {
                            // 雨量は棒。提供元ごとに横へずらして並べます。
                            BarMark(x: .value("時刻", p.time),
                                    y: .value(field.title, p.value))
                                .foregroundStyle(by: .value("提供元", s.key.short))
                                .position(by: .value("提供元", s.key.short))
                        } else {
                            LineMark(x: .value("時刻", p.time),
                                     y: .value(field.title, p.value),
                                     series: .value("提供元", s.key.short))
                                .foregroundStyle(by: .value("提供元", s.key.short))
                                .interpolationMethod(field == .pop ? .stepEnd : .catmullRom)
                        }
                    }
                }
                RuleMark(x: .value("いま", now))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary)
            }
            .chartLegend(.hidden)
            // 出せない提供元があっても色がずれないよう、対応をすべて書き出します
            .chartForegroundStyleScale(
                domain: SourceKey.allCases.map(\.short),
                range: SourceKey.allCases.map { Color(hex: settings.hex(for: $0)) })
            .chartXScale(domain: from...to)
            .chartYScale(domain: yDomain(series))
            .chartXAxis {
                // 日の変わり目には日付を出します（Web版と同じ）
                AxisMarks(values: AxisTicks.dayStarts(from: from, to: to)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary)
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(Format.shortDate(d))
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
                // 時刻の目盛り。0時には日付が出ているので、そこは重ねません。
                AxisMarks(values: AxisTicks.hourMarks(from: from, to: to, step: tick.step)) { value in
                    if (value.as(Date.self).map { JST.parts($0).hour ?? 0 } ?? 0) != 0 {
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                let hour = JST.parts(d).hour ?? 0
                                Text(tick.withUnit ? "\(hour)時" : "\(hour)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(Format.number(v, field.digits)).font(.caption2)
                        }
                    }
                }
            }
        }

        private func yDomain(_ series: [ChartSeries]) -> ClosedRange<Double> {
            if let fixed = field.fixedRange { return fixed }
            let values = series.flatMap { $0.points.map(\.value) }
            guard let lo = values.min(), let hi = values.max() else { return 0...1 }
            if field.startsAtZero {
                // 雨量は0から。降っていない日でも軸がつぶれないよう、少し余裕を持たせます。
                let scale = AxisTicks.nice(min: 0, max: Swift.max(hi, 1))
                return 0...scale.max
            }
            let scale = AxisTicks.nice(min: lo, max: hi)
            return scale.min...scale.max
        }
    }
}

/// 折り返す横並び。凡例に使います。
struct FlowRow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: spacing)],
                      alignment: .leading, spacing: 6) { content }
        }
    }
}
