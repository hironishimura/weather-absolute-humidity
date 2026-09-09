//  色と #RRGGBB のやりとり
//
//  提供元の色は iCloud に文字で置くので、行き来できるようにしています。

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else {
            self = .gray
            return
        }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
