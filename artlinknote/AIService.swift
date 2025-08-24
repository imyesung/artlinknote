// GOAL: AIService protocol + OpenAIService implementation + response schemas.
// - Three methods: suggestTitle, rehearsalSummary, extractTags
// - Timeout 12s → fallback to heuristics on network errors
// - JSON mode with strict schemas per README contract
// - Uses Keychain API key, configurable model name
// No external deps. Async/await. Graceful error handling.

import Foundation

// MARK: - AIService Protocol
protocol AIService {
    func suggestTitle(for text: String) async throws -> String
    func rehearsalSummary(for text: String) async throws -> RehearsalSummary
    func extractTags(for text: String) async throws -> [String]
}

// MARK: - Response Schemas
struct RehearsalSummary: Codable {
    let logline: String
    let beats: [String]
}

struct TitleResponse: Codable {
    let title: String
}

struct TagsResponse: Codable {
    let tags: [String]
}

// MARK: - AI Errors
enum AIError: Error, LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case networkTimeout
    case rateLimited
    case decodingFailed
    case emptyResponse
    case serverError(Int)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured. Please add your OpenAI key in Settings."
        case .invalidAPIKey: return "Invalid API key. Please check your OpenAI key in Settings."
        case .networkTimeout: return "Request timed out. Please check your connection."
        case .rateLimited: return "Rate limit exceeded. Please try again later."
        case .decodingFailed: return "Unable to parse AI response. Please try again."
        case .emptyResponse: return "Empty response from AI service."
        case .serverError(let code): return "Server error (\(code)). Please try again."
        case .unknown: return "An unexpected error occurred."
        }
    }
}

// MARK: - OpenAI Service Implementation
final class OpenAIService: AIService {
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let timeout: TimeInterval = 12.0
    private var modelName: String
    
    init(modelName: String = "gpt-4o-mini") {
        self.modelName = modelName
    }
    
    func updateModel(_ name: String) {
        modelName = name
    }
    
    // MARK: - Public AI Methods
    func suggestTitle(for text: String) async throws -> String {
        let systemPrompt = """
        You are a title generator for actors and creatives. Generate a concise, memorable title (≤48 characters) for the given note content. 
        Focus on the main theme, emotion, or key action. Avoid generic titles. 
        Return only valid JSON: {"title": "Your Title Here"}
        """
        
        let response: TitleResponse = try await makeRequest(
            systemPrompt: systemPrompt,
            userText: text,
            responseType: TitleResponse.self
        )
        
        // Fallback if title too long or empty
        let title = response.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.count > 48 {
            return heuristicTitle(from: text)
        }
        return title
    }
    
    func rehearsalSummary(for text: String) async throws -> RehearsalSummary {
        let systemPrompt = """
        You are a rehearsal coach for actors. Create a logline and 1-5 key beats for the given scene/monologue.
        Logline: One sentence capturing the core conflict or journey (≤120 chars).
        Beats: Key emotional/action shifts, each ≤80 chars.
        Return only valid JSON: {"logline": "...", "beats": ["beat1", "beat2", ...]}
        """
        
        let response: RehearsalSummary = try await makeRequest(
            systemPrompt: systemPrompt,
            userText: text,
            responseType: RehearsalSummary.self
        )
        
        // Validate and fallback if needed
        let logline = response.logline.trimmingCharacters(in: .whitespacesAndNewlines)
        let beats = response.beats.compactMap { beat in
            let trimmed = beat.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.count > 80 ? nil : trimmed
        }
        
        if logline.isEmpty {
            return heuristicSummary(from: text)
        }
        
        return RehearsalSummary(
            logline: logline.count > 120 ? String(logline.prefix(120)) : logline,
            beats: beats.isEmpty ? heuristicSummary(from: text).beats : Array(beats.prefix(5))
        )
    }
    
    func extractTags(for text: String) async throws -> [String] {
        let systemPrompt = """
        You are a content tagger for creative notes. Extract 1-5 relevant hashtags from the text.
        Tags should be lowercase, no spaces, relevant to themes, emotions, techniques, or subjects.
        Examples: #monologue #conflict #rehearsal #character #emotion #technique
        Return only valid JSON: {"tags": ["#tag1", "#tag2", ...]}
        """
        
        let response: TagsResponse = try await makeRequest(
            systemPrompt: systemPrompt,
            userText: text,
            responseType: TagsResponse.self
        )
        
        // Clean and validate tags
        let cleanTags = response.tags.compactMap { tag in
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Ensure starts with # and has valid content
            if cleaned.hasPrefix("#") && cleaned.count > 1 && cleaned.count <= 20 {
                return cleaned.components(separatedBy: .whitespaces).first // Remove spaces
            }
            return nil
        }
        
        return cleanTags.isEmpty ? heuristicTags(from: text) : Array(cleanTags.prefix(5))
    }
    
    // MARK: - Core Request Method
    private func makeRequest<T: Codable>(
        systemPrompt: String,
        userText: String,
        responseType: T.Type
    ) async throws -> T {
        // Get API key from keychain
        let apiKey: String
        do {
            guard let key = try KeychainHelper.loadAPIKey(), !key.isEmpty else {
                throw AIError.noAPIKey
            }
            apiKey = key
        } catch {
            throw AIError.noAPIKey
        }
        
        // Prepare request
        guard let url = URL(string: baseURL) else {
            throw AIError.unknown
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        
        // Request body
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ],
            "response_format": ["type": "json_object"],
            "max_tokens": 200,
            "temperature": 0.7
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw AIError.unknown
        }
        
        // Make request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if error.localizedDescription.contains("timeout") {
                throw AIError.networkTimeout
            }
            throw AIError.unknown
        }
        
        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                break
            case 401:
                throw AIError.invalidAPIKey
            case 429:
                throw AIError.rateLimited
            case 400...499:
                throw AIError.serverError(httpResponse.statusCode)
            case 500...599:
                throw AIError.serverError(httpResponse.statusCode)
            default:
                throw AIError.unknown
            }
        }
        
        // Parse OpenAI response wrapper
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty {
                
                // Parse the actual content as our expected type
                let contentData = Data(content.utf8)
                return try JSONDecoder().decode(T.self, from: contentData)
            } else {
                throw AIError.emptyResponse
            }
        } catch is DecodingError {
            throw AIError.decodingFailed
        } catch {
            throw AIError.unknown
        }
    }
}

// MARK: - Heuristic Fallbacks
extension OpenAIService {
    private func heuristicTitle(from text: String) -> String {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if words.isEmpty {
            return "Untitled Note"
        }
        
        // Take first meaningful phrase (up to 6 words, ≤48 chars)
        var title = ""
        for word in words.prefix(6) {
            let candidate = title.isEmpty ? word : "\(title) \(word)"
            if candidate.count > 48 { break }
            title = candidate
        }
        
        return title.isEmpty ? "Untitled Note" : title
    }
    
    private func heuristicSummary(from text: String) -> RehearsalSummary {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let logline = lines.first?.prefix(120).description ?? "Practice scene or monologue"
        let beats = lines.prefix(3).map { String($0.prefix(80)) }
        
        return RehearsalSummary(
            logline: String(logline),
            beats: beats.isEmpty ? ["Begin scene", "Build tension", "Find resolution"] : beats
        )
    }
    
    private func heuristicTags(from text: String) -> [String] {
        let lowercased = text.lowercased()
        let commonTags = [
            ("#rehearsal", ["rehearsal", "practice", "scene"]),
            ("#monologue", ["monologue", "solo", "speech"]),
            ("#character", ["character", "role", "person"]),
            ("#emotion", ["feel", "emotion", "mood", "angry", "sad", "happy"]),
            ("#technique", ["technique", "method", "approach", "skill"])
        ]
        
        return commonTags.compactMap { (tag, keywords) in
            keywords.contains { lowercased.contains($0) } ? tag : nil
        }.prefix(3) + ["#note"]
    }
}

// KeychainHelper is implemented in Models.swift