import SwiftUI

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
    @State private var focusRetry = 0        // diagnostic count for silent @FocusState detach bounces
    @FocusState private var focusedField: String?

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
                .animation(.easeInOut(duration: 0.2), value: activeCount)

            VStack(spacing: 8) {          // gap-2 between the cards
                headerCard                // date only
                // Settings/History slide up over the LIST card; the header + bottom bar stay put.
                ZStack {
                    listCard
                    if showHistory {
                        HistoryView(store: store, onClose: { withAnimation(.easeOut(duration: 0.28)) { showHistory = false } })
                            .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
                            .transition(sheetTransition)
                    }
                    if showSettings {
                        SettingsView(store: store, sync: sync, onClose: { withAnimation(.easeOut(duration: 0.28)) { showSettings = false } })
                            .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
                            .transition(sheetTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // fills the gap between header + bottom bar
                // Drive the sheet transitions on open AND close (slide up / slide down).
                .animation(.easeOut(duration: 0.3), value: showSettings)
                .animation(.easeOut(duration: 0.3), value: showHistory)
                // While editing, the keyboard covers the bottom bar anyway — hide it so the list
                // reclaims that height for the row being typed.
                if editingId == nil {
                    bottomBar             // chrome icons + "Buddy" — bleeds off the bottom edge
                }
            }
            .padding(.horizontal, 8)     // even side gutter
            .padding(.top, 8)            // small gutter below the status-bar safe area (no more)
            .ignoresSafeArea(.container, edges: .bottom)   // bottom bar runs off the bottom edge
            .animation(.easeInOut(duration: 0.2), value: activeCount)

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
            if let initialEditingId {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = initialEditingId }
            }
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

    // Sheet in/out: just present (a quick fade), no slide.
    private var sheetTransition: AnyTransition {
        .opacity
    }

    // MARK: - Card 1 — date block (numeral · weekday/month · weather)

    private var headerCard: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 12) {
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
                .padding(.bottom, 4)
            }
            Spacer()
            WeatherIcon(key: weather.iconKey, size: 50)
                .foregroundStyle(theme.escalationText)
                .frame(width: 50, height: 50)
                .padding(.bottom, 4)
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
                    withAnimation(.easeOut(duration: 0.28)) { showHistory.toggle(); showSettings = false }
                }
                bottomChrome("settings", selected: showSettings) {
                    withAnimation(.easeOut(duration: 0.28)) { showSettings.toggle(); showHistory = false }
                }
            }
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.28)) {
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
            .animation(.easeOut(duration: 0.3), value: store.today.items)
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
        if next != fit { fit = next }
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
            TextField("", text: $editText, axis: .vertical)
                .font(.geist(fit.font, .medium)).tracking(-0.48)
                .foregroundStyle(theme.escalationText)
                .submitLabel(.done)
                .focused($focusedField, equals: task.id)
                .onSubmit { commitEdit(id: task.id) }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { commitEdit(id: task.id) }
                    }
                }
                .onChange(of: focusedField) { _, v in
                    guard v != task.id && editingId == task.id else { return }
                    // iOS can briefly detach @FocusState while the keyboard appears, the
                    // row reflows, or sync/status changes cause a render. Treat that as
                    // a focus bounce, not as "editing is done". The prior fix still
                    // committed after two bounces / 0.5s, which is why the field visibly
                    // jittered and reverted on real devices. Only Return/Done commits.
                    focusRetry += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        if editingId == task.id { focusedField = task.id }
                    }
                }
                .padding(.horizontal, 32).padding(.vertical, fit.vpad)
                .frame(maxWidth: .infinity, maxHeight: fillH, alignment: .leading)
        } else {
            SwipeableRow(
                rowID: task.id,
                openRowID: $openRowID,
                cardFill: theme.cardBackground,
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

    // MARK: - Done (Donezo) row — neutral + adaptive (ink / inkDim, never escalation red).
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
            focusRetry = 0
            store.isEditing = true          // sync adopt() defers while a row edit is in flight
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = newId }
        }
    }

    private func startEdit(task: BuddyTask) {
        editText = task.text            // keep the existing text (don't blank the row)
        editingId = task.id
        focusRetry = 0
        store.isEditing = true          // sync adopt() defers while a row edit is in flight
        // Focus AFTER the TextField exists in the hierarchy. Setting @FocusState synchronously
        // (before the row swaps from label → field) silently fails to attach — the field shows
        // but the keyboard/cursor never lands, and the empty focus binding can bounce editingId
        // back, blanking the row. The add-task path uses the same deferred-focus trick.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = task.id }
    }

    private func commitEdit(id: String) {
        guard editingId == id else { return }
        let text = editText
        editingId = nil
        focusedField = nil
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
