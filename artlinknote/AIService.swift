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
    func extractKeywords(for text: String) async throws -> [String]
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

struct KeywordsResponse: Codable {
    let keywords: [String]
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
        let isKorean = detectKorean(in: text)
        let systemPrompt = isKorean ? """
        당신은 배우와 크리에이티브를 위한 제목 생성기입니다. 주어진 노트 내용에 대해 간결하고 기억에 남는 제목(48자 이내)을 생성하세요.
        주요 테마, 감정, 또는 핵심 행동에 집중하세요. 일반적인 제목은 피하세요.
        반드시 유효한 JSON만 반환하세요: {"title": "제목을 여기에"}
        """ : """
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
        let isKorean = detectKorean(in: text)
        let systemPrompt = isKorean ? """
        당신은 배우를 위한 리허설 코치입니다. 주어진 씬/모노로그에 대해 로그라인과 1-5개의 핵심 비트를 만드세요.
        로그라인: 핵심 갈등이나 여정을 한 문장으로 요약(120자 이내).
        비트: 핵심 감정/행동 변화, 각각 80자 이내.
        반드시 유효한 JSON만 반환하세요: {"logline": "...", "beats": ["비트1", "비트2", ...]}
        """ : """
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
        let isKorean = detectKorean(in: text)
        let systemPrompt = isKorean ? """
        당신은 크리에이티브 노트를 위한 태그 생성기입니다. 텍스트에서 1-5개의 관련 해시태그를 추출하세요.
        태그는 소문자, 공백 없이, 테마, 감정, 기법, 또는 주제와 관련되어야 합니다.
        예시: #모노로그 #갈등 #리허설 #캐릭터 #감정 #기법
        반드시 유효한 JSON만 반환하세요: {"tags": ["#태그1", "#태그2", ...]}
        """ : """
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
    
    func extractKeywords(for text: String) async throws -> [String] {
        let isKorean = detectKorean(in: text)
        let systemPrompt = isKorean ? """
        당신은 지능형 키워드 분석기입니다. 주어진 텍스트에서 가장 핵심적이고 중요한 키워드 3-6개를 정확하게 추출하세요.
        
        텍스트의 주제와 맥락을 정확히 파악하여 해당 분야에 적합한 키워드를 추출하세요:
        - 기술/개발: 알고리즘, 성능, 최적화, 구조 등
        - 연기/예술: 감정, 표현, 캐릭터, 기법 등  
        - 일반 주제: 해당 분야의 핵심 개념들
        
        키워드는:
        1. 명사 형태로 추출
        2. 조사(은/는/이/가/을/를/의/에/로 등) 제거
        3. 텍스트 내용과 직접적으로 관련된 것만
        4. 너무 일반적이거나 모호한 단어 제외
        
        반드시 유효한 JSON만 반환하세요: {"keywords": ["키워드1", "키워드2", ...]}
        """ : """
        You are an intelligent keyword analyzer. Extract 3-6 most essential and relevant keywords from the given text.
        
        Accurately understand the topic and context of the text to extract appropriate keywords for that field:
        - Tech/Development: algorithms, performance, optimization, architecture, etc.
        - Acting/Arts: emotions, expression, character, techniques, etc.
        - General topics: core concepts of the respective field
        
        Keywords should be:
        1. In noun form
        2. Directly related to the text content
        3. Specific rather than generic or vague
        4. Representative of the main concepts
        
        Return only valid JSON: {"keywords": ["keyword1", "keyword2", ...]}
        """
        
        let response: KeywordsResponse = try await makeRequest(
            systemPrompt: systemPrompt,
            userText: text,
            responseType: KeywordsResponse.self
        )
        
        // Clean and validate keywords
        let cleanKeywords = response.keywords.compactMap { keyword in
            let cleaned = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            // Validate keyword quality
            if cleaned.count >= 2 && cleaned.count <= 15 && !cleaned.isEmpty {
                return cleaned
            }
            return nil
        }
        
        return cleanKeywords.isEmpty ? heuristicKeywords(from: text) : Array(cleanKeywords.prefix(6))
    }
    
    // MARK: - Language Detection
    private func detectKorean(in text: String) -> Bool {
        let koreanCharacterSet = CharacterSet(charactersIn: "\u{AC00}"..."\u{D7A3}") // 한글 유니코드 범위
        return text.rangeOfCharacter(from: koreanCharacterSet) != nil
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
        let isKorean = detectKorean(in: text)
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if words.isEmpty {
            return isKorean ? "제목 없음" : "Untitled Note"
        }
        
        // Take first meaningful phrase (up to 6 words, ≤48 chars)
        var title = ""
        for word in words.prefix(6) {
            let candidate = title.isEmpty ? word : "\(title) \(word)"
            if candidate.count > 48 { break }
            title = candidate
        }
        
        return title.isEmpty ? (isKorean ? "제목 없음" : "Untitled Note") : title
    }
    
    private func heuristicSummary(from text: String) -> RehearsalSummary {
        let isKorean = detectKorean(in: text)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let defaultLogline = isKorean ? "연습용 씬 또는 모노로그" : "Practice scene or monologue"
        let logline = lines.first?.prefix(120).description ?? defaultLogline
        let beats = lines.prefix(3).map { String($0.prefix(80)) }
        
        let defaultBeats = isKorean ? ["장면 시작", "긴장감 조성", "결말 도출"] : ["Begin scene", "Build tension", "Find resolution"]
        
        return RehearsalSummary(
            logline: String(logline),
            beats: beats.isEmpty ? defaultBeats : beats
        )
    }
    
    private func heuristicTags(from text: String) -> [String] {
        let isKorean = detectKorean(in: text)
        let lowercased = text.lowercased()
        
        if isKorean {
            let koreanTags = [
                ("#리허설", ["리허설", "연습", "씬", "장면"]),
                ("#모노로그", ["모노로그", "독백", "연설"]),
                ("#캐릭터", ["캐릭터", "인물", "역할"]),
                ("#감정", ["감정", "기분", "화남", "슬픔", "기쁨"]),
                ("#기법", ["기법", "방법", "접근", "스킬"])
            ]
            
            let matched = koreanTags.compactMap { (tag, keywords) in
                keywords.contains { lowercased.contains($0) } ? tag : nil
            }
            return Array(matched.prefix(3)) + (matched.isEmpty ? ["#노트"] : [])
        } else {
            let englishTags = [
                ("#rehearsal", ["rehearsal", "practice", "scene"]),
                ("#monologue", ["monologue", "solo", "speech"]),
                ("#character", ["character", "role", "person"]),
                ("#emotion", ["feel", "emotion", "mood", "angry", "sad", "happy"]),
                ("#technique", ["technique", "method", "approach", "skill"])
            ]
            
            let matched = englishTags.compactMap { (tag, keywords) in
                keywords.contains { lowercased.contains($0) } ? tag : nil
            }
            return Array(matched.prefix(3)) + (matched.isEmpty ? ["#note"] : [])
        }
    }
    
    private func heuristicKeywords(from text: String) -> [String] {
        let isKorean = detectKorean(in: text)
        let lowercased = text.lowercased()
        
        if isKorean {
            // 기술/개발 관련
            let techKeywords = ["알고리즘", "스케줄링", "최적화", "성능", "멀티코어", "CPU", "메모리", "프로세서", "시스템", "구조", "설계", "분석"]
            // 연기/예술 관련  
            let actingKeywords = ["감정", "표현", "캐릭터", "연기", "기법", "즉흥", "호흡", "발성", "갈등", "긴장"]
            // 일반적인 중요 키워드
            let generalKeywords = ["방법", "전략", "과정", "결과", "문제", "해결", "개선", "효과", "영향", "변화"]
            
            let allKeywords = techKeywords + actingKeywords + generalKeywords
            let matched = allKeywords.filter { lowercased.contains($0) }
            
            // 매칭되는 키워드가 없으면 텍스트에서 직접 추출
            if matched.isEmpty {
                let words = text.components(separatedBy: .whitespacesAndNewlines)
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;()[]{}\"'")) }
                    .filter { $0.count >= 2 && $0.count <= 10 }
                    .prefix(3)
                return Array(words)
            }
            
            return Array(matched.prefix(6))
        } else {
            // 기술/개발 관련
            let techKeywords = ["algorithm", "scheduling", "optimization", "performance", "multicore", "cpu", "memory", "processor", "system", "architecture", "design", "analysis"]
            // 연기/예술 관련
            let actingKeywords = ["emotion", "expression", "character", "acting", "technique", "improvisation", "breathing", "voice", "conflict", "tension"]
            // 일반적인 중요 키워드
            let generalKeywords = ["method", "strategy", "process", "result", "problem", "solution", "improvement", "effect", "impact", "change"]
            
            let allKeywords = techKeywords + actingKeywords + generalKeywords
            let matched = allKeywords.filter { lowercased.contains($0) }
            
            // 매칭되는 키워드가 없으면 텍스트에서 직접 추출
            if matched.isEmpty {
                let words = text.components(separatedBy: .whitespacesAndNewlines)
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;()[]{}\"'")) }
                    .filter { $0.count >= 2 && $0.count <= 10 }
                    .prefix(3)
                return Array(words)
            }
            
            return Array(matched.prefix(6))
        }
    }
}

// KeychainHelper is implemented in Models.swift