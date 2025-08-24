// GOAL: Editor with Title, Cue mode toggle, TextEditor.
// - Toolbar: Star toggle, AI actions (Suggest Title / Rehearsal Summary / Tags) to be added later.
// - onChange(note) -> store.upsert(newValue) via closure.
// - AI actions placeholder (disabled) for now.

import SwiftUI

struct NoteEditorView: View {
    @State private var draft: Note
    @State private var cueMode: Bool = false
    @State private var zoomLevel: NotesStore.SummaryLevel = .full
    @State private var showBeats: Bool = false
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
                        .font(cueMode ? .system(.title2, design: .serif) : .system(.title3, design: .serif))
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
            
            Toggle(isOn: $cueMode) {
                Text("Cue Mode")
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .accessibilityLabel("Cue Mode")
            
            // Zoom Summary Segment
            Picker("Level", selection: $zoomLevel) {
                Text("Line").tag(NotesStore.SummaryLevel.line)
                Text("Key").tag(NotesStore.SummaryLevel.key)
                Text("Brief").tag(NotesStore.SummaryLevel.brief)
                Text("Full").tag(NotesStore.SummaryLevel.full)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: zoomLevel) { _ in /* trigger view refresh */ }
            Group {
                if zoomLevel == .full {
                    ZStack(alignment: .topLeading) {
                        if draft.body.isEmpty {
                            Text("Write your note…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $draft.body)
                            .font(cueMode ? .system(.title3, design: .serif) : .system(.body, design: .serif))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            // Hardcoded test to see if this section is even shown
                            Text("🔍 ZOOM MODE: \(zoomLevelName)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            
                            // Test local summary generation
                            let text = testSummary()
                            Text(text)
                                .font(.system(.body, design: .serif))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity, alignment: .top)

            // Beats Section Toggle
            if zoomLevel == .full {
                VStack(alignment: .leading, spacing: 8) {
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
                }
                .padding(.horizontal)
            }
            
            // AI Action Bar
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
            .padding(.bottom, 10)
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
    
    // MARK: - Test Helpers
    private var zoomLevelName: String {
        switch zoomLevel {
        case .line: return "LINE"
        case .key: return "KEY" 
        case .brief: return "BRIEF"
        case .full: return "FULL"
        }
    }
    
    private func testSummary() -> String {
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "📝 No content to summarize" }
        
        switch zoomLevel {
        case .line:
            let firstLine = body.components(separatedBy: .newlines).first ?? ""
            return "📏 FIRST LINE:\n\(firstLine.prefix(120))..."
        case .key:
            let words = body.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
                .prefix(5)
            return "🔑 KEY WORDS:\n• " + words.joined(separator: "\n• ")
        case .brief:
            let sentences = body.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .prefix(3)
            return "📋 BRIEF SUMMARY:\n" + sentences.joined(separator: ". ")
        case .full:
            return body // This shouldn't be called since Full shows TextEditor
        }
    }
    
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

#Preview {
    let sample = Note.sampleA
    return NoteEditorView(note: sample) { _ in }
        .frame(height: 600)
}
