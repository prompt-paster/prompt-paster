import SwiftUI

struct PlaceholderOverlayView: View {
    let message: String?
    let close: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.separator.opacity(0.6), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt Paster")
                            .font(.title2.weight(.semibold))
                        Text("Overlay shell placeholder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Close", action: close)
                        .keyboardShortcut(.escape, modifiers: [])
                }

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.background.opacity(0.65))
                    .overlay(alignment: .leading) {
                        Text("Search field and prompt cards land in OVERLAY-1.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                    }
                    .frame(height: 48)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    ForEach(1...9, id: \.self) { index in
                        PlaceholderPromptCard(index: index)
                    }
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .padding(1)
        .frame(minWidth: 760, minHeight: 480)
    }
}

private struct PlaceholderPromptCard: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("Prompt \(index)")
                    .font(.headline)
                Spacer()
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }

            Text("Prompt library cards will show title, category, preview, tags, and a keyboard badge.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}
