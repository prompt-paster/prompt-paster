import SwiftUI

struct PromptOverlayView: View {
    @ObservedObject var promptStore: PromptStore

    let message: String?
    let clipboard: ClipboardCopying
    let openSettings: () -> Void
    let close: () -> Void

    @State private var query = ""
    @State private var selectedCategoryID = PromptCategoryFilter.all.id
    @State private var selectedPromptID: Prompt.ID?
    @State private var copyStatusMessage: String?
    @FocusState private var isSearchFocused: Bool

    init(
        promptStore: PromptStore,
        message: String?,
        clipboard: ClipboardCopying = ClipboardService(),
        openSettings: @escaping () -> Void = {},
        close: @escaping () -> Void
    ) {
        self.promptStore = promptStore
        self.message = message
        self.clipboard = clipboard
        self.openSettings = openSettings
        self.close = close
    }

    private var prompts: [Prompt] {
        promptStore.library?.prompts ?? []
    }

    private var categories: [PromptCategoryFilter] {
        PromptSearch.categories(for: prompts)
    }

    private var visiblePrompts: [Prompt] {
        PromptOverlayState.visiblePrompts(
            prompts: prompts,
            query: query,
            selectedCategoryID: selectedCategoryID
        )
    }

    private var selectedIndex: Int? {
        guard let selectedPromptID else {
            return nil
        }
        return visiblePrompts.firstIndex { $0.id == selectedPromptID }
    }

    private var actions: PromptOverlayActions {
        PromptOverlayActions(clipboard: clipboard)
    }

    private var searchStrokeStyle: AnyShapeStyle {
        isSearchFocused
            ? AnyShapeStyle(Color.accentColor.opacity(0.55))
            : AnyShapeStyle(Color(nsColor: .separatorColor).opacity(0.5))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.separator.opacity(0.6), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 14) {
                header
                categoryChips
                statusArea
                resultArea
            }
            .padding(22)
        }
        .background(
            OverlayKeyCaptureView(handleKeyDown: handleKeyDown)
                .frame(width: 0, height: 0)
        )
        .padding(1)
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            selectedCategoryID = PromptCategoryFilter.all.id
            keepCategoryVisible()
            keepSelectionVisible()
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in
            keepSelectionVisible()
        }
        .onChange(of: selectedCategoryID) { _, _ in
            keepSelectionVisible()
        }
        .onChange(of: prompts) { _, _ in
            keepCategoryVisible()
            keepSelectionVisible()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TextField("Search prompts", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.background.opacity(0.74), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(searchStrokeStyle, lineWidth: 1)
                )

            Text("\(visiblePrompts.count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34)

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")

            Button("Close", action: close)
                .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        Text(category.title)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .foregroundStyle(selectedCategoryID == category.id ? .primary : .secondary)
                            .background(
                                chipBackgroundStyle(isSelected: selectedCategoryID == category.id),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var statusArea: some View {
        let messages = statusMessages
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(messages, id: \.self) { message in
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var statusMessages: [String] {
        PromptOverlayState.statusMessages(
            message: message,
            validation: promptStore.lastErrorMessage == nil ? promptStore.validation : nil,
            copyStatusMessage: copyStatusMessage
        )
    }

    @ViewBuilder
    private var resultArea: some View {
        if let emptyState = PromptOverlayState.emptyState(
            prompts: prompts,
            visiblePrompts: visiblePrompts,
            query: query,
            lastErrorMessage: promptStore.lastErrorMessage
        ) {
            OverlayEmptyState(
                title: emptyState.title,
                detail: emptyState.detail
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(visiblePrompts.enumerated()), id: \.element.id) { index, prompt in
                        PromptRowView(
                            prompt: prompt,
                            shortcutBadge: index < 9 ? "\(index + 1)" : nil,
                            isSelected: prompt.id == selectedPromptID
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectPrompt(at: index)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }

        switch event.keyCode {
        case 53:
            close()
            return true
        case 36, 76:
            selectCurrentPrompt()
            return true
        case 125:
            moveSelection(by: 1)
            return true
        case 126:
            moveSelection(by: -1)
            return true
        default:
            guard let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
                  (1...9).contains(digit)
            else {
                return false
            }

            selectPrompt(at: digit - 1)
            return true
        }
    }

    private func chipBackgroundStyle(isSelected: Bool) -> AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(.selection.opacity(0.24))
            : AnyShapeStyle(.background.opacity(0.48))
    }

    private func moveSelection(by offset: Int) {
        selectedPromptID = PromptOverlayState.selectedPromptIDMoving(
            currentID: selectedPromptID,
            visiblePrompts: visiblePrompts,
            offset: offset
        )
        copyStatusMessage = nil
    }

    private func keepCategoryVisible() {
        if categories.contains(where: { $0.id == selectedCategoryID }) {
            return
        }
        selectedCategoryID = PromptCategoryFilter.all.id
    }

    private func keepSelectionVisible() {
        selectedPromptID = PromptOverlayState.selectedPromptIDKeepingVisible(
            currentID: selectedPromptID,
            visiblePrompts: visiblePrompts
        )
    }

    private func selectCurrentPrompt() {
        guard let outcome = actions.selectCurrentPrompt(
            selectedPromptID: selectedPromptID,
            visiblePrompts: visiblePrompts
        ) else {
            return
        }

        apply(outcome)
    }

    private func selectPrompt(at index: Int) {
        guard let outcome = actions.selectPrompt(at: index, visiblePrompts: visiblePrompts) else {
            return
        }

        apply(outcome)
    }

    private func apply(_ outcome: PromptOverlaySelectionOutcome) {
        selectedPromptID = outcome.selectedPromptID
        copyStatusMessage = outcome.copyStatusMessage

        if outcome.shouldClose {
            close()
        }
    }
}

private struct PromptRowView: View {
    let prompt: Prompt
    let shortcutBadge: String?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(prompt.title)
                        .font(.headline)
                        .lineLimit(1)

                    if let category = prompt.category, !category.isEmpty {
                        Text(category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                    }
                }

                Text(prompt.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !prompt.tags.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(Array(prompt.tags.prefix(5).enumerated()), id: \.offset) { _, tag in
                            Text(tag)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.background.opacity(0.45), in: Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            if let shortcutBadge {
                Text(shortcutBadge)
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 30, height: 30)
                    .background(badgeBackgroundStyle, in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(rowBackgroundStyle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(rowStrokeStyle, lineWidth: 1)
        )
    }

    private var badgeBackgroundStyle: AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.accentColor)
            : AnyShapeStyle(.background.opacity(0.6))
    }

    private var rowBackgroundStyle: AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(.selection.opacity(0.18))
            : AnyShapeStyle(.background.opacity(0.56))
    }

    private var rowStrokeStyle: AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.accentColor.opacity(0.65))
            : AnyShapeStyle(Color(nsColor: .separatorColor).opacity(0.35))
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let arrangement = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, origin) in arrangement.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (origins: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var origins: [CGPoint] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += lineHeight + lineSpacing
                lineHeight = 0
            }

            origins.append(cursor)
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, cursor.x - spacing)
        }

        return (origins, CGSize(width: usedWidth, height: cursor.y + lineHeight))
    }
}

private struct OverlayEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(.background.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
    }
}
