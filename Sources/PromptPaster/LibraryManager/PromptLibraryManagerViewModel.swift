import AppKit
import Combine
import Foundation

@MainActor
final class PromptLibraryManagerViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedCategoryID = PromptCategoryFilter.all.id
    @Published var selectedTagID = PromptLibraryManagerState.allTagID
    @Published var selectedPromptID: Prompt.ID?
    @Published private(set) var draft: PromptLibraryDraft?
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var githubSources: [GitHubPromptSource]
    @Published var composites: [CompositePromptDefinition]

    private let promptStore: PromptStore
    private var originalDraft: PromptLibraryDraft?
    private var promptStoreCancellable: AnyCancellable?
    private var editorFileSignature: PromptLibraryFileSignature?
    private var originalSources: [GitHubPromptSource] = []
    private var originalComposites: [CompositePromptDefinition] = []

    init(promptStore: PromptStore) {
        self.promptStore = promptStore
        self.githubSources = promptStore.library?.githubSources ?? []
        self.composites = promptStore.library?.composites ?? []
        self.editorFileSignature = promptStore.libraryFileSignature
        self.originalSources = self.githubSources
        self.originalComposites = self.composites
        selectedPromptID = promptStore.library?.prompts.first?.id
        refreshDraft()
        promptStoreCancellable = promptStore.$library.sink { [weak self] library in
            self?.handleLibraryChange(library)
        }
    }

    var libraryURL: URL {
        promptStore.libraryURL
    }

    var prompts: [Prompt] {
        promptStore.library?.prompts ?? []
    }

    var categories: [PromptCategoryFilter] {
        PromptLibraryManagerState.categories(for: prompts)
    }

    var tags: [PromptCategoryFilter] {
        PromptLibraryManagerState.tags(for: prompts)
    }

    var filteredPrompts: [Prompt] {
        PromptLibraryManagerState.filteredPrompts(
            prompts,
            query: query,
            categoryID: selectedCategoryID,
            tagID: selectedTagID
        )
    }

    var selectedPrompt: Prompt? {
        selectedPromptID.flatMap { id in prompts.first { $0.id == id } }
    }

    var isDirty: Bool {
        draft != originalDraft
    }

    var configurationsDirty: Bool {
        githubSources != promptStore.library?.githubSources
            || composites != promptStore.library?.composites
    }

    var titleErrorMessage: String? {
        guard let draft, draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "Title is required."
    }

    var bodyErrorMessage: String? {
        guard let draft, draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "Body is required."
    }

    var saveDisabled: Bool {
        titleErrorMessage != nil || bodyErrorMessage != nil || !isDirty
    }

    func updateDraft(_ draft: PromptLibraryDraft) {
        self.draft = draft
        errorMessage = nil
        statusMessage = nil
    }

    func requestSelection(_ promptID: Prompt.ID?) {
        guard promptID != selectedPromptID else {
            return
        }
        guard canDiscardCurrentDraft() else {
            return
        }
        selectedPromptID = promptID
        refreshDraft()
    }

    func reconcileSelectionAfterFiltering() {
        let visibleIDs = Set(filteredPrompts.map(\.id))
        guard selectedPromptID == nil || !visibleIDs.contains(selectedPromptID ?? "") else {
            return
        }
        guard canDiscardCurrentDraft() else {
            return
        }
        selectedPromptID = filteredPrompts.first?.id
        refreshDraft()
    }

    func saveSelectedPrompt() {
        guard let selectedPromptID, let draft, let library = promptStore.library else {
            return
        }

        do {
            let updatedLibrary = try PromptLibraryManagerState.library(
                byUpdatingPromptID: selectedPromptID,
                in: library,
                with: draft
            )
            _ = try promptStore.save(updatedLibrary, expectedSignature: editorFileSignature)
            editorFileSignature = promptStore.libraryFileSignature
            self.statusMessage = "Saved prompt library."
            self.errorMessage = nil
            refreshDraft()
        } catch {
            self.errorMessage = error.localizedDescription
            promptStore.recordError(error)
        }
    }

    func reloadLibrary() {
        guard canDiscardCurrentDraft(action: "Save or discard changes before reloading.") else {
            return
        }
        let result = promptStore.reload()
        if let errorMessage = result.errorMessage {
            self.errorMessage = "Reload failed. Keeping last valid library. \(errorMessage)"
            return
        }
        statusMessage = "Reloaded \(result.library?.prompts.count ?? 0) prompts."
        errorMessage = nil
        selectedPromptID = promptStore.library?.prompts.first?.id
        refreshDraft()
    }

    func discardChanges() {
        githubSources = promptStore.library?.githubSources ?? []
        composites = promptStore.library?.composites ?? []
        originalSources = githubSources
        originalComposites = composites
        editorFileSignature = promptStore.libraryFileSignature
        refreshDraft()
        errorMessage = nil
        statusMessage = "Discarded unsaved changes."
    }

    func addGitHubSource() {
        let number = githubSources.count + 1
        githubSources.append(GitHubPromptSource(
            id: "github-source-\(number)",
            title: "New GitHub prompt",
            owner: "owner",
            repository: "repository",
            path: "prompts/prompt.md"
        ))
    }

    func removeGitHubSources(at offsets: IndexSet) {
        githubSources.remove(atOffsets: offsets)
    }

    func addComposite() {
        let number = composites.count + 1
        composites.append(CompositePromptDefinition(
            id: "composite-\(number)",
            title: "New composite prompt",
            componentPromptIDs: prompts.prefix(1).map(\.id)
        ))
    }

    func removeComposites(at offsets: IndexSet) {
        composites.remove(atOffsets: offsets)
    }

    func saveConfigurations() {
        guard let library = promptStore.library else { return }
        do {
            _ = try promptStore.save(PromptLibrary(
                version: library.version,
                prompts: library.prompts,
                githubSources: githubSources,
                composites: composites
            ), expectedSignature: editorFileSignature)
            editorFileSignature = promptStore.libraryFileSignature
            originalSources = githubSources
            originalComposites = composites
            statusMessage = "Saved GitHub sources and composite prompts. They refresh the next time Prompt Paster opens."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            promptStore.recordError(error)
        }
    }

    func openLibraryFile() {
        do {
            NSWorkspace.shared.open(try promptStore.prepareLibraryFile())
        } catch {
            errorMessage = error.localizedDescription
            promptStore.recordError(error)
        }
    }

    func revealLibraryFile() {
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try promptStore.prepareLibraryFile()])
        } catch {
            errorMessage = error.localizedDescription
            promptStore.recordError(error)
        }
    }

    func refreshDraft() {
        let refreshedDraft = selectedPrompt.map(PromptLibraryDraft.init(prompt:))
        draft = refreshedDraft
        originalDraft = refreshedDraft
    }

    private func handleLibraryChange(_ library: PromptLibrary?) {
        objectWillChange.send()

        guard !isDirty, githubSources == originalSources, composites == originalComposites else {
            errorMessage = "Prompt library changed while this editor has unsaved changes. Save or discard changes before continuing."
            return
        }

        let prompts = library?.prompts ?? []
        githubSources = library?.githubSources ?? []
        composites = library?.composites ?? []
        originalSources = githubSources
        originalComposites = composites
        editorFileSignature = promptStore.libraryFileSignature
        if let selectedPromptID, prompts.contains(where: { $0.id == selectedPromptID }) {
            refreshDraft(from: prompts)
        } else {
            selectedPromptID = prompts.first?.id
            refreshDraft(from: prompts)
        }
    }

    private func refreshDraft(from prompts: [Prompt]) {
        let selectedPrompt = selectedPromptID.flatMap { id in prompts.first { $0.id == id } }
        let refreshedDraft = selectedPrompt.map(PromptLibraryDraft.init(prompt:))
        draft = refreshedDraft
        originalDraft = refreshedDraft
    }

    @discardableResult
    private func canDiscardCurrentDraft(action: String = "Save or discard changes before switching prompts.") -> Bool {
        guard isDirty || githubSources != originalSources || composites != originalComposites else {
            return true
        }
        errorMessage = action
        return false
    }
}
