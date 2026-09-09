//  カードの見た目をひとつにまとめたもの
//
//  上の色帯は、角丸のあとから重ねると両端が丸みからはみ出して
//  「出っ張って」見えます。帯もカードの中身として積んでから、
//  まとめて角丸で切り抜くことで、Web版の border-top と同じ見え方にします。

import SwiftUI

struct CardBox<Content: View>: View {
    /// 上の色帯。nil のときは場所だけ空けます（並んだカードの高さをそろえるため）
    var accent: Color?
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(accent ?? .clear)
                .frame(height: 3)
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 同じ行のカードと高さをそろえます
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension GridItem {
    /// カードを並べるときの区切り。上ぞろえにして、背の低いカードが
    /// 上下中央に寄ってずれるのを防ぎます。
    static func cards(minimum: CGFloat, spacing: CGFloat = 14) -> GridItem {
        GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .top)
    }
}
