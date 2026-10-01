import Foundation

// MARK: - HistoryModel
// Pure (view-free) rules for the History sheet, mirrored from the Mac (dist/index.html):
//   histTabCount → tab counts · doneDays/renderPast → Done paging + day headings.
// Kept pure so they're unit-testable and the two platforms can't quietly drift.
enum HistoryModel {
    /// Done pages by ITEMS, not days: 30 completed tasks at a time (Mac DONE_PAGE).
    static let donePage = 30

    struct Line: Identifiable, Equatable { let id: String; let text: String }
    struct Group: Identifiable, Equatable { let id: String; let header: String; let lines: [Line] }

    // MARK: Tab counts — Mac histTabCount

    /// Future (n): items still parked — sent-to-today rows aren't waiting any more; blank text doesn't count.
    static func futureCount(_ deferred: [DeferredTask]) -> Int {
        deferred.filter { $0.sent != true && !isBlank($0.text) }.count
    }

    /// Done (n): EXACTLY what the Done tab can show — today's live completions + every archived
    /// done task with text dated before today (the same filter donePage uses, so they never disagree).
    static func doneCount(todayDone: [BuddyTask], history: [Day], now: Date = Date()) -> Int {
        let today = BuddyStore.localDate(now)
        return todayDone.count + history.filter { $0.date < today }
            .reduce(0) { $0 + $1.items.filter { $0.done && !isBlank($0.text) }.count }
    }

    // MARK: Day headings — Mac doneDays

    /// Within the last week → the weekday ("Monday"); older → "Monday, Sep 22" (paging by items
    /// can reach back past a week). English, like the Mac's DOW table.
    static func dayHeading(date: String, now: Date = Date()) -> String {
        guard let d = parse(date) else { return date }
        let weekAgo = BuddyStore.localDate(now.addingTimeInterval(-7 * 86400))
        let wd = format(d, "EEEE")
        return date > weekAgo ? wd : "\(wd), \(format(d, "MMM d"))"
    }

    // MARK: Done paging — Mac renderPast

    /// The first `shown` completions, newest first: today's count toward the page, then archived
    /// days (date < today) newest first, cutting mid-day if needed. `hasMore` → show "Load more".
    static func donePage(todayDone: [BuddyTask], history: [Day], shown: Int,
                         now: Date = Date()) -> (groups: [Group], hasMore: Bool) {
        var groups: [Group] = []
        if !todayDone.isEmpty {
            groups.append(Group(id: "today", header: "Today",
                                lines: todayDone.map { Line(id: $0.id, text: $0.text) }))
        }
        let today = BuddyStore.localDate(now)
        var room = max(0, shown - todayDone.count), total = todayDone.count
        let days = history.filter { $0.date < today }.sorted { $0.date > $1.date }
        for d in days {
            let items = d.items.filter { $0.done && !isBlank($0.text) }
            guard !items.isEmpty else { continue }
            total += items.count
            if room > 0 {
                let take = Array(items.prefix(room))
                groups.append(Group(id: d.date, header: dayHeading(date: d.date, now: now),
                                    lines: take.enumerated().map { i, it in
                                        Line(id: it.id.isEmpty ? "\(d.date)-\(i)" : it.id, text: it.text) }))
                room -= take.count
            }
        }
        return (groups, total > shown)
    }

    // MARK: helpers

    private static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    // Formatters are expensive to build — make them once (main-thread use only).
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static var named: [String: DateFormatter] = [:]
    private static func parse(_ ds: String) -> Date? { isoDay.date(from: ds) }
    private static func format(_ d: Date, _ fmt: String) -> String {
        if let f = named[fmt] { return f.string(from: d) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = fmt
        named[fmt] = f
        return f.string(from: d)
    }
}
