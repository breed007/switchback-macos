import AppKit

/// The New Location and Rename Location dialog (F4). It checks the name on every
/// keystroke against the current locations: OK stays disabled while the name is
/// invalid, and a line under the field says why. Lookalike warnings show without
/// disabling OK.
final class NameDialog: NSObject, NSTextFieldDelegate {
    private let alert = NSAlert()
    private let field = NSTextField()
    private let note = NSTextField(wrappingLabelWithString: "")
    private let existing: [LocationNameValidator.Existing]
    private let excludingID: String?

    /// - Parameters:
    ///   - initial: text to start with (the current name when renaming, or the
    ///     user's text when reopening after the backend rejected it).
    ///   - error: a message to show from that rejection.
    init(title: String, message: String, initial: String,
         existing: [LocationNameValidator.Existing], excludingID: String? = nil, error: String? = nil) {
        self.existing = existing
        self.excludingID = excludingID
        super.init()

        alert.icon = NSApp.applicationIconImage
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        field.stringValue = initial
        field.placeholderString = "Location name"
        field.delegate = self
        field.setAccessibilityLabel("Location name")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.setAccessibilityLabel("Name check")

        let stack = NSStackView(views: [field, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 52)
        field.widthAnchor.constraint(equalToConstant: 280).isActive = true
        note.widthAnchor.constraint(equalToConstant: 280).isActive = true
        alert.accessoryView = stack
        alert.window.initialFirstResponder = field

        update()
        if let error {
            note.stringValue = error
            note.textColor = .systemRed
        }
    }

    /// Show the dialog. Returns the text to save, or nil if canceled.
    func run() -> String? {
        // A menu-bar agent isn't active by default; without this the dialog can
        // open unfocused or behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func controlTextDidChange(_ notification: Notification) {
        update()
    }

    private func update() {
        let result = LocationNameValidator.validate(field.stringValue, existing: existing, excludingID: excludingID)
        let feedback = result.feedback
        note.stringValue = feedback?.text ?? ""
        note.textColor = (feedback?.blocksConfirm ?? false) ? .systemRed : .secondaryLabelColor
        alert.buttons.first?.isEnabled = result.isValid
    }
}
