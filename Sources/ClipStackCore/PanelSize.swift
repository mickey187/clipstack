import Foundation

/// How large the popup panel is drawn — a fixed set of steps rather than a free
/// resize, so every choice stays a layout we have actually looked at.
///
/// One `scale` drives both the panel frame and the type inside it. Making the
/// panel bigger without growing the text would only show more rows at the same
/// squint, which is the opposite of what this setting is for.
public enum PanelSize: String, CaseIterable, Codable, Sendable {
    case small
    case medium
    case large

    /// Medium, not small: the original 340×440 reads cramped on a dense display,
    /// and a new install should not start at the size people go looking for a
    /// setting to escape.
    public static let `default` = PanelSize.medium

    public var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Multiplier applied to every hardcoded dimension in the popup.
    public var scale: CGFloat {
        switch self {
        case .small: return 1.0
        case .medium: return 1.18
        case .large: return 1.38
        }
    }

    /// The 1.0 baseline — the panel as it shipped before this setting existed.
    private static let baseWidth: CGFloat = 340
    private static let baseHeight: CGFloat = 440

    public var width: CGFloat { (Self.baseWidth * scale).rounded() }
    public var height: CGFloat { (Self.baseHeight * scale).rounded() }

    /// Scales a baseline point size (font, padding, icon box) to this step.
    ///
    /// Rounded to a whole point: half-point type and half-point padding are
    /// where fuzzy text comes from.
    public func scaled(_ points: CGFloat) -> CGFloat {
        (points * scale).rounded()
    }
}
