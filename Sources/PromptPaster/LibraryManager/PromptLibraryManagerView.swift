import SwiftUI

struct PromptLibraryManagerView: View {
    @ObservedObject var viewModel: PromptLibraryManagerViewModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                TextField("Search prompts", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)

                Picker("Category", selection: $viewModel.selectedCategoryID) {
                    ForEach(viewModel.categories) { category in
                        Text(category.title).tag(category.id)
                    }
                }

                Picker("Tag", selection: $viewModel.selectedTagID) {
                    ForEach(viewModel.tags) { tag in
                        Text(tag.title).tag(tag.id)
                    }
                }

                List(
                    viewModel.filteredPrompts,
                    selection: Binding(
                        get: {
                            viewModel.selectedPromptID
                        },
                        set: { promptID in
                            viewModel.requestSelection(promptID)
                        }
                    )
                ) { prompt in
                    PromptLibraryPromptRow(prompt: prompt)
                        .tag(prompt.id)
                }
                .frame(minWidth: 260)
            }
            .padding()
            .navigationSplitViewColumnWidth(min: 300, ideal: 340)
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                if let selectedPrompt = viewModel.selectedPrompt, viewModel.draft != nil {
                    PromptLibraryEditor(
                        prompt: selectedPrompt,
                        draft: Binding(
                            get: {
                                viewModel.draft ?? PromptLibraryDraft(prompt: selectedPrompt)
                            },
                            set: { draft in
                                viewModel.updateDraft(draft)
                            }
                        ),
                        titleErrorMessage: viewModel.titleErrorMessage,
                        bodyErrorMessage: viewModel.bodyErrorMessage,
                        saveDisabled: viewModel.saveDisabled,
                        save: viewModel.saveSelectedPrompt
                    )
                } else {
                    ContentUnavailableView(
                        "No Prompt Selected",
                        systemImage: "text.badge.plus",
                        description: Text("Select a prompt from the library.")
                    )
                }
            }
            .padding()
            .frame(minWidth: 520, minHeight: 620)
        }
        .safeAreaInset(edge: .bottom) {
            PromptLibraryManagerFooter(viewModel: viewModel)
        }
        .onChange(of: viewModel.query) { _, _ in viewModel.reconcileSelectionAfterFiltering() }
        .onChange(of: viewModel.selectedCategoryID) { _, _ in viewModel.reconcileSelectionAfterFiltering() }
        .onChange(of: viewModel.selectedTagID) { _, _ in viewModel.reconcileSelectionAfterFiltering() }
    }
}

private struct PromptLibraryPromptRow: View {
    let prompt: Prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prompt.title)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text(prompt.category ?? "Uncategorized")
                if !prompt.tags.isEmpty {
                    Text(prompt.tags.prefix(3).joined(separator: ", "))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}

private struct PromptLibraryEditor: View {
    let prompt: Prompt
    @Binding var draft: PromptLibraryDraft
    let titleErrorMessage: String?
    let bodyErrorMessage: String?
    let saveDisabled: Bool
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.title2)
                    Text(prompt.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save") {
                    save()
                }
                .disabled(saveDisabled)
                .keyboardShortcut("s", modifiers: [.command])
            }

            LabeledContent("Title") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                    if let titleErrorMessage {
                        Text(titleErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            LabeledContent("Category") {
                TextField("Category", text: $draft.category)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Tags") {
                TextField("Comma-separated tags", text: $draft.tagsText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Body")
                TextEditor(text: $draft.body)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor))
                    )
                if let bodyErrorMessage {
                    Text(bodyErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

private struct PromptLibraryManagerFooter: View {
    @ObservedObject var viewModel: PromptLibraryManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text(viewModel.libraryURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if viewModel.isDirty {
                    Button("Discard Changes") {
                        viewModel.discardChanges()
                    }
                }

                Button("Open File") {
                    viewModel.openLibraryFile()
                }
                Button("Reload") {
                    viewModel.reloadLibrary()
                }
                Button("Reveal") {
                    viewModel.revealLibraryFile()
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding([.horizontal, .bottom])
        .background(.bar)
    }
}
