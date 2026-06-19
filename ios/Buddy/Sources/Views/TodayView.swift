import SwiftUI

// MARK: - TodayView
// The iPhone's main screen. The drawer's contents go full-bleed here —
// a date header + active task list + done section, all on one scrollable view.
//
// The entire view background adapts to the escalation theme. No hardcoded colours.
struct TodayView: View {

    // Mock data for scaffold — swap for live store in Phase 5.
    @State private var tasks: [BuddyTask]

    // DEBUG: force an escalation level in previews / debug builds.
    // Set to 5 to see lvl1 (red text), 6+ to see lvl2 (red background).
    @State var debugActiveOverride: Int?

    init(tasks: [BuddyTask] = MockData.normalTasks, debugActiveOverride: Int? = nil) {
        _tasks = State(initialValue: tasks)
        _debugActiveOverride = State(initialValue: debugActiveOverride)
    }

    // MARK: Computed state

    private var activeTasks: [BuddyTask] {
        tasks.filter { $0.isActive }
    }

    private var doneTasks: [BuddyTask] {
        tasks.filter { $0.isDone }
    }

    private var activeCount: Int {
        debugActiveOverride ?? activeTasks.count
    }

    private var theme: EscalationTheme {
        EscalationTheme.from(activeCount: activeCount)
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                dateCard
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                // Divider
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                // Active task rows — numbered from 1
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                    TaskRowView(task: task, index: index + 1, theme: theme)

                    // Divider between rows
                    if index < activeTasks.count - 1 {
                        Rectangle()
                            .fill(theme.line)
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                    }
                }

                // Done section header — only shown when there are done tasks
                if !doneTasks.isEmpty {
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

                    // Done task rows — no number badge, struck-through
                    ForEach(doneTasks) { task in
                        TaskRowView(task: task, index: 0, theme: theme)

                        if task.id != doneTasks.last?.id {
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
        .background(theme.cardBackground)
        .animation(.easeInOut(duration: 0.2), value: activeCount)
    }

    // MARK: Date header card
    // Shows weekday name + big day number — mirrors the web app's date card.
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

    // MARK: Date helpers

    private var currentWeekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }

    private var currentDayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: Date())
    }
}

// MARK: - Previews

#Preview("Normal — lvl0 (≤4 active)") {
    TodayView(tasks: MockData.normalTasks)
}

#Preview("Warning — lvl1 (5 active, red text)") {
    TodayView(tasks: MockData.warningTasks, debugActiveOverride: 5)
}

#Preview("Alarm — lvl2 (6+ active, red background)") {
    TodayView(tasks: MockData.alarmTasks, debugActiveOverride: 6)
}

#Preview("Empty state") {
    TodayView(tasks: [])
}
