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
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                TextField("Title / 제목", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .font(cueMode ? .title3 : .headline)
                    .accessibilityLabel("Title")
                Button { toggleStar() } label: {
                    Image(systemName: draft.starred ? "star.fill" : "star")
                        .foregroundStyle(draft.starred ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(draft.starred ? "Unstar" : "Star")
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
                    Text("Body / 메모를 입력하세요…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $draft.body)
                    .font(cueMode ? .title3 : .body)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity)
            
            // Placeholder AI action bar (disabled)
            HStack(spacing: 12) {
                // Fix: correct key path escape (id: \.self) for String array
                ForEach(["Suggest Title", "Rehearsal Summary", "Tags"], id: \.self) { label in
                    Button(label) {}.disabled(true)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("AI actions disabled")
        }
        .padding(.top, 12)
        .background(AppBackground.gradient.ignoresSafeArea())
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
