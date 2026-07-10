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

    enum Tab: String, CaseIterable { case future = "Future", done = "Done" }
    @State private var tab: Tab = .future
    @State private var pastDaysShown = 7   // Mac PAST_PAGE — "Load more" pages a week at a time
    @State private var openFutureRowID: String? = nil

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
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if DEBUG
        .onAppear {   // screenshot harness: -uiTab Future|Done|Skipped
            if let raw = UserDefaults.standard.string(forKey: "uiTab"),
               let t = Tab(rawValue: raw) { tab = t }
        }
        #endif
    }

    // MARK: Segmented control ([Future | Done | Skipped])
    private var segmented: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                let active = tab == t
                Text(t.rawValue)
                    .font(.geist(15, .regular)).tracking(-0.30)
                    // Selected label follows escalation like the selected chrome icon
                    // (black → red at lvl1/lvl2); pill stays white — mirrors Mac .seg-sel.
                    .foregroundStyle(active ? (theme.level == .lvl0 ? Color.black : Color(hex: "#e5484d")) : theme.chromeInk)
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(
                        Capsule().fill(active ? Color.white : .clear)
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
    private struct HistLine: Identifiable { let id: String; let text: String }
    private struct HistGroup: Identifiable { let id: String; let header: String; let lines: [HistLine] }

    private var doneGroups: [HistGroup] {
        var out: [HistGroup] = []
        let today = store.doneTasks.map { HistLine(id: $0.id, text: $0.text) }
        if !today.isEmpty { out.append(HistGroup(id: "today", header: "Today", lines: today)) }
        for d in pastDays {
            let lines = d.items.filter { $0.done }.map { HistLine(id: $0.id, text: $0.text) }
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
                    ForEach(g.lines) { line in doneRow(id: line.id, text: line.text) }
                }
            }
            if store.hasHistoryBefore(days: pastDaysShown) { loadMoreButton }
        }
    }

    private var loadMoreButton: some View {
        Button { withAnimation { pastDaysShown += 7 } } label: {
            Text("Load more")
                .font(.geist(15, .regular)).tracking(-0.30).foregroundStyle(theme.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32).padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Future — parked tasks, restorable (+ add to today, × remove for good — Mac parity)
    @ViewBuilder private var futureBody: some View {
        if store.deferred.isEmpty {
            emptyState("Nothing in Future yet.")
        } else {
            let rows = Array(store.deferred.reversed())
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, d in
                if i > 0 { historyDivider }
                if d.sent == true {
                    sentFutureRow(id: d.id, text: d.text)
                } else {
                    futureRow(id: d.id, text: d.text)
                }
            }
        }
    }

    // MARK: Row + group builders

    @ViewBuilder private func group<C: View>(header: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header)
                .font(.geist(18, .medium)).tracking(-0.36)
                .foregroundStyle(theme.inkDim)   // grey day headers, distinct from the (darker) done word
                .padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32).padding(.vertical, 20)
        Rectangle().fill(theme.line).frame(height: 1)
    }

    // Done tab row — struck done word + a stable revert icon (rewind to to-do), like the main view.
    private func doneRow(id: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DoneWords.word(for: id)).font(.geist(18, .semibold)).tracking(-0.30)
                .foregroundStyle(theme.ink).fixedSize(horizontal: true, vertical: false)
            Text(text).font(.geist(18, .regular)).tracking(-0.36)
                .strikethrough(true, color: theme.inkDim).foregroundStyle(theme.inkDim).lineLimit(1)
            Spacer(minLength: 8)
            rowIcon("undo") { store.restoreHistoryTask(text: text) }
        }
        .padding(.vertical, 5)
    }

    private var historyDivider: some View {
        Rectangle().fill(theme.line).frame(height: 1)
    }

    // Future rows use the Today row visual language, but fixed at 110pt and scrollable.
    private func futureRow(id: String, text: String) -> some View {
        SwipeableRow(
            rowID: id,
            openRowID: $openFutureRowID,
            cardFill: theme.cardBackground,
            onAdd: store.atHardCap ? nil : { withoutAnimation { store.wakeDeferredTask(id: id) } },
            onDelete: { withoutAnimation { store.deleteDeferred(id: id) } }
        ) {
            Text(text)
                .font(.geist(24, .medium)).tracking(-0.48).lineSpacing(2)
                .foregroundStyle(theme.escalationText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
        }
        .frame(height: 110)
    }

    // A parked task already sent to today. Same fixed row, swipe to undo.
    private func sentFutureRow(id: String, text: String) -> some View {
        SwipeableRow(
            rowID: id,
            openRowID: $openFutureRowID,
            cardFill: theme.cardBackground,
            onRestore: { withoutAnimation { store.unsendDeferred(id: id) } }
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Sent to today!").font(.geist(18, .semibold)).tracking(-0.30)
                    .foregroundStyle(theme.escalationText).fixedSize(horizontal: true, vertical: false)
                Text(text).font(.geist(18, .regular)).tracking(-0.36)
                    .foregroundStyle(futureDimText).lineLimit(1)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
        }
        .frame(height: 110)
    }

    private var futureDimText: Color {
        switch theme.level {
        case .lvl0: return theme.inkDim
        case .lvl1: return Color(hex: "#e5484d").opacity(0.65)
        case .lvl2: return theme.inkDim
        }
    }

    // Rightmost row icon: glyph hugs the row's trailing edge so every surface's icons line up
    // at the same 32pt gutter (the group's horizontal padding).
    private func rowIcon(_ name: String, size: CGFloat = 18, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(name, size: size).foregroundStyle(theme.inkDim)
                .frame(width: 22, height: 26, alignment: .trailing).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyState(_ msg: String) -> some View {
        Text(msg)
            .font(.geist(15, .regular)).tracking(-0.32)
            .foregroundStyle(theme.inkDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.vertical, 40)
    }

    private func withoutAnimation(_ action: () -> Void) {
        var tx = Transaction(animation: nil)
        tx.disablesAnimations = true
        withTransaction(tx) { action() }
    }

    // Last N days from history that fall within the configured window, most-recent first.
    private var pastDays: [Day] {
        let n = pastDaysShown
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
