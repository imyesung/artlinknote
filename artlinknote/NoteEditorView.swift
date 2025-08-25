// GOAL: Editor with Title, Cue mode toggle, TextEditor.
// - Toolbar: Star toggle, AI actions (Suggest Title / Rehearsal Summary / Tags) to be added later.
// - onChange(note) -> store.upsert(newValue) via closure.
// - AI actions placeholder (disabled) for now.

import SwiftUI

struct NoteEditorView: View {
    @State private var draft: Note
    @State private var zoomLevel: NotesStore.SummaryLevel? = nil
    // @State private var showBeats: Bool = false // COMMENTED OUT - Can be reused for AI chatbot toggle
    let onCommit: (Note) -> Void
    @EnvironmentObject private var store: NotesStore
    
    // AI State Management
    @State private var isProcessingAI: Bool = false
    @State private var aiError: String = ""
    @State private var showAIError: Bool = false
    @State private var pendingTitle: String = ""
    @State private var pendingSummary: RehearsalSummary? = nil
    @State private var pendingTags: [String] = []
    @State private var showTitleConfirm: Bool = false
    @State private var showSummaryResult: Bool = false
    @State private var showTagsResult: Bool = false
    
    private let aiService = OpenAIService()
    
    
    init(note: Note, onCommit: @escaping (Note) -> Void) {
        _draft = State(initialValue: note)
        self.onCommit = onCommit
    }
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    TextField("Untitled", text: $draft.title)
                        .font(.system(.title3, design: .serif))
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)
                        .accessibilityLabel("Title")
                    Spacer()
                    Button { toggleStar() } label: {
                        Image(systemName: draft.starred ? "star.fill" : "star")
                            .foregroundStyle(draft.starred ? .yellow : .secondary)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(draft.starred ? "Unstar" : "Star")
                }
                Divider()
            }
            .padding(.horizontal)
            
            // AI Action Bar (moved from bottom)
            HStack(spacing: 8) {
                // Title Button
                Button {
                    Task { await suggestTitle() }
                } label: {
                    HStack(spacing: 4) {
                        if isProcessingAI {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "textformat.alt")
                        }
                        Text("Title")
                    }
                }
                .disabled(isProcessingAI || draft.body.trimmed().isEmpty)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .foregroundStyle(isProcessingAI || draft.body.trimmed().isEmpty ? .secondary : .primary)
                .accessibilityLabel("Suggest Title")
                
                // Summary Button
                Button {
                    Task { await generateSummary() }
                } label: {
                    HStack(spacing: 4) {
                        if isProcessingAI {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "doc.text")
                        }
                        Text("Summary")
                    }
                }
                .disabled(isProcessingAI || draft.body.trimmed().isEmpty)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .foregroundStyle(isProcessingAI || draft.body.trimmed().isEmpty ? .secondary : .primary)
                .accessibilityLabel("Rehearsal Summary")
                
                // Tags Button
                Button {
                    Task { await extractTags() }
                } label: {
                    HStack(spacing: 4) {
                        if isProcessingAI {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "number")
                        }
                        Text("Tags")
                    }
                }
                .disabled(isProcessingAI || draft.body.trimmed().isEmpty)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .foregroundStyle(isProcessingAI || draft.body.trimmed().isEmpty ? .secondary : .primary)
                .accessibilityLabel("Extract Tags")
            }
            .padding(.horizontal)
            
            // Progressive Zoom Control (Always visible - Fixed UI)
            VStack(alignment: .leading, spacing: 12) {
                // Custom Segment Control - Always visible
                HStack(spacing: 0) {
                    ForEach(NotesStore.SummaryLevel.allCases, id: \.rawValue) { level in
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if level == zoomLevel {
                                    zoomLevel = nil // Toggle off if same level
                                } else {
                                    zoomLevel = level
                                }
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: level.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(level == zoomLevel ? .white : .primary)
                                Text(level.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(level == zoomLevel ? .white : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(level == zoomLevel ? .blue : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        if level.rawValue < NotesStore.SummaryLevel.allCases.count {
                            Divider()
                                .frame(height: 20)
                                .opacity(level == zoomLevel || NotesStore.SummaryLevel(rawValue: level.rawValue + 1) == zoomLevel ? 0 : 0.3)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(.horizontal)
            
            // Content Area - Either Normal Editor or Progressive View
            if let currentLevel = zoomLevel {
                // Progressive Content Stack
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            // Always show content up to current level
                            ForEach(NotesStore.SummaryLevel.allCases.filter { $0.rawValue <= currentLevel.rawValue }, id: \.rawValue) { level in
                                ProgressiveLevelView(
                                    level: level,
                                    draft: $draft,
                                    store: store,
                                    isCurrentLevel: level == currentLevel,
                                    onCommit: onCommit
                                )
                                .id("level-\(level.rawValue)")
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: zoomLevel) { newLevel in
                        // Auto-scroll to current level when changed
                        if let level = newLevel {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                // Use .top anchor for FULL level to focus on editing area
                                let anchor: UnitPoint = level == .full ? .top : .center
                                scrollProxy.scrollTo("level-\(level.rawValue)", anchor: anchor)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                // Normal TextEditor Mode
                ZStack(alignment: .topLeading) {
                    if draft.body.isEmpty {
                        Text("Write your note…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: Binding(
                        get: { draft.body },
                        set: { newValue in 
                            draft.body = newValue
                            draft.touch()
                            onCommit(draft)
                        }
                    ))
                        .font(.system(.body, design: .serif))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 200)
                        .padding(8)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .frame(maxHeight: .infinity, alignment: .top)
            }

            // MARK: - Reserved Space for Future AI Chatbot Integration
            // Beats Section Toggle - COMMENTED OUT FOR FUTURE AI CHATBOT USE
            if zoomLevel == .full {
                VStack(alignment: .leading, spacing: 8) {
                    // Reserved grey layout space - can be used for AI chatbot UI
                    Rectangle()
                        .fill(.clear)
                        .frame(height: 60) // Maintains layout space
                    
                    /* COMMENTED OUT - BEATS FUNCTIONALITY
                    HStack {
                        Text("Beats").font(.caption.smallCaps()).foregroundStyle(.secondary)
                        Spacer()
                        Button(showBeats ? "Hide" : "Show") { showBeats.toggle() }
                            .font(.caption)
                    }
                    if showBeats {
                        let beats = store.beats(for: draft)
                        if beats.isEmpty {
                            Text("No beats detected. Use blank lines or --- separators.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(beats.prefix(12), id: \..self) { b in
                                        Text(b.trimmingCharacters(in: .whitespaces).prefix(80))
                                            .font(.system(.footnote, design: .serif))
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                            .frame(minWidth: 120, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    */
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 16)
        .background(
            LinearGradient(colors: [Color(.systemGray6), Color(.systemGray5), Color(.systemGray4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .brightness(-0.02)
                .ignoresSafeArea()
        )
        .onChange(of: draft) { newValue in
            var copy = newValue
            copy.touch()
            onCommit(copy)
        }
        // AI Error Alert
        .alert("AI Error", isPresented: $showAIError) {
            Button("OK") { }
        } message: {
            Text(aiError)
        }
        // Title Confirmation Alert
        .alert("Apply Title?", isPresented: $showTitleConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Apply") { applyTitle() }
        } message: {
            Text("Replace current title with: \"\(pendingTitle)\"")
        }
        // Summary Result Alert
        .alert("Summary Generated", isPresented: $showSummaryResult) {
            Button("Cancel", role: .cancel) { }
            Button("Append") { applySummary() }
        } message: {
            if let summary = pendingSummary {
                Text("Logline: \(summary.logline)\n\nBeats: \(summary.beats.count) items")
            }
        }
        // Tags Result Alert
        .alert("Tags Generated", isPresented: $showTagsResult) {
            Button("Cancel", role: .cancel) { }
            Button("Add") { applyTags() }
        } message: {
            Text("Found \(pendingTags.count) tags: \(pendingTags.joined(separator: ", "))")
        }
    }
    
    private func toggleStar() { draft.starred.toggle(); draft.touch(); onCommit(draft) }
    
    
    // MARK: - AI Methods
    private func suggestTitle() async {
        await MainActor.run {
            guard !isProcessingAI && !draft.body.trimmed().isEmpty else { return }
            isProcessingAI = true
        }
        
        do {
            let title = try await aiService.suggestTitle(for: draft.body)
            await MainActor.run {
                pendingTitle = title
                
                // Auto-apply if current title is empty, otherwise ask for confirmation
                if draft.title.trimmed().isEmpty {
                    applyTitle()
                } else {
                    showTitleConfirm = true
                }
            }
        } catch {
            await MainActor.run {
                handleAIError(error)
            }
        }
        
        await MainActor.run {
            isProcessingAI = false
        }
    }
    
    private func generateSummary() async {
        await MainActor.run {
            guard !isProcessingAI && !draft.body.trimmed().isEmpty else { return }
            isProcessingAI = true
        }
        
        do {
            let summary = try await aiService.rehearsalSummary(for: draft.body)
            await MainActor.run {
                pendingSummary = summary
                showSummaryResult = true
            }
        } catch {
            await MainActor.run {
                handleAIError(error)
            }
        }
        
        await MainActor.run {
            isProcessingAI = false
        }
    }
    
    private func extractTags() async {
        await MainActor.run {
            guard !isProcessingAI && !draft.body.trimmed().isEmpty else { return }
            isProcessingAI = true
        }
        
        do {
            let tags = try await aiService.extractTags(for: draft.body)
            await MainActor.run {
                pendingTags = tags
                showTagsResult = true
            }
        } catch {
            await MainActor.run {
                handleAIError(error)
            }
        }
        
        await MainActor.run {
            isProcessingAI = false
        }
    }
    
    private func handleAIError(_ error: Error) {
        if let aiError = error as? AIError {
            self.aiError = aiError.errorDescription ?? "Unknown AI error"
        } else {
            self.aiError = "Network error: \(error.localizedDescription)"
        }
        showAIError = true
    }
    
    // MARK: - Result Application
    private func applyTitle() {
        draft.title = pendingTitle
        draft.touch()
        onCommit(draft)
        pendingTitle = ""
    }
    
    private func applySummary() {
        guard let summary = pendingSummary else { return }
        
        // Check if we already have a separator near the end
        let body = draft.body
        let lastPart = String(body.suffix(20))
        let hasSeparator = lastPart.contains("---") || lastPart.contains("___")
        
        var newContent = body
        if !body.trimmed().isEmpty && !hasSeparator {
            newContent += body.hasSuffix("\n") ? "\n---\n\n" : "\n\n---\n\n"
        } else if !body.trimmed().isEmpty {
            newContent += body.hasSuffix("\n") ? "\n" : "\n\n"
        }
        
        newContent += "**Logline:** \(summary.logline)\n\n"
        newContent += "**Beats:**\n"
        for (index, beat) in summary.beats.enumerated() {
            newContent += "\(index + 1). \(beat)\n"
        }
        
        draft.body = newContent
        draft.touch()
        onCommit(draft)
        pendingSummary = nil
    }
    
    private func applyTags() {
        // Find existing tags in the body and avoid duplicates
        let existingText = draft.body.lowercased()
        let newTags = pendingTags.filter { tag in
            !existingText.contains(tag.lowercased())
        }
        
        guard !newTags.isEmpty else {
            pendingTags = []
            return
        }
        
        var newContent = draft.body
        if !newContent.trimmed().isEmpty {
            newContent += newContent.hasSuffix("\n") ? "\n" : "\n\n"
        }
        
        newContent += newTags.joined(separator: " ")
        
        draft.body = newContent
        draft.touch()
        onCommit(draft)
        pendingTags = []
    }
}

// MARK: - Progressive Level View Component
struct ProgressiveLevelView: View {
    let level: NotesStore.SummaryLevel
    @Binding var draft: Note
    let store: NotesStore
    let isCurrentLevel: Bool
    let onCommit: (Note) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Level Header
            HStack(spacing: 8) {
                Image(systemName: level.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isCurrentLevel ? .blue : .secondary)
                
                Text(levelTitle)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundStyle(isCurrentLevel ? .blue : .secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                if isCurrentLevel {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.blue)
                        .rotationEffect(.degrees(180))
                }
            }
            
            // Level Content
            Group {
                if level == .full {
                    // Full Editor
                    ZStack(alignment: .topLeading) {
                        if draft.body.isEmpty {
                            Text("Write your note…")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: Binding(
                            get: { draft.body },
                            set: { newValue in 
                                draft.body = newValue
                                draft.touch()
                                onCommit(draft)
                            }
                        ))
                            .font(.system(.body, design: .serif))
                            .scrollContentBackground(.hidden)
                            .scrollDisabled(true)
                            .frame(minHeight: 120)
                            .padding(8)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isCurrentLevel ? .blue.opacity(0.3) : .clear, lineWidth: 2)
                    )
                } else {
                    // Summary Content with special handling for Keywords
                    let summaryText = store.summary(for: draft, level: level)
                    
                    if level == .keywords {
                        // Special keyword and tags display
                        KeywordTagsDisplayView(
                            summaryText: summaryText, 
                            noteBody: draft.body,
                            isCurrentLevel: isCurrentLevel
                        )
                    } else if !summaryText.isEmpty {
                        Text(summaryText)
                            .font(.system(.body, design: .serif))
                            .lineSpacing(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isCurrentLevel ? .blue.opacity(0.3) : .clear, lineWidth: 2)
                            )
                    } else {
                        Text("No content available")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var levelTitle: String {
        switch level {
        case .keywords: return "Keywords"
        case .line: return "Line"
        case .brief: return "Brief"
        case .full: return "Full"
        }
    }
}

// MARK: - Keyword & Tags Display Component
struct KeywordTagsDisplayView: View {
    let summaryText: String
    let noteBody: String
    let isCurrentLevel: Bool
    
    @State private var aiKeywords: [String] = []
    @State private var isLoadingKeywords = false
    private let aiService = OpenAIService()
    
    private var keywords: [String] {
        // Use AI-generated keywords if available, otherwise fallback to basic extraction
        return aiKeywords.isEmpty ? basicKeywordExtraction() : aiKeywords
    }
    
    private func basicKeywordExtraction() -> [String] {
        // Fallback basic extraction (much simpler than before)
        let text = summaryText.isEmpty ? noteBody : summaryText
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;()[]{}\"'")) }
            .filter { $0.count >= 2 && $0.count <= 10 }
            .prefix(3)
        return Array(words)
    }
    
    private var hashTags: [String] {
        // Extract hashtags from note body
        let regex = try? NSRegularExpression(pattern: "#\\w+", options: [])
        let range = NSRange(location: 0, length: noteBody.utf16.count)
        let matches = regex?.matches(in: noteBody, options: [], range: range) ?? []
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: noteBody) else { return nil }
            let hashtag = String(noteBody[range])
            // Remove the # symbol for display
            return String(hashtag.dropFirst())
        }
    }
    
    private var allItems: [(text: String, type: ItemType)] {
        var items: [(text: String, type: ItemType)] = []
        
        // Add AI keywords
        items += keywords.map { (text: $0, type: .keyword) }
        
        // Add hashtags
        items += hashTags.map { (text: $0, type: .hashtag) }
        
        return Array(items.prefix(8)) // Limit total items
    }
    
    enum ItemType {
        case keyword, hashtag
        
        var color: Color {
            switch self {
            case .keyword: return .blue
            case .hashtag: return .green
            }
        }
        
        var icon: String {
            switch self {
            case .keyword: return "brain.head.profile"
            case .hashtag: return "number"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                if isLoadingKeywords {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.blue)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text("AI 키워드 & 태그")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Text("\(allItems.count)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            
            if allItems.isEmpty && !isLoadingKeywords {
                // Empty state
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 16, weight: .medium))
                    Text("AI 분석 중이거나 키워드 없음")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                // Keywords and Tags grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(Array(allItems.enumerated()), id: \.offset) { index, item in
                        KeywordTagCard(text: item.text, type: item.type)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrentLevel ? .blue.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: isCurrentLevel ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: 2)
        .task {
            await loadAIKeywords()
        }
    }
    
    private func loadAIKeywords() async {
        let textToAnalyze = summaryText.isEmpty ? noteBody : summaryText
        guard !textToAnalyze.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        await MainActor.run {
            isLoadingKeywords = true
        }
        
        do {
            let extractedKeywords = try await aiService.extractKeywords(for: textToAnalyze)
            await MainActor.run {
                aiKeywords = extractedKeywords
                isLoadingKeywords = false
            }
        } catch {
            // Fallback to basic extraction on error
            await MainActor.run {
                aiKeywords = basicKeywordExtraction()
                isLoadingKeywords = false
            }
        }
    }
}

// MARK: - Individual Keyword/Tag Card
struct KeywordTagCard: View {
    let text: String
    let type: KeywordTagsDisplayView.ItemType
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon based on type
            Image(systemName: type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(type.color)
                .frame(width: 16, height: 16)
            
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [type.color.opacity(0.08), type.color.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(type.color.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    let sample = Note.sampleA
    return NoteEditorView(note: sample) { _ in }
        .frame(height: 600)
}
