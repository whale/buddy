import SwiftUI

// MARK: - TaskRowView
// One row in the today list. Adapts its colours entirely from EscalationTheme
// so it's legible at all three escalation levels — never hardcodes colours.
//
// Active row:  task number + task text, coloured by escalation theme
// Done row:    struck-through title in inkDim — which follows THE PATTERN
//              (2026-07-10): black → red at lvl1 → white at lvl2, like everything else
struct TaskRowView: View {
    let task: BuddyTask
    let index: Int              // 1-based position in the active list (for the number badge)
    let theme: EscalationTheme

    var body: some View {
        if task.isDone {
            doneRow
        } else {
            activeRow
        }
    }

    // MARK: Active row
    private var activeRow: some View {
        HStack(alignment: .top, spacing: 10) {
            // Task number badge — uses escalationText so it turns red at lvl1
            Text("\(index)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.escalationText)
                .frame(width: 20, alignment: .trailing)
                .padding(.top, 2)

            Text(task.text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(theme.escalationText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Done / Donezo row
    // Uses inkDim, which follows THE PATTERN like everything else
    // (black-dim → red-dim at lvl1 → white-dim at lvl2).
    private var doneRow: some View {
        HStack(alignment: .top, spacing: 10) {
            // Checkmark placeholder where the number would be
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.inkDim)
                .frame(width: 20, alignment: .trailing)
                .padding(.top, 3)

            Text(task.text)
                .font(.system(size: 16, weight: .regular))
                .strikethrough(true, color: theme.inkDim)
                .foregroundStyle(theme.inkDim)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Previews
#Preview("Active — lvl0") {
    VStack(spacing: 0) {
        TaskRowView(
            task: BuddyTask(id: "1", text: "Write the iOS scaffold", state: .focused),
            index: 1,
            theme: EscalationTheme.from(activeCount: 2)
        )
        TaskRowView(
            task: BuddyTask(id: "2", text: "Review sync plan", state: .neutral),
            index: 2,
            theme: EscalationTheme.from(activeCount: 2)
        )
        TaskRowView(
            task: BuddyTask(id: "3", text: "Morning walk done", state: .done, doneAt: Date()),
            index: 0,
            theme: EscalationTheme.from(activeCount: 2)
        )
    }
    .background(Color.white)
}

#Preview("Active — lvl1 (5 active, red text)") {
    VStack(spacing: 0) {
        TaskRowView(
            task: BuddyTask(id: "1", text: "Write the iOS scaffold", state: .focused),
            index: 1,
            theme: EscalationTheme.from(activeCount: 5)
        )
        TaskRowView(
            task: BuddyTask(id: "5", text: "Fifth task — at the limit", state: .neutral),
            index: 5,
            theme: EscalationTheme.from(activeCount: 5)
        )
        TaskRowView(
            task: BuddyTask(id: "d", text: "Done task should NOT be red", state: .done, doneAt: Date()),
            index: 0,
            theme: EscalationTheme.from(activeCount: 5)
        )
    }
    .background(Color.white)
}

#Preview("Active — lvl2 (red background)") {
    VStack(spacing: 0) {
        TaskRowView(
            task: BuddyTask(id: "1", text: "Write the iOS scaffold", state: .focused),
            index: 1,
            theme: EscalationTheme.from(activeCount: 6)
        )
        TaskRowView(
            task: BuddyTask(id: "6", text: "Sixth task — over limit", state: .neutral),
            index: 6,
            theme: EscalationTheme.from(activeCount: 6)
        )
        TaskRowView(
            task: BuddyTask(id: "d", text: "Done task — must be readable on red", state: .done, doneAt: Date()),
            index: 0,
            theme: EscalationTheme.from(activeCount: 6)
        )
    }
    .background(Color(hex: "#e5484d"))
}
