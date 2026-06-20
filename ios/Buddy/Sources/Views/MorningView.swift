import SwiftUI

// MARK: - MorningView
// The morning planner — mirrors the Mac's full-screen morning overlay. Shows on a
// fresh/rolled day until the user presses Buddy! (or Skip). Yesterday's unfinished
// tasks are already carried into today.items by the store's rollover, so they appear
// here automatically — you trim down to your three, then start the day.
//
// Functionality-first (Phase 1): plan/add/edit tasks + Skip / Buddy! controls.
// Visual polish to match `mac-morning.png` is Phase 2.
struct MorningView: View {
    @Bindable var store: BuddyStore
    var onDone: () -> Void

    @State private var editingId: String? = nil
    @State private var editText: String = ""
    @FocusState private var focusedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 40)

            ScrollView {
                plannerCard.padding(.horizontal, 16)
            }

            controlBar
        }
        .background(Color.white.ignoresSafeArea())
    }

    // Mac-style header: weekday + month stacked, giant numeral on the right.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: -2) {
                Text(weekday).font(.system(size: 28, weight: .bold)).foregroundStyle(.black)
                Text(month).font(.system(size: 16)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(dayNumber).font(.system(size: 56, weight: .bold)).foregroundStyle(.black)
        }
    }

    private let line = Color(hex: "#d9d9d9")

    // The planner list in the same bordered card as the daily view.
    private var plannerCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.today.items.enumerated()), id: \.element.id) { i, task in
                if i > 0 { Rectangle().fill(line).frame(height: 1) }
                plannerRow(task)
            }
            if !store.atHardCap {
                if !store.today.items.isEmpty { Rectangle().fill(line).frame(height: 1) }
                addRow
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(line, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
    }

    // MARK: planner row — tap to edit, inline TextField while editing
    @ViewBuilder
    private func plannerRow(_ task: BuddyTask) -> some View {
        if editingId == task.id {
            TextField("", text: $editText)
                .font(.system(size: 16))
                .focused($focusedField, equals: task.id)
                .submitLabel(.done)
                .onSubmit { commit(task.id) }
                .onChange(of: focusedField) { _, newVal in if newVal != task.id { commit(task.id) } }
                .padding(.horizontal, 16).padding(.vertical, 12)
        } else {
            Text(task.text.isEmpty ? "Untitled" : task.text)
                .font(.system(size: 16))
                .foregroundStyle(task.text.isEmpty ? Color.secondary : Color.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 16).padding(.vertical, 12)
                .onTapGesture { startEdit(task) }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Text("Add").font(.system(size: 16)).foregroundStyle(.secondary)
            Image(systemName: "plus").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 16).padding(.vertical, 12)
        .onTapGesture { addTask() }
    }

    private var controlBar: some View {
        HStack {
            Button { skip() } label: {
                Text("Skip").font(.system(size: 15)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { finish() } label: {
                Text("Buddy!")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: interactions
    private func startEdit(_ task: BuddyTask) { editText = task.text; editingId = task.id; focusedField = task.id }
    private func commit(_ id: String) {
        guard editingId == id else { return }
        let text = editText
        editingId = nil; focusedField = nil
        store.commitEdit(id: id, text: text)
    }
    private func addTask() {
        if let id = store.addTask() {
            // Set editingId SYNCHRONOUSLY so a Buddy!/Skip tap in the focus-delay window
            // still commits (and an empty new task gets cleaned up). Focus is deferred a
            // beat so the new row exists before we focus it.
            editText = ""
            editingId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusedField = id }
        }
    }
    private func finish() {           // Buddy!
        if let id = editingId { commit(id) }
        store.completeMorning()
        onDone()
    }
    private func skip() {             // Skip — same effect today, distinct intent on the Mac
        if let id = editingId { commit(id) }
        store.skipMorning()
        onDone()
    }

    private var weekday: String { let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: Date()) }
    private var month: String { let f = DateFormatter(); f.dateFormat = "MMMM"; return f.string(from: Date()) }
    private var dayNumber: String { let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: Date()) }
}
