// GOAL: List screen with segmented filter, searchable, swipe actions, toolbar new+settings.
// - Tapping row opens NoteEditorView(sheet).
// - Maintain @State searchText, filter, editingNote.
// - Use relative date, 2-line body preview, star icon if starred.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: NotesStore
    @State private var filter: NoteFilter = .all
    @State private var searchText: String = ""
    @State private var showSettings: Bool = false // placeholder for future settings sheet
    @State private var path: [Note] = [] // navigation stack path for push editor
    
    private var filtered: [Note] {
        store.filtered(query: searchText, filter: filter)
    }
    
    var body: some View { NavigationStack(path: $path) { mainContent
            .navigationDestination(for: Note.self) { note in
                NoteEditorView(note: note) { updated in store.upsert(updated) }
                    .navigationBarTitleDisplayMode(.inline)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        } }
    
    @ViewBuilder
    private var mainContent: some View {
    VStack(spacing: 0) {
            filterPicker
            Group {
                if filtered.isEmpty { emptyState } else { notesList }
            }
        }
    .navigationTitle("Artlink")
        .toolbar { toolbarContent }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
    }
    
    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            Text("All").tag(NoteFilter.all)
            Text("Star").tag(NoteFilter.starred)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil").font(.system(size: 38)).foregroundStyle(.secondary)
            Text("No Notes").font(.headline).foregroundStyle(.secondary)
            Text("Tap + to create your first cue note.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground.gradient)
    }
    
    private var notesList: some View {
        List {
            ForEach(filtered) { note in
                NavigationLink(value: note) {
                    NoteRow(note: note)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { store.delete(id: note.id) } label: { Label("Delete", systemImage: "trash") }
                    Button { store.toggleStar(id: note.id) } label: { Label(note.starred ? "Unstar" : "Star", systemImage: note.starred ? "star.slash" : "star") }.tint(.yellow)
                }
            }
            .listRowBackground(AppBackground.row)
        }
        .listStyle(.plain)
        .background(AppBackground.gradient)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { Button { createAndEditNew() } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("New Note") }
        ToolbarItem(placement: .topBarLeading) { Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") }
    }
    
    // Removed sheet; using navigationDestination now.

    // MARK: - Row View
    private struct NoteRow: View {
        let note: Note
        var body: some View {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title.isEmpty ? "(Untitled)" : note.title)
                            .font(.system(.headline, design: .serif))
                            .lineLimit(1)
                        Text(note.body.trimmed())
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(note.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if note.starred { StarBadge() }
                    }
                }
                .padding(.vertical, 6)
            }
            .contentShape(Rectangle())
        }
        private struct StarBadge: View {
            var body: some View {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Starred")
            }
        }
    }
    
    private func createAndEditNew() {
        let new = store.createNew()
        path.append(new) // push into editor
    }
}

// MARK: - Background Styling (monotone subtle)
enum AppBackground {
    // Subtle neutral drift: slightly cooler mid-tone without introducing chroma.
    static let gradient = LinearGradient(
        colors: [Color(.systemGray6), Color(.systemGray5), Color(.systemGray6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let row = Color(.systemGray6).opacity(0.55)
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var modelName: String = "gpt-4o-mini"
    @State private var isValidating: Bool = false
    @State private var validationMessage: String = ""
    @State private var showValidationAlert: Bool = false
    
    private let aiService = OpenAIService()
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Enter your OpenAI API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onAppear(perform: loadAPIKey)
                        .accessibilityLabel("API Key")
                    
                    TextField("Model name", text: $modelName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityLabel("Model Name")
                    
                    Button(action: validateAPIKey) {
                        HStack {
                            if isValidating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Validating...")
                            } else {
                                Image(systemName: "checkmark.shield")
                                Text("Validate Key")
                            }
                        }
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                    .accessibilityLabel("Validate API Key")
                    
                } header: {
                    Text("OpenAI Configuration")
                } footer: {
                    Text("Your API key is stored securely in Keychain and never leaves your device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    Text("All data stays on your device. AI processing uses your OpenAI account. No analytics or tracking.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Validation Result", isPresented: $showValidationAlert) {
                Button("OK") { }
            } message: {
                Text(validationMessage)
            }
            .background(AppBackground.gradient.ignoresSafeArea())
        }
    }
    
    private func loadAPIKey() {
        do {
            if let key = try KeychainHelper.loadAPIKey() {
                apiKey = key
            }
        } catch {
            // Silent fail - no existing key
        }
    }
    
    private func saveSettings() {
        // Save API key to keychain
        if !apiKey.isEmpty {
            do {
                try KeychainHelper.save(apiKey: apiKey)
            } catch {
                // Could show error alert, but keep it simple for MVP
            }
        }
        
        // Update AI service model
        aiService.updateModel(modelName)
    }
    
    private func validateAPIKey() {
        guard !apiKey.isEmpty else { return }
        
        isValidating = true
        validationMessage = ""
        
        Task { @MainActor in
            do {
                // Try a simple API call to validate the key
                _ = try await aiService.suggestTitle(for: "Test validation")
                validationMessage = "✅ API key is valid and working!"
            } catch let error as AIError {
                validationMessage = "❌ " + (error.errorDescription ?? "Validation failed")
            } catch {
                validationMessage = "❌ Validation failed: \(error.localizedDescription)"
            }
            
            isValidating = false
            showValidationAlert = true
        }
    }
}

#Preview {
    let store = NotesStore(notes: Note.seed)
    return ContentView()
        .environmentObject(store)
}

#Preview("Settings") {
    SettingsView()
}
