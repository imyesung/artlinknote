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

// MARK: - Improved Heuristic Fallbacks
extension OpenAIService {

    // MARK: - Stopwords (Extended)
    private var koreanStopwords: Set<String> {
        ["이", "그", "저", "것", "수", "등", "들", "및", "에", "의", "를", "을", "가", "이", "는", "은", "로", "으로",
         "에서", "와", "과", "도", "만", "이런", "저런", "그런", "어떤", "무슨", "이것", "저것", "그것",
         "하다", "되다", "있다", "없다", "같다", "보다", "주다", "받다", "하고", "하는", "하면", "해서",
         "그리고", "하지만", "그러나", "그래서", "따라서", "또한", "즉", "왜냐하면", "때문에"]
    }

    private var englishStopwords: Set<String> {
        ["the", "a", "an", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had",
         "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "shall",
         "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
         "my", "your", "his", "its", "our", "their", "this", "that", "these", "those",
         "and", "or", "but", "if", "then", "else", "when", "where", "why", "how", "what", "which",
         "in", "on", "at", "to", "for", "of", "with", "by", "from", "as", "into", "through",
         "during", "before", "after", "above", "below", "between", "under", "again", "further",
         "just", "also", "very", "really", "actually", "basically", "simply", "only", "even"]
    }

    // MARK: - Title Generation (Improved)
    private func heuristicTitle(from text: String) -> String {
        let isKorean = detectKorean(in: text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return isKorean ? "제목 없음" : "Untitled Note"
        }

        // 1. Try to extract first sentence
        let firstSentence = extractFirstSentence(from: trimmed)

        // 2. Find key phrase from the sentence
        let keyPhrase = extractKeyPhrase(from: firstSentence, isKorean: isKorean)

        // 3. If key phrase is good, use it
        if !keyPhrase.isEmpty && keyPhrase.count <= 48 {
            return keyPhrase
        }

        // 4. Fallback: Smart truncation of first sentence
        if firstSentence.count <= 48 {
            return firstSentence
        }

        // 5. Truncate at word boundary
        let words = firstSentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var title = ""
        for word in words {
            let candidate = title.isEmpty ? word : "\(title) \(word)"
            if candidate.count > 45 { break }
            title = candidate
        }

        return title.isEmpty ? (isKorean ? "제목 없음" : "Untitled Note") : title + "..."
    }

    private func extractFirstSentence(from text: String) -> String {
        // Split by sentence-ending punctuation
        let patterns = [".", "!", "?", "。", "！", "？"]
        var endIndex = text.endIndex

        for pattern in patterns {
            if let range = text.range(of: pattern) {
                if range.lowerBound < endIndex {
                    endIndex = range.upperBound
                }
            }
        }

        let sentence = String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)

        // If no sentence found or too long, take first 120 chars
        if sentence.isEmpty || sentence.count > 120 {
            return String(text.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sentence
    }

    private func extractKeyPhrase(from sentence: String, isKorean: Bool) -> String {
        let words = sentence.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }

        let stopwords = isKorean ? koreanStopwords : englishStopwords

        // Find content words (non-stopwords)
        let contentWords = words.filter { word in
            let lower = word.lowercased()
            return lower.count >= 2 && !stopwords.contains(lower)
        }

        // Take first 4-6 content words
        let keyWords = Array(contentWords.prefix(6))

        if keyWords.count >= 2 {
            return keyWords.joined(separator: " ")
        }

        return ""
    }

    // MARK: - Summary Generation (Improved)
    private func heuristicSummary(from text: String) -> RehearsalSummary {
        let isKorean = detectKorean(in: text)
        let sentences = splitIntoSentences(text)

        if sentences.isEmpty {
            let defaultLogline = isKorean ? "연습용 씬 또는 모노로그" : "Practice scene or monologue"
            let defaultBeats = isKorean
                ? ["장면 시작", "긴장감 조성", "결말 도출"]
                : ["Begin scene", "Build tension", "Find resolution"]
            return RehearsalSummary(logline: defaultLogline, beats: defaultBeats)
        }

        // Score sentences for importance
        let scoredSentences = sentences.enumerated().map { (index, sentence) -> (String, Double) in
            var score = 0.0

            // Position score: first and last sentences are important
            if index == 0 { score += 3.0 }
            if index == sentences.count - 1 { score += 2.0 }

            // Length score: medium-length sentences are better
            let wordCount = sentence.components(separatedBy: .whitespaces).count
            if wordCount >= 5 && wordCount <= 25 { score += 2.0 }

            // Keyword density score
            let keywords = isKorean ? actingKeywordsKorean : actingKeywordsEnglish
            let matchCount = keywords.filter { sentence.lowercased().contains($0) }.count
            score += Double(matchCount) * 1.5

            // Action verb score (indicates dramatic beats)
            let actionVerbs = isKorean
                ? ["결심", "깨닫", "발견", "마주", "직면", "선택", "포기", "시작", "끝", "변화"]
                : ["decides", "realizes", "discovers", "faces", "chooses", "abandons", "begins", "ends", "changes", "reveals"]
            let actionCount = actionVerbs.filter { sentence.lowercased().contains($0) }.count
            score += Double(actionCount) * 2.0

            return (sentence, score)
        }

        // Best sentence for logline
        let sortedByScore = scoredSentences.sorted { $0.1 > $1.1 }
        let logline = String(sortedByScore.first?.0.prefix(120) ?? "")

        // Extract beats: find turning points or distinct sections
        let beats = extractBeats(from: text, sentences: sentences, isKorean: isKorean)

        return RehearsalSummary(
            logline: logline.isEmpty ? (isKorean ? "캐릭터의 여정" : "A character's journey") : logline,
            beats: beats.isEmpty ? (isKorean ? ["시작", "전개", "마무리"] : ["Beginning", "Development", "Resolution"]) : beats
        )
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        // Better sentence splitting
        var sentences: [String] = []
        var current = ""

        for char in text {
            current.append(char)

            // Check for sentence endings
            if [".", "!", "?", "。", "！", "？"].contains(String(char)) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 10 { // Minimum sentence length
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        // Don't forget remaining text
        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if remaining.count >= 10 {
            sentences.append(remaining)
        }

        return sentences
    }

    private func extractBeats(from text: String, sentences: [String], isKorean: Bool) -> [String] {
        // Look for natural section breaks
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count >= 15 }

        if paragraphs.count >= 2 && paragraphs.count <= 5 {
            // Use paragraph first sentences as beats
            return paragraphs.prefix(5).compactMap { para in
                let firstSentence = extractFirstSentence(from: para)
                return firstSentence.count <= 80 ? firstSentence : String(firstSentence.prefix(77)) + "..."
            }
        }

        // Otherwise, pick key sentences evenly distributed
        if sentences.count >= 3 {
            let indices = [0, sentences.count / 2, sentences.count - 1]
            return indices.compactMap { idx in
                guard idx < sentences.count else { return nil }
                let s = sentences[idx]
                return s.count <= 80 ? s : String(s.prefix(77)) + "..."
            }
        }

        return sentences.prefix(3).map { s in
            s.count <= 80 ? s : String(s.prefix(77)) + "..."
        }
    }

    // MARK: - Tag Generation (Improved)
    private var actingKeywordsKorean: [String] {
        ["감정", "표현", "캐릭터", "연기", "기법", "즉흥", "호흡", "발성", "갈등", "긴장",
         "대사", "동작", "제스처", "리액션", "서브텍스트", "비트", "목표", "장애물", "전술"]
    }

    private var actingKeywordsEnglish: [String] {
        ["emotion", "expression", "character", "acting", "technique", "improvisation",
         "breathing", "voice", "conflict", "tension", "dialogue", "movement", "gesture",
         "reaction", "subtext", "beat", "objective", "obstacle", "tactic"]
    }

    private func heuristicTags(from text: String) -> [String] {
        let isKorean = detectKorean(in: text)
        let lowercased = text.lowercased()

        // Extended tag categories with weighted keywords
        let tagCategories: [(tag: String, keywords: [String], weight: Int)] = isKorean ? [
            // 형식/장르
            ("#모노로그", ["모노로그", "독백", "혼잣말", "솔로"], 3),
            ("#대화씬", ["대화", "상대역", "파트너", "듀오", "대본"], 3),
            ("#오디션", ["오디션", "자기소개", "슬레이트", "콜백"], 4),
            // 감정/톤
            ("#드라마", ["드라마", "극적", "진지", "무거운", "슬픔", "비극"], 2),
            ("#코미디", ["코미디", "웃긴", "유머", "희극", "가벼운"], 2),
            ("#로맨스", ["로맨스", "사랑", "연인", "이별", "설렘"], 2),
            ("#스릴러", ["스릴러", "긴장", "서스펜스", "공포", "미스터리"], 2),
            // 기법/스킬
            ("#감정연기", ["감정", "울음", "눈물", "분노", "기쁨", "슬픔"], 2),
            ("#신체연기", ["동작", "움직임", "제스처", "마임", "신체"], 2),
            ("#발성", ["발성", "목소리", "톤", "억양", "사투리", "액센트"], 2),
            // 상태/목적
            ("#리허설", ["리허설", "연습", "연기연습", "대본리딩"], 2),
            ("#분석", ["분석", "해석", "서브텍스트", "의도", "목표"], 2),
            ("#메모", ["메모", "노트", "기록", "생각", "아이디어"], 1)
        ] : [
            // Format/Genre
            ("#monologue", ["monologue", "solo", "soliloquy", "aside"], 3),
            ("#scene", ["scene", "dialogue", "partner", "duo", "script"], 3),
            ("#audition", ["audition", "slate", "callback", "casting", "self-tape"], 4),
            // Emotion/Tone
            ("#drama", ["drama", "dramatic", "serious", "heavy", "tragedy"], 2),
            ("#comedy", ["comedy", "funny", "humor", "comedic", "light"], 2),
            ("#romance", ["romance", "love", "romantic", "heartbreak", "passion"], 2),
            ("#thriller", ["thriller", "tension", "suspense", "horror", "mystery"], 2),
            // Technique/Skill
            ("#emotional", ["emotion", "cry", "tears", "anger", "joy", "grief"], 2),
            ("#physical", ["movement", "gesture", "physical", "mime", "body"], 2),
            ("#vocal", ["voice", "vocal", "tone", "accent", "dialect", "projection"], 2),
            // Status/Purpose
            ("#rehearsal", ["rehearsal", "practice", "run-through", "reading"], 2),
            ("#analysis", ["analysis", "breakdown", "subtext", "intention", "objective"], 2),
            ("#notes", ["note", "memo", "thought", "idea", "reminder"], 1)
        ]

        // Score each tag category
        var tagScores: [(String, Int)] = []

        for category in tagCategories {
            let matchCount = category.keywords.filter { lowercased.contains($0) }.count
            if matchCount > 0 {
                tagScores.append((category.tag, matchCount * category.weight))
            }
        }

        // Sort by score and take top 5
        let sortedTags = tagScores.sorted { $0.1 > $1.1 }.map { $0.0 }

        if sortedTags.isEmpty {
            // Extract from content words as fallback
            return extractContentTags(from: text, isKorean: isKorean)
        }

        return Array(sortedTags.prefix(5))
    }

    private func extractContentTags(from text: String, isKorean: Bool) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }

        let stopwords = isKorean ? koreanStopwords : englishStopwords
        let contentWords = words.filter { !stopwords.contains($0) }

        // Word frequency
        var freq: [String: Int] = [:]
        for word in contentWords {
            freq[word, default: 0] += 1
        }

        // Top words as tags
        let topWords = freq.sorted { $0.value > $1.value }
            .prefix(3)
            .map { "#\($0.key)" }

        return topWords.isEmpty ? [isKorean ? "#메모" : "#note"] : Array(topWords)
    }

    // MARK: - Keyword Extraction (Improved with TF-IDF style)
    private func heuristicKeywords(from text: String) -> [String] {
        let isKorean = detectKorean(in: text)
        let lowercased = text.lowercased()

        // Tokenize
        let tokens = lowercased
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        let stopwords = isKorean ? koreanStopwords : englishStopwords

        // Calculate term frequency
        var termFreq: [String: Int] = [:]
        for token in tokens {
            if !stopwords.contains(token) && token.count >= 2 && token.count <= 15 {
                termFreq[token, default: 0] += 1
            }
        }

        // Boost domain-specific keywords
        let domainBoost: [String: Double] = isKorean ? [
            // Acting terms get 2x boost
            "감정": 2.0, "캐릭터": 2.0, "연기": 2.0, "대사": 2.0, "장면": 2.0,
            "동기": 2.0, "목표": 2.0, "갈등": 2.0, "서브텍스트": 2.5, "비트": 2.0,
            "즉흥": 2.0, "리액션": 2.0, "제스처": 2.0, "호흡": 1.5, "발성": 1.5
        ] : [
            "emotion": 2.0, "character": 2.0, "acting": 2.0, "dialogue": 2.0, "scene": 2.0,
            "motivation": 2.0, "objective": 2.0, "conflict": 2.0, "subtext": 2.5, "beat": 2.0,
            "improvisation": 2.0, "reaction": 2.0, "gesture": 2.0, "breathing": 1.5, "voice": 1.5
        ]

        // Score each term
        var scoredTerms: [(String, Double)] = []
        for (term, freq) in termFreq {
            var score = Double(freq)

            // Apply domain boost
            if let boost = domainBoost[term] {
                score *= boost
            }

            // Longer words slightly more important (likely more specific)
            if term.count >= 5 { score *= 1.2 }
            if term.count >= 8 { score *= 1.3 }

            scoredTerms.append((term, score))
        }

        // Sort by score and return top keywords
        let topKeywords = scoredTerms
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map { $0.0 }

        if topKeywords.isEmpty {
            return isKorean ? ["메모", "노트"] : ["note", "memo"]
        }

        return Array(topKeywords)
    }
}

// KeychainHelper is implemented in Models.swift