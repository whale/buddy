import SwiftUI

// MARK: - TodayView
// The iPhone's main screen — a faithful port of the Mac's right-edge drawer:
// two floating rounded cards (header + list) on a neutral backdrop, set in Geist.
//   Card 1: chrome glyphs + "Buddy" · divider · big date block (numeral · weekday/month · weather)
//   Card 2: Donezo rows (top) · active task rows · Add row
// All colour comes from EscalationTheme so lvl0/lvl1/lvl2 re-theme together (RULE 1).
struct TodayView: View {

    @State private var store: BuddyStore

    // Sheets
    @State private var showHistory  = false
    @State private var showSettings = false

    // Inline editing
    @State private var editingId: String? = nil
    @State private var editText: String   = ""
    @FocusState private var focusedField: String?

    // Celebration overlay
    @State private var showCelebration = false

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

            VStack(spacing: 8) {          // gap-2 between the two cards
                headerCard
                // Settings/History slide up over the LIST card only — the header card (with
                // the now-selected chrome icon) stays visible, exactly like the Mac.
                ZStack {
                    listCard
                    if showHistory {
                        HistoryView(store: store, onClose: { withAnimation(.easeOut(duration: 0.28)) { showHistory = false } })
                            .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if showSettings {
                        SettingsView(store: store, onClose: { withAnimation(.easeOut(duration: 0.28)) { showSettings = false } })
                            .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 10)     // ≈ the Mac drawer's p-2 gutter
            .padding(.top, 8)
            .padding(.bottom, 10)
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
        }
    }

    // MARK: - Card 1 — chrome row + date block

    private var headerCard: some View {
        VStack(spacing: 0) {
            // chrome row: pin / history / gear on the left, "Buddy" on the right
            HStack(spacing: 2) {
                ChromeButton("pin", size: 15, ink: theme.chromeInk) {}
                ChromeButton("calendar", size: 16, ink: theme.chromeInk,
                             selected: showHistory, selBg: theme.selBg, selInk: theme.selInk) {
                    withAnimation(.easeOut(duration: 0.28)) { showHistory.toggle(); showSettings = false }
                }
                ChromeButton("gearshape", size: 17, ink: theme.chromeInk,
                             selected: showSettings, selBg: theme.selBg, selInk: theme.selInk) {
                    withAnimation(.easeOut(duration: 0.28)) { showSettings.toggle(); showHistory = false }
                }
                Spacer()
                Text("Buddy")
                    .font(.geist(18, .regular))
                    .tracking(-0.36)
                    .foregroundStyle(theme.chromeMuted)
            }
            .padding(.leading, 18)
            .padding(.trailing, 24)
            .padding(.vertical, 12)

            Rectangle().fill(theme.line).frame(height: 1)

            // date block: numeral (left) · weekday/month · weather (right)
            HStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text(dayNumber)
                        .font(.geist(62, .medium))
                        .tracking(-1.24)
                        .foregroundStyle(theme.escalationText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(weekday)
                            .font(.geist(24, .medium))
                            .tracking(-0.48)
                            .foregroundStyle(theme.escalationText)
                        Text(month)
                            .font(.geist(18, .regular))
                            .tracking(-0.36)
                            .foregroundStyle(theme.chromeMuted)
                    }
                    .padding(.bottom, 4)   // optical baseline nudge toward the numeral
                }
                Spacer()
                Image(systemName: weatherSymbol)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(theme.escalationText)
                    .frame(width: 50, height: 50)
            }
            .padding(.leading, 28)
            .padding(.trailing, 24)
            .padding(.vertical, 24)
        }
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
                if task.isDone { doneRowView(task: task) } else { activeRowView(task: task) }
            }
            if !store.atHardCap {
                if !rows.isEmpty { rowDivider }
                addRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .buddyCard(fill: theme.cardBackground, shadow: theme.level != .lvl2)
    }

    private var rowDivider: some View {
        Rectangle().fill(theme.line).frame(height: 1)
    }

    // MARK: - Active row — clean text at rest (Mac idiom). Tap completes; long-press edits.
    @ViewBuilder
    private func activeRowView(task: BuddyTask) -> some View {
        Group {
            if editingId == task.id {
                TextField("", text: $editText, axis: .vertical)
                    .font(.geist(19, .medium))
                    .tracking(-0.48)
                    .foregroundStyle(theme.escalationText)
                    .submitLabel(.done)
                    .focused($focusedField, equals: task.id)
                    .onSubmit { commitEdit(id: task.id) }
                    .onChange(of: focusedField) { _, v in
                        if v != task.id && editingId == task.id { commitEdit(id: task.id) }
                    }
            } else {
                Text(task.text.isEmpty ? "Untitled" : task.text)
                    .font(.geist(19, .medium))
                    .tracking(-0.48)
                    .lineSpacing(2)
                    .foregroundStyle(task.text.isEmpty ? theme.inkDim : theme.escalationText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)   // flex:1 1 auto — equal share of leftover height
        .contentShape(Rectangle())
        .onTapGesture { if editingId == nil { handleComplete(task: task) } }
        .contextMenu {
            Button { startEdit(task: task) } label: { Label("Edit", systemImage: "pencil") }
            Button { store.deferToTomorrow(id: task.id) } label: { Label("Move to Future", systemImage: "moon.zzz") }
            Button(role: .destructive) { store.deleteTask(id: task.id) } label: { Label("Remove", systemImage: "trash") }
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
        .padding(.horizontal, 24)
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
        .font(.geist(19, .medium))
        .tracking(-0.48)
        .foregroundStyle(theme.addInk)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)   // flex:1 1 auto — matches the active rows
        .contentShape(Rectangle())
        .onTapGesture { addTask() }
    }

    // MARK: - Interactions

    private func handleComplete(task: BuddyTask) {
        let didComplete = store.complete(task)
        if didComplete && store.settings.celebrate > 0 {
            withAnimation { showCelebration = true }
        }
    }

    private func addTask() {
        if let newId = store.addTask() {
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

    // Placeholder glyph (a moon) matching the Mac's night state. Live weather is a
    // separate feature (Open-Meteo fetch) not yet ported to iOS.
    private var weatherSymbol: String { "moon" }
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
