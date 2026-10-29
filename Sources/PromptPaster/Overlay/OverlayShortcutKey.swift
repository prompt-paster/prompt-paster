import AppKit
import Carbon.HIToolbox

/// Respect configured characters first, then allow Latin shortcut badges to work
/// from their physical keys when a non-Latin input source (for example Hebrew) is active.
enum OverlayShortcutKey {
    static func promptID(for event: NSEvent, assignments: [PromptOverlayShortcutAssignment]) -> Prompt.ID? {
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else { return nil }
        if let id = PromptOverlayState.promptIDForShortcut(characters, assignments: assignments) { return id }
        guard characters.unicodeScalars.contains(where: { !$0.isASCII }),
              let physicalKey = latinKeys[event.keyCode] else { return nil }
        return PromptOverlayState.promptIDForShortcut(physicalKey, assignments: assignments)
    }

    private static let latinKeys: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_C): "c",
        UInt16(kVK_ANSI_D): "d", UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_F): "f",
        UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_H): "h", UInt16(kVK_ANSI_I): "i",
        UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k", UInt16(kVK_ANSI_L): "l",
        UInt16(kVK_ANSI_M): "m", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_O): "o",
        UInt16(kVK_ANSI_P): "p", UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_R): "r",
        UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_T): "t", UInt16(kVK_ANSI_U): "u",
        UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_X): "x",
        UInt16(kVK_ANSI_Y): "y", UInt16(kVK_ANSI_Z): "z"
    ]
}
