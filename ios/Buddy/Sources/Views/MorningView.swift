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
    @State private var weather = WeatherService()

    // Adaptive fit (see RowFit) — the morning planner fills the column and shrinks to fit
    // like the Mac, instead of scrolling. Morning's comfortable ceiling is 22pt.
    @State private var fit = RowFit.Result(font: 22, vpad: 16, scroll: false)

    private var theme: EscalationTheme { EscalationTheme.from(activeCount: store.activeCount) }

    var body: some View {
        ZStack {
            theme.cardBackground.ignoresSafeArea()
            // Header pinned top, planner scrolls in the middle (Mac caps the list at 70vh),
            // footer pinned bottom — so a full planner never shoves the date or Buddy! offscreen.
            VStack(spacing: 16) {
                dateHeader
                    .padding(.leading, 28)
                    .padding(.trailing, 24)
                    .padding(.top, 16)
                GeometryReader { geo in
                    Group {
                        if fit.scroll { ScrollView { plannerCard } }
                        else { plannerCard.frame(maxHeight: .infinity, alignment: .top) }
                    }
                    .onAppear { recomputeFit(geo.size) }
                    .onChange(of: store.today.items) { _, _ in recomputeFit(geo.size) }
                    .onChange(of: geo.size) { _, _ in recomputeFit(geo.size) }
                }
                footer
            }
            .padding(.horizontal, 14)
        }
        .task {
            #if DEBUG
            if ScreenshotHarness.activeFixture == nil { weather.refresh() }
            #else
            weather.refresh()
            #endif
        }
    }

    // Big date block — numeral (left) · weekday/month · weather (right). Mirrors the drawer.
    private var dateHeader: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 12) {
                Text(dayNumber).font(.geist(62, .medium)).tracking(-1.24).foregroundStyle(theme.escalationText)
                VStack(alignment: .leading, spacing: 4) {
                    Text(weekday).font(.geist(24, .medium)).tracking(-0.48).foregroundStyle(theme.escalationText)
                    Text(month).font(.geist(18, .regular)).tracking(-0.36).foregroundStyle(theme.inkDim)
                }
                .padding(.bottom, 4)
            }
            Spacer()
            WeatherIcon(key: weather.iconKey, size: 34).foregroundStyle(theme.escalationText).frame(width: 50, height: 50)
        }
    }

    // The planner list — a bordered rounded card (Mac uses a border here, not a shadow).
    private var plannerCard: some View {
        // Mirror the Mac: completed tasks sort to the TOP as compact Donezo rows, active
        // tasks below as tall editable rows (the Mac morning uses the same renderToday).
        let rows = store.doneTasks + store.activeTasks
        let showRestore = rows.isEmpty && !store.lastListForRestore().isEmpty
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, task in
                if i > 0 { Rectangle().fill(theme.line).frame(height: 1) }
                if task.isDone { doneRow(task) } else { plannerRow(task) }
            }
            if showRestore { restoreRow }
            if !store.atHardCap {
                if !rows.isEmpty || showRestore { Rectangle().fill(theme.line).frame(height: 1) }
                addRow
            }
        }
        .frame(maxHeight: fit.scroll ? nil : .infinity, alignment: .top)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    private func recomputeFit(_ size: CGSize) {
        let active = store.activeTasks.map(\.text)
        let showRestore = active.isEmpty && store.doneTasks.isEmpty && !store.lastListForRestore().isEmpty
        // The restore row behaves like one active row for fitting when the list is empty.
        let texts = active.isEmpty && showRestore ? ["Restore your last list"] : active
        let next = RowFit.compute(active: texts, doneCount: store.doneTasks.count,
                                  height: size.height, width: size.width, ceil: 22)
        if next != fit { fit = next }
    }

    // Compact Donezo row (done-word + struck title), like the Mac's buildDonezoRow(morning).
    private func doneRow(_ task: BuddyTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DoneWords.word(for: task.id)).font(.geist(15, .semibold)).tracking(-0.30)
                .foregroundStyle(theme.ink).fixedSize(horizontal: true, vertical: false)
            Text(task.text).font(.geist(15, .regular)).tracking(-0.30)
                .strikethrough(true, color: theme.inkDim).foregroundStyle(theme.inkDim).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { store.restoreTask(id: task.id) }
    }

    @ViewBuilder
    private func plannerRow(_ task: BuddyTask) -> some View {
        Group {
            if editingId == task.id {
                TextField("", text: $editText, axis: .vertical)
                    .font(.geist(fit.font, .medium)).tracking(-0.48)
                    .foregroundStyle(theme.escalationText)
                    .focused($focusedField, equals: task.id)
                    .submitLabel(.done)
                    .onSubmit { commit(task.id) }
                    .onChange(of: focusedField) { _, v in if v != task.id { commit(task.id) } }
            } else {
                Text(task.text.isEmpty ? "Untitled" : task.text)
                    .font(.geist(fit.font, .medium)).tracking(-0.48).lineSpacing(2)
                    .foregroundStyle(task.text.isEmpty ? theme.inkDim : theme.escalationText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { startEdit(task) }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, fit.vpad)
        .frame(maxWidth: .infinity, maxHeight: fit.scroll ? nil : .infinity, alignment: .leading)
    }

    // Empty-morning "Restore your last list" (Mac buildRestoreRowEl) — pulls the most
    // recent archived day's unfinished tasks back into today.
    private var restoreRow: some View {
        let texts = store.lastListForRestore()
        return HStack(spacing: 8) {
            Text("Restore your last list").font(.geist(22, .medium)).tracking(-0.48).foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            Text("\(texts.count) task\(texts.count == 1 ? "" : "s")")
                .font(.geist(15, .regular)).tracking(-0.28).foregroundStyle(theme.inkDim)
        }
        .frame(maxWidth: .infinity, maxHeight: fit.scroll ? nil : .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 32).padding(.vertical, fit.vpad)
        .onTapGesture { withAnimation { store.restoreLastList() } }
    }

    private var addRow: some View {
        HStack(spacing: 18) { Text("Add"); Text("+") }
            .font(.geist(fit.font, .medium)).tracking(-0.48)
            .foregroundStyle(theme.addInk)
            .frame(maxWidth: .infinity, maxHeight: fit.scroll ? nil : .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 32).padding(.vertical, fit.vpad)
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
