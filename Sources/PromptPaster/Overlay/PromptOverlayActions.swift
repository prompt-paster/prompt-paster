import Foundation

struct PromptOverlaySelectionOutcome: Equatable {
    let selectedPromptID: Prompt.ID
    let shouldClose: Bool
    let copyStatusMessage: String?
}

@MainActor
struct PromptOverlayActions {
    private let clipboard: ClipboardCopying

    init(clipboard: ClipboardCopying) {
        self.clipboard = clipboard
    }

    func selectPrompt(at index: Int, visiblePrompts: [Prompt]) -> PromptOverlaySelectionOutcome? {
        guard visiblePrompts.indices.contains(index) else {
            return nil
        }

        return copy(visiblePrompts[index])
    }

    func selectCurrentPrompt(
        selectedPromptID: Prompt.ID?,
        visiblePrompts: [Prompt]
    ) -> PromptOverlaySelectionOutcome? {
        guard let selectedPromptID,
              let index = visiblePrompts.firstIndex(where: { $0.id == selectedPromptID })
        else {
            return nil
        }

        return selectPrompt(at: index, visiblePrompts: visiblePrompts)
    }

    private func copy(_ prompt: Prompt) -> PromptOverlaySelectionOutcome {
        do {
            try clipboard.copyPlainText(prompt.body)
            return PromptOverlaySelectionOutcome(
                selectedPromptID: prompt.id,
                shouldClose: true,
                copyStatusMessage: nil
            )
        } catch {
            return PromptOverlaySelectionOutcome(
                selectedPromptID: prompt.id,
                shouldClose: false,
                copyStatusMessage: "Could not copy \"\(prompt.title)\". \(error.localizedDescription)"
            )
        }
    }
}
