import AppKit

/// The Manage Locations window (F5): a table of locations. Drag to reorder;
/// double-click or Return to rename in place; − or Delete to delete. The window
/// only presents. Privileged work goes back to the status item controller through
/// `Actions`, which then calls `refresh()`.
final class ManageLocationsWindowController: NSWindowController,
    NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

    struct Actions {
        /// Locations in display order.
        var locations: () -> [NetworkLocation]
        var create: () -> Void
        var rename: (_ id: String, _ name: String) -> Void
        var delete: (_ id: String) -> Void
        var reorder: (_ ids: [String]) -> Void
    }

    private enum Column {
        static let current = NSUserInterfaceItemIdentifier("current")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let services = NSUserInterfaceItemIdentifier("services")
    }
    private static let rowType = NSPasteboard.PasteboardType("com.breed007.switchback.location-row")

    private let actions: Actions
    private var rows: [NetworkLocation] = []
    private let table = LocationsTableView()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let hint: String
    /// The name a row had when inline editing began; nil when not editing.
    private var nameBeforeEdit: String?
    /// A refresh that arrived mid-rename (a DHCP renewal, say); applied when the
    /// edit ends, so background events don't throw away what the user is typing.
    private var refreshPending = false

    init(actions: Actions) {
        self.actions = actions
        hint = HelperPolicy.isAdmin(uid: getuid())
            ? "Drag to reorder. Double-click a name to rename it."
            : "Changes need an administrator\u{2019}s name and password."
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Manage Locations"
        window.minSize = NSSize(width: 420, height: 220)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildLayout(in: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("ManageLocationsWindowController is built in code") }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(table)
    }

    /// Reload from the controller, keeping the selection on the same location.
    func refresh() {
        guard nameBeforeEdit == nil else { refreshPending = true; return }
        refreshPending = false
        let selectedID = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        rows = actions.locations()
        table.reloadData()
        if let selectedID, let row = rows.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
        }
        updateButtons()
        showStatus(nil)
    }

    // MARK: - Layout

    private func buildLayout(in window: NSWindow) {
        table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.rowHeight = 24
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(renameSelected)
        table.onReturn = { [weak self] in self?.renameSelected() }
        table.onDelete = { [weak self] in self?.deleteSelected() }
        table.registerForDraggedTypes([Self.rowType])
        table.setAccessibilityLabel("Locations")

        for (id, title, width) in [(Column.current, "", 24.0), (Column.name, "Name", 220.0),
                                   (Column.services, "Services", 220.0)] {
            let column = NSTableColumn(identifier: id)
            column.title = title
            column.width = width
            column.minWidth = id == Column.current ? 24 : 100
            if id == Column.current { column.maxWidth = 24 }
            table.addTableColumn(column)
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        configure(addButton, image: NSImage.addTemplateName, label: "New Location", action: #selector(addLocation))
        configure(removeButton, image: NSImage.removeTemplateName, label: "Delete Location", action: #selector(deleteSelected))
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.setAccessibilityLabel("Status")

        let content = NSView()
        window.contentView = content
        for view in [scroll, addButton, removeButton, status] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            addButton.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -1),
            addButton.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 22),
            removeButton.topAnchor.constraint(equalTo: addButton.topAnchor),
            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: -1),
            removeButton.widthAnchor.constraint(equalTo: addButton.widthAnchor),
            removeButton.heightAnchor.constraint(equalTo: addButton.heightAnchor),

            status.leadingAnchor.constraint(equalTo: removeButton.trailingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            status.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            addButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    private func configure(_ button: NSButton, image: NSImage.Name, label: String, action: Selector) {
        button.bezelStyle = .smallSquare
        button.image = NSImage(named: image)
        button.setAccessibilityLabel(label)
        button.toolTip = label
        button.target = self
        button.action = action
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, rows.indices.contains(row) else { return nil }
        let location = rows[row]
        switch id {
        case Column.current:
            let cell = imageCell()
            cell.imageView?.image = location.isCurrent
                ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Current location") : nil
            return cell
        case Column.name:
            let cell = textCell(Column.name)
            cell.textField?.stringValue = location.name
            cell.textField?.isEditable = LocationRules.renameBlockReason(for: location) == nil
            cell.textField?.delegate = self
            cell.setAccessibilityLabel(accessibilityDescription(of: location))
            return cell
        default:
            let cell = textCell(Column.services)
            cell.textField?.stringValue = servicesSummary(of: location)
            cell.textField?.textColor = .secondaryLabelColor
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        showStatus(nil)
    }

    private func servicesSummary(of location: NetworkLocation) -> String {
        switch location.serviceCount {
        case 0: return "No services"
        case 1: return "1 service" + (location.primaryService.map { " \u{00B7} \($0)" } ?? "")
        default: return "\(location.serviceCount) services" + (location.primaryService.map { " \u{00B7} \($0) first" } ?? "")
        }
    }

    /// Spoken by VoiceOver, so no "·" separators (read aloud as "middle dot").
    private func accessibilityDescription(of location: NetworkLocation) -> String {
        var parts = [location.name]
        if location.isCurrent { parts.append("current location") }
        switch location.serviceCount {
        case 0: parts.append("no services")
        case 1: parts.append("1 service")
        default: parts.append("\(location.serviceCount) services")
        }
        if let primary = location.primaryService { parts.append("first is \(primary)") }
        return parts.joined(separator: ", ")
    }

    private func textCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        if let reused = table.makeView(withIdentifier: id, owner: self) as? NSTableCellView { return reused }
        let cell = NSTableCellView()
        cell.identifier = id
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func imageCell() -> NSTableCellView {
        if let reused = table.makeView(withIdentifier: Column.current, owner: self) as? NSTableCellView { return reused }
        let cell = NSTableCellView()
        cell.identifier = Column.current
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(image)
        cell.imageView = image
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: - Reorder

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === table else { return [] }
        if dropOperation == .on { tableView.setDropRow(row, dropOperation: .above) }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let text = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.rowType),
              let from = Int(text) else { return false }
        actions.reorder(LocationOrder.moving(rows, from: from, to: row))
        refresh()
        return true
    }

    // MARK: - Rename in place

    @objc private func renameSelected() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard rows.indices.contains(row) else { return }
        if let reason = LocationRules.renameBlockReason(for: rows[row]) {
            showStatus(reason, isError: true)
            NSSound.beep()
            return
        }
        guard let nameColumn = table.tableColumns.firstIndex(where: { $0.identifier == Column.name }) else { return }
        nameBeforeEdit = rows[row].name
        table.editColumn(nameColumn, row: row, with: nil, select: true)
    }

    private func validation(for field: NSTextField) -> LocationNameValidator.Result? {
        let row = table.row(for: field)
        guard rows.indices.contains(row) else { return nil }
        let existing = rows.map { LocationNameValidator.Existing(id: $0.id, name: $0.name) }
        return LocationNameValidator.validate(field.stringValue, existing: existing, excludingID: rows[row].id)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let result = validation(for: field) else { return }
        let feedback = result.feedback
        showStatus(feedback?.text, isError: feedback?.blocksConfirm ?? false)
    }

    /// Keep editing while the name can't be saved, instead of committing it.
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        guard nameBeforeEdit != nil, let field = control as? NSTextField,
              let result = validation(for: field) else { return true }
        if !result.isValid { NSSound.beep() }
        return result.isValid
    }

    /// Escape cancels the rename and restores the old name.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), let original = nameBeforeEdit else { return false }
        nameBeforeEdit = nil
        control.abortEditing()
        (control as? NSTextField)?.stringValue = original
        showStatus(nil)
        window?.makeFirstResponder(table)
        if refreshPending { refresh() }
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let original = nameBeforeEdit else { return }
        nameBeforeEdit = nil
        let row = table.row(for: field)
        guard rows.indices.contains(row) else { return }
        showStatus(nil)
        window?.makeFirstResponder(table)
        // A rename to the same name would ask for a password for nothing.
        if LocationNameValidator.clean(field.stringValue) != original {
            actions.rename(rows[row].id, field.stringValue)
        } else if refreshPending {
            refresh()
        }
    }

    // MARK: - Add and delete

    @objc private func addLocation() {
        actions.create()
    }

    @objc private func deleteSelected() {
        guard rows.indices.contains(table.selectedRow), let window else { return }
        let location = rows[table.selectedRow]
        if let reason = LocationRules.deleteBlockReason(for: location, among: rows) {
            showStatus(reason, isError: true)
            NSSound.beep()
            return
        }
        let confirm = NSAlert()
        confirm.messageText = "Delete \u{201C}\(location.name)\u{201D}?"
        confirm.informativeText = "This removes the location and its saved network settings. This can\u{2019}t be undone."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Delete")
        confirm.addButton(withTitle: "Cancel")
        confirm.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.actions.delete(location.id) }
        }
    }

    private func updateButtons() {
        guard rows.indices.contains(table.selectedRow) else {
            removeButton.isEnabled = false
            removeButton.toolTip = "Select a location to delete"
            return
        }
        let reason = LocationRules.deleteBlockReason(for: rows[table.selectedRow], among: rows)
        removeButton.isEnabled = reason == nil
        removeButton.toolTip = reason ?? "Delete Location"
    }

    private func showStatus(_ text: String?, isError: Bool = false) {
        let message = (text?.isEmpty == false) ? text! : hint
        status.stringValue = message
        status.textColor = (isError && text?.isEmpty == false) ? .systemRed : .secondaryLabelColor
    }
}

/// Return renames and Delete deletes the selected row; everything else is standard.
final class LocationsTableView: NSTableView {
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:  onReturn?()   // Return, keypad Enter
        case 51, 117: onDelete?()   // Delete, forward delete
        default:      super.keyDown(with: event)
        }
    }
}

#if DEBUG
extension ManageLocationsWindowController {
    /// Each row as the table shows it, with the delete button's state when that row
    /// is selected (debug flag `--manage`).
    func debugDump() -> [String] {
        refresh()
        return (0..<numberOfRows(in: table)).map { row in
            table.selectRowIndexes([row], byExtendingSelection: false)
            func cell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView? {
                table.tableColumns.first { $0.identifier == id }
                    .flatMap { tableView(table, viewFor: $0, row: row) as? NSTableCellView }
            }
            let name = cell(Column.name)
            let check = cell(Column.current)?.imageView?.image == nil ? " " : "✓"
            return "\(check) \(name?.textField?.stringValue ?? "?") | \(cell(Column.services)?.textField?.stringValue ?? "?")"
                + " | rename: \(name?.textField?.isEditable == true ? "yes" : "no")"
                + " | delete: \(removeButton.isEnabled ? "enabled" : "disabled (\(removeButton.toolTip ?? ""))")"
                + " | VoiceOver: \"\(name?.accessibilityLabel() ?? "")\""
        } + ["status line: \"\(status.stringValue)\""]
    }
}
#endif
