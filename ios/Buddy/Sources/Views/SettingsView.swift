import SwiftUI
import UIKit

// MARK: - SettingsView
// Custom Buddy sheet (NOT a native iOS Form/List) — flat full-width rows with thin
// dividers, "Settings" + ✕ header, black-thumb sliders. Mirrors the Mac settings sheet.
struct SettingsView: View {
    @Bindable var store: BuddyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.openURL) private var openURL

    @State private var celebrate: Double = 100
    @State private var historyDays: Double = 7
    @State private var showEraseConfirm = false

    private let line = Color(hex: "#e6e6e6")

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings").font(.system(size: 22, weight: .bold)).foregroundStyle(.black)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "#999999"))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 16)
            divider

            ScrollView {
                VStack(spacing: 0) {
                    // Celebrate
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Celebrate completed tasks").font(.system(size: 16, weight: .medium))
                            if reducedMotion {
                                Spacer()
                                Text("Reduced motion").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            Text("👍")
                            Slider(value: $celebrate, in: 0...100, step: 1).tint(.black).disabled(reducedMotion)
                                .onChange(of: celebrate) { _, v in store.settings.celebrate = Int(v) }
                            Text("🦜")
                        }
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22).padding(.vertical, 18)
                    divider

                    // History days
                    VStack(alignment: .leading, spacing: 12) {
                        Text(historyDaysLabel).font(.system(size: 16, weight: .medium)).foregroundStyle(.black)
                        Slider(value: $historyDays, in: 0...14, step: 1).tint(.black)
                            .onChange(of: historyDays) { _, v in store.settings.historyDays = Int(v) }
                        HStack {
                            Text("No days").font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Text("14 days").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 18)
                    divider

                    tapRow("Report a bug") { openURL(bugReportURL) }
                    divider
                    tapRow("Erase all data", tint: Color(hex: "#e5484d")) { showEraseConfirm = true }

                    #if DEBUG
                    divider
                    tapRow("Reset data (show morning)") { store.resetForDev(); dismiss() }
                    divider
                    tapRow("Restart app (quit)", tint: Color(hex: "#e5484d")) { exit(0) }
                    #endif
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .alert("Erase all data?", isPresented: $showEraseConfirm) {
            Button("Erase", role: .destructive) { store.eraseAll(); dismiss() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes every task and all history on this device. This can't be undone.")
        }
        .onAppear {
            celebrate = Double(store.settings.celebrate)
            historyDays = Double(store.settings.historyDays)
        }
    }

    private var divider: some View { Rectangle().fill(line).frame(height: 1) }

    @ViewBuilder
    private func tapRow(_ title: String, tint: Color = .black, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 16)).foregroundStyle(tint)
                Spacer()
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var historyDaysLabel: String {
        let n = Int(historyDays)
        if n <= 0 { return "No history" }
        return "\(n) day\(n == 1 ? "" : "s") of history"
    }

    private var bugReportURL: URL {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let body = """


        ---
        Buddy iOS \(v) (\(build)) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        What happened:
        What you expected:
        """
        var c = URLComponents(string: "https://github.com/whale/buddy/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: "Bug: "),
                        URLQueryItem(name: "body", value: body)]
        return c.url ?? URL(string: "https://github.com/whale/buddy/issues/new")!
    }
}
