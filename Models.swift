// GOAL: Note model, NotesStore, Keychain helper, JSON persistence.
// - NotesStore: @Published notes[], create/upsert/delete/toggleStar, filtered(query, filter)
// - fileURL: Documents/notes.json; load() async; saveAsync() detached & atomic
// - Keychain: simple add/update/read for "OPENAI_API_KEY"
// No external deps. No force unwraps. Unit-test friendly pure helpers.
//
// Phase 1: Define Note model (atomic minimal step per build contract). Other components added incrementally.

import Foundation

/// Core note domain model. Codable for JSON persistence; Hashable for diffable lists.
struct Note: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var starred: Bool
    var updatedAt: Date
    
    /// True if both title and body are empty/whitespace after trimming.
    var isEmpty: Bool {
        title.trimmed().isEmpty && body.trimmed().isEmpty
    }
    
    /// Update the modification timestamp to now.
    mutating func touch() { updatedAt = Date() }
    
    /// Create a new empty note (e.g. for New button action).
    static func blank() -> Note {
        Note(id: UUID(), title: "", body: "", starred: false, updatedAt: Date())
    }
}

// MARK: - Sample Seed Data (used when load fails)
extension Note {
    static let sampleA = Note(
        id: UUID(),
        title: "Beat Shift Monologue", 
        body: "Character wrestles with self-doubt then pivots to resolve.", 
        starred: true, 
        updatedAt: Date().addingTimeInterval(-3600)
    )
    static let sampleB = Note(
        id: UUID(),
        title: "Cold Read Practice", 
        body: "Focus on pacing. Emphasize subtext in second paragraph.", 
        starred: false, 
        updatedAt: Date().addingTimeInterval(-7200)
    )
    static var seed: [Note] { [sampleA, sampleB] }
}

// MARK: - Internal Helpers
fileprivate extension String {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// Placeholder for forthcoming types (added in later atomic steps to honor 5-file limit):
// final class NotesStore: ObservableObject { /* to be implemented next */ }
// enum KeychainError: Error { /* to be implemented */ }
// struct KeychainHelper { /* to be implemented */ }
