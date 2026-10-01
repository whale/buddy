import SwiftUI
import UIKit

// MARK: - HistoryView
// A faithful port of the Mac's history sheet: a Buddy card with a [Future | Done |
// Skipped] segmented control + ✕ close, hairline dividers, Geist type. Adopts the
// escalation theme. Tabs mirror the Mac:
//   Future  — parked tasks (oldest first), restorable with +, editable, plus an Add row
//   Done    — today's completions + past days' done tasks, struck with a done word
//   Skipped — past undone tasks, each restorable with +
struct HistoryView: View {
    @Bindable var store: BuddyStore
    var onClose: () -> Void = {}

    enum Tab: String, CaseIterable { case future = "Future", done = "Done" }
    @State private var tab: Tab = .future
    @State private var pastDaysShown = 7   // Mac PAST_PAGE — "Load more" pages a week at a time
    @State private var openFutureRowID: String? = nil

    // Future inline editing — mirrors TodayView's Add/edit. The NEW-item draft lives ONLY
    // here (never in store.deferred) so a blank row can't sync to the Mac as an empty task;
    // it's written to the store once, on commit, with trimmed non-empty text.
    @State private var editingId: String? = nil        // a deferred id, or draftID for a new item
    @State private var editText: String = ""
    @State private var editOriginal: String? = nil     // text when an existing-row edit began (nil for a draft)
    @Environment(\.scenePhase) private var scenePhase
    @State private var editSession = 0                 // bumps per edit → a fresh editor + stale-write guard
    private static let draftID = "future-draft"
    private static let addRowHeight: CGFloat = 110
    @State private var futureRowsHeight: CGFloat = 0   // measured height of the rows (excl. Add)
    @State private var keyboardTop: CGFloat = .infinity
    @State private var sheetMaxY: CGFloat = 0

    private var theme: EscalationTheme { EscalationTheme.from(activeCount: store.escalationCount, limit: store.taskLimit) }

    var body: some View {
        VStack(spacing: 0) {
            BuddySheetHeader(theme: theme, onClose: { commitFutureEdit(); onClose() }) {
                segmented
            }
            switch tab {
            case .future:
                futureScroll
            case .done:
                ScrollView {
                    VStack(spacing: 0) { doneBody }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { sheetMaxY = g.frame(in: .global).maxY }
                .onChange(of: g.frame(in: .global).maxY) { _, v in sheetMaxY = v }
        })
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardTop = frame.minY
            }
        }
        // Leaving Future or closing the sheet commits a draft with text (Mac parity);
        // an empty draft is simply dropped.
        .onChange(of: tab) { _, _ in commitFutureEdit() }
        .onDisappear { commitFutureEdit() }
        // TRUE backgrounding flushes the edit straight to disk — the app may be killed next.
        // Not .inactive: Control Center / app switcher / Face ID mustn't end the edit
        // (same gate as TodayView).
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { commitFutureEdit(immediate: true) }
        }
        #if DEBUG
        .onAppear {   // screenshot harness: -uiTab Future|Done|Skipped, -uiFutureDraft "text"
            if let raw = UserDefaults.standard.string(forKey: "uiTab"),
               let t = Tab(rawValue: raw) { tab = t }
            if tab == .future, let draft = UserDefaults.standard.string(forKey: "uiFutureDraft") {
                startDraft()
                editText = draft
            }
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
                    // Selected label follows escalation (black → red at lvl1/lvl2);
                    // pill stays white at every level — mirrors Mac .seg-sel.
                    .foregroundStyle(active ? theme.segSelInk : theme.chromeInk)
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
        .background(Capsule().fill(theme.segTrack))
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

    // MARK: Future — parked tasks, oldest first (store order, like Today), then Add.
    // + add to today, × remove for good (Mac parity); tap a row's text to edit it.
    // The Add row sits right after the last row; once the list outgrows the sheet it pins
    // to the bottom and the rows scroll beneath it.
    private var keyboardOverlap: CGFloat {
        guard editingId != nil, keyboardTop.isFinite, sheetMaxY > 0 else { return 0 }
        return max(0, sheetMaxY - keyboardTop)
    }

    private var futureScroll: some View {
        GeometryReader { geo in
            // Compare rows-only height (never changes with pin state → no layout feedback loop).
            let pinned = futureRowsHeight + 1 + Self.addRowHeight > geo.size.height + 0.5
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        futureRows
                            .background(GeometryReader { g in
                                Color.clear
                                    .onAppear { futureRowsHeight = g.size.height }
                                    .onChange(of: g.size.height) { _, v in futureRowsHeight = v }
                            })
                        if !pinned { addBlock(showDivider: !futureRowsEmpty) }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if pinned {
                        addBlock(showDivider: true).background(theme.cardBackground)
                    }
                }
                .onChange(of: editingId) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
                .onChange(of: keyboardOverlap) { _, _ in
                    guard let id = editingId else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        // The app column ignores the keyboard, so shrink just this list while editing so
        // the field (and the pinned Add) stay above the keyboard.
        .padding(.bottom, keyboardOverlap)
    }

    private var futureRowsEmpty: Bool { store.deferred.isEmpty && editingId != Self.draftID }

    @ViewBuilder private var futureRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.deferred.enumerated()), id: \.element.id) { i, d in
                if i > 0 { historyDivider }
                Group {
                    if d.sent == true {
                        sentFutureRow(id: d.id, text: d.text)
                    } else if editingId == d.id {
                        futureEditorRow(id: d.id)
                    } else {
                        futureRow(id: d.id, text: d.text)
                    }
                }
                .id(d.id)
            }
            // The in-progress new item: view-local only, no + / × actions (it isn't a task yet).
            if editingId == Self.draftID {
                if !store.deferred.isEmpty { historyDivider }
                futureEditorRow(id: Self.draftID).id(Self.draftID)
            }
        }
    }

    @ViewBuilder private func addBlock(showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            if showDivider { historyDivider }
            futureAddRow
        }
    }

    // Same "Add +" as Today's Add row (Geist medium, −0.48 tracking, 18pt gap, addInk token),
    // at the Future rows' fixed 24pt / 110pt.
    private var futureAddRow: some View {
        HStack(spacing: 18) {
            Text("Add")
            Text("+")
        }
        .font(.geist(24, .medium))
        .tracking(-0.48)
        .foregroundStyle(theme.addInk)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, minHeight: Self.addRowHeight, maxHeight: Self.addRowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { startDraft() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add to Future")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("future-add")
    }

    // Inline editor row — the same UIKit editor as Today, at the Future rows' 24pt. At least
    // 110pt, and it GROWS with long text while editing instead of clipping. It sizes from the
    // editor's own measured height (not Today's invisible-Text ghost): UITextView lines are a
    // touch taller than SwiftUI Text, so a ghost-sized box clipped the 3rd+ line.
    private func futureEditorRow(id: String) -> some View {
        let session = editSession
        let binding = Binding<String>(
            get: { editText },
            // A torn-down editor's end-editing write must never land in the NEXT edit's text.
            set: { v in if editingId == id && editSession == session { editText = v } }
        )
        return InlineTaskEditor(
            text: binding,
            fontSize: 24,
            textColor: UIColor(theme.escalationText),
            accessibilityIdentifier: "future-editor-\(id)",
            wrapsToProposedWidth: true,
            onCommit: { if editingId == id && editSession == session { commitFutureEdit() } }
        )
        .id(session)   // a fresh UITextView per edit — never reuse the last entry's text
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32).padding(.vertical, 16)
        .frame(minHeight: Self.addRowHeight)
    }

    private func startDraft() {
        commitFutureEdit()                 // a draft with text is kept; an empty one is dropped
        openFutureRowID = nil
        editText = ""
        editOriginal = nil
        editSession += 1
        editingId = Self.draftID
    }

    private func startFutureEdit(id: String, text: String) {
        commitFutureEdit()
        openFutureRowID = nil
        editText = text                    // keep the existing text (don't blank the row)
        editOriginal = text
        editSession += 1
        editingId = id
    }

    /// Commit whatever is being edited. Draft → addDeferred (rejects blank); existing row →
    /// editDeferred (empty deletes + tombstones; a change bumps v). Idempotent.
    private func commitFutureEdit(immediate: Bool = false) {
        guard let id = editingId else { return }
        let text = editText
        let original = editOriginal
        editingId = nil
        editText = ""
        editOriginal = nil
        withoutAnimation {
            if id == Self.draftID { store.addDeferred(text: text, immediate: immediate) }
            else { store.editDeferred(id: id, text: text, original: original, immediate: immediate) }
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
            theme: theme,
            onAdd: store.atHardCap ? nil : { withoutAnimation { store.wakeDeferredTask(id: id) } },
            onDelete: { withoutAnimation { store.deleteDeferred(id: id) } },
            onTap: { startFutureEdit(id: id, text: text) }
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
            theme: theme,
            onRestore: { withoutAnimation { store.unsendDeferred(id: id) } }
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Sent to today!").font(.geist(18, .semibold)).tracking(-0.30)
                    .foregroundStyle(theme.escalationText).fixedSize(horizontal: true, vertical: false)
                Text(text).font(.geist(18, .regular)).tracking(-0.36)
                    .foregroundStyle(theme.inkDim).lineLimit(1)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
        }
        .frame(height: 110)
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
