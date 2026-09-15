import Foundation

/// A per-setting revision, carried in the existing top-level extras bag so old
/// clients preserve it. Matches normalizeTaskLimit/pickTaskLimit on the Mac.
struct TaskLimit: Equatable {
    var value: Int = 6
    var v: Int64 = 0
    var writer: String = ""
    static let maxRevision: Int64 = 9_007_199_254_740_990

    private static func number(_ raw: JSONValue?) -> Double? {
        switch raw {
        case .int(let n)?: return Double(n)
        case .number(let n)?: return n
        default: return nil
        }
    }
    static func normalized(_ raw: JSONValue?) -> TaskLimit {
        guard case .object(let r) = raw,
              let revision = number(r["v"]), revision.isFinite, revision.rounded() == revision,
              revision >= 1, revision <= Double(maxRevision),
              case .string(let writer) = r["writer"],
              writer.range(of: "^[a-z0-9-]{1,64}$", options: .regularExpression) != nil
        else { return TaskLimit() }
        var value = 6
        if let n = number(r["value"]), n.isFinite, n.rounded() == n {
            value = Int(max(3, min(6, n)))
        }
        return TaskLimit(value: value, v: Int64(revision), writer: writer)
    }
    static func pick(_ a: JSONValue?, _ b: JSONValue?) -> TaskLimit {
        let a = normalized(a), b = normalized(b)
        if a.v != b.v { return a.v > b.v ? a : b }
        if a.writer != b.writer { return a.writer > b.writer ? a : b }
        return a.value >= b.value ? a : b
    }
    var json: JSONValue {
        .object(["value": .int(Int64(value)), "v": .int(v), "writer": .string(writer)])
    }
    static func mergeExtras(_ older: [String: JSONValue], _ newer: [String: JSONValue]) -> [String: JSONValue] {
        var result = older.merging(newer) { _, n in n }
        let limit = pick(older["taskLimit"], newer["taskLimit"])
        result["taskLimit"] = limit.v > 0 ? limit.json : nil
        return result
    }
}
