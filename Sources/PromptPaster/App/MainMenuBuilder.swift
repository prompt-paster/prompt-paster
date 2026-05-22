import AppKit

@MainActor
enum MainMenuBuilder {
    static func build(quitTarget: AnyObject, quitAction: Selector) -> NSMenu {
        let menu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = buildAppMenu(quitTarget: quitTarget, quitAction: quitAction)
        menu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = buildEditMenu()
        menu.addItem(editMenuItem)

        return menu
    }

    private static func buildAppMenu(quitTarget: AnyObject, quitAction: Selector) -> NSMenu {
        let menu = NSMenu(title: "Prompt Paster")
        let quitItem = NSMenuItem(
            title: "Quit Prompt Paster",
            action: quitAction,
            keyEquivalent: "q"
        )
        quitItem.target = quitTarget
        menu.addItem(quitItem)
        return menu
    }

    private static func buildEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        addItem("Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x", to: menu)
        addItem("Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c", to: menu)
        addItem("Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v", to: menu)
        menu.addItem(NSMenuItem.separator())
        addItem("Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a", to: menu)
        return menu
    }

    private static func addItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = nil
        menu.addItem(item)
    }
}
