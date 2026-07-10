import SwiftUI
import UIKit

// MARK: - SettingsView
// A faithful port of the Mac's Settings sheet: a Buddy card (not a native Form) with
// a "Settings" + ✕ header, hairline #d9d9d9 dividers, Geist type, and the celebrate
// slider bracketed by 👍🏼 … 🦜. Adopts the escalation theme (red bg + light text at lvl2).
struct SettingsView: View {
    @Bindable var store: BuddyStore
    var sync: SyncEngine? = nil
    var onClose: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    @State private var celebrate: Double = 100

    // Sync section state
    @State private var showScanner = false
    @State private var manualExpanded = false
    @State private var fURL = ""
    @State private var fAnon = ""
    @State private var fKey = ""
    @State private var pairError: String?
    @State private var bugReportMessage: String?

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
                            BuddySlider(value: $celebrate,
                                        track: theme.sliderTrack,
                                        thumb: theme.sliderThumb)
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

                    // Sync — pair with the Mac by QR (or manual entry)
                    section {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 0) {
                                Text("Sync with your Mac")
                                    .font(.geist(18, .regular)).tracking(-0.36).foregroundStyle(theme.sheetLabel)
                                Spacer()
                                Text(syncStatusText)
                                    .font(.geist(15, .regular)).foregroundStyle(theme.sheetFaint)
                            }
                            if isConnected {
                                syncPillRow {
                                    pill("Disconnect") { disconnect() }
                                    Spacer()
                                }
                            } else {
                                syncPillRow {
                                    pill("Scan QR to pair") { pairError = nil; showScanner = true }
                                    pill(manualExpanded ? "Hide" : "Enter manually") {
                                        withAnimation { manualExpanded.toggle() }
                                    }
                                    Spacer()
                                }
                            }
                            if manualExpanded && !isConnected {
                                syncField("Backend URL", text: $fURL, keyboard: .URL)
                                syncField("Anon key", text: $fAnon)
                                syncField("Sync key (43 characters)", text: $fKey)
                                syncPillRow { pill("Connect") { connect() }; Spacer() }
                            }
                            if let e = pairError {
                                // Token red; red-on-red is invisible on the lvl2 sheet →
                                // white + semibold there (mirrors Mac #syncError).
                                Text(e).font(.geist(14, theme.level == .lvl2 ? .semibold : .regular))
                                    .foregroundStyle(theme.errorText)
                            }
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

                    // Report a bug. Prefer the private repo intake endpoint when configured;
                    // otherwise fall back to email. Never send users to GitHub's login wall.
                    rowButton {
                        Task { await submitBugReport() }
                    } label: {
                        Text("Report a bug")
                            .font(.geist(18, .regular)).tracking(-0.36).foregroundStyle(theme.sheetLabel)
                        Spacer()
                        if let bugReportMessage {
                            Text(bugReportMessage)
                                .font(.geist(15, .regular)).foregroundStyle(theme.sheetFaint)
                        } else {
                            Image(systemName: "ladybug").font(.system(size: 15)).foregroundStyle(theme.sheetFaint)
                        }
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
                            .foregroundStyle(theme.sheetGhost)
                        Spacer()
                    }
                    .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            celebrate = Double(store.settings.celebrate)
            if let c = sync?.currentConfig { fURL = c.backendUrl; fAnon = c.anonKey; fKey = c.syncKey }
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView(onScan: { applyScanned($0) }, onCancel: { showScanner = false })
        }
    }

    // MARK: - Sync helpers

    private var isConnected: Bool { sync?.currentConfig.isSyncable ?? false }

    private var syncStatusText: String {
        guard let sync else { return "Off" }
        if sync.currentConfig.enabled, sync.lastError != nil, sync.lastSyncedAt == nil { return "Error" }
        if let t = sync.lastSyncedAt { return "Synced \(Self.hm.string(from: t))" }
        if sync.currentConfig.isSyncable { return "Connected" }
        return "Not connected"
    }
    private static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    private func applyScanned(_ s: String) {
        showScanner = false
        guard let p = SyncIdentity.parse(s) else {
            pairError = "That QR code isn’t a Buddy pairing code."; manualExpanded = true; return
        }
        fURL = p.backendUrl; fAnon = p.anonKey; fKey = p.syncKey
        connect()
    }

    private func connect() {
        let cfg = SyncConfig(backendUrl: fURL.trimmingCharacters(in: .whitespacesAndNewlines),
                             anonKey: fAnon.trimmingCharacters(in: .whitespacesAndNewlines),
                             syncKey: fKey.trimmingCharacters(in: .whitespacesAndNewlines),
                             enabled: true)
        guard cfg.isSyncable else {
            pairError = SyncConfig.isValidSyncKey(cfg.syncKey)
                ? "Check the backend URL and anon key."
                : "That sync key looks wrong — it should be 43 characters."
            return
        }
        pairError = nil
        SyncConfigStore.save(cfg)
        sync?.updateConfig(cfg)
        withAnimation { manualExpanded = false }
    }

    private func disconnect() {
        var cfg = sync?.currentConfig ?? SyncConfig(backendUrl: "", anonKey: "", syncKey: "", enabled: false)
        cfg.enabled = false
        SyncConfigStore.save(cfg)
        sync?.updateConfig(cfg)
        pairError = nil
    }

    @ViewBuilder private func syncPillRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) { content() }
    }

    @ViewBuilder private func syncField(_ placeholder: String, text: Binding<String>,
                                        keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .font(.geist(15, .regular))
            .foregroundStyle(theme.sheetLabel)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
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

    private var bugReportEndpoint: URL? {
        let raw = (Bundle.main.infoDictionary?["BuddyBugReportEndpoint"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains("REPLACE-AFTER-DEPLOY") else { return nil }
        return URL(string: raw)
    }

    private struct BugReportPayload: Encodable {
        let version: String
        let platform: String
        let logs: String
    }

    private func submitBugReport() async {
        let logs = bugReportLogs
        if let endpoint = bugReportEndpoint {
            do {
                var req = URLRequest(url: endpoint)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONEncoder().encode(BugReportPayload(
                    version: "iOS \(appVersion)",
                    platform: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                    logs: logs
                ))
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    await MainActor.run { flashBugMessage("Sent") }
                    return
                }
            } catch {
                // Fall through to email so the report is not lost.
            }
        }
        await MainActor.run { openBugEmail(logs: logs) }
    }

    @MainActor private func flashBugMessage(_ message: String) {
        bugReportMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { bugReportMessage = nil }
    }

    @MainActor private func openBugEmail(logs: String) {
        if let url = bugReportEmailURL(logs: logs) { UIApplication.shared.open(url) }
        flashBugMessage("Email")
    }

    private var bugReportLogs: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return [
            "Buddy iOS bug report",
            "version: \(appVersion) (\(build))",
            "platform: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "active: \(store.activeCount) · done: \(store.doneTasks.count) · future: \(store.deferred.count)",
            "synced: \(isConnected)",
            "",
            "What happened:",
            "What you expected:"
        ].joined(separator: "\n")
    }

    private func bugReportEmailURL(logs: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = "hi+buddy@whale.fyi"
        c.queryItems = [
            URLQueryItem(name: "subject", value: "Buddy iOS bug report"),
            URLQueryItem(name: "body", value: logs)
        ]
        return c.url
    }

}

#Preview {
    SettingsView(store: { let s = BuddyStore(); return s }())
}
