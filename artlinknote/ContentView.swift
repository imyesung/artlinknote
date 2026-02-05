// GOAL: List screen with segmented filter, searchable, swipe actions, toolbar new+settings.
// - Tapping row opens NoteEditorView via navigation.
// - Maintain @State searchText, filter, path.
// - Use relative date, 2-line body preview, star icon if starred.
// - Enhanced with animations, haptics, context menus.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: NotesStore
    @State private var filter: NoteFilter = .all
    @State private var searchText: String = ""
    @State private var showSettings: Bool = false
    @State private var path: [Note] = []
    @State private var animateEmptyState: Bool = false

    private var filtered: [Note] {
        store.filtered(query: searchText, filter: filter)
    }

    var body: some View {
        NavigationStack(path: $path) {
            mainContent
                .navigationDestination(for: Note.self) { note in
                    NoteEditorView(note: note) { updated in store.upsert(updated) }
                        .navigationBarTitleDisplayMode(.inline)
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            filterPicker
            Group {
                if filtered.isEmpty {
                    emptyState
                } else {
                    notesList
                }
            }
        }
        .navigationTitle("Artlink")
        .toolbar { toolbarContent }
        .searchable(text: $searchText, prompt: "Search notes...")
    }

    // MARK: - Filter Picker (Enhanced)
    private var filterPicker: some View {
        HStack(spacing: 12) {
            ForEach(NoteFilter.allCases) { filterOption in
                FilterChip(
                    title: filterOption == .all ? "All" : "Starred",
                    icon: filterOption == .all ? "doc.text" : "star.fill",
                    isSelected: filter == filterOption,
                    count: filterOption == .all ? store.notes.count : store.notes.filter { $0.starred }.count
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        filter = filterOption
                    }
                    HapticManager.light()
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityLabel("Filter notes")
    }

    // MARK: - Empty State (Enhanced)
    private var emptyState: some View {
        VStack(spacing: 24) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)

                Image(systemName: filter == .starred ? "star.slash" : "note.text")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                    .scaleEffect(animateEmptyState ? 1.0 : 0.8)
                    .opacity(animateEmptyState ? 1.0 : 0.5)
            }

            VStack(spacing: 8) {
                Text(filter == .starred ? "No Starred Notes" : "No Notes Yet")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(filter == .starred
                     ? "Star your important notes to see them here"
                     : "Create your first note to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Action button
            if filter != .starred {
                Button {
                    createAndEditNew()
                    HapticManager.medium()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Note")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.blue.gradient, in: Capsule())
                    .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create new note")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground.gradient)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateEmptyState = true
            }
        }
        .onDisappear {
            animateEmptyState = false
        }
    }

    // MARK: - Notes List (Enhanced)
    private var notesList: some View {
        List {
            ForEach(filtered) { note in
                NavigationLink(value: note) {
                    NoteRow(note: note)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .accessibilityLabel("Note: \(note.title.isEmpty ? "Untitled" : note.title)")
                .accessibilityHint("Tap to edit, long press for options")
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation(.spring(response: 0.3)) {
                            store.delete(id: note.id)
                        }
                        HapticManager.warning()
                    } label: {
                        Label("Delete", systemImage: "trash.fill")
                    }

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            store.toggleStar(id: note.id)
                        }
                        HapticManager.light()
                    } label: {
                        Label(note.starred ? "Unstar" : "Star",
                              systemImage: note.starred ? "star.slash.fill" : "star.fill")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        duplicateNote(note)
                        HapticManager.success()
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc.fill")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    contextMenuContent(for: note)
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppBackground.gradient)
        .animation(.spring(response: 0.4), value: filtered.count)
    }

    // MARK: - Context Menu
    @ViewBuilder
    private func contextMenuContent(for note: Note) -> some View {
        Button {
            store.toggleStar(id: note.id)
            HapticManager.light()
        } label: {
            Label(note.starred ? "Remove Star" : "Add Star",
                  systemImage: note.starred ? "star.slash" : "star.fill")
        }

        Button {
            duplicateNote(note)
            HapticManager.light()
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            UIPasteboard.general.string = note.body
            HapticManager.success()
        } label: {
            Label("Copy Content", systemImage: "doc.on.clipboard")
        }

        Divider()

        Button(role: .destructive) {
            withAnimation {
                store.delete(id: note.id)
            }
            HapticManager.warning()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Toolbar (Enhanced)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                createAndEditNew()
                HapticManager.medium()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("New Note")
        }

        ToolbarItem(placement: .topBarLeading) {
            Button {
                showSettings = true
                HapticManager.light()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Actions
    private func createAndEditNew() {
        let new = store.createNew()
        path.append(new)
    }

    private func duplicateNote(_ note: Note) {
        var copy = Note.blank()
        copy.title = note.title + " (Copy)"
        copy.body = note.body
        copy.starred = false
        store.upsert(copy)
    }
}

// MARK: - Filter Chip Component
private struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? .white.opacity(0.2) : Color(.systemGray5))
                        )
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? .clear : Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Note Row (Enhanced Card Style)
private struct NoteRow: View {
    let note: Note
    @State private var isPressed: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Star indicator
            if note.starred {
                Circle()
                    .fill(.orange.gradient)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(.headline, design: .serif))
                    .fontWeight(.semibold)
                    .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                // Body preview
                if !note.body.trimmed().isEmpty {
                    Text(note.body.trimmed())
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(2)
                }

                // Metadata row
                HStack(spacing: 8) {
                    // Time
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(note.updatedAt, style: .relative)
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)

                    // Word count
                    let wordCount = note.body.components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }.count
                    if wordCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "text.word.spacing")
                                .font(.system(size: 10))
                            Text("\(wordCount) words")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(.systemGray4).opacity(0.5), lineWidth: 0.5)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.2), value: isPressed)
        .contentShape(Rectangle())
    }
}

// MARK: - Haptic Manager
enum HapticManager {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Background Styling (Enhanced)
enum AppBackground {
    static let gradient = LinearGradient(
        colors: [
            Color(.systemBackground),
            Color(.systemGray6).opacity(0.5),
            Color(.systemBackground)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardGradient = LinearGradient(
        colors: [Color(.systemGray6), Color(.systemGray5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let row = Color(.systemGray6).opacity(0.55)
}

// MARK: - Settings View (Simplified - No API Key)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Info Card
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsCardHeader(
                                icon: "info.circle",
                                title: "How it works",
                                subtitle: nil
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(icon: "iphone", text: "All notes stay on your device")
                                InfoRow(icon: "bolt.fill", text: "Smart summaries & keywords built-in")
                                InfoRow(icon: "lock.fill", text: "No external services required")
                            }
                        }
                    }

                    // Privacy Card
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsCardHeader(
                                icon: "hand.raised.fill",
                                title: "Privacy",
                                subtitle: nil
                            )

                            Text("Your data never leaves your device. No analytics, no tracking, no accounts. Everything is processed locally.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }
                    }

                    // App Info
                    VStack(spacing: 4) {
                        Text("Artlink")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("Version 1.1")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .background(AppBackground.gradient.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                        HapticManager.light()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Settings Card Components
private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(.systemGray4).opacity(0.5), lineWidth: 0.5)
            )
    }
}

private struct SettingsCardHeader: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
