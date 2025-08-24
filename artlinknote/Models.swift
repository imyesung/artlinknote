// GOAL: Note model, NotesStore, Keychain helper, JSON persistence.
// (Moved into app target folder for compilation.)

import Foundation
import Combine

struct Note: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var starred: Bool
    var updatedAt: Date
    var isEmpty: Bool { title.trimmed().isEmpty && body.trimmed().isEmpty }
    mutating func touch() { updatedAt = Date() }
    static func blank() -> Note { Note(id: UUID(), title: "", body: "", starred: false, updatedAt: Date()) }
}

extension Note {
    static let sampleA = Note(id: UUID(), title: "Beat Shift Monologue", body: "Character wrestles with self-doubt then pivots to resolve.", starred: true, updatedAt: Date().addingTimeInterval(-3600))
    static let sampleB = Note(id: UUID(), title: "Cold Read Practice", body: "Focus on pacing. Emphasize subtext in second paragraph.", starred: false, updatedAt: Date().addingTimeInterval(-7200))
    static var seed: [Note] { [sampleA, sampleB] }
}

extension String { func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) } }

enum NoteFilter: String, CaseIterable, Identifiable { case all, starred; var id: String { rawValue } }

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note]
    private var pendingSaveTask: Task<Void, Never>? = nil
    private let saveDelay: UInt64 = 300_000_000
    
    init(notes: [Note] = []) { self.notes = notes }
    
    @discardableResult
    func createNew() -> Note { var note = Note.blank(); note.touch(); notes.insert(note, at: 0); scheduleSave(); return note }
    func upsert(_ note: Note) { if let i = notes.firstIndex(where: { $0.id == note.id }) { notes[i] = note } else { notes.insert(note, at: 0) }; scheduleSave() }
    func delete(id: UUID) { notes.removeAll { $0.id == id }; scheduleSave() }
    func toggleStar(id: UUID) { guard let i = notes.firstIndex(where: { $0.id == id }) else { return }; notes[i].starred.toggle(); notes[i].touch(); sortInPlace(); scheduleSave() }
    func filtered(query: String, filter: NoteFilter) -> [Note] { let q = query.trimmed().lowercased(); return notes.lazy.filter { filter == .all ? true : $0.starred }.filter { n in q.isEmpty || n.title.lowercased().contains(q) || n.body.lowercased().contains(q) }.sorted { $0.updatedAt > $1.updatedAt } }
    func load() async { do { let data = try Data(contentsOf: Self.fileURL); notes = try Self.parseNotes(from: data) } catch { notes = Note.seed }; sortInPlace() }
    private func sortInPlace() { notes.sort { $0.updatedAt > $1.updatedAt } }
    private func scheduleSave() { pendingSaveTask?.cancel(); let snap = notes; pendingSaveTask = Task { [snap] in try? await Task.sleep(nanoseconds: saveDelay); await performSave(snapshot: snap) } }
    private func performSave(snapshot: [Note]) async { do { let data = try Self.makeData(from: snapshot); try await Self.atomicWrite(data: data, to: Self.fileURL) } catch { /* swallow */ } }
}

extension NotesStore {
    enum PersistenceError: Error { case encodingFailed, decodingFailed, writeFailed }
    static var fileURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("notes.json") ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notes.json") }
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    static func makeData(from notes: [Note]) throws -> Data { do { return try encoder.encode(notes) } catch { throw PersistenceError.encodingFailed } }
    static func parseNotes(from data: Data) throws -> [Note] { do { return try decoder.decode([Note].self, from: data) } catch { throw PersistenceError.decodingFailed } }
    static func atomicWrite(data: Data, to url: URL) async throws { do { try data.write(to: url, options: .atomic) } catch { throw PersistenceError.writeFailed } }
}
