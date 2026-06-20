import SwiftUI

// MARK: - TodayView
// The iPhone's main screen. A date header, active task list, Donezo section,
// an Add row, and toolbar buttons for history + settings.
// All colours come from EscalationTheme — never hardcoded.
struct TodayView: View {

    @State private var store = BuddyStore()

    // Sheet state
    @State private var showHistory  = false
    @State private var showSettings = false

    // Inline editing
    @State private var editingId: String? = nil
    @State private var editText: String   = ""

    // New task that should auto-focus
    @State private var pendingFocusId: String? = nil

    // Celebration overlay
    @State private var showCelebration = false

    // Morning planner (shown on a fresh/rolled day until Buddy!/Skip)
    @State private var showMorning = false

    // DEBUG: force an escalation level in previews
    @State var debugActiveOverride: Int? = nil

    init(debugActiveOverride: Int? = nil) {
        _debugActiveOverride = State(initialValue: debugActiveOverride)
    }

    // MARK: Computed state

    private var activeCount: Int {
        debugActiveOverride ?? store.activeCount
    }

    private var theme: EscalationTheme {
        EscalationTheme.from(activeCount: activeCount)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            theme.cardBackground
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.2), value: activeCount)

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        dateHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        taskCard
                            .padding(.horizontal, 16)

                        Spacer(minLength: 40)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(theme.cardBackground)
                .animation(.easeInOut(duration: 0.2), value: activeCount)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
            }
            .tint(theme.ink)

            // Celebration overlay
            if showCelebration {
                CelebrationView(intensity: store.settings.celebrate) {
                    showCelebration = false
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showHistory)  { HistoryView(store: store) }
        .sheet(isPresented: $showSettings) { SettingsView(store: store) }
        .fullScreenCover(isPresented: $showMorning) {
            MorningView(store: store, onDone: { showMorning = false })
        }
        // Show the planner on a fresh/rolled day. Runs once on appear — ACCEPTED GAP:
        // an app left open across midnight won't re-show the morning until next launch
        // (the Mac re-runs rollover on focus/interval; iOS live-rollover is a later item).
        .task { showMorning = store.needsMorning }
    }

    // MARK: - Date header

    // Mac-style header: weekday + month stacked on the left, giant numeral on the right.
    private var dateHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: -2) {
                Text(currentWeekday)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.ink)
                Text(currentMonth)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(theme.inkDim)
            }
            Spacer()
            Text(currentDayNumber)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(theme.ink)
        }
    }

    // The bordered rounded card holding Donezo (top) + active tasks + Add (Mac model).
    private var taskCard: some View {
        let rows = store.doneTasks + store.activeTasks   // Donezo first, then active
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
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
        .shadow(color: theme.level == .lvl2 ? .clear : Color.black.opacity(0.06), radius: 12, y: 6)
    }

    private var rowDivider: some View {
        Rectangle().fill(theme.line).frame(height: 1)
    }

    // MARK: - Active task row
    // Check-off circle completes; tapping the body cycles (focus → done); tapping the
    // text edits; long-press opens edit/sleep/delete (swipeActions don't work outside a List).
    @ViewBuilder
    private func activeRowView(task: BuddyTask) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Check-off circle — the discoverable "mark done" affordance.
            Button { handleComplete(task: task) } label: {
                Circle()
                    .strokeBorder(theme.escalationText.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            if editingId == task.id {
                TextField("", text: $editText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.escalationText)
                    .submitLabel(.done)
                    .focused($focusedField, equals: task.id)
                    .onSubmit { commitEdit(id: task.id) }
                    .onChange(of: focusedField) { _, newVal in
                        if newVal != task.id && editingId == task.id {
                            commitEdit(id: task.id)
                        }
                    }
            } else {
                Text(task.text.isEmpty ? "Untitled" : task.text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(task.text.isEmpty ? theme.inkDim : theme.escalationText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { startEdit(task: task) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // The focused task is your "now" — fill it so you can see it at a glance (mirrors the Mac).
        .background(task.state == .focused ? theme.focusFill : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if editingId == nil { handleCycle(task: task) } }
        .contextMenu {
            Button { startEdit(task: task) } label: { Label("Edit", systemImage: "pencil") }
            Button { store.deferToTomorrow(id: task.id) } label: { Label("Sleep till tomorrow", systemImage: "moon.zzz") }
            Button(role: .destructive) { store.deleteTask(id: task.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - Done (Donezo) row — neutral + adaptive (inkDim, not escalationText).
    // Filled circle (tap to restore) + inline struck "Donezo. <title>" like the Mac.
    @ViewBuilder
    private func doneRowView(task: BuddyTask) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { store.restoreTask(id: task.id) } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(theme.inkDim)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.atHardCap)

            HStack(spacing: 6) {
                Text("Donezo.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(task.text)
                    .font(.system(size: 15))
                    .strikethrough(true, color: theme.inkDim)
                    .foregroundStyle(theme.inkDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .contextMenu {
            Button { store.restoreTask(id: task.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { store.deleteTask(id: task.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - Add row
    private var addRow: some View {
        HStack(spacing: 18) {
            Text("Add")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.inkDim)
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.inkDim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { addTask() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // History (calendar icon) — hidden if historyDays is 0
        if store.settings.historyDays > 0 {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(theme.ink)
                }
            }
        }

        // Settings (gear icon)
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(theme.ink)
            }
        }
    }

    // MARK: - Focus state
    @FocusState private var focusedField: String?

    // MARK: - Interactions

    private func handleCycle(task: BuddyTask) {
        let didComplete = store.cycle(task)
        if didComplete && store.settings.celebrate > 0 {
            withAnimation { showCelebration = true }
        }
    }

    private func handleComplete(task: BuddyTask) {
        let didComplete = store.complete(task)
        if didComplete && store.settings.celebrate > 0 {
            withAnimation { showCelebration = true }
        }
    }

    private func addTask() {
        if let newId = store.addTask() {
            pendingFocusId = newId
            // Auto-start editing the new task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                startEditById(id: newId, currentText: "")
            }
        }
    }

    private func startEdit(task: BuddyTask) {
        startEditById(id: task.id, currentText: task.text)
    }

    private func startEditById(id: String, currentText: String) {
        editText   = currentText
        editingId  = id
        focusedField = id
    }

    private func commitEdit(id: String) {
        guard editingId == id else { return }
        let text = editText
        editingId    = nil
        focusedField = nil
        store.commitEdit(id: id, text: text)
    }

    // MARK: - Date helpers

    private var currentWeekday: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    private var currentDayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: Date())
    }

    private var currentMonth: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: Date())
    }
}

// MARK: - Previews

#Preview("Normal — lvl0 (≤4 active)") {
    TodayView()
}

#Preview("Warning — lvl1 (5 active, red text)") {
    TodayView(debugActiveOverride: 5)
}

#Preview("Alarm — lvl2 (6+ active, red background)") {
    TodayView(debugActiveOverride: 6)
}

#Preview("Empty state") {
    TodayView()
}
