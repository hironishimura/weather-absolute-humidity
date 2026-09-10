//  いまの実況（大きな数字）と、その下の細かい値

import SwiftUI
import WeatherCore

struct NowTiles: View {
    @Environment(WeatherStore.self) private var weather

    private var columns: [GridItem] {
        [.cards(minimum: 190)]
    }

    var body: some View {
        let avg = weather.average
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 14) {
                Tile(title: "気温", value: Format.number(avg.temp, 1), unit: "℃",
                     caption: caption("temp", avg))
                Tile(title: "相対湿度", value: Format.number(avg.rh, 0), unit: "%",
                     caption: caption("rh", avg))
                Tile(title: "絶対湿度", value: Format.number(avg.mr, 1), unit: "g/kg(DA)",
                     caption: caption("mr", avg), highlighted: true)
            }
            Text("大きな数字は、取れている提供元の平均です。実況と予報が混ざることがあります。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func caption(_ field: String, _ avg: AverageNow) -> String {
        let n = avg.counts[field] ?? 0
        guard n > 0 else { return "取得できていません" }
        return "\(n)社の平均"
    }
}

private struct Tile: View {
    var title: String
    var value: String
    var unit: String
    var caption: String
    var highlighted: Bool = false

    var body: some View {
        CardBox(accent: highlighted ? Color.accentColor : nil) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 露点や気圧など、細かい値
struct SubValues: View {
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        let avg = weather.average
        let jma = weather.nows[.jma]
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)],
                  spacing: 12) {
            Item("絶対湿度（容積）", Format.number(avg.vh, 1), "g/m³")
            Item("露点温度", Format.number(avg.dp, 1), "℃")
            Item("気圧（現地）", Format.number(avg.pressure, 1), "hPa")
            Item("風", Wind.text(direction: jma?.windDirection, speed: jma?.wind), "")
            Item("降水量（前1時間）", Format.number(jma?.precipitation1h, 1), "mm")
            Item("不快指数", Format.number(avg.di, 1), "")
        }
    }

    private struct Item: View {
        var title: String
        var value: String
        var unit: String
        init(_ title: String, _ value: String, _ unit: String) {
            self.title = title
            self.value = value
            self.unit = unit
        }
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.headline).monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
