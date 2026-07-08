import Foundation

// MARK: - JSONValue — a Codable bag for fields this app version doesn't know about.
// Version-skew safety (sync Slice 2): a NEWER peer may add wire fields iOS has never
// heard of. Every wire/domain struct carries an `extras: [String: JSONValue]` bag that
// captures unknown keys at decode and re-emits them at encode, so a Mac→iOS→Mac
// round-trip never strips the Mac's data. Mirrors the Mac's `{...blob}` spreads +
// top-level `extras` bag in dist/index.html.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)          // kept separate from .number so 80 re-encodes as 80, not 80.0
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Dynamic coding key (for capturing/re-emitting unknown wire fields)
struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// Decode every key NOT in `known` into an extras bag (tolerates any value shape).
func decodeExtras(from decoder: Decoder, known: Set<String>) -> [String: JSONValue] {
    guard let c = try? decoder.container(keyedBy: AnyCodingKey.self) else { return [:] }
    var out = [String: JSONValue]()
    for key in c.allKeys where !known.contains(key.stringValue) {
        if let v = try? c.decode(JSONValue.self, forKey: key) { out[key.stringValue] = v }
    }
    return out
}

// MARK: - CanonicalJSON — byte-identical mirror of the Mac's canonicalJSON()
// (dist/index.html). Used ONLY for deterministic ORDERING between two candidate
// values during merge: both platforms must serialize the same logical wire content
// to the SAME string, or they order two candidates differently and never converge.
//
// Mirrors JS exactly:
//   • object keys recursively sorted (JS Array.sort = UTF-16 code-unit order)
//   • JSON.stringify string escaping: only `"`, `\`, and control chars < 0x20
//     (as \b \t \n \f \r or \u00xx) — NOT `/` (JSONSerialization escapes it; JS doesn't)
//   • integral numbers render with no decimal point (JS Number→String)
enum CanonicalJSON {

    static func canonical(_ v: JSONValue) -> String {
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .number(let d): return numberLiteral(d)
        case .string(let s): return stringLiteral(s)
        case .array(let a): return "[" + a.map(canonical).joined(separator: ",") + "]"
        case .object(let o):
            let keys = o.keys.sorted { compare($0, $1) < 0 }
            return "{" + keys.map { stringLiteral($0) + ":" + canonical(o[$0]!) }.joined(separator: ",") + "}"
        }
    }

    /// JS string relational compare (`<` / `<=` on strings) = UTF-16 code-unit order.
    /// Swift's String `<` orders by Unicode scalar, which DIVERGES from JS for
    /// supplementary-plane characters (emoji in task text) — so compare code units.
    static func compare(_ a: String, _ b: String) -> Int {
        var ia = a.utf16.makeIterator(), ib = b.utf16.makeIterator()
        while true {
            switch (ia.next(), ib.next()) {
            case (nil, nil): return 0
            case (nil, _): return -1
            case (_, nil): return 1
            case (let x?, let y?):
                if x != y { return x < y ? -1 : 1 }
            }
        }
    }
    static func lessOrEqual(_ a: String, _ b: String) -> Bool { compare(a, b) <= 0 }

    /// JSON.stringify-style string literal.
    static func stringLiteral(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\t": out += "\\t"
            case "\n": out += "\\n"
            case "\u{0C}": out += "\\f"
            case "\r": out += "\\r"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) }
                else { out.append(Character(u)) }
            }
        }
        return out + "\""
    }

    /// JS Number→String for the magnitudes Buddy carries (epoch ms, counters):
    /// integral doubles render with no decimal point; fractional values use Swift's
    /// shortest round-trip form, which matches JS for non-exponential magnitudes.
    static func numberLiteral(_ d: Double) -> String {
        if d.isFinite, d == d.rounded(), abs(d) < 9_007_199_254_740_992 {   // < 2^53 → exact integer
            return String(Int64(d))
        }
        return "\(d)"
    }
}
