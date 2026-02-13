// GOAL: Note model, NotesStore, Keychain helper, JSON persistence.
// (Moved into app target folder for compilation.)

import Foundation
import Combine
#if canImport(Security)
import Security
#endif

struct Note: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var starred: Bool
    var updatedAt: Date
    // Tier A extensions
    var levelSummaries: [Int: String]? // zoom summaries cache (1=line,2=bullets,3=brief,4=full)
    var beatsCache: [String]? // extracted beat segments (order preserved)
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

// MARK: - Keychain (API Key)
enum KeychainError: Error {
    case itemNotFound
    case unexpectedData
    case unhandled(OSStatus)
}

struct KeychainHelper {
    private static let service = "ArtlinkAI"
    private static let account = "OPENAI_API_KEY"

    static func save(apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        #if canImport(Security)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let findQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attrs: [String: Any] = [kSecValueData as String: data]
            let upd = SecItemUpdate(findQuery as CFDictionary, attrs as CFDictionary)
            guard upd == errSecSuccess else { throw KeychainError.unhandled(upd) }
            return
        }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        #else
        // Fallback (non-Apple platform): No-op
        #endif
    }

    static func loadAPIKey() throws -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = item as? Data, let str = String(data: data, encoding: .utf8) else { throw KeychainError.unexpectedData }
        return str
        #else
        return nil
        #endif
    }

    static func deleteAPIKey() throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        #else
        // No-op
        #endif
    }
}

// MARK: - Improved Heuristics (Summaries + Beats + Keywords)
extension NotesStore {
    enum SummaryLevel: Int, CaseIterable {
        case keywords = 1
        case line = 2
        case brief = 3
        case full = 4

        var displayName: String {
            switch self {
            case .keywords: return "Keywords"
            case .line: return "Line"
            case .brief: return "Brief"
            case .full: return "Full"
            }
        }

        var icon: String {
            switch self {
            case .keywords: return "key.horizontal"
            case .line: return "text.line.first.and.arrowtriangle.forward"
            case .brief: return "doc.plaintext"
            case .full: return "square.and.pencil"
            }
        }
    }

    // MARK: - Extended Stopwords
    private var koreanStopwords: Set<String> {
        ["이", "그", "저", "것", "수", "등", "들", "및", "에", "의", "를", "을", "가", "는", "은", "로", "으로",
         "에서", "와", "과", "도", "만", "이런", "저런", "그런", "어떤", "무슨", "이것", "저것", "그것",
         "하다", "되다", "있다", "없다", "같다", "보다", "주다", "받다", "하고", "하는", "하면", "해서",
         "그리고", "하지만", "그러나", "그래서", "따라서", "또한", "즉", "왜냐하면", "때문에", "위해"]
    }

    private var englishStopwords: Set<String> {
        ["the", "a", "an", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had",
         "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "shall",
         "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
         "my", "your", "his", "its", "our", "their", "this", "that", "these", "those",
         "and", "or", "but", "if", "then", "else", "when", "where", "why", "how", "what", "which",
         "in", "on", "at", "to", "for", "of", "with", "by", "from", "as", "into", "through",
         "just", "also", "very", "really", "only", "even", "about", "after", "before", "more"]
    }

    // Acting domain keywords for boosting
    private var actingKeywords: Set<String> {
        ["감정", "캐릭터", "연기", "대사", "장면", "동기", "목표", "갈등", "서브텍스트", "비트",
         "emotion", "character", "acting", "dialogue", "scene", "motivation", "objective",
         "conflict", "subtext", "beat", "monologue", "rehearsal", "technique"]
    }

    func summary(for note: Note, level: SummaryLevel) -> String {
        if level == .full { return note.body }

        let generated = makeSummary(note.body, level: level)
        return generated.isEmpty ? note.body : generated
    }

    func beats(for note: Note) -> [String] {
        return extractBeats(from: note.body)
    }

    private func cacheSummary(_ text: String, for id: UUID, level: SummaryLevel) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var map = notes[i].levelSummaries ?? [:]
        map[level.rawValue] = text
        notes[i].levelSummaries = map
        scheduleSave()
    }

    private func cacheBeats(_ beats: [String], for id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].beatsCache = beats
        scheduleSave()
    }

    // MARK: - Improved Summary Generation
    private func makeSummary(_ body: String, level: SummaryLevel) -> String {
        let sentences = splitSentences(body)
        guard !sentences.isEmpty else { return body }

        switch level {
        case .keywords:
            let kws = topKeywords(from: body, maxCount: 5)
            return kws.map { "• \($0)" }.joined(separator: "\n")

        case .line:
            // Find the most representative single line
            let bestSentence = findBestSentence(from: sentences, body: body)
            if bestSentence.count <= 120 {
                return bestSentence
            }
            // Smart truncation at word boundary
            let words = bestSentence.components(separatedBy: .whitespaces)
            var result = ""
            for word in words {
                let candidate = result.isEmpty ? word : "\(result) \(word)"
                if candidate.count > 117 { break }
                result = candidate
            }
            return result + "…"

        case .brief:
            // Score and select top 3 sentences
            let scoredSentences = sentences.map { sentence -> (String, Double) in
                var score = 0.0

                // Position bonus
                if sentence == sentences.first { score += 2.0 }
                if sentence == sentences.last { score += 1.0 }

                // Length preference (medium length is best)
                let wordCount = sentence.components(separatedBy: .whitespaces).count
                if wordCount >= 5 && wordCount <= 20 { score += 1.5 }

                // Keyword density
                let kwCount = actingKeywords.filter { sentence.lowercased().contains($0) }.count
                score += Double(kwCount) * 2.0

                return (sentence, score)
            }

            let topSentences = scoredSentences
                .sorted { $0.1 > $1.1 }
                .prefix(3)
                .map { $0.0 }

            return topSentences.joined(separator: " ")

        case .full:
            return body
        }
    }

    private func findBestSentence(from sentences: [String], body: String) -> String {
        guard !sentences.isEmpty else { return "" }

        // Score each sentence
        var bestScore = 0.0
        var bestSentence = sentences[0]

        for (index, sentence) in sentences.enumerated() {
            var score = 0.0

            // First sentence bonus
            if index == 0 { score += 3.0 }

            // Appropriate length
            let length = sentence.count
            if length >= 30 && length <= 100 { score += 2.0 }

            // Contains action words
            let actionWords = ["결심", "깨닫", "발견", "선택", "decides", "realizes", "discovers", "chooses", "must", "needs"]
            for word in actionWords {
                if sentence.lowercased().contains(word) { score += 1.5 }
            }

            // Contains domain keywords
            for keyword in actingKeywords {
                if sentence.lowercased().contains(keyword) { score += 1.0 }
            }

            if score > bestScore {
                bestScore = score
                bestSentence = sentence
            }
        }

        return bestSentence
    }

    // MARK: - Improved Beat Extraction
    private func extractBeats(from body: String) -> [String] {
        let lines = body.replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmed() }

        var beats: [String] = []
        var currentBeat = ""
        var lastLineWasEmpty = false

        for line in lines {
            let isEmptyLine = line.isEmpty
            let isSeparator = line.hasPrefix("---") || line.hasPrefix("###") ||
                              line.hasPrefix("***") || line.hasPrefix("===")

            // Detect beat boundary
            let isBeatBoundary = isSeparator || (isEmptyLine && lastLineWasEmpty) ||
                                 (isEmptyLine && !currentBeat.isEmpty && currentBeat.count > 50)

            if isBeatBoundary {
                if !currentBeat.isEmpty {
                    // Trim beat to reasonable length
                    let trimmedBeat = currentBeat.count > 150
                        ? String(currentBeat.prefix(147)) + "..."
                        : currentBeat
                    beats.append(trimmedBeat)
                    currentBeat = ""
                }
            } else if !isEmptyLine {
                if currentBeat.isEmpty {
                    currentBeat = line
                } else {
                    currentBeat += " " + line
                }
            }

            lastLineWasEmpty = isEmptyLine
        }

        // Don't forget the last beat
        if !currentBeat.isEmpty {
            let trimmedBeat = currentBeat.count > 150
                ? String(currentBeat.prefix(147)) + "..."
                : currentBeat
            beats.append(trimmedBeat)
        }

        // Quality control: need at least 2 meaningful beats
        let meaningfulBeats = beats.filter { $0.count >= 15 }

        if meaningfulBeats.count < 2 {
            // Fall back to sentence-based beats
            let sentences = splitSentences(body)
            if sentences.count >= 2 {
                return Array(sentences.prefix(5))
            }
            return []
        }

        return Array(meaningfulBeats.prefix(10))
    }

    // MARK: - Improved Sentence Splitting
    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        for char in text {
            current.append(char)

            // Detect sentence boundary (handles Korean and English)
            let isSentenceEnd = [".", "!", "?", "。", "！", "？"].contains(String(char))
            let isFollowedBySpace = true // simplified

            // Avoid splitting on abbreviations like "Dr.", "Mr.", "etc."
            let isAbbreviation = current.count < 5 && char == "."

            if isSentenceEnd && !isAbbreviation && isFollowedBySpace {
                let trimmed = current.trimmed()
                // Minimum sentence length to filter fragments
                if trimmed.count >= 12 {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        // Handle remaining text
        let remaining = current.trimmed()
        if remaining.count >= 12 {
            sentences.append(remaining)
        }

        return sentences
    }

    // MARK: - Improved Keyword Extraction (TF-IDF style)
    private func topKeywords(from body: String, maxCount: Int) -> [String] {
        let isKorean = body.range(of: "[\u{AC00}-\u{D7A3}]", options: .regularExpression) != nil
        let stopwords = isKorean ? koreanStopwords : englishStopwords

        // Tokenize
        let tokens = body.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !$0.isEmpty }

        // Calculate term frequency with filtering
        var termFreq: [String: Int] = [:]
        for token in tokens {
            guard !stopwords.contains(token) else { continue }
            guard token.count >= 2 && token.count <= 20 else { continue }

            // Skip pure numbers
            guard token.range(of: "^[0-9]+$", options: .regularExpression) == nil else { continue }

            termFreq[token, default: 0] += 1
        }

        // Score terms with domain boost
        var scoredTerms: [(String, Double)] = []
        let totalTokens = Double(tokens.count)
        let divisor = totalTokens > 0 ? totalTokens : 1.0

        for (term, freq) in termFreq {
            // Base TF score (normalized)
            var score = Double(freq) / divisor * 100.0

            // Domain keyword boost
            if actingKeywords.contains(term) {
                score *= 2.5
            }

            // Length preference (longer = more specific)
            if term.count >= 5 { score *= 1.3 }
            if term.count >= 8 { score *= 1.2 }

            // Frequency boost (appearing multiple times is significant)
            if freq >= 3 { score *= 1.5 }

            scoredTerms.append((term, score))
        }

        // Sort by score and return top keywords
        return scoredTerms
            .sorted { $0.1 > $1.1 }
            .prefix(maxCount)
            .map { $0.0 }
    }
}

