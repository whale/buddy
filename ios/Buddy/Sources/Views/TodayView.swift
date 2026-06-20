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
                    VStack(alignment: .leading, spacing: 0) {

                        dateCard
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        Divider()
                            .background(theme.line)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)

                        // Active tasks
                        let active = store.activeTasks
                        ForEach(Array(active.enumerated()), id: \.element.id) { index, task in
                            activeRowView(task: task, index: index + 1)

                            if index < active.count - 1 {
                                Rectangle()
                                    .fill(theme.line)
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                        }

                        // Add row (hidden at hard cap)
                        if !store.atHardCap {
                            if !store.activeTasks.isEmpty {
                                Rectangle()
                                    .fill(theme.line)
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                            addRow
                        }

                        // Donezo section
                        let done = store.doneTasks
                        if !done.isEmpty {
                            Rectangle()
                                .fill(theme.line)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)

                            Text("Donezo")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.5)
                                .textCase(.uppercase)
                                .foregroundStyle(theme.inkDim)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 4)

                            ForEach(done) { task in
                                doneRowView(task: task)

                                if task.id != done.last?.id {
                                    Rectangle()
                                        .fill(theme.line)
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }

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

    private var dateCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(currentWeekday)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.inkDim)

            Text(currentDayNumber)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(theme.ink)
        }
    }

    // MARK: - Active task row
    // Tapping cycles the task state. Swipe actions for edit, defer, delete.
    @ViewBuilder
    private func activeRowView(task: BuddyTask, index: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Task number badge — escalationText so it turns red at lvl1
            Text("\(index)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.escalationText)
                .frame(width: 20, alignment: .trailing)

            // Inline edit or display
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
                    .onTapGesture { startEdit(task: task) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // The focused task is your "now" — fill it so you can see it at a glance (mirrors the Mac).
        .background(task.state == .focused ? theme.focusFill : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if editingId != nil { return }
            handleCycle(task: task)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                handleCycle(task: task)
            } label: {
                Label("Cycle", systemImage: task.state == .neutral ? "circle.fill" : "checkmark.circle.fill")
            }
            .tint(theme.escalationText == .black ? .black : Color(hex: "#e5484d"))
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteTask(id: task.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                store.deferToTomorrow(id: task.id)
            } label: {
                Label("Tomorrow", systemImage: "calendar.badge.plus")
            }
            .tint(.indigo)

            Button {
                startEdit(task: task)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.gray)
        }
    }

    // MARK: - Done (Donezo) row
    // Neutral and adaptive — inkDim, not escalationText. Tap or swipe to restore.
    @ViewBuilder
    private func doneRowView(task: BuddyTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.inkDim)
                .frame(width: 20, alignment: .trailing)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 1) {
                Text("Donezo.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(task.text)
                    .font(.system(size: 15))
                    .strikethrough(true, color: theme.inkDim)
                    .foregroundStyle(theme.inkDim)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { store.restoreTask(id: task.id) }
        .swipeActions(edge: .leading) {
            Button {
                store.restoreTask(id: task.id)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.gray)
            .disabled(store.atHardCap)
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
