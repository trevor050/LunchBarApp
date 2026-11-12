import Foundation

/// Display-only casing for provider text.
///
/// Rutgers FoodPro sends every item and station name in capitals ("BBQ PORK SANDWICH",
/// "LUNCH TAKEOUT"); Nutrislice sends normal capitalization. `DisplayText.normalized`
/// title-cases text that arrives entirely in capitals and returns anything else
/// untouched, so a correctly cased Nutrislice name can never be altered.
///
/// It only ever changes letter case. Providers apply it when they build a `MenuItem` or
/// `MenuSection`, and keep the string they received in `MenuItem.rawName` /
/// `MenuSection.rawTitle` (see `providerName` / `providerTitle`), so ids, recipe lookups
/// and the ranking tie-break still use the provider's own text.
public enum DisplayText {
    /// Returns a title-cased copy when `text` has letters and none of them is lowercase.
    /// Otherwise returns `text` unchanged.
    public static func normalized(_ text: String) -> String {
        var hasUpper = false
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            if CharacterSet.lowercaseLetters.contains(scalar) { return text }
            hasUpper = true
        }
        guard hasUpper else { return text }
        return titleCased(text)
    }

    // MARK: Vocabulary

    /// Initialisms and menu shorthand that stay in capitals.
    static let keepUppercase: Set<String> = [
        "BBQ", "BLT", "NY", "NYC", "PB&J", "LTO", "CTO", "GF", "V", "VG", "DF", "OJ", "BYO", "USA", "TLC"
    ]
    /// Lowercase inside a name unless first or last.
    static let smallWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "con", "de", "du", "for", "from", "in", "la", "le",
        "of", "on", "or", "per", "the", "to", "with"
    ]
    /// Units written after a number ("12 OZ", "4OZ").
    static let units: Set<String> = ["oz", "lb", "lbs", "ml", "l", "g", "kg", "pc", "pcs", "ct", "fl"]
    static let ordinals: Set<String> = ["st", "nd", "rd", "th"]

    // MARK: Implementation

    private static let leading = CharacterSet(charactersIn: "([\"\u{201C}")
    private static let trailing = CharacterSet(charactersIn: ")]\"\u{201D},.;:!?")
    private static let separators = CharacterSet(charactersIn: "-/,&;:\u{2013}")

    private struct Chunk {
        var text: String
        var isWord: Bool
    }

    private static func titleCased(_ text: String) -> String {
        // Whitespace runs are kept verbatim; everything else is a chunk.
        var chunks: [Chunk] = []
        var current = ""
        var inSpace = false
        for character in text {
            let space = character.isWhitespace
            if space != inSpace, !current.isEmpty {
                chunks.append(Chunk(text: current, isWord: !inSpace && current.contains(where: \.isLetter)))
                current = ""
            }
            inSpace = space
            current.append(character)
        }
        if !current.isEmpty { chunks.append(Chunk(text: current, isWord: !inSpace && current.contains(where: \.isLetter))) }

        let wordIndexes = chunks.indices.filter { chunks[$0].isWord }
        let first = wordIndexes.first, last = wordIndexes.last
        var previousCore = ""
        var result = ""
        for index in chunks.indices {
            let chunk = chunks[index]
            guard chunk.text.contains(where: { !$0.isWhitespace }) else { result += chunk.text; continue }
            let (head, core, tail) = split(chunk.text)
            let cased = chunk.isWord || core.contains(where: \.isNumber)
                ? caseCore(core, isFirst: index == first, isLast: index == last, previous: previousCore)
                : core
            result += head + cased + tail
            if !core.isEmpty { previousCore = cased }
        }
        return result
    }

    private static func split(_ chunk: String) -> (head: String, core: String, tail: String) {
        var scalars = Array(chunk.unicodeScalars)
        var head = String.UnicodeScalarView(), tail = String.UnicodeScalarView()
        while let firstScalar = scalars.first, leading.contains(firstScalar), scalars.count > 1 {
            head.append(scalars.removeFirst())
        }
        var tailScalars: [Unicode.Scalar] = []
        while let lastScalar = scalars.last, trailing.contains(lastScalar), scalars.count > 1 {
            tailScalars.insert(scalars.removeLast(), at: 0)
        }
        tail.append(contentsOf: tailScalars)
        var core = String.UnicodeScalarView(); core.append(contentsOf: scalars)
        return (String(head), String(core), String(tail))
    }

    private static func caseCore(_ core: String, isFirst: Bool, isLast: Bool, previous: String) -> String {
        let upper = core.uppercased()
        if keepUppercase.contains(upper) { return upper }
        // "W/" and "W/O" are lowercase; "W/MUSHROOMS" becomes "w/Mushrooms".
        if upper == "W/" || upper == "W/O" { return core.lowercased() }
        if upper.hasPrefix("W/") {
            return "w/" + caseCore(String(core.dropFirst(2)), isFirst: false, isLast: isLast, previous: "w/")
        }

        // Split on separators, keeping them.
        var parts: [(text: String, isSeparator: Bool)] = []
        var buffer = ""
        for character in core {
            if character.unicodeScalars.allSatisfy(separators.contains) {
                if !buffer.isEmpty { parts.append((buffer, false)); buffer = "" }
                parts.append((String(character), true))
            } else { buffer.append(character) }
        }
        if !buffer.isEmpty { parts.append((buffer, false)) }

        let partIndexes = parts.indices.filter { !parts[$0].isSeparator }
        var out = ""
        var before = previous
        for index in parts.indices {
            let part = parts[index]
            if part.isSeparator { out += part.text; continue }
            let atStart = isFirst && index == partIndexes.first
            let atEnd = isLast && index == partIndexes.last
            let cased = casePart(part.text, atStart: atStart, atEnd: atEnd, previous: before, joined: index != partIndexes.first)
            out += cased
            before = cased
        }
        return out
    }

    private static func casePart(_ part: String, atStart: Bool, atEnd: Bool, previous: String, joined: Bool) -> String {
        let upper = part.uppercased()
        if keepUppercase.contains(upper) { return upper }
        // Already has lowercase: leave it alone.
        if part.contains(where: \.isLowercase) { return part }

        if part.contains(where: \.isNumber) {
            // "4OZ" -> "4oz", "1ST" -> "1st", "7UP" stays.
            let digits = part.prefix { $0.isNumber || $0 == "." }
            let suffix = part.dropFirst(digits.count).lowercased()
            if !suffix.isEmpty, units.contains(suffix) || ordinals.contains(suffix) { return String(digits) + suffix }
            return part
        }

        let lower = part.lowercased()
        // "12 OZ", "12 FL OZ": a unit word right after a number or another unit.
        if units.contains(lower), !joined, let lastCharacter = previous.last,
           lastCharacter.isNumber || units.contains(previous.lowercased()) {
            return lower
        }
        if smallWords.contains(lower), !atStart, !atEnd { return lower }
        return capitalizedWord(part)
    }

    /// "TSO'S" -> "Tso's", "O'BRIEN" -> "O'Brien", "KICKIN'" -> "Kickin'".
    private static func capitalizedWord(_ word: String) -> String {
        let pieces = word.split(separator: "'", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: "\u{2019}", omittingEmptySubsequences: false) }
        guard pieces.count > 1 else { return capitalizedPiece(word) }
        let mark = word.contains("\u{2019}") ? "\u{2019}" : "'"
        let prefix = pieces[0]
        // Irish/French elision prefixes: O'Brien, D'Angelo. Everything else is a possessive or contraction.
        let elision = prefix.count == 1 && ["O", "D"].contains(prefix.uppercased()) && (pieces.dropFirst().first?.count ?? 0) > 2
        return pieces.enumerated().map { offset, piece in
            offset == 0 || elision ? capitalizedPiece(String(piece)) : String(piece).lowercased()
        }.joined(separator: mark)
    }

    private static func capitalizedPiece(_ piece: String) -> String {
        guard let first = piece.first else { return piece }
        return String(first).uppercased() + piece.dropFirst().lowercased()
    }
}
