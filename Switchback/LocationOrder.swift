import Foundation

/// The user's own location order, set by dragging in the Manage Locations window.
/// Stored by set ID, because IDs are stable and names aren't.
struct LocationOrder {
    static let defaultsKey = "LocationOrder"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ids: [String] { defaults.stringArray(forKey: Self.defaultsKey) ?? [] }

    func save(_ ids: [String]) {
        defaults.set(ids, forKey: Self.defaultsKey)
    }

    /// Ordered IDs first, in saved order; everything else after them, alphabetically.
    /// So a location created after the last reorder lands at the end, and an empty
    /// order is plain alphabetical.
    static func apply(_ order: [String], to locations: [NetworkLocation]) -> [NetworkLocation] {
        var rank: [String: Int] = [:]
        for (index, id) in order.enumerated() where rank[id] == nil { rank[id] = index }
        let ordered = locations.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
        let rest = locations.filter { rank[$0.id] == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return ordered + rest
    }

    /// The full ID order after moving the row at `from` so it lands before the row
    /// at `to` (table-drop semantics: `to` may equal the count, meaning the end).
    static func moving(_ displayed: [NetworkLocation], from: Int, to: Int) -> [String] {
        var ids = displayed.map(\.id)
        guard ids.indices.contains(from), (0...ids.count).contains(to) else { return ids }
        let moved = ids.remove(at: from)
        ids.insert(moved, at: to > from ? to - 1 : to)
        return ids
    }
}
