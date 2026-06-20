import SwiftUI

// MARK: - SettingsView
// A sheet showing: celebrate intensity slider, history days slider, and a
// disabled "Sync — set up on Mac (coming)" placeholder row.
// Mirrors the Mac app's settings sheet (gear button).
struct SettingsView: View {
    @Bindable var store: BuddyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    // Local mirror of store.settings so we can preview changes live
    @State private var celebrate: Double = 100
    @State private var historyDays: Double = 7
    @State private var showEraseConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // Celebration intensity
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Celebration")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            if reducedMotion {
                                Text("Reduced motion — system override")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Slider(value: $celebrate, in: 0...100, step: 1)
                            .disabled(reducedMotion)
                            .tint(.black)
                            .onChange(of: celebrate) { _, v in
                                store.settings.celebrate = Int(v)
                            }
                        HStack {
                            Text("Off")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Full")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Confetti")
                }

                // History days
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(historyDaysLabel)
                            .font(.system(size: 16, weight: .medium))
                        Slider(value: $historyDays, in: 0...14, step: 1)
                            .tint(.black)
                            .onChange(of: historyDays) { _, v in
                                store.settings.historyDays = Int(v)
                            }
                        HStack {
                            Text("Off")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("14 days")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("History")
                }

                // Sync placeholder — DO NOT implement; another layer owns this
                Section {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync")
                                .foregroundStyle(.secondary)
                            Text("Set up on Mac (coming)")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("Coming")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("Account")
                }
                .disabled(true)

                // Erase all data — mirrors the Mac's eraseAll(); stamps erasedAt so a
                // real wipe propagates over sync (the merge treats it as a barrier).
                Section {
                    Button(role: .destructive) {
                        showEraseConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Erase all data")
                        }
                    }
                } header: {
                    Text("Danger zone")
                } footer: {
                    Text("Removes every task and all history on this device. This can't be undone.")
                }
            }
            .alert("Erase all data?", isPresented: $showEraseConfirm) {
                Button("Erase", role: .destructive) { store.eraseAll(); dismiss() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes every task and all history on this device. This can't be undone.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                celebrate = Double(store.settings.celebrate)
                historyDays = Double(store.settings.historyDays)
            }
        }
    }

    private var historyDaysLabel: String {
        let n = Int(historyDays)
        if n <= 0 { return "No history" }
        return "\(n) day\(n == 1 ? "" : "s") of history"
    }
}

// MARK: - Previews
#Preview {
    SettingsView(store: {
        let s = BuddyStore()
        return s
    }())
}
