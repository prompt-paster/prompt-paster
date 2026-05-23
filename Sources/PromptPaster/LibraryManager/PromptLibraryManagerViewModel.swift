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

    private let promptStore: PromptStore
    private var originalDraft: PromptLibraryDraft?
    private var promptStoreCancellable: AnyCancellable?

    init(promptStore: PromptStore) {
        self.promptStore = promptStore
        selectedPromptID = promptStore.library?.prompts.first?.id
        refreshDraft()
        promptStoreCancellable = promptStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
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
            _ = try promptStore.save(updatedLibrary)
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
        refreshDraft()
        errorMessage = nil
        statusMessage = "Discarded unsaved changes."
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

    @discardableResult
    private func canDiscardCurrentDraft(action: String = "Save or discard changes before switching prompts.") -> Bool {
        guard isDirty else {
            return true
        }
        errorMessage = action
        return false
    }
}
