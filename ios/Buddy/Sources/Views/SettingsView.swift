import SwiftUI
import UIKit

// MARK: - SettingsView
// A faithful port of the Mac's Settings sheet: a Buddy card (not a native Form) with
// a "Settings" + ✕ header, hairline #d9d9d9 dividers, Geist type, and the celebrate
// slider bracketed by 👍🏼 … 🦜. Adopts the escalation theme (red bg + light text at lvl2).
struct SettingsView: View {
    @Bindable var store: BuddyStore
    var onClose: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    @State private var celebrate: Double = 100

    private var theme: EscalationTheme { EscalationTheme.from(activeCount: store.activeCount) }

    var body: some View {
        VStack(spacing: 0) {
            BuddySheetHeader(theme: theme, onClose: { onClose() }) {
                Text("Settings").font(.geist(18, .medium)).tracking(-0.36).foregroundStyle(theme.sheetTitle)
            }

            ScrollView {
                VStack(spacing: 0) {
                    // Celebrate
                    section {
                        Text("Celebrate completed tasks")
                            .font(.geist(18, .regular)).tracking(-0.36)
                            .foregroundStyle(theme.sheetLabel)
                            .padding(.bottom, 14)
                        HStack(spacing: 12) {
                            Text("👍🏼").font(.system(size: 20))
                            Slider(value: $celebrate, in: 0...100, step: 1)
                                .tint(theme.level == .lvl2 ? .white : .black)
                                .disabled(reducedMotion)
                                .onChange(of: celebrate) { _, v in store.settings.celebrate = Int(v) }
                            Text("🦜").font(.system(size: 20))
                        }
                        if reducedMotion {
                            Text("Off while your system is set to reduce motion.")
                                .font(.geist(14, .regular)).foregroundStyle(theme.sheetFaint)
                                .padding(.top, 10)
                        }
                    }

                    // Export my done tasks (Mac parity) — share sheet with a live done-count
                    ShareLink(item: store.doneExport.joined(separator: "\n")) {
                        HStack(spacing: 0) {
                            Text("Export my done tasks")
                                .font(.geist(18, .regular)).tracking(-0.36).foregroundStyle(theme.sheetLabel)
                            Spacer()
                            Text("\(store.doneExport.count)")
                                .font(.geist(15, .regular)).foregroundStyle(theme.sheetFaint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 32).padding(.vertical, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(theme.line).frame(height: 1)

                    // Report a bug
                    rowButton {
                        if let url = bugReportURL { UIApplication.shared.open(url) }
                    } label: {
                        Text("Report a bug")
                            .font(.geist(18, .regular)).tracking(-0.36).foregroundStyle(theme.sheetLabel)
                        Spacer()
                        Image(systemName: "ladybug").font(.system(size: 15)).foregroundStyle(theme.sheetFaint)
                    }

                    #if DEBUG
                    HStack(spacing: 12) {
                        pill("Reset data") { store.resetForDev(); onClose() }
                        pill("Restart") { exit(0) }
                    }
                    .padding(.horizontal, 32).padding(.vertical, 20)
                    Rectangle().fill(theme.line).frame(height: 1)
                    #endif

                    HStack {
                        Text("Buddy \(appVersion)")
                            .font(.geist(14, .regular)).tracking(-0.26)
                            .foregroundStyle(theme.level == .lvl2 ? Color.white.opacity(0.4) : Color.black.opacity(0.3))
                        Spacer()
                    }
                    .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { celebrate = Double(store.settings.celebrate) }
    }

    // MARK: row helpers

    @ViewBuilder private func section<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32).padding(.vertical, 20)
        Rectangle().fill(theme.line).frame(height: 1)
    }

    @ViewBuilder private func rowButton<C: View>(_ action: @escaping () -> Void, @ViewBuilder label: () -> C) -> some View {
        Button(action: action) {
            HStack(spacing: 0) { label() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32).padding(.vertical, 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Rectangle().fill(theme.line).frame(height: 1)
    }

    private func pill(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.geist(15, .regular)).tracking(-0.30)
                .foregroundStyle(theme.sheetLabel)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .overlay(Capsule().stroke(theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var bugReportURL: URL? {
        let v = appVersion
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let body = "\n\n---\nBuddy iOS \(v) (\(build)) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\nWhat happened:\nWhat you expected:"
        var c = URLComponents(string: "https://github.com/whale/buddy/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: "Bug: "), URLQueryItem(name: "body", value: body)]
        return c.url
    }

}

#Preview {
    SettingsView(store: { let s = BuddyStore(); return s }())
}
