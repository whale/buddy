import SwiftUI

// MARK: - HistoryView
// Past days with their done/undone items. Mirrors the Mac's history panel
// (calendar icon → "Done" tab). Shows the last `historyDays` days.
struct HistoryView: View {
    @Bindable var store: BuddyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if visibleGroups.isEmpty {
                    emptyState
                } else {
                    List {
                        // Today's done tasks (live, from state.today.items)
                        if !store.doneTasks.isEmpty {
                            Section("Today") {
                                ForEach(store.doneTasks) { task in
                                    doneRow(task.text, isToday: true, taskId: task.id)
                                }
                            }
                        }

                        // Past days from history
                        ForEach(visibleGroups, id: \.date) { day in
                            let doneDayItems = day.items.filter { $0.done }
                            if !doneDayItems.isEmpty {
                                Section(day.weekday.isEmpty ? day.date : "\(day.weekday)  \(day.date)") {
                                    ForEach(doneDayItems, id: \.text) { item in
                                        doneRow(item.text, isToday: false, taskId: nil)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func doneRow(_ text: String, isToday: Bool, taskId: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text("Donezo.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(text)
                    .font(.system(size: 15))
                    .strikethrough(true, color: .secondary)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Undo restore button — only for today's live items (not history)
            if isToday, let id = taskId {
                Button {
                    store.restoreTask(id: id)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(store.atHardCap)
                .opacity(store.atHardCap ? 0.3 : 1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No completed tasks yet.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data helpers

    // Last N days from history, filtered to those with at least one done item.
    private var visibleGroups: [Day] {
        let n = store.settings.historyDays
        guard n > 0 else { return [] }
        let base = Date()
        return (1...n).compactMap { i -> Day? in
            guard let d = Calendar.current.date(byAdding: .day, value: -i, to: base) else { return nil }
            let dateStr = BuddyStore.localDate(d)
            if let rec = store.history.first(where: { $0.date == dateStr }) {
                return rec
            }
            return nil
        }.filter { $0.items.contains(where: { $0.done }) }
    }
}

// MARK: - Previews
#Preview {
    HistoryView(store: {
        let s = BuddyStore()
        return s
    }())
}
