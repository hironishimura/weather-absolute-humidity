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
                 + "ECMWFに降水確率はありません。"
                 + "雨量は気象庁が前1時間の実測、ほかは予報です。"
                 + "Yahoo!天気は3時間ごとの合計で出しているため、1時間あたりに割って並べています。"
                 + "小さな丸が実際の値のある時刻です。降っていない区間は線を引いていません。"
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
                    // 雨量が全部0のときは「提供元がない」ではありません
                    Text(weather.hasAnyValue(for: field, days: days)
                         ? "この期間、雨の予報はありません。"
                         : "この項目を出せる提供元がありません。")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    GeometryReader { geo in
                        let usable = max(geo.size.width - 60, 60)
                        let tick = AxisTicks.hours(span: ChartWindow.span(days: days),
                                                   usable: usable)
                        chart(series: series, marks: marks(from: from, to: to, usable: usable),
                              from: from, to: to, now: now, tick: tick)
                    }
                    .frame(height: field == .temp ? 230 : 160)
                }
            }
            .padding(.vertical, 2)
        }

        /// 気温のグラフにだけ、日ごとの最高・最低を重ねます。
        /// せまくて字が重なる日は落とします（Web版と同じ考え方）。
        private func marks(from: Date, to: Date, usable: CGFloat) -> [DayMark] {
            guard field == .temp else { return [] }
            let span = ChartWindow.span(days: days)
            return weather.dailyMarks(days: days).filter { m in
                let hours = m.visibleHours(from: from, to: to)
                return hours / span * Double(usable) >= 40
            }
        }

        @ViewBuilder
        private func chart(series: [ChartSeries], marks: [DayMark],
                           from: Date, to: Date, now: Date,
                           tick: AxisTicks.Hour) -> some View {
            let jma = Color(hex: settings.hex(for: .jma))
            Chart {
                ForEach(series) { s in
                    ForEach(s.points) { p in
                        // 提供元の分け方は foregroundStyle(by:) に任せます。
                        // 色を直に指定すると、線は分かれても全部同じ色になります。
                        LineMark(x: .value("時刻", p.time),
                                 y: .value(field.title, p.value),
                                 series: .value("線", s.id))
                            .foregroundStyle(by: .value("提供元", s.key.short))
                            .interpolationMethod(Self.method(field.interpolation))
                            .symbol(.circle)
                            .symbolSize(field.showsPoints ? 18 : 0)
                    }
                }
                RuleMark(x: .value("いま", now))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary)

                // 気象庁の日ごとの最高・最低。線ではなく印なので、
                // 提供元ごとの色分けとは別に気象庁の色で描きます。
                ForEach(marks) { m in
                    let mid = m.mid(from: from, to: to)
                    let wide = m.visibleHours(from: from, to: to)
                        / ChartWindow.span(days: days) * 100
                    if let hi = m.high, let lo = m.low {
                        RuleMark(x: .value("日", mid),
                                 yStart: .value("最低", lo),
                                 yEnd: .value("最高", hi))
                            .foregroundStyle(jma.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    if let hi = m.high {
                        PointMark(x: .value("日", mid), y: .value("最高", hi))
                            .symbol { Circle().stroke(jma, lineWidth: 2).frame(width: 8, height: 8) }
                            .annotation(position: .trailing, spacing: 3) {
                                Text("\(Int(hi.rounded()))°")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                    }
                    if let lo = m.low {
                        PointMark(x: .value("日", mid), y: .value("最低", lo))
                            .symbol { Circle().stroke(jma, lineWidth: 2).frame(width: 8, height: 8) }
                            .annotation(position: .trailing, spacing: 3) {
                                Text("\(Int(lo.rounded()))°")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                    }
                    if !m.weather.isEmpty, wide >= 12, let hi = m.high {
                        PointMark(x: .value("日", mid), y: .value("最高", hi))
                            .symbolSize(0)
                            .annotation(position: .top, spacing: 2) {
                                Text(m.weather)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                    }
                }
            }
            .chartLegend(.hidden)
            // 出せない提供元があっても色がずれないよう、対応をすべて書き出します
            .chartForegroundStyleScale(
                domain: SourceKey.allCases.map(\.short),
                range: SourceKey.allCases.map { Color(hex: settings.hex(for: $0)) })
            .chartXScale(domain: from...to)
            .chartYScale(domain: yDomain(series, marks: marks))
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

        private static func method(_ shape: LineShape) -> InterpolationMethod {
            switch shape {
            case .smooth: return .catmullRom
            case .straight: return .linear
            case .stepEnd: return .stepEnd
            }
        }

        private func yDomain(_ series: [ChartSeries], marks: [DayMark]) -> ClosedRange<Double> {
            if let fixed = field.fixedRange { return fixed }
            // 日ごとの最高・最低も軸に入れます。入れないと丸印が枠から出ます
            var values = series.flatMap { $0.points.map(\.value) }
            values += marks.compactMap(\.high)
            values += marks.compactMap(\.low)
            guard let lo = values.min(), let hi = values.max() else { return 0...1 }
            if field.startsAtZero {
                // 雨量は0から。降っていない日でも軸がつぶれないよう、少し余裕を持たせます。
                let scale = AxisTicks.nice(min: 0, max: Swift.max(hi, 1))
                return 0...scale.max
            }
            let scale = AxisTicks.nice(min: lo, max: hi)
            // 天気の字を上に出すぶん、気温だけ少し上に余白を取ります
            guard !marks.isEmpty else { return scale.min...scale.max }
            let head = (scale.max - scale.min) * 0.18
            return scale.min...(scale.max + head)
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
