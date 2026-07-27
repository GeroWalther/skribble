import AppKit

/// Builds the application menu bar. Actions are sent to `nil` so they travel the
/// responder chain up to `AppDelegate`.
enum MainMenuBuilder {

    static func install() {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(toolsMenuItem())
        mainMenu.addItem(screenMenuItem())
        mainMenu.addItem(windowMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private static func item(_ title: String,
                             _ action: Selector?,
                             _ key: String = "",
                             modifiers: NSEvent.ModifierFlags = .command,
                             represented: Any? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.representedObject = represented
        return menuItem
    }

    private static func appMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(item("About Skribble", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hide Skribble", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                          modifiers: [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Skribble", #selector(NSApplication.terminate(_:)), "q"))

        let container = NSMenuItem()
        container.submenu = menu
        return container
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Canvas", #selector(AppDelegate.newCanvas(_:)), "n"))
        menu.addItem(item("Open…", #selector(AppDelegate.openDocument(_:)), "o"))
        menu.addItem(.separator())
        menu.addItem(item("Save", #selector(AppDelegate.saveDocument(_:)), "s"))
        menu.addItem(item("Save As…", #selector(AppDelegate.saveDocumentAs(_:)), "s",
                          modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Export as PNG…", #selector(AppDelegate.exportPNG(_:)), "e",
                          modifiers: [.command, .shift]))
        menu.addItem(item("Export as JPEG…", #selector(AppDelegate.exportJPEG(_:)), "j",
                          modifiers: [.command, .shift]))
        menu.addItem(item("Export as PDF…", #selector(AppDelegate.exportPDF(_:)), "p",
                          modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))

        let container = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        container.submenu = menu
        return container
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", #selector(AppDelegate.undoAction(_:)), "z"))
        menu.addItem(item("Redo", #selector(AppDelegate.redoAction(_:)), "z",
                          modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Copy as Image", #selector(AppDelegate.copyDrawing(_:)), "c"))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(AppDelegate.selectAllShapes(_:)), "a"))
        menu.addItem(item("Delete Selection", #selector(AppDelegate.deleteSelection(_:)), "\u{8}",
                          modifiers: []))
        menu.addItem(.separator())
        menu.addItem(item("Bring to Front", #selector(AppDelegate.bringToFront(_:)), "]",
                          modifiers: [.command, .shift]))
        menu.addItem(item("Send to Back", #selector(AppDelegate.sendToBack(_:)), "[",
                          modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Clear Canvas", #selector(AppDelegate.clearCanvas(_:)), "\u{8}",
                          modifiers: [.command, .shift]))

        let container = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        container.submenu = menu
        return container
    }

    private static func toolsMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Tools")
        for (index, tool) in Tool.drawingTools.enumerated() {
            let key = index < 9 ? String(index + 1) : ""
            menu.addItem(item(tool.title, #selector(AppDelegate.chooseTool(_:)), key,
                              represented: tool.rawValue))
        }
        let container = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        container.submenu = menu
        return container
    }

    private static func screenMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Screen")
        menu.addItem(item("Draw on Screen", #selector(AppDelegate.toggleOverlay(_:)), "d",
                          modifiers: [.command, .option, .control]))
        menu.addItem(item("Toggle Click-Through", #selector(AppDelegate.toggleClickThrough(_:)), "p",
                          modifiers: [.command, .option, .control]))
        menu.addItem(item("Erase Annotations", #selector(AppDelegate.clearAnnotations(_:)), "e",
                          modifiers: [.command, .option, .control]))
        menu.addItem(.separator())
        menu.addItem(item("Save Screen + Annotations…",
                          #selector(AppDelegate.captureScreenWithAnnotations(_:))))

        let container = NSMenuItem(title: "Screen", action: nil, keyEquivalent: "")
        container.submenu = menu
        return container
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))

        let container = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        container.submenu = menu
        NSApp.windowsMenu = menu
        return container
    }
}
