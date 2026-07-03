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
    @FocusState private var focusedField: String?

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

    init(store: BuddyStore = BuddyStore(),
         debugActiveOverride: Int? = nil,
         initialSheet: InitialSheetKind = .none,
         forceMorning: Bool = false,
         forceCelebration: Bool = false) {
        _store = State(initialValue: store)
        _debugActiveOverride = State(initialValue: debugActiveOverride)
        _showHistory  = State(initialValue: initialSheet == .history)
        _showSettings = State(initialValue: initialSheet == .settings)
        self.forceMorning = forceMorning
        self.forceCelebration = forceCelebration
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
                bottomBar                 // chrome icons + "Buddy" — bleeds off the bottom edge
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
            showMorning = forceMorning || store.needsMorning
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
            if phase == .active { sync?.syncOnForeground() }   // pull + go live on foreground
            else { sync?.pauseSync() }                          // stop polling in the background
        }
    }

    // Sheet in/out: slide UP from below on open, slide DOWN on close (symmetric).
    private var sheetTransition: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }

    // MARK: - Card 1 — date block (numeral · weekday/month · weather)

    private var headerCard: some View {
        HStack(alignment: .center) {   // Figma 41:286: fixed 114h, items-center
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(dayNumber)
                    .font(.geist(62, .medium)).tracking(-1.24)
                    .foregroundStyle(theme.escalationText)
                    .fixedSize()
                    // The 62pt numeral's font descent drops its baseline ~12pt below the month's,
                    // so it hangs low. Nudge its reported baseline down → SwiftUI lifts the glyph
                    // up, bottom-aligning it with the month like the Figma.
                    .alignmentGuide(.lastTextBaseline) { $0[.lastTextBaseline] + 12 }
                VStack(alignment: .leading, spacing: 12) {   // gap-3 (Figma)
                    Text(weekday)
                        .font(.geist(24, .medium)).tracking(-0.48)
                        .foregroundStyle(theme.escalationText)
                    Text(month)
                        .font(.geist(18, .regular)).tracking(-0.36)
                        .foregroundStyle(theme.chromeMuted)
                }
                .fixedSize()
            }
            Spacer()
            WeatherIcon(key: weather.iconKey, size: 50)
                .foregroundStyle(theme.escalationText)
                .frame(width: 50, height: 50)
        }
        .padding(.horizontal, 32)
        .frame(height: 114)          // Figma fixed header height
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
            Text("Buddy")
                .font(.geist(18, .regular)).tracking(-0.36)
                .foregroundStyle(theme.chromeMuted)
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
        let rows = store.doneTasks + store.activeTasks   // Donezo first, then active
        // Mac flex logic: done rows are compact (flex:0 0 auto); active rows + the Add row
        // stretch to share the leftover height EQUALLY (flex:1 1 auto). So the whole list
        // fills the viewport with no scroll and every undone row is the same height.
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, task in
                if i > 0 { rowDivider }
                Group {
                    if task.isDone { doneRowView(task: task) } else { activeRowView(task: task) }
                }
                .transition(.opacity)   // rows fade in/out; the reorder to Donezo glides (below)
            }
            if !store.atHardCap {
                if !rows.isEmpty { rowDivider }
                addRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
        // Item changes (complete→glide to Donezo, add, delete) animate; done→Donezo morph.
        .animation(.easeOut(duration: 0.3), value: store.today.items)
    }

    private var rowDivider: some View {
        Rectangle().fill(theme.line).frame(height: 1)
    }

    // MARK: - Active row — tap the text to edit (Mac idiom); swipe for Complete / Sleep / Delete.
    @ViewBuilder
    private func activeRowView(task: BuddyTask) -> some View {
        if editingId == task.id {
            TextField("", text: $editText, axis: .vertical)
                .font(.geist(24, .medium)).tracking(-0.48)
                .foregroundStyle(theme.escalationText)
                .submitLabel(.done)
                .focused($focusedField, equals: task.id)
                .onSubmit { commitEdit(id: task.id) }
                .onChange(of: focusedField) { _, v in
                    if v != task.id && editingId == task.id { commitEdit(id: task.id) }
                }
                .padding(.horizontal, 32).padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                    .font(.geist(24, .medium)).tracking(-0.48).lineSpacing(2)
                    .foregroundStyle(task.text.isEmpty ? theme.inkDim : theme.escalationText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 32).padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // flex:1 1 auto — equal share of leftover height
        }
    }

    // MARK: - Done (Donezo) row — neutral + adaptive (ink / inkDim, never escalation red).
    @ViewBuilder
    private func doneRowView(task: BuddyTask) -> some View {
        SwipeableRow(
            rowID: task.id,
            openRowID: $openRowID,
            cardFill: theme.cardBackground,
            onRestore: { withAnimation(.easeOut(duration: 0.3)) { store.restoreTask(id: task.id) } },
            onTap: { store.restoreTask(id: task.id) }   // tap also restores
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DoneWords.word(for: task.id))
                    .font(.geist(15, .semibold))
                    .tracking(-0.30)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: true, vertical: false)
                Text(task.text)
                    .font(.geist(15, .regular))
                    .tracking(-0.30)
                    .strikethrough(true, color: theme.inkDim)
                    .foregroundStyle(theme.inkDim)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Add row
    private var addRow: some View {
        HStack(spacing: 18) {
            Text("Add")
            Text("+")
        }
        .font(.geist(24, .medium))
        .tracking(-0.48)
        .foregroundStyle(theme.addInk)
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)   // flex:1 1 auto — matches the active rows
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = newId }
        }
    }

    private func startEdit(task: BuddyTask) {
        editText = task.text
        editingId = task.id
        focusedField = task.id
    }

    private func commitEdit(id: String) {
        guard editingId == id else { return }
        let text = editText
        editingId = nil
        focusedField = nil
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
