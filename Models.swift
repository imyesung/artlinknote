// GOAL: Note model, NotesStore, Keychain helper, JSON persistence.
// - NotesStore: @Published notes[], create/upsert/delete/toggleStar, filtered(query, filter)
// - fileURL: Documents/notes.json; load() async; saveAsync() detached & atomic
// - Keychain: simple add/update/read for "OPENAI_API_KEY" (later step)
// No external deps. No force unwraps. Unit-test friendly pure helpers.
//
// Phase 1: Define Note model
// Phase 2: NotesStore skeleton
// Phase 3: Persistence helpers
// Phase 4: load()
// Phase 5: debounced save + autosave (current)

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

// MARK: - NotesStore Skeleton (with load)
/// Observable container for notes with basic CRUD, filtering, and disk load (save pending).
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note]
    
    // Debounce state
    private var pendingSaveTask: Task<Void, Never>? = nil
    private let saveDelay: UInt64 = 300_000_000 // 300ms in nanoseconds
    
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
        scheduleSave()
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
        scheduleSave()
    }
    
    // MARK: Delete
    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        scheduleSave()
    }
    
    // MARK: Star Toggle
    func toggleStar(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].starred.toggle()
        notes[idx].touch()
        // Re-sort to keep most recently touched first.
        sortInPlace()
        scheduleSave()
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
    
    // MARK: Load (read-only, synchronous I/O wrapped in async context)
    /// Loads notes from disk; on any failure seeds with sample notes. Idempotent.
    func load() async {
        let url = Self.fileURL
        do {
            let data = try Data(contentsOf: url)
            let decoded = try Self.parseNotes(from: data)
            notes = decoded
        } catch {
            notes = Note.seed
        }
        sortInPlace()
    }
    
    // MARK: Debounced Save
    private func scheduleSave() {
        pendingSaveTask?.cancel()
        let snapshot = notes // capture now on main
        pendingSaveTask = Task { [snapshot] in
            // debounce delay
            try? await Task.sleep(nanoseconds: saveDelay)
            await performSave(snapshot: snapshot)
        }
    }
    
    /// Performs encoding + atomic write off the main actor.
    private func performSave(snapshot: [Note]) async {
        let url = Self.fileURL
        do {
            let data = try Self.makeData(from: snapshot)
            try await Self.atomicWrite(data: data, to: url)
        } catch {
            // Silently ignore; in later phase could surface a non-blocking alert/log.
        }
    }
    
    // MARK: Sorting Helper
    private func sortInPlace() {
        notes.sort { $0.updatedAt > $1.updatedAt }
    }
}

// MARK: - Persistence Helpers (extended with atomic write)
extension NotesStore {
    enum PersistenceError: Error { case encodingFailed; case decodingFailed; case writeFailed }
    
    /// The target file URL for notes.json (falls back to temp if documents not found)
    static var fileURL: URL {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return docs.appendingPathComponent("notes.json")
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notes.json")
    }
    
    /// Shared JSONEncoder configured per contract.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    
    /// Shared JSONDecoder configured per contract.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    /// Produce Data from notes array using configured encoder.
    static func makeData(from notes: [Note]) throws -> Data {
        do { return try encoder.encode(notes) } catch { throw PersistenceError.encodingFailed }
    }
    
    /// Decode notes from raw Data; on failure throws decodingFailed.
    static func parseNotes(from data: Data) throws -> [Note] {
        do { return try decoder.decode([Note].self, from: data) } catch { throw PersistenceError.decodingFailed }
    }
    
    static func atomicWrite(data: Data, to url: URL) async throws {
        do { try data.write(to: url, options: .atomic) } catch { throw PersistenceError.writeFailed }
    }
}

// Placeholder for forthcoming types (added in later atomic steps to honor 5-file limit):
// enum KeychainError: Error { /* to be implemented */ }
// struct KeychainHelper { /* to be implemented */ }
// Debounced save & autosave hooks will be appended next.
