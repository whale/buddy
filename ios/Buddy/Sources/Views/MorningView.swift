import SwiftUI

// MARK: - MorningView
// A faithful port of the Mac's full-screen morning planner: a centered column with
// the big date header (numeral · weekday/month · weather), a bordered rounded list
// card, and a Skip / Buddy! footer — all set in Geist. Yesterday's unfinished tasks
// are pre-carried by the store's rollover, so they appear here to trim down.
struct MorningView: View {
    @Bindable var store: BuddyStore
    var onDone: () -> Void

    @State private var editingId: String? = nil
    @State private var editText: String = ""
    @FocusState private var focusedField: String?

    private var theme: EscalationTheme { EscalationTheme.from(activeCount: store.activeCount) }

    var body: some View {
        ZStack {
            theme.cardBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                dateHeader
                    .padding(.leading, 28)
                    .padding(.trailing, 24)
                plannerCard
                footer
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
        }
    }

    // Big date block — numeral (left) · weekday/month · weather (right). Mirrors the drawer.
    private var dateHeader: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 12) {
                Text(dayNumber).font(.geist(62, .medium)).tracking(-1.24).foregroundStyle(theme.escalationText)
                VStack(alignment: .leading, spacing: 4) {
                    Text(weekday).font(.geist(24, .medium)).tracking(-0.48).foregroundStyle(theme.escalationText)
                    Text(month).font(.geist(18, .regular)).tracking(-0.36).foregroundStyle(theme.chromeMuted)
                }
                .padding(.bottom, 4)
            }
            Spacer()
            Image(systemName: "moon").font(.system(size: 24)).foregroundStyle(theme.escalationText).frame(width: 50, height: 50)
        }
    }

    // The planner list — a bordered rounded card (Mac uses a border here, not a shadow).
    private var plannerCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.today.items.enumerated()), id: \.element.id) { i, task in
                if i > 0 { Rectangle().fill(theme.line).frame(height: 1) }
                plannerRow(task)
            }
            if !store.atHardCap {
                if !store.today.items.isEmpty { Rectangle().fill(theme.line).frame(height: 1) }
                addRow
            }
        }
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func plannerRow(_ task: BuddyTask) -> some View {
        Group {
            if editingId == task.id {
                TextField("", text: $editText, axis: .vertical)
                    .font(.geist(20, .medium)).tracking(-0.48)
                    .foregroundStyle(theme.escalationText)
                    .focused($focusedField, equals: task.id)
                    .submitLabel(.done)
                    .onSubmit { commit(task.id) }
                    .onChange(of: focusedField) { _, v in if v != task.id { commit(task.id) } }
            } else {
                Text(task.text.isEmpty ? "Untitled" : task.text)
                    .font(.geist(20, .medium)).tracking(-0.48)
                    .foregroundStyle(task.text.isEmpty ? theme.inkDim : theme.escalationText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { startEdit(task) }
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addRow: some View {
        HStack(spacing: 18) { Text("Add"); Text("+") }
            .font(.geist(20, .medium)).tracking(-0.48)
            .foregroundStyle(theme.addInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 28).padding(.vertical, 22)
            .onTapGesture { addTask() }
    }

    private var footer: some View {
        HStack {
            Button { skip() } label: {
                Text("Skip").font(.geist(15, .regular)).tracking(-0.32).foregroundStyle(theme.inkDim)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { finish() } label: {
                Text("Buddy!")
                    .font(.geist(18, .medium)).tracking(-0.36)
                    .foregroundStyle(theme.level == .lvl2 ? Color(hex: "#e5484d") : .white)
                    .padding(.horizontal, 28).padding(.vertical, 13)
                    .background(Capsule().fill(theme.level == .lvl2 ? Color.white : Color.black))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: interactions
    private func startEdit(_ task: BuddyTask) { editText = task.text; editingId = task.id; focusedField = task.id }
    private func commit(_ id: String) {
        guard editingId == id else { return }
        let text = editText; editingId = nil; focusedField = nil
        store.commitEdit(id: id, text: text)
    }
    private func addTask() {
        if let id = store.addTask() {
            editText = ""; editingId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = id }
        }
    }
    private func finish() { if let id = editingId { commit(id) }; store.completeMorning(); onDone() }
    private func skip()   { if let id = editingId { commit(id) }; store.skipMorning(); onDone() }

    private var weekday: String   { Self.df("EEEE") }
    private var month: String     { Self.df("MMMM") }
    private var dayNumber: String { Self.df("d") }
    private static func df(_ fmt: String) -> String { let f = DateFormatter(); f.dateFormat = fmt; return f.string(from: Date()) }
}
