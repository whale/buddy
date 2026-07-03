import SwiftUI

// MARK: - HistoryView
// A faithful port of the Mac's history sheet: a Buddy card with a [Future | Done |
// Skipped] segmented control + ✕ close, hairline dividers, Geist type. Adopts the
// escalation theme. Tabs mirror the Mac:
//   Future  — parked ("Move to Future") tasks, each restorable with +
//   Done    — today's completions + past days' done tasks, struck with a done word
//   Skipped — past undone tasks, each restorable with +
struct HistoryView: View {
    @Bindable var store: BuddyStore
    var onClose: () -> Void = {}

    enum Tab: String, CaseIterable { case future = "Future", done = "Done", skipped = "Skipped" }
    @State private var tab: Tab = .done

    private var theme: EscalationTheme { EscalationTheme.from(activeCount: store.activeCount) }

    var body: some View {
        VStack(spacing: 0) {
            BuddySheetHeader(theme: theme, onClose: { onClose() }) {
                segmented
            }
            ScrollView {
                VStack(spacing: 0) {
                    switch tab {
                    case .future:  futureBody
                    case .done:    doneBody
                    case .skipped: skippedBody
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Segmented control ([Future | Done | Skipped])
    private var segmented: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                let active = tab == t
                Text(t.rawValue)
                    .font(.geist(15, .regular)).tracking(-0.30)
                    .foregroundStyle(active ? (theme.level == .lvl2 ? Color(hex: "#e5484d") : Color(hex: "#1a1a1a")) : theme.chromeInk)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(
                        Capsule().fill(active ? (theme.level == .lvl2 ? Color.white : Color.white) : .clear)
                            .shadow(color: active && theme.level != .lvl2 ? .black.opacity(0.08) : .clear, radius: 2, y: 1)
                    )
                    .contentShape(Capsule())
                    .onTapGesture { tab = t }
            }
        }
        .padding(4)
        .background(Capsule().fill(theme.level == .lvl2 ? Color.white.opacity(0.20) : Color.black.opacity(0.05)))
    }

    // A rendered group: a header + its lines. Precomputed so the view body stays
    // simple enough for the Swift type-checker (nested filter/tuple/ForEach times out).
    private struct HistGroup: Identifiable { let id: String; let header: String; let lines: [String] }

    private var doneGroups: [HistGroup] {
        var out: [HistGroup] = []
        let today = store.doneTasks.map { $0.text }
        if !today.isEmpty { out.append(HistGroup(id: "today", header: "Today", lines: today)) }
        for d in pastDays {
            let lines = d.items.filter { $0.done }.map { $0.text }
            if !lines.isEmpty { out.append(HistGroup(id: d.date, header: d.weekday.isEmpty ? d.date : d.weekday, lines: lines)) }
        }
        return out
    }

    private var skippedGroups: [HistGroup] {
        var out: [HistGroup] = []
        for d in pastDays {
            let lines = d.items.filter { !$0.done }.map { $0.text }
            if !lines.isEmpty { out.append(HistGroup(id: d.date, header: d.weekday.isEmpty ? d.date : d.weekday, lines: lines)) }
        }
        return out
    }

    // MARK: Done — today's completions + past done, struck with a done word
    @ViewBuilder private var doneBody: some View {
        let groups = doneGroups
        if groups.isEmpty {
            emptyState("No completed tasks yet.")
        } else {
            ForEach(groups) { g in
                group(header: g.header) {
                    ForEach(g.lines, id: \.self) { line in doneRow(line) }
                }
            }
        }
    }

    // MARK: Skipped — past undone, restorable
    @ViewBuilder private var skippedBody: some View {
        let groups = skippedGroups
        if groups.isEmpty {
            emptyState("Nothing skipped yet.")
        } else {
            ForEach(groups) { g in
                group(header: g.header) {
                    ForEach(g.lines, id: \.self) { line in
                        plainRow(line, canAdd: !store.atHardCap) { store.restoreHistoryTask(text: line) }
                    }
                }
            }
        }
    }

    // MARK: Future — parked tasks, restorable
    @ViewBuilder private var futureBody: some View {
        if store.deferred.isEmpty {
            emptyState("Nothing in Future yet.")
        } else {
            group(header: "Future") {
                ForEach(store.deferred) { d in
                    plainRow(d.text, canAdd: !store.atHardCap) { store.wakeDeferredTask(id: d.id) }
                }
            }
        }
    }

    // MARK: Row + group builders

    @ViewBuilder private func group<C: View>(header: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header)
                .font(.geist(18, .medium)).tracking(-0.36)
                .foregroundStyle(theme.ink)
                .padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28).padding(.vertical, 20)
        Rectangle().fill(theme.line).frame(height: 1)
    }

    private func doneRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Donezo.").font(.geist(18, .semibold)).tracking(-0.30).foregroundStyle(theme.ink)
            Text(text).font(.geist(18, .regular)).tracking(-0.36)
                .strikethrough(true, color: theme.inkDim).foregroundStyle(theme.inkDim).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private func plainRow(_ text: String, canAdd: Bool, add: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.geist(18, .regular)).tracking(-0.36).foregroundStyle(theme.ink).lineLimit(1)
            Spacer(minLength: 0)
            if canAdd {
                Button(action: add) {
                    Image(systemName: "plus").font(.system(size: 15)).foregroundStyle(theme.inkDim)
                        .frame(width: 32, height: 32).contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
    }

    private func emptyState(_ msg: String) -> some View {
        Text(msg)
            .font(.geist(15, .regular)).tracking(-0.32)
            .foregroundStyle(theme.inkDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.vertical, 40)
    }

    // Last N days from history that fall within the configured window, most-recent first.
    private var pastDays: [Day] {
        let n = store.settings.historyDays
        guard n > 0 else { return [] }
        let base = Date()
        return (1...n).compactMap { i -> Day? in
            guard let d = Calendar.current.date(byAdding: .day, value: -i, to: base) else { return nil }
            return store.history.first(where: { $0.date == BuddyStore.localDate(d) })
        }
    }
}

#Preview {
    HistoryView(store: { let s = BuddyStore(); return s }())
}
