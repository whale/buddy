import Foundation

// MARK: - BuddyDiag — privacy-safe diagnostics event log (JSONL)
// Mirror of the Mac's diag()/buddy-events.jsonl: structured events appended to a
// local file so a field incident ("it burped and reverted") can be diagnosed after
// the fact. RULES: never log task text or any user content — event names, counts,
// short id prefixes, versions and timings only. Buffered + debounced writes.
// File: Application Support/Buddy/buddy-events.jsonl (rotates at ~1 MB → .1).
enum BuddyDiag {
    private static let queue = DispatchQueue(label: "buddy.diag", qos: .utility)
    private static var pending: [String] = []
    private static var flushScheduled = false

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Buddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("buddy-events.jsonl")
    }

    static func log(_ evt: String, _ data: [String: Any] = [:]) {
        var rec: [String: Any] = ["t": ISO8601DateFormatter().string(from: Date()), "evt": evt]
        for (k, v) in data { rec[k] = v }
        guard let d = try? JSONSerialization.data(withJSONObject: rec, options: [.sortedKeys]),
              let line = String(data: d, encoding: .utf8) else { return }
        queue.async {
            pending.append(line)
            guard !flushScheduled else { return }
            flushScheduled = true
            queue.asyncAfter(deadline: .now() + 2) { flushLocked() }
        }
    }

    private static func flushLocked() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let chunk = pending.joined(separator: "\n") + "\n"
        pending.removeAll()
        let url = fileURL
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 1_000_000 {
            let rotated = url.deletingPathExtension().appendingPathExtension("jsonl.1")
            try? FileManager.default.removeItem(at: rotated)
            try? FileManager.default.moveItem(at: url, to: rotated)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(chunk.utf8))
        } else {
            try? Data(chunk.utf8).write(to: url)
        }
    }

    /// The last `limit` events as raw JSONL — for a future Settings "Export diagnostics".
    static func tail(_ limit: Int = 200) -> String {
        guard let s = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        return s.split(separator: "\n").suffix(limit).joined(separator: "\n")
    }
}
