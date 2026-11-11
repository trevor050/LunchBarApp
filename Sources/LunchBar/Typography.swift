import AppKit
import SwiftUI

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Multiplier from the app's Text Size setting. macOS doesn't apply Dynamic
    /// Type to third-party apps, so the popover scales its text styles itself.
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let style: NSFont.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        let base = NSFont.preferredFont(forTextStyle: style).pointSize
        let defaultWeight: Font.Weight = style == .headline ? .semibold : .regular
        content.font(.system(size: (base * scale).rounded(), weight: weight ?? defaultWeight))
    }
}

extension View {
    /// A system text style, scaled by the user's Text Size setting.
    func scaledFont(_ style: NSFont.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFont(style: style, weight: weight))
    }
}
