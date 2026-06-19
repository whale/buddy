import Foundation

// MARK: - Sync protocol stub
//
// NEXT PHASE: Whole-document last-write-wins sync, QR-paired sync key, opt-in
// (local-first by default). This protocol will be implemented when the sync
// layer is built (Phase 3 on Mac, Phase 5 on iOS per IOS-COMPANION-PLAN.md).
//
// Design decisions (locked 2026-06-18):
// - Backend: opt-in Supabase (single table: buddy_state(owner_id, blob jsonb, updated_at))
// - Identity: QR-code device pairing — Mac generates a high-entropy sync key,
//   phone scans it once. No email, no password, no OAuth.
// - Conflict: whole-document last-write-wins by updated_at, overwritten blob
//   saved as local backup before overwrite.
// - Local-only is the default: app boots and works fully without any backend.
//   Sync is opt-in via Settings (paste Supabase URL + anon key).
// - Open-source friendly: no secret committed; contributors bring their own
//   Supabase project or run offline.
//
// See: /Users/whale/Projects/buddy/IOS-COMPANION-PLAN.md § Sync section

protocol SyncClientProtocol {
    /// Pull the latest state from the backend.
    /// Throws if not configured or network unavailable.
    func fetchState() async throws -> BuddyState

    /// Push the current state to the backend.
    /// Throws if not configured or network unavailable.
    func pushState(_ state: BuddyState) async throws
}

// MARK: - Local-only no-op (default until sync is configured)
// Used by the scaffold so the app compiles and runs without any backend.
final class LocalSyncClient: SyncClientProtocol {
    enum SyncError: Error {
        case notConfigured
    }

    func fetchState() async throws -> BuddyState {
        throw SyncError.notConfigured
    }

    func pushState(_ state: BuddyState) async throws {
        throw SyncError.notConfigured
    }
}
