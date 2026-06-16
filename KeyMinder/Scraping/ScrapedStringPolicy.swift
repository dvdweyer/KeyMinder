// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Sanitizes strings that cross the trust boundary from a scraped (potentially hostile)
/// source into KeyMinder's UI or export layers.
///
/// Applied at the point where AX menu titles and `NSUserKeyEquivalents` keys are first
/// read. Hardened against spoofing via bidi overrides, control characters, and length abuse.
enum ScrapedStringPolicy {

    /// Maximum grapheme-cluster count kept after sanitization.
    static let maxLength = 256

    /// Unicode scalar values for bidi formatting characters that must be stripped:
    /// LRM, RLM, ALM, LRE, RLE, PDF, LRO, RLO, LRI, RLI, FSI, PDI.
    private static let bidiScalars: Set<UInt32> = [
        0x200E, 0x200F, 0x061C,           // directional marks
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E, // embeddings / overrides
        0x2066, 0x2067, 0x2068, 0x2069,   // isolates
    ]

    /// Returns a sanitized copy of `raw`:
    /// - NFC-normalized (merges combining marks)
    /// - C0 controls (U+0000–U+001F) stripped
    /// - C1 controls (U+0080–U+009F) stripped
    /// - Bidi override / embedding / isolate scalars stripped
    /// - Truncated to `maxLength` grapheme clusters
    static func sanitize(_ raw: String) -> String {
        let normalized = raw.precomposedStringWithCanonicalMapping
        var result = ""
        result.reserveCapacity(min(normalized.unicodeScalars.count, maxLength))
        for scalar in normalized.unicodeScalars {
            let v = scalar.value
            guard v >= 0x20,
                  !(v >= 0x80 && v <= 0x9F),
                  !bidiScalars.contains(v)
            else { continue }
            result.unicodeScalars.append(scalar)
        }
        if result.count > maxLength {
            let end = result.index(result.startIndex, offsetBy: maxLength)
            result = String(result[..<end])
        }
        return result
    }
}
