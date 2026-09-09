//  結露チェック
//
//  表面温度が露点を下回ると結露します。窓ガラスや壁の表面温度を入れて確かめます。

import SwiftUI
import WeatherCore

struct DewCheckSection: View {
    @Environment(WeatherStore.self) private var weather
    @State private var surface: Double = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("結露チェック")
            Text("表面温度が露点を下回ると結露します。窓ガラスや壁の表面温度を入れて確かめられます。")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("表面温度")
                    .font(.subheadline)
                Text("\(Format.number(surface, 1)) ℃")
                    .font(.subheadline.bold()).monospacedDigit()
                Spacer()
            }
            Slider(value: $surface, in: -10...40, step: 0.5)

            Text(verdict)
                .font(.subheadline)
                .foregroundStyle(color)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var dewPoint: Double? { weather.average.dp }

    private var verdict: String {
        guard let dp = dewPoint else { return "露点を計算できる値がまだありません。" }
        let diff = surface - dp
        if diff < 0 {
            return "結露します。露点 \(Format.number(dp, 1))℃ に対して表面温度が "
                + "\(Format.number(-diff, 1))℃ 低い状態です。"
        }
        if diff < 3 {
            return "結露しやすい状態です。露点 \(Format.number(dp, 1))℃ との差は "
                + "\(Format.number(diff, 1))℃ しかありません。"
        }
        return "結露しません。露点 \(Format.number(dp, 1))℃ に対して "
            + "\(Format.number(diff, 1))℃ の余裕があります。"
    }

    private var color: Color {
        guard let dp = dewPoint else { return .secondary }
        let diff = surface - dp
        if diff < 0 { return .red }
        if diff < 3 { return .orange }
        return .green
    }
}
