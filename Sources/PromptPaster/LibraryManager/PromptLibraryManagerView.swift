import SwiftUI

struct PromptLibraryManagerView: View {
    @ObservedObject var viewModel: PromptLibraryManagerViewModel
    @State private var selectedTab = "prompts"

    var body: some View {
        TabView(selection: $selectedTab) {
            promptEditor
                .tabItem { Label("Prompts", systemImage: "text.book.closed") }
                .tag("prompts")
            configurationEditor
                .tabItem { Label("Sources & Composites", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag("configurations")
        }
    }

    private var promptEditor: some View {
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

    private var configurationEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub prompt sources")
                .font(.title2)
            Text("Each source reads a Markdown or text file when the overlay opens. Choose GitHub CLI sign-in to reuse gh auth login, a public repository, or the app token from Settings > GitHub access.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                Section("Markdown and text files") {
                    ForEach($viewModel.githubSources) { $source in
                        GitHubSourceEditor(source: $source)
                    }
                    .onDelete(perform: viewModel.removeGitHubSources)

                    Button {
                        viewModel.addGitHubSource()
                    } label: {
                        Label("Add GitHub file", systemImage: "plus")
                    }
                }

                Section("Composite prompts") {
                    Text("Component IDs can refer to local prompts or GitHub sources. A GitHub source named `team-rules` becomes the prompt ID `github-team-rules`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach($viewModel.composites) { $composite in
                        CompositePromptEditor(composite: $composite)
                    }
                    .onDelete(perform: viewModel.removeComposites)

                    Button {
                        viewModel.addComposite()
                    } label: {
                        Label("Add composite prompt", systemImage: "plus")
                    }
                }
            }

            HStack {
                Spacer()
                Button("Save Sources & Composites") {
                    viewModel.saveConfigurations()
                }
                .disabled(!viewModel.configurationsDirty)
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 620)
        .safeAreaInset(edge: .bottom) {
            PromptLibraryManagerFooter(viewModel: viewModel)
        }
    }
}

private struct GitHubSourceEditor: View {
    @Binding var source: GitHubPromptSource

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("ID")
                TextField("team-rules", text: $source.id)
            }
            GridRow {
                Text("Title")
                TextField("Team rules", text: $source.title)
            }
            GridRow {
                Text("Repository")
                HStack {
                    TextField("owner", text: $source.owner)
                    Text("/").foregroundStyle(.secondary)
                    TextField("repository", text: $source.repository)
                    Text("@").foregroundStyle(.secondary)
                    TextField("main or a tag", text: $source.ref)
                }
            }
            GridRow {
                Text("File")
                TextField("prompts/rules.md", text: $source.path)
            }
            GridRow {
                Text("Access")
                Picker("Access", selection: $source.authentication) {
                    ForEach(GitHubSourceAuthentication.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            GridRow {
                Text("Content")
                Picker("Content", selection: $source.content) {
                    ForEach(GitHubSourceContent.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            GridRow {
                Text("Category")
                TextField("Optional", text: Binding(
                    get: { source.category ?? "" },
                    set: { source.category = $0.isEmpty ? nil : $0 }
                ))
            }
            GridRow {
                Text("Tags")
                TextField("Comma-separated", text: Binding(
                    get: { source.tags.joined(separator: ", ") },
                    set: { source.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
            }
        }
        .padding(.vertical, 6)
    }
}

private struct CompositePromptEditor: View {
    @Binding var composite: CompositePromptDefinition

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("ID")
                TextField("combined-team-rules", text: $composite.id)
            }
            GridRow {
                Text("Title")
                TextField("Combined team rules", text: $composite.title)
            }
            GridRow {
                Text("Component IDs")
                TextField("github-first, github-second", text: Binding(
                    get: { composite.componentPromptIDs.joined(separator: ", ") },
                    set: { composite.componentPromptIDs = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
            }
            GridRow {
                Text("Separator")
                TextField("Blank line", text: $composite.separator)
            }
            GridRow {
                Text("Category")
                TextField("Optional", text: Binding(
                    get: { composite.category ?? "" },
                    set: { composite.category = $0.isEmpty ? nil : $0 }
                ))
            }
            GridRow {
                Text("Tags")
                TextField("Comma-separated", text: Binding(
                    get: { composite.tags.joined(separator: ", ") },
                    set: { composite.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
            }
        }
        .padding(.vertical, 6)
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
