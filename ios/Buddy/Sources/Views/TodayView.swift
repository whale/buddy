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
                bottomBar                 // chrome icons + "Buddy"
            }
            .padding(.horizontal, 8)     // even gutter all around
            .padding(.vertical, 8)
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
        HStack(alignment: .bottom) {
            // numeral + weekday/month, baseline-aligned like the Mac (items-end, leading-none)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(dayNumber)
                    .font(.geist(62, .medium)).tracking(-1.24)
                    .foregroundStyle(theme.escalationText)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 12) {   // gap-3 like the Mac (was 4)
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
            WeatherIcon(key: weather.iconKey, size: 50)   // fills the 50px box (was 40)
                .foregroundStyle(theme.escalationText)
                .frame(width: 50, height: 50)
        }
        .padding(.leading, 32).padding(.trailing, 26).padding(.vertical, 30)
        .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
    }

    // MARK: - Bottom bar — chrome icons + "Buddy" (moved out of the header)
    private var bottomBar: some View {
        HStack(spacing: 10) {
            ChromeButton("calendar", size: 18, ink: theme.chromeInk,
                         selected: showHistory, selBg: theme.selBg, selInk: theme.selInk) {
                withAnimation(.easeOut(duration: 0.28)) { showHistory.toggle(); showSettings = false }
            }
            ChromeButton("settings", size: 19, ink: theme.chromeInk,
                         selected: showSettings, selBg: theme.selBg, selInk: theme.selInk) {
                withAnimation(.easeOut(duration: 0.28)) { showSettings.toggle(); showHistory = false }
            }
            Spacer()
            Text("Buddy")
                .font(.geist(18, .regular)).tracking(-0.36)
                .foregroundStyle(theme.chromeMuted)
        }
        .padding(.leading, 22).padding(.trailing, 28).padding(.vertical, 14)
        .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
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
                .font(.geist(22, .medium)).tracking(-0.48)
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
                cardFill: theme.cardBackground,
                onComplete: { handleComplete(task: task) },
                onSleep:    { withAnimation { store.deferToTomorrow(id: task.id) } },
                onDelete:   { withAnimation { store.deleteTask(id: task.id) } },
                onTap:      { startEdit(task: task) }
            ) {
                Text(task.text.isEmpty ? "Untitled" : task.text)
                    .font(.geist(22, .medium)).tracking(-0.48).lineSpacing(2)
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
        .onTapGesture { store.restoreTask(id: task.id) }
        .contextMenu {
            Button { store.restoreTask(id: task.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { store.deleteTask(id: task.id) } label: { Label("Remove", systemImage: "trash") }
        }
    }

    // MARK: - Add row
    private var addRow: some View {
        HStack(spacing: 18) {
            Text("Add")
            Text("+")
        }
        .font(.geist(22, .medium))
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
