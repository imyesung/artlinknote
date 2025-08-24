// GOAL: Editor with Title, Cue mode toggle, TextEditor.
// - Toolbar: Star toggle, AI actions (Suggest Title / Rehearsal Summary / Tags) to be added later.
// - onChange(note) -> store.upsert(newValue) via closure.
// - AI actions placeholder (disabled) for now.

import SwiftUI

struct NoteEditorView: View {
    @State private var draft: Note
    @State private var cueMode: Bool = false
    let onCommit: (Note) -> Void
    
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
            .padding(.horizontal)
            .frame(maxHeight: .infinity, alignment: .top)
            
            // Placeholder AI action bar (disabled)
            HStack(spacing: 8) {
                ForEach(["Title", "Summary", "Tags"], id: \.self) { label in
                    Button(label) {}
                        .disabled(true)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("AI actions disabled")
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

#Preview {
    let sample = Note.sampleA
    return NoteEditorView(note: sample) { _ in }
        .frame(height: 600)
}
