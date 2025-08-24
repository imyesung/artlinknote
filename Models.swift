// GOAL: Note model, NotesStore, Keychain helper, JSON persistence.
// - NotesStore: @Published notes[], create/upsert/delete/toggleStar, filtered(query, filter)
// - fileURL: Documents/notes.json; load() async; saveAsync() detached & atomic (later step)
// - Keychain: simple add/update/read for "OPENAI_API_KEY" (later step)
// No external deps. No force unwraps. Unit-test friendly pure helpers.
//
// Phase 1: Define Note model
// Phase 2: Add NotesStore skeleton (this update) WITHOUT persistence yet.

import Foundation
import Combine

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

// MARK: - Filtering Support
/// Filter modes for list segmentation.
enum NoteFilter: String, CaseIterable, Identifiable { // Identifiable for UI Segmented Picker
    case all
    case starred
    var id: String { rawValue }
}

// MARK: - NotesStore Skeleton (no persistence yet)
/// Observable container for notes with basic CRUD and filtering logic.
/// Persistence, debounce save & keychain will be added in subsequent atomic steps.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note]
    
    init(notes: [Note] = []) {
        self.notes = notes
    }
    
    // MARK: Creation
    /// Create and append a new blank note; returns it for immediate editing.
    @discardableResult
    func createNew() -> Note {
        var note = Note.blank()
        note.touch()
        notes.insert(note, at: 0) // newest first
        return note
    }
    
    // MARK: Upsert
    /// Insert or replace a note by id; updates timestamp if body/title changed.
    func upsert(_ note: Note) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.insert(note, at: 0)
        }
    }
    
    // MARK: Delete
    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
    }
    
    // MARK: Star Toggle
    func toggleStar(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].starred.toggle()
        notes[idx].touch()
        // Re-sort to keep most recently touched first.
        sortInPlace()
    }
    
    // MARK: Filtering
    /// Returns notes filtered by query & filter, sorted by updatedAt desc.
    func filtered(query: String, filter: NoteFilter) -> [Note] {
        let trimmedQuery = query.trimmed().lowercased()
        return notes
            .lazy
            .filter { n in
                switch filter { case .all: return true; case .starred: return n.starred }
            }
            .filter { n in
                guard !trimmedQuery.isEmpty else { return true }
                return n.title.lowercased().contains(trimmedQuery) || n.body.lowercased().contains(trimmedQuery)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    
    // MARK: Sorting Helper
    private func sortInPlace() {
        notes.sort { $0.updatedAt > $1.updatedAt }
    }
}

// Placeholder for forthcoming types (added in later atomic steps to honor 5-file limit):
// enum KeychainError: Error { /* to be implemented */ }
// struct KeychainHelper { /* to be implemented */ }
// Persistence (load/save, debounce) will be appended here next.
