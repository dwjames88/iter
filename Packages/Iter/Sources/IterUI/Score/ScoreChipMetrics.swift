import Foundation
import Synchronization
#if canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
#endif

/// Text measurement for the chip's fixed widths, cross-platform (AppKit or UIKit font, same API shape).
enum ScoreChipMeasure {
    private static func weight(_ w: FontWeightName) -> PlatformFont.Weight {
        switch w {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }

    static func width(_ string: String, size: CGFloat, weight w: FontWeightName) -> CGFloat {
        let font = PlatformFont.monospacedDigitSystemFont(ofSize: size, weight: weight(w))
        return NSAttributedString(string: string, attributes: [.font: font]).size().width
    }
}

/// A small thread-safe cache for measured widths.
final class WidthCache<Key: Hashable & Sendable>: Sendable {
    private let storage = Mutex<[Key: CGFloat]>([:])
    func value(for key: Key, _ compute: () -> CGFloat) -> CGFloat {
        if let hit = storage.withLock({ $0[key] }) { return hit }
        let v = compute()
        storage.withLock { $0[key] = v }
        return v
    }
}
