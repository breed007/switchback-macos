import Foundation

/// Why a location can't be renamed or deleted right now. The backend enforces the
/// same rules; these give the UI the reason up front instead of after a password.
enum LocationRules {
    static func renameBlockReason(for location: NetworkLocation) -> String? {
        location.isProtected
            ? "\u{201C}\(location.name)\u{201D} is the macOS default location and can\u{2019}t be renamed."
            : nil
    }

    static func deleteBlockReason(for location: NetworkLocation, among all: [NetworkLocation]) -> String? {
        if location.isProtected {
            return "\u{201C}\(location.name)\u{201D} is the macOS default location and can\u{2019}t be deleted."
        }
        if all.count <= 1 { return "You can\u{2019}t delete your only location." }
        if location.isCurrent { return "Switch to another location before deleting this one." }
        return nil
    }
}

/// The one line shown under a name field.
struct NameFeedback: Equatable {
    let text: String
    /// True when the name can't be saved (OK stays disabled).
    let blocksConfirm: Bool
}

extension LocationNameValidator.Result {
    /// Feedback for the name dialog and the inline rename. Empty names block
    /// without a message, so a fresh field doesn't nag.
    var feedback: NameFeedback? {
        if let problem {
            switch problem {
            case .empty:
                return NameFeedback(text: "", blocksConfirm: true)
            case .tooLong:
                return NameFeedback(text: "That\u{2019}s longer than \(LocationNameValidator.maxLength) characters.",
                                    blocksConfirm: true)
            case .reserved:
                return NameFeedback(text: "\u{201C}\(LocationNameValidator.reservedName)\u{201D} is reserved for the macOS default location.",
                                    blocksConfirm: true)
            case .duplicate(let other):
                return NameFeedback(text: "\u{201C}\(other)\u{201D} already uses that name.", blocksConfirm: true)
            }
        }
        switch warning {
        case .lookalike(let other, let script):
            return NameFeedback(text: "Looks like \u{201C}\(other)\u{201D} but uses \(script) letters.", blocksConfirm: false)
        case .mixedScript(let script):
            return NameFeedback(text: "Mixes Latin and \(script) letters.", blocksConfirm: false)
        case nil:
            return nil
        }
    }
}
