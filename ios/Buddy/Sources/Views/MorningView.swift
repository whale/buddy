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
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 40)
                .padding(.bottom, 8)

            Divider().padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.today.items) { task in
                        plannerRow(task)
                        Rectangle().fill(Color(hex: "#d9d9d9")).frame(height: 1).padding(.horizontal, 16)
                    }
                    if !store.atHardCap { addRow }
                }
            }

            Spacer(minLength: 0)
            controlBar
        }
        .background(Color.white.ignoresSafeArea())
    }

    // MARK: header (weekday + day number). Phase 2 unifies this with TodayView's header.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(weekday).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            Text(dayNumber).font(.system(size: 32, weight: .semibold)).foregroundStyle(.black)
        }
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
            Spacer()
            Button { finish() } label: {
                Text("Buddy!")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(Capsule().fill(Color.black))
            }
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
    private var dayNumber: String { let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: Date()) }
}
