// GOAL: List screen with segmented filter, searchable, swipe actions, toolbar new+settings.
// - Tapping row opens NoteEditorView(sheet).
// - Maintain @State searchText, filter, editingNote.
// - Use relative date, 2-line body preview, star icon if starred.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: NotesStore
    @State private var filter: NoteFilter = .all
    @State private var searchText: String = ""
    @State private var editingNote: Note? = nil
    @State private var showEditor: Bool = false
    @State private var showSettings: Bool = false // placeholder for future settings sheet
    
    private var filtered: [Note] {
        store.filtered(query: searchText, filter: filter)
    }
    
    var body: some View {
        NavigationStack { mainContent }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            filterPicker
            Group {
                if filtered.isEmpty { emptyState } else { notesList }
            }
        }
        .navigationTitle("Actor Notes")
        .toolbar { toolbarContent }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .sheet(isPresented: $showEditor, onDismiss: { editingNote = nil }) { editorSheet }
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
                NoteRow(note: note)
                    .contentShape(Rectangle())
                    .onTapGesture { editingNote = note; showEditor = true }
                    .swipeActions {
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
    
    @ViewBuilder
    private var editorSheet: some View {
        if let note = editingNote {
            NoteEditorView(note: note) { updated in store.upsert(updated) }
                .presentationDetents([.large])
                .background(AppBackground.gradient.ignoresSafeArea())
        }
    }

    // MARK: - Row View
    private struct NoteRow: View {
        let note: Note
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                if note.starred {
                    Image(systemName: "star.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Starred")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title.isEmpty ? "(Untitled)" : note.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(note.body.trimmed())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(note.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func createAndEditNew() {
        let new = store.createNew()
        editingNote = new
        showEditor = true
    }
}

// MARK: - Background Styling (monotone subtle)
enum AppBackground {
    static let gradient = LinearGradient(colors: [Color(.systemGray6), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let row = Color(.secondarySystemBackground)
}

#Preview {
    let store = NotesStore(notes: Note.seed)
    return ContentView()
        .environmentObject(store)
}
