import Foundation

// MARK: - Done words
// The Mac shows a rotating completion word on each done row (not always "Donezo.").
// Port the list; pick deterministically from a STABLE hash of the task so a given task
// always shows the same word, but different tasks vary. (Swift's String.hashValue is
// per-process randomized — must use our own stable hash.)
enum DoneWords {
    static let all = [
        "Donezo!", "Done!", "Done & Dusted!", "Sorted!", "Wrapped!", "Handled!", "Bagged!",
        "Squared Away!", "Locked In!", "Ticked Off!", "Checked Off!", "Buttoned Up!", "All Set!",
        "Good To Go!", "Cleared!", "Settled!", "Tidied!", "Put To Bed!", "Golden!", "There It Is!",
        "Ta-Da!", "Voilà!", "Finito!", "Fin!", "Shipped!"
    ]

    /// Stable djb2 hash → word index. Same key ⇒ same word across launches.
    static func word(for key: String) -> String {
        var h: UInt64 = 5381
        for b in key.utf8 { h = (h &* 33) &+ UInt64(b) }
        return all[Int(h % UInt64(all.count))]
    }
}
