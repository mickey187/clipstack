import ClipStackCore
import Foundation

/// The handful of user choices that outlive a launch.
///
/// Reads fall back to the default on anything unrecognised, so a hand-edited or
/// downgraded defaults entry can never leave the popup with no size at all.
enum Preferences {
    private static let panelSizeKey = "panelSize"

    static var panelSize: PanelSize {
        get {
            UserDefaults.standard.string(forKey: panelSizeKey)
                .flatMap(PanelSize.init(rawValue:)) ?? .default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: panelSizeKey)
        }
    }
}
