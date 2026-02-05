// GOAL: Editor with Title, Star toggle, TextEditor.
// - Progressive zoom levels: Keywords, Line, Brief, Full
// - onChange(note) -> store.upsert(newValue) via closure.
// - Local heuristic-based keyword extraction (no external API).

import SwiftUI

struct NoteEditorView: View {
    @State private var draft: Note
    @State private var zoomLevel: NotesStore.SummaryLevel? = nil
    let onCommit: (Note) -> Void
    @EnvironmentObject private var store: NotesStore
    
    
    init(note: Note, onCommit: @escaping (Note) -> Void) {
        _draft = State(initialValue: note)
        self.onCommit = onCommit
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with title and star
            HStack(alignment: .center, spacing: 12) {
                TextField("Untitled", text: $draft.title)
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .accessibilityLabel("Title")

                Spacer()

                // Enhanced star button
                Button {
                    toggleStar()
                    HapticManager.light()
                } label: {
                    Image(systemName: draft.starred ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(draft.starred ? .orange : .secondary)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(draft.starred ? Color.orange.opacity(0.15) : Color(.systemGray5))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(draft.starred ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                        .scaleEffect(draft.starred ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: draft.starred)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(draft.starred ? "Remove star" : "Add star")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            
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
                        .accessibilityLabel("\(level.displayName) view")
                        .accessibilityHint("Switch to \(level.displayName.lowercased()) view mode")
                        .accessibilityAddTraits(level == zoomLevel ? .isSelected : [])
                        
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
    }
    
    private func toggleStar() { draft.starred.toggle(); draft.touch(); onCommit(draft) }
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
                            .frame(minHeight: 500)
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

// MARK: - Keyword & Tags Display Component (Local Heuristic Only)
struct KeywordTagsDisplayView: View {
    let summaryText: String
    let noteBody: String
    let isCurrentLevel: Bool

    private var keywords: [String] {
        extractKeywordsLocal()
    }

    private func extractKeywordsLocal() -> [String] {
        let text = summaryText.isEmpty ? noteBody : summaryText
        let isKorean = text.range(of: "[\u{AC00}-\u{D7A3}]", options: .regularExpression) != nil

        // Stopwords
        let koreanStopwords: Set<String> = ["이", "그", "저", "것", "수", "등", "들", "및", "에", "의", "를", "을", "가", "는", "은", "로", "으로", "에서", "와", "과", "도", "만", "하다", "되다", "있다", "없다", "같다", "보다", "주다", "받다", "하고", "하는", "하면", "해서", "그리고", "하지만", "그러나", "그래서", "따라서", "또한", "즉", "왜냐하면", "때문에"]
        let englishStopwords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "shall", "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his", "its", "our", "their", "this", "that", "these", "those", "and", "or", "but", "if", "then", "else", "when", "where", "why", "how", "what", "which", "in", "on", "at", "to", "for", "of", "with", "by", "from", "as", "into", "through", "just", "also", "very", "really", "only", "even"]
        let stopwords = isKorean ? koreanStopwords : englishStopwords

        // Tokenize and filter
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && $0.count <= 15 && !stopwords.contains($0) }

        // Term frequency
        var freq: [String: Int] = [:]
        for token in tokens {
            freq[token, default: 0] += 1
        }

        // Sort by frequency and return top 5
        return freq.sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }

    private var hashTags: [String] {
        let regex = try? NSRegularExpression(pattern: "#\\w+", options: [])
        let range = NSRange(location: 0, length: noteBody.utf16.count)
        let matches = regex?.matches(in: noteBody, options: [], range: range) ?? []

        return matches.compactMap { match in
            guard let range = Range(match.range, in: noteBody) else { return nil }
            let hashtag = String(noteBody[range])
            return String(hashtag.dropFirst())
        }
    }

    private var allItems: [(text: String, type: ItemType)] {
        var items: [(text: String, type: ItemType)] = []
        items += keywords.map { (text: $0, type: .keyword) }
        items += hashTags.map { (text: $0, type: .hashtag) }
        return Array(items.prefix(8))
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
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.system(size: 14, weight: .semibold))
                Text("Keywords & Tags")
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

            if allItems.isEmpty {
                HStack {
                    Image(systemName: "text.magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 16, weight: .medium))
                    Text("No keywords found")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
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
    }
}

// MARK: - Individual Keyword/Tag Card
struct KeywordTagCard: View {
    let text: String
    let type: KeywordTagsDisplayView.ItemType

    var body: some View {
        HStack(spacing: 8) {
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
