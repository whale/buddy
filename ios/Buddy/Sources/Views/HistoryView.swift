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
    @State private var doneShown = HistoryModel.donePage   // Mac DONE_PAGE — 30 completed items per page
    @State private var openFutureRowID: String? = nil

    // Future inline editing — mirrors TodayView's Add/edit. The NEW-item draft lives ONLY
    // here (never in store.deferred) so a blank row can't sync to the Mac as an empty task;
    // it's written to the store once, on commit, with trimmed non-empty text.
    @State private var editingId: String? = nil        // a deferred id, or draftID for a new item
    @State private var editText: String = ""
    @State private var editOriginal: String? = nil     // text when an existing-row edit began (nil for a draft)
    @Environment(\.scenePhase) private var scenePhase
    @State private var highlightId: String? = nil      // existing row flashed when an Add is a duplicate title
    @State private var editSession = 0                 // bumps per edit → a fresh editor + stale-write guard
    private static let draftID = "future-draft"
    @State private var futureLayoutHeight: CGFloat = 0 // panel height without the keyboard (row sizing)
    private var sentRowHeight: CGFloat { FutureFit.sentRowHeight }   // compact "Sent to today!" row = fit floor
    @State private var heldFitStep: Int? = nil         // fit step frozen while editing (no jump mid-type)
    @State private var fitMemo = FitMemo()             // last computed step (read when an edit starts)
    // "N more ↓" — parent-owned so a rebuilt Add row never replays its entrance.
    @State private var moreN = 0                       // rows currently ≥ half under the pinned Add
    @State private var moreShown = 0                   // number on screen (kept while fading out)
    @State private var moreRollUp = true
    @State private var landedId: String? = nil
    @State private var moreTapWidth: CGFloat = 400         // a just-committed draft's new row id (scroll it into view)
    // Memo: the fit is a pure function of these inputs — re-renders (scrolling, the count, sync
    // adopts that don't touch Future) reuse the last result instead of re-measuring.
    private final class FitMemo {
        var lastStep = 0
        var key: [AnyHashable] = []
        var result: FutureFit.Result?
        var lastH: CGFloat = 0, lastW: CGFloat = 0           // the frozen panel size last fitted to
        var heldOverflow: (session: Int, overflow: Bool)?    // overflow mode, held for one edit session
        var lastMids: [String: CGFloat] = [:]                // row mid-Ys, for re-counting on resize
        var moreHiddenAt: Date = .distantPast                // when "N more" last started fading out
    }
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
        .onChange(of: tab) { _, _ in commitFutureEdit(); doneShown = HistoryModel.donePage; moreN = 0 }
        .onDisappear { commitFutureEdit() }
        // TRUE backgrounding flushes the edit straight to disk — the app may be killed next.
        // Not .inactive: Control Center / app switcher / Face ID mustn't end the edit
        // (same gate as TodayView).
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { commitFutureEdit(immediate: true) }
            // Heal: the Future sync guard is only ever up while an editor is (never wedge sync).
            if phase == .active, editingId == nil, store.isEditingFuture { store.isEditingFuture = false }
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

    // MARK: Segmented control ([Future (n) | Done (n)])
    private func tabCount(_ t: Tab) -> Int {
        switch t {
        case .future: return HistoryModel.futureCount(store.deferred)
        case .done:   return HistoryModel.doneCount(todayDone: store.doneTasks, history: store.history)
        }
    }

    private var segmented: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                let active = tab == t
                // "Future (12)": the count is the label's own colour at 55% (so it follows
                // lvl0/1/2), 6pt past the word space, and never wraps (Mac .seg-count).
                HStack(spacing: 0) {
                    Text(t.rawValue)
                    Text(" (\(tabCount(t)))").opacity(0.55).padding(.leading, 6)
                }
                .font(.geist(15, .regular)).tracking(-0.30)
                .lineLimit(1).fixedSize()
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(t.rawValue), \(tabCount(t))")
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("tab-\(t.rawValue.lowercased())")
            }
        }
        .padding(4)
        .background(Capsule().fill(theme.segTrack))
    }

    // MARK: Done — the first `doneShown` completions (today's count toward it), newest first,
    // struck with a done word; "Load more" adds another page (Mac renderPast).
    @ViewBuilder private var doneBody: some View {
        let page = HistoryModel.donePage(todayDone: store.doneTasks, history: store.history, shown: doneShown)
        if page.groups.isEmpty {
            emptyState("No completed tasks yet.")
        } else {
            ForEach(page.groups) { g in
                group(header: g.header) {
                    ForEach(g.lines) { line in doneRow(id: line.id, text: line.text) }
                }
            }
            if page.hasMore { loadMoreButton }
        }
    }

    private var loadMoreButton: some View {
        Button { withAnimation { doneShown += HistoryModel.donePage } } label: {
            Text("Load more")
                .font(.geist(15, .regular)).tracking(-0.30).foregroundStyle(theme.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32).padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("done-load-more")
    }

    // MARK: Future — parked tasks, oldest first (store order, like Today), then Add.
    // + add to today, × remove for good (Mac parity); tap a row's text to edit it.
    // The Add row sits right after the last row; once the list outgrows the sheet it pins
    // to the bottom and the rows scroll beneath it.
    private var keyboardOverlap: CGFloat {
        guard editingId != nil, keyboardTop.isFinite, sheetMaxY > 0 else { return 0 }
        return max(0, sheetMaxY - keyboardTop)
    }

    // Future list layout — mirrors Today's flex rows:
    //   • "Sent to today!" rows sit on TOP, compact like Today's Donezo rows (natural height).
    //   • Plain rows + the draft + the Add row SHARE the remaining height equally, each ≥ 110pt,
    //     so a short list fills the panel (no empty band at the bottom) — Today's rhythm.
    //   • Only when every flex row is at its 110pt floor and still doesn't fit does the list
    //     scroll, with Add pinned at the bottom and rows flowing under it.
    // Heights are set EXPLICITLY (not maxHeight: .infinity) so the view tree is identical in
    // both modes — switching trees mid-edit would rebuild the UITextView and drop focus.
    private enum FutureItem: Identifiable {
        case sent(DeferredTask), plain(DeferredTask), draft
        var id: String {
            switch self {
            case .sent(let d), .plain(let d): return d.id
            case .draft: return HistoryView.draftID
            }
        }
    }

    private var futureItems: [FutureItem] {
        var out = store.deferred.filter { $0.sent == true }.map { FutureItem.sent($0) }       // store order
        out += store.deferred.filter { $0.sent != true }.map { FutureItem.plain($0) }
        if editingId == Self.draftID { out.append(.draft) }
        return out
    }

    private func futureFit(height H: CGFloat, width W: CGFloat, items: [FutureItem]) -> FutureFit.Result {
        var texts: [String] = [], sent = 0
        for item in items {
            switch item {
            case .sent: sent += 1
            case .plain(let d): texts.append(editingId == d.id ? editText : d.text)
            case .draft: texts.append(editText)
            }
        }
        // While editing, overflow mode is held too (decided on the edit's first layout): the
        // field growing to 2 lines must not flip Add into the pinned bar mid-type — the list
        // just scrolls instead (Mac: the fit is frozen while a field is live).
        let editing = editingId != nil
        let held = editing ? fitMemo.heldOverflow.flatMap { $0.session == editSession ? $0.overflow : nil } : nil
        let key: [AnyHashable] = [texts, sent, H, W, heldFitStep ?? -1, held.map { $0 ? 1 : 0 } ?? -1]
        fitMemo.lastH = H; fitMemo.lastW = W
        if let cached = fitMemo.result, fitMemo.key == key { return cached }
        let r = FutureFit.compute(texts: texts, sentCount: sent, sentH: sentRowHeight,
                                  height: H, width: W, heldStep: heldFitStep, heldOverflow: held)
        if editing && held == nil { fitMemo.heldOverflow = (editSession, r.overflow) }
        fitMemo.key = key; fitMemo.result = r
        if !editing { fitMemo.lastStep = r.step }
        return r
    }

    private struct RowMidsKey: PreferenceKey {
        static var defaultValue: [String: CGFloat] = [:]
        static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    /// A row counts once at least HALF of it is under the pinned Add (one change per row while
    /// scrolling). Nothing can hide when the list doesn't overflow.
    private func updateMore(mids: [String: CGFloat], addTop: CGFloat, overflow: Bool) {
        fitMemo.lastMids = mids
        let n = overflow ? mids.values.filter { $0 > addTop }.count : 0
        let prev = moreN
        guard n != prev else { return }
        if n == 0 {                                            // fade out (0.24s), keeping the last number
            fitMemo.moreHiddenAt = Date()
            withAnimation(BuddyEase.out(0.24)) { moreN = 0 }
            return
        }
        if prev == 0 {                                         // appearing: number set first (no roll),
            var tx = Transaction(animation: nil); tx.disablesAnimations = true
            withTransaction(tx) { moreShown = n }
            withAnimation(BuddyEase.out(BuddyEase.drift)) { moreN = n }   // then Fade + Drift in (0.48s)
            return
        }
        moreN = n
        if n == moreShown { return }
        // Roll: fewer hidden (scrolling down) → up; more hidden → down. Direction renders first
        // so the outgoing number leaves the right way, then the value changes.
        moreRollUp = n < prev
        DispatchQueue.main.async { withAnimation(BuddyEase.out(0.18)) { moreShown = moreN > 0 ? moreN : moreShown } }
    }

    private var futureScroll: some View {
        GeometryReader { geo in
            // While the keyboard is up the list is shortened (padding below); keep sizing rows
            // from the pre-keyboard height so they don't jump as it rises — the list scrolls.
            // Frozen for the WHOLE edit (not just once the keyboard is up): the panel shrinks as the
            // keyboard starts rising, before keyboardOverlap reports it, and refitting to that
            // flipped a fitting list into overflow mid-type.
            let H = editingId != nil && futureLayoutHeight > 0 ? futureLayoutHeight : geo.size.height
            let items = futureItems
            let fit = futureFit(height: H, width: geo.size.width, items: items)
            let addH = fit.heights.last ?? fit.floorH
            let flexIndex = flexIndices(items)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            if i > 0 { historyDivider }
                            Group {
                                switch item {
                                case .sent(let d):
                                    sentFutureRow(id: d.id, text: d.text)
                                case .plain(let d):
                                    let h = fit.heights[flexIndex[i] ?? 0]
                                    if editingId == d.id { futureEditorRow(id: d.id, height: h, fit: fit) }
                                    else { futureRow(id: d.id, text: d.text, height: h, fit: fit) }
                                case .draft:
                                    // View-local only, no + / × actions (it isn't a task yet).
                                    futureEditorRow(id: Self.draftID, height: fit.heights[flexIndex[i] ?? 0], fit: fit)
                                }
                            }
                            .id(item.id)
                            .background(GeometryReader { g in
                                Color.clear.preference(key: RowMidsKey.self,
                                                       value: [item.id: g.frame(in: .named("futureViewport")).midY])
                            })
                        }
                        if !fit.overflow { addBlock(showDivider: !items.isEmpty, height: addH, fit: fit, proxy: nil) }
                        // Overflow: room for the pinned Add at the very end, so the last row can
                        // scroll up to sit just above it (scrollTo ignores a safeAreaInset).
                        if fit.overflow { Color.clear.frame(height: addH + 1).id(Self.endID) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .overlay(alignment: .bottom) {
                    if fit.overflow {
                        addBlock(showDivider: true, height: addH, fit: fit, proxy: proxy)
                            .background(theme.cardBackground)
                    }
                }
                .onPreferenceChange(RowMidsKey.self) { mids in
                    updateMore(mids: mids, addTop: geo.size.height - addH - 1, overflow: fit.overflow)
                }
                .onChange(of: editingId) { _, id in
                    guard let id else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.2)) { scrollToEditor(id, proxy: proxy, overflow: fit.overflow) }
                    }
                }
                .onChange(of: highlightId) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: keyboardOverlap) { _, _ in
                    // After the shortened list has laid out — scrolling in the same pass measured
                    // against the old height and went nowhere.
                    guard let id = editingId else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) { scrollToEditor(id, proxy: proxy, overflow: fit.overflow) }
                    }
                }
                // The field grows as you type — keep its last line in view (not under Add/keyboard).
                .onChange(of: editText) { _, _ in
                    guard let id = editingId else { return }
                    DispatchQueue.main.async { scrollToEditor(id, proxy: proxy, overflow: fit.overflow) }
                }
                // A draft just landed in an overflowing list → show it right above the pinned Add.
                .onChange(of: landedId) { _, id in
                    guard let id else { return }
                    landedId = nil
                    DispatchQueue.main.async {
                        if fit.overflow { proxy.scrollTo(Self.endID, anchor: .bottom) }
                        else { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
            .coordinateSpace(name: "futureViewport")
            .onAppear { if editingId == nil { futureLayoutHeight = geo.size.height } }
            .onChange(of: geo.size.height) { _, h in
                if editingId == nil && keyboardOverlap == 0 { futureLayoutHeight = h }
                // The viewport moved under the rows (keyboard) — re-count with the last row positions.
                updateMore(mids: fitMemo.lastMids, addTop: h - addH - 1, overflow: fit.overflow)
            }
        }
        // The app column ignores the keyboard, so shrink just this list while editing so
        // the field (and the pinned Add) stay above the keyboard.
        .padding(.bottom, keyboardOverlap)
    }

    private static let endID = "future-end"

    /// Keep the field in view: above the pinned Add when overflowing (the draft is last → the end
    /// spacer), else centred in what's left above the keyboard. (A .bottom anchor on a row did
    /// nothing once the keyboard shortened the list — observed; .center lands reliably.)
    private func scrollToEditor(_ id: String, proxy: ScrollViewProxy, overflow: Bool) {
        if !overflow { proxy.scrollTo(id, anchor: .center) }
        else if id == Self.draftID { proxy.scrollTo(Self.endID, anchor: .bottom) }
        else { proxy.scrollTo(id, anchor: .center) }
    }

    /// items index → index into fit.heights (flex rows only: plain + draft).
    private func flexIndices(_ items: [FutureItem]) -> [Int: Int] {
        var out: [Int: Int] = [:], k = 0
        for (i, item) in items.enumerated() {
            if case .sent = item { continue }
            out[i] = k; k += 1
        }
        return out
    }

    @ViewBuilder private func addBlock(showDivider: Bool, height: CGFloat, fit: FutureFit.Result,
                                       proxy: ScrollViewProxy?) -> some View {
        VStack(spacing: 0) {
            if showDivider { historyDivider }
            futureAddRow(height: height, fit: fit, proxy: proxy)
        }
    }

    // Same "Add +" as Today's Add row (Geist medium, −0.48-per-24pt tracking, 18pt gap, addInk),
    // at the Future rows' current fit size. While rows sit under it, the quiet "N more ↓"
    // count rides on the right (Mac: a fixed 15px beside a 24→18px Add — see FutureFit.moreFont).
    private func futureAddRow(height: CGFloat, fit: FutureFit.Result, proxy: ScrollViewProxy?) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 18) {
                Text("Add")
                Text("+")
            }
            .font(.geist(fit.font, .medium))
            .tracking(-0.02 * fit.font)
            .foregroundStyle(theme.addInk)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Add to Future")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("future-add")
            Spacer(minLength: 12)
            if let proxy {
                FutureMoreCount(shown: moreShown, visible: moreN > 0, rollUp: moreRollUp,
                                fontSize: FutureFit.moreFont(fit.step), theme: theme) {
                    // Jump to the bottom — never starts an add.
                    withAnimation(BuddyEase.out(BuddyEase.drift)) { proxy.scrollTo(Self.endID, anchor: .bottom) }
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { loc in
            // A tap aimed at "N more" while it fades must not fall through and start an add.
            let fading = Date().timeIntervalSince(fitMemo.moreHiddenAt) < 0.35
            if proxy != nil, fading, loc.x > 0.6 * moreTapWidth { return }
            startDraft()
        }
        .background(GeometryReader { g in Color.clear.onAppear { moreTapWidth = g.size.width }
            .onChange(of: g.size.width) { _, w in moreTapWidth = w } })
    }

    // Inline editor row — the same UIKit editor as Today, at the Future rows' 24pt. At least
    // 110pt, and it GROWS with long text while editing instead of clipping. It sizes from the
    // editor's own measured height (not Today's invisible-Text ghost): UITextView lines are a
    // touch taller than SwiftUI Text, so a ghost-sized box clipped the 3rd+ line.
    private func futureEditorRow(id: String, height: CGFloat, fit: FutureFit.Result) -> some View {
        let session = editSession
        let binding = Binding<String>(
            get: { editText },
            // A torn-down editor's end-editing write must never land in the NEXT edit's text.
            set: { v in if editingId == id && editSession == session { editText = v } }
        )
        return InlineTaskEditor(
            text: binding,
            fontSize: fit.font,
            textColor: UIColor(theme.escalationText),
            accessibilityIdentifier: "future-editor-\(id)",
            wrapsToProposedWidth: true,
            onCommit: { if editingId == id && editSession == session { commitFutureEdit() } }
        )
        .id(session)   // a fresh UITextView per edit — never reuse the last entry's text
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32).padding(.vertical, fit.vpad)
        .frame(minHeight: height)          // its share of the panel; grows past it for long text
    }

    private func startDraft() {
        commitFutureEdit()                 // a draft with text is kept; an empty one is dropped
        openFutureRowID = nil
        editText = ""
        editOriginal = nil
        editSession += 1
        heldFitStep = freshStep(withDraft: true)   // hold the size while typing (Mac: futureFit held mid-edit)
        editingId = Self.draftID
        store.isEditingFuture = true       // sync adopt + rollover wait until this edit ends
    }

    private func startFutureEdit(id: String, text: String) {
        commitFutureEdit()
        openFutureRowID = nil
        editText = text                    // keep the existing text (don't blank the row)
        editOriginal = text
        editSession += 1
        heldFitStep = freshStep(withDraft: false)
        editingId = id
        store.isEditingFuture = true       // sync adopt + rollover wait until this edit ends
    }

    /// The step a FRESH fit would pick right now — after any previous edit was committed, and
    /// counting the new draft row (Mac: render → fitFuture runs before the new field is live).
    /// Never the previous edit's held step.
    private func freshStep(withDraft: Bool) -> Int {
        guard fitMemo.lastH > 0, fitMemo.lastW > 0 else { return fitMemo.lastStep }
        let plain = store.deferred.filter { $0.sent != true }.map(\.text) + (withDraft ? [""] : [])
        let sent = store.deferred.count - store.deferred.filter { $0.sent != true }.count
        return FutureFit.compute(texts: plain, sentCount: sent, sentH: sentRowHeight,
                                 height: fitMemo.lastH, width: fitMemo.lastW).step
    }

    /// Commit whatever is being edited. Draft → addDeferred (rejects blank); existing row →
    /// editDeferred (empty deletes + tombstones; a change bumps v). Idempotent.
    private func commitFutureEdit(immediate: Bool = false) {
        guard let id = editingId else {
            if store.isEditingFuture { store.isEditingFuture = false }   // never leave sync wedged
            return
        }
        let text = editText
        let original = editOriginal
        editingId = nil
        editText = ""
        editOriginal = nil
        heldFitStep = nil                  // re-fit once the edit lands
        store.isEditingFuture = false      // edit over — the next sync pass may adopt again
        var duplicateOf: String? = nil
        withoutAnimation {
            if id == Self.draftID {
                switch store.addDeferred(text: text, immediate: immediate) {
                case .duplicate(let existing)?: duplicateOf = existing
                case .added(let newId)?: landedId = newId
                case nil: break
                }
            } else {
                store.editDeferred(id: id, text: text, original: original, immediate: immediate)
            }
        }
        if let existing = duplicateOf { flashDuplicate(existing) }
    }

    // Already in Future under the same title → nothing added; point at the existing row instead.
    private func flashDuplicate(_ id: String) {
        highlightId = nil
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) { highlightId = id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if highlightId == id { withAnimation(.easeOut(duration: 0.4)) { highlightId = nil } }
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

    // Future rows use the Today row visual language at the list's current fit size.
    private func futureRow(id: String, text: String, height: CGFloat, fit: FutureFit.Result) -> some View {
        SwipeableRow(
            rowID: id,
            openRowID: $openFutureRowID,
            theme: theme,
            onAdd: store.atHardCap ? nil : { withoutAnimation { store.wakeDeferredTask(id: id) } },
            onDelete: { withoutAnimation { store.deleteDeferred(id: id) } },
            onTap: { startFutureEdit(id: id, text: text) }
        ) {
            Text(text)
                .font(.geist(fit.font, .medium)).tracking(-0.02 * fit.font).lineSpacing(FutureFit.lineSpacing)
                .foregroundStyle(theme.escalationText)
                .lineLimit(FutureFit.maxLines)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                // Duplicate-add flash: the adaptive hairline token as a soft wash (RULE 1 —
                // grey on white at lvl0/lvl1, translucent white on red at lvl2).
                .background(theme.line.opacity(highlightId == id ? 0.7 : 0))
                .accessibilityIdentifier(highlightId == id ? "future-highlight" : "future-row-\(id)")
        }
        .frame(height: height)
    }

    // A parked task already sent to today — compact like Today's Donezo rows (same
    // RowFit.doneFont/donePad at Today's 24pt/16pt fit), swipe to undo.
    private func sentFutureRow(id: String, text: String) -> some View {
        let f = RowFit.doneFont(for: 24)
        return SwipeableRow(
            rowID: id,
            openRowID: $openFutureRowID,
            theme: theme,
            onRestore: { withoutAnimation { store.unsendDeferred(id: id) } }
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Sent to today!").font(.geist(f, .semibold)).tracking(-0.02 * f)
                    .foregroundStyle(theme.escalationText).fixedSize(horizontal: true, vertical: false)
                Text(text).font(.geist(f, .regular)).tracking(-0.02 * f)
                    .foregroundStyle(theme.inkDim).lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: sentRowHeight)      // exact — the fit's floor is this same number
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

}

#Preview {
    HistoryView(store: { let s = BuddyStore(); return s }())
}
