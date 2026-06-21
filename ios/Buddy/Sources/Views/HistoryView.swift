import SwiftUI

// MARK: - HistoryView
// Custom Buddy sheet (NOT native List/NavigationStack). A Future / Done segmented
// toggle + ✕, flat rows — mirrors the Mac's history panel.
struct HistoryView: View {
    @Bindable var store: BuddyStore
    @Environment(\.dismiss) private var dismiss

    enum Tab { case future, done }
    @State private var tab: Tab = .done

    private let line = Color(hex: "#e6e6e6")

    var body: some View {
        VStack(spacing: 0) {
            // Header: segmented control + ✕
            HStack {
                segmented
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "#999999"))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 16)
            divider

            ScrollView {
                if tab == .future { futureContent } else { doneContent }
            }
        }
        .background(Color.white.ignoresSafeArea())
    }

    // MARK: segmented
    private var segmented: some View {
        HStack(spacing: 0) {
            segButton("Future", .future)
            segButton("Done", .done)
        }
        .padding(3)
        .background(Capsule().fill(Color(hex: "#f0f0f0")))
    }

    private func segButton(_ title: String, _ t: Tab) -> some View {
        Button { tab = t } label: {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tab == t ? .black : Color.secondary)
                .padding(.horizontal, 18).padding(.vertical, 7)
                .background(tab == t ? AnyView(Capsule().fill(.white)) : AnyView(Color.clear))
        }.buttonStyle(.plain)
    }

    // MARK: Future (pushed-forward / slept tasks)
    @ViewBuilder private var futureContent: some View {
        if store.deferred.isEmpty {
            emptyState("Nothing pushed forward.")
        } else {
            VStack(spacing: 0) {
                ForEach(store.deferred) { d in
                    HStack {
                        Text(d.text).font(.system(size: 15)).foregroundStyle(.black)
                        Spacer()
                        Text(d.wake).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    divider
                }
            }
        }
    }

    // MARK: Done (today's done + past days)
    @ViewBuilder private var doneContent: some View {
        if store.doneTasks.isEmpty && visibleGroups.isEmpty {
            emptyState("No completed tasks yet.")
        } else {
            VStack(spacing: 0) {
                if !store.doneTasks.isEmpty {
                    dayHeader("Today")
                    ForEach(store.doneTasks) { task in doneRow(task.text, restoreId: task.id) }
                }
                ForEach(visibleGroups, id: \.date) { day in
                    let done = day.items.filter { $0.done }
                    if !done.isEmpty {
                        dayHeader(day.weekday.isEmpty ? day.date : "\(day.weekday)  \(day.date)")
                        ForEach(done, id: \.id) { item in doneRow(item.text, restoreId: nil) }
                    }
                }
            }
        }
    }

    private func dayHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold)).tracking(0.5).textCase(.uppercase)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 6)
    }

    @ViewBuilder
    private func doneRow(_ text: String, restoreId: String?) -> some View {
        HStack(spacing: 6) {
            Text("Donezo.").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
            Text(text).font(.system(size: 15)).strikethrough(true, color: .secondary).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let id = restoreId {
                Button { store.restoreTask(id: id) } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).disabled(store.atHardCap).opacity(store.atHardCap ? 0.3 : 1)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        divider
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.vertical, 28)
    }

    private var divider: some View { Rectangle().fill(line).frame(height: 1) }

    // Last N days from history with at least one done item.
    private var visibleGroups: [Day] {
        let n = store.settings.historyDays
        guard n > 0 else { return [] }
        let base = Date()
        return (1...n).compactMap { i -> Day? in
            guard let d = Calendar.current.date(byAdding: .day, value: -i, to: base) else { return nil }
            return store.history.first(where: { $0.date == BuddyStore.localDate(d) })
        }.filter { $0.items.contains(where: { $0.done }) }
    }
}
