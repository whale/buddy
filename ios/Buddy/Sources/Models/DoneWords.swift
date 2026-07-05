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

    /// Stable hash → word index, matching the Mac (h*31 + charCode, seed 0, over UTF-16).
    /// Key off the task id everywhere so the drawer and History show the SAME word.
    static func word(for key: String) -> String {
        var h = 0
        for c in key.utf16 { h = (h &* 31) &+ Int(c) }
        return all[((h % all.count) + all.count) % all.count]
    }
}
