import Foundation

/// Location-name rules, shared by the backend (the authoritative check), the name
/// dialog, and the Manage Locations window. Pure functions, unit-tested directly.
///
/// Two forms matter:
/// - the **stored name** (`clean`): what the user typed, minus things that break a
///   menu item, with emoji and accents intact;
/// - the **skeleton** (`skeleton`): a comparison key, so two names that look the
///   same (full-width letters, invisible characters, case) can't both exist.
enum LocationNameValidator {
    static let maxLength = 128

    /// The macOS default location. Switchback protects it and won't let another
    /// location take its name.
    static let reservedName = "Automatic"

    enum Problem: Equatable {
        case empty
        case tooLong
        case reserved
        case duplicate(of: String)
    }

    enum Warning: Equatable {
        /// A word mixes Latin with another script's lookalike letters and then
        /// matches an existing name, e.g. "Оffice" with a Cyrillic "О".
        case lookalike(of: String, script: String)
        /// A word mixes Latin with Cyrillic or Greek letters.
        case mixedScript(script: String)
    }

    struct Result: Equatable {
        /// The name that would be stored.
        let name: String
        let problem: Problem?
        let warning: Warning?
        var isValid: Bool { problem == nil }
    }

    struct Existing: Equatable {
        let id: String
        let name: String
    }

    /// Check `raw` against the current locations. Pass `excludingID` when renaming,
    /// so a location doesn't collide with itself (a case-only rename is allowed).
    static func validate(_ raw: String, existing: [Existing], excludingID: String? = nil) -> Result {
        let name = clean(raw)
        let key = skeleton(name)
        let others = existing.filter { $0.id != excludingID }

        let problem: Problem?
        if key.isEmpty {
            problem = .empty
        } else if name.count > maxLength {
            problem = .tooLong
        } else if isReserved(name) {
            problem = .reserved
        } else if let clash = others.first(where: { skeleton($0.name) == key }) {
            problem = .duplicate(of: clash.name)
        } else {
            problem = nil
        }
        return Result(name: name, problem: problem, warning: scriptWarning(for: name, among: others))
    }

    /// True when `name` is the reserved default-location name, however it's written.
    static func isReserved(_ name: String) -> Bool {
        skeleton(name) == skeleton(reservedName)
    }

    // MARK: - Stored form

    /// Control characters (newlines, tabs) become spaces. Invisible format
    /// characters are removed, except the zero-width joiner and non-joiner, which
    /// emoji sequences and some scripts need. Whitespace runs, including no-break
    /// spaces, collapse to one space. The result is trimmed and NFC-normalized.
    static func clean(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control:
                scalars.append(" ")
            case .format:
                if scalar == zeroWidthJoiner || scalar == zeroWidthNonJoiner {
                    scalars.append(scalar)
                }
            default:
                scalars.append(scalar)
            }
        }
        return collapseWhitespace(String(scalars)).precomposedStringWithCanonicalMapping
    }

    // MARK: - Comparison key

    /// NFKC (folds full-width and compatibility forms), every format character
    /// removed (joiners included), whitespace collapsed, case folded. Accents stay
    /// significant: "Résumé" and "Resume" are different names.
    static func skeleton(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.precomposedStringWithCompatibilityMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .format:  continue
            case .control: scalars.append(" ")
            default:       scalars.append(scalar)
            }
        }
        return collapseWhitespace(String(scalars)).folding(options: .caseInsensitive, locale: nil)
    }

    // MARK: - Lookalike letters

    /// Warn (never block) when a word mixes Latin with Cyrillic or Greek letters.
    /// If swapping the common lookalikes for Latin makes it match an existing
    /// location, name that location.
    private static func scriptWarning(for name: String, among others: [Existing]) -> Warning? {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard let mixed = words.lazy.compactMap({ mixedScript(in: $0) }).first else { return nil }

        let latinized = skeleton(String(String.UnicodeScalarView(name.unicodeScalars.map {
            latinLookalikes[$0] ?? $0
        })))
        if let match = others.first(where: { skeleton($0.name) == latinized }) {
            return .lookalike(of: match.name, script: mixed)
        }
        return .mixedScript(script: mixed)
    }

    /// The non-Latin script mixed into a Latin word, if any.
    private static func mixedScript(in word: Substring) -> String? {
        var latin = false, cyrillic = false, greek = false
        for scalar in word.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: latin = true
            case 0x400...0x52F:                                           cyrillic = true
            case 0x370...0x3FF, 0x1F00...0x1FFF:                          greek = true
            default: break
            }
        }
        guard latin else { return nil }
        if cyrillic { return "Cyrillic" }
        if greek { return "Greek" }
        return nil
    }

    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"
    private static let zeroWidthNonJoiner: Unicode.Scalar = "\u{200C}"

    /// Cyrillic and Greek letters that are commonly mistaken for Latin ones.
    private static let latinLookalikes: [Unicode.Scalar: Unicode.Scalar] = {
        let pairs: [(String, String)] = [
            // Cyrillic
            ("а", "a"), ("е", "e"), ("о", "o"), ("р", "p"), ("с", "c"), ("у", "y"),
            ("х", "x"), ("і", "i"), ("ј", "j"), ("ѕ", "s"), ("һ", "h"), ("ԁ", "d"),
            ("А", "A"), ("В", "B"), ("Е", "E"), ("К", "K"), ("М", "M"), ("Н", "H"),
            ("О", "O"), ("Р", "P"), ("С", "C"), ("Т", "T"), ("Х", "X"), ("І", "I"),
            ("Ј", "J"), ("Ѕ", "S"),
            // Greek
            ("ο", "o"), ("ν", "v"), ("ρ", "p"), ("Α", "A"), ("Β", "B"), ("Ε", "E"),
            ("Ζ", "Z"), ("Η", "H"), ("Ι", "I"), ("Κ", "K"), ("Μ", "M"), ("Ν", "N"),
            ("Ο", "O"), ("Ρ", "P"), ("Τ", "T"), ("Υ", "Y"), ("Χ", "X"),
        ]
        var map: [Unicode.Scalar: Unicode.Scalar] = [:]
        for (from, to) in pairs { map[from.unicodeScalars.first!] = to.unicodeScalars.first! }
        return map
    }()

    private static func collapseWhitespace(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
