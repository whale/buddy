import SwiftUI
import UIKit

// MARK: - TodayView
// The iPhone's main screen — a faithful port of the Mac's right-edge drawer:
// two floating rounded cards (header + list) on a neutral backdrop, set in Geist.
//   Card 1: chrome glyphs + "Buddy" · divider · big date block (numeral · weekday/month · weather)
//   Card 2: Donezo rows (top) · active task rows · Add row
// All colour comes from EscalationTheme so lvl0/lvl1/lvl2 re-theme together (RULE 1).
struct TodayView: View {

    @State private var store: BuddyStore

    // Sync (P2/P3): created once on appear; drives pull-on-foreground + debounced push.
    @State private var sync: SyncEngine?
    @Environment(\.scenePhase) private var scenePhase

    // Sheets
    @State private var showHistory  = false
    @State private var showSettings = false

    // Swipe: which row's actions are currently open (only one at a time)
    @State private var openRowID: String? = nil

    // Inline editing
    @State private var editingId: String? = nil
    @State private var editText: String   = ""

    // Adaptive row fitting (see RowFit) — recomputed when the list or its size changes.
    @State private var fit = RowFit.Result(font: 24, vpad: 16, scroll: false)

    // Celebration overlay
    @State private var showCelebration = false

    // Live weather ornament
    @State private var weather = WeatherService()

    // Morning planner (shown on a fresh/rolled day until Buddy!/Skip)
    @State private var showMorning = false

    // DEBUG override to force an escalation level in previews
    @State private var debugActiveOverride: Int? = nil
    // Screenshot harness: force the morning surface even when morningDone (so captures
    // are deterministic) and pre-fire the celebration overlay.
    private let forceMorning: Bool
    private let forceCelebration: Bool
    private let initialEditingId: String?

    init(store: BuddyStore = BuddyStore(),
         debugActiveOverride: Int? = nil,
         initialSheet: InitialSheetKind = .none,
         forceMorning: Bool = false,
         forceCelebration: Bool = false,
         initialEditingId: String? = nil) {
        _store = State(initialValue: store)
        _debugActiveOverride = State(initialValue: debugActiveOverride)
        _showHistory  = State(initialValue: initialSheet == .history)
        _showSettings = State(initialValue: initialSheet == .settings)
        _editingId = State(initialValue: initialEditingId)
        _editText = State(initialValue: store.today.items.first(where: { $0.id == initialEditingId })?.text ?? "")
        if initialEditingId != nil { store.isEditing = true }
        self.forceMorning = forceMorning
        self.forceCelebration = forceCelebration
        self.initialEditingId = initialEditingId
    }

    // MARK: Derived

    private var activeCount: Int { debugActiveOverride ?? store.activeCount }
    private var theme: EscalationTheme { EscalationTheme.from(activeCount: activeCount) }

    // MARK: Body

    var body: some View {
        ZStack {
            theme.screenBackground
                .ignoresSafeArea()
                .animation((showHistory || showSettings) ? nil : .easeInOut(duration: 0.2), value: activeCount)

            VStack(spacing: 8) {          // gap-2 between the cards
                headerCard                // date only
                // Settings/History slide up over the LIST card; the header + bottom bar stay put.
                ZStack {
                    listCard
                    if showHistory {
                        HistoryView(store: store, onClose: { withAnimation(.easeIn(duration: 0.32)) { showHistory = false } })
                            .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
                            .transition(sheetTransition)
                    }
                    if showSettings {
                        SettingsView(store: store, sync: sync, onClose: { withAnimation(.easeIn(duration: 0.32)) { showSettings = false } })
                            .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
                            .transition(sheetTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // fills the gap between header + bottom bar
                // No blanket .animation here — the per-action withAnimation curves drive the
                // slide (open .easeOut 0.42, close .easeIn 0.32) so direction stays distinct.
                // Keep the bottom bar mounted while editing. Removing it changes the list height
                // at the same moment the keyboard tries to appear, which can make SwiftUI drop and
                // reacquire focus on real devices (visible cursor flicker, keyboard not lifting).
                bottomBar                 // chrome icons + "Buddy" — bleeds off the bottom edge
                    .opacity(editingId == nil ? 1 : 0)
                    .allowsHitTesting(editingId == nil)
            }
            .padding(.horizontal, 8)     // even side gutter
            .padding(.top, 8)            // small gutter below the status-bar safe area (no more)
            .ignoresSafeArea(.container, edges: .bottom)   // bottom bar runs off the bottom edge
            // The keyboard must NOT shrink the layout: a rising keyboard changed geo.size,
            // retriggered recomputeFit mid-add and made the whole list's font flash.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation((showHistory || showSettings) ? nil : .easeInOut(duration: 0.2), value: activeCount)

            if showCelebration {
                CelebrationView(intensity: store.settings.celebrate) { showCelebration = false }
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showMorning) {
            MorningView(store: store, onDone: { showMorning = false })
        }
        .task {
            // iOS MORNING VIEW DISABLED (2026-07-08, user decision): the morning is a
            // Mac ritual for now — on the phone its text fields fought the 1.5s sync
            // adopt (tap → cursor jitter → focus lost). The phone just shows the list;
            // morningDone stays untouched so the MAC's morning still appears (it would
            // OR-merge across sync). Re-enable by restoring the gate below.
            // showMorning = forceMorning || store.needsMorning
            showMorning = forceMorning
            if forceCelebration { showCelebration = true }
            #if DEBUG
            if ScreenshotHarness.activeFixture == nil { weather.refresh() }   // no network under a fixture (deterministic shots)
            #else
            weather.refresh()
            #endif
            // Bring up the sync engine (inert until the user pairs) and pull once on launch.
            if sync == nil { sync = SyncEngine(store: store) }
            sync?.syncOnForeground()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Roll the day over BEFORE syncing — a phone suspended overnight must not
                // push a yesterday-dated blob and drag the other device back a day.
                store.performRolloverIfNeeded()
                sync?.syncOnForeground()                        // pull + go live on foreground
            }
            else { sync?.pauseSync() }                          // stop polling in the background
        }
    }

    // Sheet in/out: a vertical slide over the list card (the card stays put).
    // Open animates .easeOut (fast → slow at the top), close .easeIn (slow → fast down).
    private var sheetTransition: AnyTransition {
        .move(edge: .bottom)
    }

    // MARK: - Card 1 — date block (numeral · weekday/month · weather)

    // Baseline-aligned like the Mac (text-box-trim + items-end): the 62pt numeral's
    // baseline sits on the month line's baseline; the weather icon's bottom rests on it too.
    private var headerCard: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(dayNumber)
                    .font(.geist(62, .medium)).tracking(-1.24)
                    .foregroundStyle(theme.escalationText)
                    .lineLimit(1)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 3) {
                    Text(weekday)
                        .font(.geist(24, .medium)).tracking(-0.48)
                        .foregroundStyle(theme.escalationText)
                        .lineLimit(1)
                    Text(month)
                        .font(.geist(18, .regular)).tracking(-0.36)
                        .foregroundStyle(theme.chromeMuted)
                        .lineLimit(1)
                }
                .fixedSize()
            }
            Spacer()
            WeatherIcon(key: weather.iconKey, size: 50)
                .foregroundStyle(theme.escalationText)
                .frame(width: 50, height: 50)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }   // icon bottom on the text baseline
        }
        .padding(.leading, 32)
        .padding(.trailing, 26)
        .padding(.vertical, 32)
        .frame(height: 114, alignment: .bottom)
        .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
    }

    // MARK: - Bottom bar (Figma 41:306) — pin/calendar/gear + "Buddy".
    // Top corners rounded only; runs off the bottom edge (bleeds past the home indicator).
    private var bottomBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 30) {    // Figma gap-35 between the 20px icons
                // (Figma shows a pin here too, but it has no iPhone function — omitted for now.)
                bottomChrome("calendar", selected: showHistory) {
                    if showHistory { withAnimation(.easeIn(duration: 0.32)) { showHistory = false } }
                    else { withAnimation(.easeOut(duration: 0.42)) { showHistory = true; showSettings = false } }
                }
                bottomChrome("settings", selected: showSettings) {
                    if showSettings { withAnimation(.easeIn(duration: 0.32)) { showSettings = false } }
                    else { withAnimation(.easeOut(duration: 0.42)) { showSettings = true; showHistory = false } }
                }
            }
            Spacer()
            Button {
                withAnimation(.easeIn(duration: 0.32)) {
                    showHistory = false
                    showSettings = false
                }
            } label: {
                Text("Buddy")
                    .font(.geist(18, .regular)).tracking(-0.36)
                    .foregroundStyle(theme.chromeMuted)
                    .frame(minWidth: 80, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .padding(.top, 26)
        .padding(.bottom, 36)        // extends past the home-indicator area → bleed (−8pt shorter)
        .frame(maxWidth: .infinity)
        .background(
            theme.cardBackground,
            in: UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 0, topTrailingRadius: 24, style: .continuous)
        )
        .shadow(color: theme.level != .lvl2 ? .black.opacity(0.06) : .clear, radius: 8, y: -2)
    }

    private func bottomChrome(_ icon: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: 20)
                .foregroundStyle(selected ? theme.selInk : theme.chromeInk)
                .frame(width: 34, height: 34, alignment: .center)
                .background(selected ? theme.selBg : .clear, in: Circle())   // filled circle when active
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card 2 — task list

    private var listCard: some View {
        GeometryReader { geo in
            let rows = store.doneTasks + store.activeTasks   // Donezo first, then active
            // The list content. Rows flex-fill to share the column height equally when there's
            // room; when the fit falls to its floor and still overflows, we scroll instead of clip.
            let content = VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, task in
                    if i > 0 { rowDivider }
                    Group {
                        if task.isDone { doneRowView(task: task) } else { activeRowView(task: task) }
                    }
                    .transition(.opacity)
                }
                if !store.atHardCap {
                    if !rows.isEmpty { rowDivider }
                    addRow
                }
            }
            Group {
                if fit.scroll {
                    ScrollView { content.frame(maxWidth: .infinity, alignment: .top) }
                } else {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .animation((showHistory || showSettings) ? nil : .easeOut(duration: 0.3), value: store.today.items)
            .onAppear { recomputeFit(geo.size) }
            .onChange(of: store.today.items) { _, _ in recomputeFit(geo.size) }
            .onChange(of: geo.size) { _, _ in recomputeFit(geo.size) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
    }

    private func recomputeFit(_ size: CGSize) {
        let active = store.activeTasks.map(\.text)
        let done = store.doneTasks.map(\.text)
        let next = RowFit.compute(active: active, done: done,
                                  height: size.height, width: size.width,
                                  includesAdd: !store.atHardCap)
        guard next != fit else { return }   // no-op when nothing changed — no redundant re-render
        // Apply fit WITHOUT animation: the uniform font/vpad must snap, never ping-pong.
        // (Row insert/remove keeps its own transition; only the fit values are exempt.)
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { fit = next }
    }

    private var rowDivider: some View {
        Rectangle().fill(theme.line).frame(height: 1)
    }

    // MARK: - Active row — tap the text to edit (Mac idiom); swipe for Complete / Sleep / Delete.
    @ViewBuilder
    private func activeRowView(task: BuddyTask) -> some View {
        // Flex-fill rows to share the column when there's room; natural height when scrolling.
        let fillH: CGFloat? = fit.scroll ? nil : .infinity
        if editingId == task.id {
            InlineTaskEditor(
                text: $editText,
                fontSize: fit.font,
                textColor: UIColor(theme.escalationText),
                accessibilityIdentifier: "task-editor-\(task.id)",
                onCommit: { commitEdit(id: task.id) }
            )
            .padding(.horizontal, 32).padding(.vertical, fit.vpad)
            .frame(maxWidth: .infinity, maxHeight: fillH, alignment: .leading)
        } else {
            SwipeableRow(
                rowID: task.id,
                openRowID: $openRowID,
                theme: theme,
                onComplete: { handleComplete(task: task) },
                onSleep:    { withAnimation { store.deferToTomorrow(id: task.id) } },
                onDelete:   { withAnimation { store.deleteTask(id: task.id) } },
                onTap:      { startEdit(task: task) }
            ) {
                Text(task.text.isEmpty ? "Untitled" : task.text)
                    .font(.geist(fit.font, .medium)).tracking(-0.48).lineSpacing(2)
                    .foregroundStyle(task.text.isEmpty ? theme.inkDim : theme.escalationText)
                    .frame(maxWidth: .infinity, maxHeight: fillH, alignment: .leading)
                    .padding(.horizontal, 32).padding(.vertical, fit.vpad)
            }
            .frame(maxWidth: .infinity, maxHeight: fillH)
        }
    }

    // MARK: - Done (Donezo) row — ink / inkDim, so it follows THE PATTERN (red at lvl1 too).
    @ViewBuilder
    private func doneRowView(task: BuddyTask) -> some View {
        // Compact done row with a STABLE revert icon on the right (no swipe). Its right edge
        // sits at the row's 32pt trailing gutter — same as the weather icon's right edge.
        let doneFont = RowFit.doneFont(for: fit.font)
        let doneTracking = -0.02 * doneFont
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DoneWords.word(for: task.id))
                .font(.geist(doneFont, .semibold))
                .tracking(doneTracking)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: true, vertical: false)
            Text(task.text)
                .font(.geist(doneFont, .regular))
                .tracking(doneTracking)
                .strikethrough(true, color: theme.inkDim)
                .foregroundStyle(theme.inkDim)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button { withAnimation(.easeOut(duration: 0.3)) { store.restoreTask(id: task.id) } } label: {
                LucideIcon("undo", size: 18)
                    .foregroundStyle(theme.inkDim)
                    .frame(width: 22, height: 22, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, RowFit.donePad(for: fit.vpad))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Add row
    private var addRow: some View {
        HStack(spacing: 18) {
            Text("Add")
            Text("+")
        }
        .font(.geist(fit.font, .medium))
        .tracking(-0.48)
        .foregroundStyle(theme.addInk)
        .padding(.horizontal, 32)
        .padding(.top, fit.vpad)
        .padding(.bottom, fit.vpad + RowFit.addBottomExtra)
        .frame(maxWidth: .infinity, maxHeight: fit.scroll ? nil : .infinity, alignment: .leading)   // flex like the active rows
        .contentShape(Rectangle())
        .onTapGesture { addTask() }
    }

    // MARK: - Interactions

    private func handleComplete(task: BuddyTask) {
        let didComplete = withAnimation(.easeOut(duration: 0.3)) { store.complete(task) }
        if didComplete && store.settings.celebrate > 0 {
            withAnimation { showCelebration = true }
        }
    }

    private func addTask() {
        let newId = withAnimation(.easeOut(duration: 0.28)) { store.addTask() }
        if let newId {
            editText = ""
            editingId = newId
            store.isEditing = true          // sync adopt() defers while a row edit is in flight
        }
    }

    private func startEdit(task: BuddyTask) {
        editText = task.text            // keep the existing text (don't blank the row)
        editingId = task.id
        store.isEditing = true          // sync adopt() defers while a row edit is in flight
    }

    private func commitEdit(id: String) {
        guard editingId == id else { return }
        let text = editText
        editingId = nil
        store.isEditing = false         // edit committed — the next sync pass may adopt again
        store.commitEdit(id: id, text: text)
    }

    // MARK: - Date + weather helpers

    private var weekday: String   { Self.df("EEEE") }
    private var month: String     { Self.df("MMMM") }
    private var dayNumber: String { Self.df("d") }

    private static func df(_ fmt: String) -> String {
        let f = DateFormatter(); f.dateFormat = fmt; return f.string(from: Date())
    }

}

// Kept in this file so the app target sees it even in release (harness uses a DEBUG-gated variant).
enum InitialSheetKind { case none, history, settings }

// MARK: - UIKit-backed inline editor
// SwiftUI FocusState was unstable here on device: the row could flicker between focused
// and unfocused while the keyboard was trying to rise. This tiny UIKit bridge gives the
// task editor one native first-responder owner, so the keyboard has a stable anchor.
private struct InlineTaskEditor: UIViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let textColor: UIColor
    let accessibilityIdentifier: String
    let onCommit: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        context.coordinator.textView = view
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.returnKeyType = .done
        view.autocorrectionType = .default
        view.autocapitalizationType = .sentences
        view.accessibilityIdentifier = accessibilityIdentifier

        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.accessibilityIdentifier = accessibilityIdentifier
        view.font = UIFont(name: "Geist-Medium", size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .medium)
        view.textColor = textColor
        if !view.isFirstResponder && view.text != text { view.text = text }
        if !view.isFirstResponder {
            DispatchQueue.main.async {
                view.becomeFirstResponder()
                view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: InlineTaskEditor
        weak var textView: UITextView?
        private var hasCommitted = false

        init(parent: InlineTaskEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            commitCurrentText(textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n" {
                commitCurrentText(textView)
                textView.resignFirstResponder()
                return false
            }
            return true
        }

        private func commitCurrentText(_ textView: UITextView) {
            guard !hasCommitted else { return }
            hasCommitted = true
            parent.text = textView.text
            parent.onCommit()
        }
    }
}

// MARK: - Previews
#Preview("lvl0")  { TodayView(store: seeded(MockData.normalTasks)) }
#Preview("lvl1")  { TodayView(store: seeded(MockData.warningTasks)) }
#Preview("lvl2")  { TodayView(store: seeded(MockData.alarmTasks)) }
#Preview("empty") { TodayView(store: seeded([])) }

private func seeded(_ tasks: [BuddyTask]) -> BuddyStore {
    let s = BuddyStore()
    #if DEBUG
    s.seedForScreenshot(tasks: tasks)
    #endif
    return s
}
