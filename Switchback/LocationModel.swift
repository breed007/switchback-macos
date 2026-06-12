import Foundation

/// A macOS network location (an `SCNetworkSet`).
struct NetworkLocation: Identifiable, Equatable {
    let id: String          // SCNetworkSet setID
    let name: String
    var isCurrent: Bool

    /// The default "Automatic" location is special — it carries every detected
    /// service and is the system fallback, so Switchback won't rename or delete it.
    var isProtected: Bool {
        name.compare("Automatic", options: .caseInsensitive) == .orderedSame
    }
}
