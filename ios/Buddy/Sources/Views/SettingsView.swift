import SwiftUI
import UIKit

// MARK: - SettingsView
// Port of the Mac's REDESIGNED Settings sheet (2026-07-18): grouped INSET CARDS under
// quiet section labels (Behavior · Mac · Your data · App), instead of a flat list of
// dividered rows. Dividers live only inside a card; groups are separated by whitespace.
// Card fills / hairlines / button backgrounds are token-driven (EscalationTheme.setCard/
// setHair/setButton) so the whole sheet re-themes across lvl0/1/2.
struct SettingsView: View {
    @Bindable var store: BuddyStore
    var sync: SyncEngine? = nil
    var onClose: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    @State private var celebrate: Double = 100

    // Sync section state
    @State private var showScanner = false
    @State private var manualExpanded = false
    @State private var scannedCloud = false   // pairing came from a v2 (Buddy Cloud) QR
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
                VStack(alignment: .leading, spacing: 0) {

                    // ===== BEHAVIOR =====
                    sectionLabel("Behavior", first: true)
                    setCard {
                        cardItem {
                            Text("Celebrate completed tasks")
                                .font(.geist(18, .regular)).tracking(-0.36)
                                .foregroundStyle(theme.sheetLabel)
                                .padding(.bottom, 14)
                            HStack(spacing: 12) {
                                Text("👍🏼").font(.system(size: 20))
                                BuddySlider(value: $celebrate, track: theme.sliderTrack, thumb: theme.sliderThumb)
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
                    }

                    // ===== MAC (sync) =====
                    sectionLabel("Mac")
                    setCard {
                        cardItem {
                            HStack(spacing: 0) {
                                Text("Sync").font(.geist(18, .regular)).tracking(-0.36).foregroundStyle(theme.sheetLabel)
                                Spacer()
                                Text(syncStatusText).font(.geist(14, .regular)).foregroundStyle(theme.sheetFaint)
                            }
                            if isConnected {
                                setButton("Disconnect") { disconnect() }
                                    .padding(.top, 16)
                            } else {
                                VStack(spacing: 8) {
                                    setSplit(("Scan QR to pair", { pairError = nil; showScanner = true }),
                                             (manualExpanded ? "Hide" : "Enter manually", { withAnimation { manualExpanded.toggle() } }))
                                    if manualExpanded {
                                        // Hosted builds (BuddyCloud present) never show server tooling —
                                        // the backend is part of the service. Manual entry is just the sync
                                        // key (camera-broken fallback); server fields are the OSS edition's UI.
                                        if !BuddyCloud.present {
                                            syncField("Backend URL", text: $fURL, keyboard: .URL)
                                            syncField("Anon key", text: $fAnon)
                                        }
                                        syncField("Sync key (43 characters)", text: $fKey)
                                        setButton("Connect") { connect() }
                                    }
                                }
                                .padding(.top, 16)
                            }
                            if let e = pairError {
                                // red-on-red is invisible on the lvl2 sheet → white + semibold there.
                                Text(e).font(.geist(14, theme.level == .lvl2 ? .semibold : .regular))
                                    .foregroundStyle(theme.errorText).padding(.top, 10)
                            }
                        }
                    }

                    // ===== YOUR DATA =====
                    sectionLabel("Your data")
                    setCard {
                        cardItem {
                            ShareLink(item: store.doneExport.joined(separator: "\n")) {
                                setButtonLabel("Export my done tasks")
                            }
                            .buttonStyle(.plain)
                            Text("\(store.doneExport.count) done task\(store.doneExport.count == 1 ? "" : "s")")
                                .font(.geist(14, .regular)).tracking(-0.26).foregroundStyle(theme.sheetFaint)
                                .padding(.top, 16)
                        }
                    }

                    // ===== APP =====
                    sectionLabel("App")
                    setCard {
                        cardItem {
                            setButton(bugReportMessage ?? "Report a bug") { Task { await submitBugReport() } }
                            #if DEBUG
                            setSplit(("Reset data", { store.resetForDev(); onClose() }), ("Restart", { exit(0) }))
                                .padding(.top, 8)
                            #endif
                            Text("Buddy Version \(appVersion) (basically a toddler)")
                                .font(.geist(14, .regular)).tracking(-0.26).foregroundStyle(theme.sheetGhost)
                                .padding(.top, 16)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
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

    // MARK: - Grouped-card layout helpers (Mac redesign parity)

    @ViewBuilder private func sectionLabel(_ text: String, first: Bool = false) -> some View {
        Text(text.uppercased())
            .font(.geist(12, .semibold)).tracking(0.6)
            .foregroundStyle(theme.setSectionLabel)
            .padding(.leading, 16)                 // 16(body)+16(card pad) = 32 rail with row labels
            .padding(.top, first ? 8 : 22).padding(.bottom, 10)
    }

    @ViewBuilder private func setCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.setCard, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func cardItem<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    private func setButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { setButtonLabel(title) }.buttonStyle(.plain)
    }

    private func setButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.geist(15, .regular)).tracking(-0.30)
            .foregroundStyle(theme.sheetLabel)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(theme.setButton, in: Capsule())
            .overlay(Capsule().stroke(theme.line, lineWidth: 1))
            .contentShape(Capsule())
    }

    @ViewBuilder private func setSplit(_ a: (String, () -> Void), _ b: (String, () -> Void)) -> some View {
        HStack(spacing: 8) { setButton(a.0, a.1); setButton(b.0, b.1) }
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

    // MARK: - Sync helpers

    private var isConnected: Bool { sync?.currentConfig.isSyncable ?? false }

    private var syncStatusText: String {
        guard let sync else { return "Off" }
        // Bucket id prefix (the Mac shows the same 6 chars): two devices showing
        // the same suffix are provably on the same sync bucket — split-brain
        // pairings sync "fine" but never see each other (field report 2026-07-10).
        // BACKEND-AWARE display id (sha256(url|syncKey), Mac parity): same 6 chars on
        // two devices now proves same bucket AND same backend. The url is NORMALIZED
        // (trailing slashes, case) exactly like the Mac's syncDisplayId.
        let live = sync.currentConfig.resolved
        var normUrl = live.backendUrl.lowercased()
        while normUrl.hasSuffix("/") { normUrl.removeLast() }
        let bucket = live.isSyncable
            ? " · " + String(SyncIdentity.ownerId(for: normUrl + "|" + live.syncKey).prefix(6)) : ""
        if sync.currentConfig.enabled, sync.lastError != nil, sync.lastSyncedAt == nil { return "Error" + bucket }
        if let t = sync.lastSyncedAt { return "Synced \(Self.hm.string(from: t))" + bucket }
        if sync.currentConfig.isSyncable { return "Connected" + bucket }
        return "Not connected"
    }
    private static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    private func applyScanned(_ s: String) {
        showScanner = false
        guard let p = SyncIdentity.parse(s) else {
            pairError = "That QR code isn’t a Buddy pairing code."; manualExpanded = true; return
        }
        fURL = p.backendUrl; fAnon = p.anonKey; fKey = p.syncKey
        scannedCloud = p.cloud
        connect()
    }

    private func connect() {
        // Manual entry on a hosted build: the user only typed the sync key — fill the
        // backend from BuddyCloud (the fields aren't shown; see manualExpanded above).
        if BuddyCloud.present && fURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fURL = BuddyCloud.url!; fAnon = BuddyCloud.anon!; scannedCloud = true
        }
        let cfg = SyncConfig(backendUrl: fURL.trimmingCharacters(in: .whitespacesAndNewlines),
                             anonKey: fAnon.trimmingCharacters(in: .whitespacesAndNewlines),
                             syncKey: fKey.trimmingCharacters(in: .whitespacesAndNewlines),
                             enabled: true,
                             cloud: scannedCloud)
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
