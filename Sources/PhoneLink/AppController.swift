import AppKit
import AdbBridge
import Companion

/// Owns the status-bar item, its menu, and the session manager. This is the
/// app's root object (NSApplicationDelegate).
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let sessions = SessionManager()
    private var mirrorControllers: [UInt32: MirrorWindowController] = [:]

    // Companion plane (notifications, media, ring, battery, clipboard). The
    // encrypted KDE Connect transport is the next milestone; until it is wired
    // this stays nil and the related menu items explain how to finish setup.
    private var companion: CompanionClient?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Phone Link") {
                button.image = image
            } else {
                button.title = "📱" // fallback if SF Symbol is unavailable
            }
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(header("mac-phone-link"))
        menu.addItem(.separator())

        let mirror = NSMenuItem(title: "Mirror Phone Screen",
                                action: #selector(mirrorFullScreen), keyEquivalent: "m")
        mirror.target = self
        menu.addItem(mirror)

        let appItem = NSMenuItem(title: "Open App in Its Own Window…",
                                 action: #selector(openAppWindow), keyEquivalent: "o")
        appItem.target = self
        menu.addItem(appItem)

        menu.addItem(.separator())
        menu.addItem(header("Companion"))

        let ring = NSMenuItem(title: "Ring My Phone",
                              action: #selector(ringPhone), keyEquivalent: "r")
        ring.target = self
        menu.addItem(ring)

        let mediaMenu = NSMenu()
        for (titleText, action) in [("Play / Pause", "PlayPause"),
                                    ("Next", "Next"),
                                    ("Previous", "Previous")] {
            let item = NSMenuItem(title: titleText,
                                  action: #selector(mediaControl(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            mediaMenu.addItem(item)
        }
        let media = NSMenuItem(title: "Media", action: nil, keyEquivalent: "")
        media.submenu = mediaMenu
        menu.addItem(media)

        if !mirrorControllers.isEmpty {
            menu.addItem(.separator())
            menu.addItem(header("Open Windows"))
            for (_, controller) in mirrorControllers {
                let item = NSMenuItem(title: "• \(controller.title)",
                                      action: #selector(focusWindow(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = controller
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func mirrorFullScreen() {
        launchSession(newDisplay: nil, startApp: nil, title: "Phone Screen")
    }

    @objc private func openAppWindow() {
        let pkg = promptForPackage()
        guard let pkg, !pkg.isEmpty else { return }
        // Each app gets its own virtual display => its own independent window,
        // leaving the phone itself free to keep doing something else.
        launchSession(newDisplay: "1920x1080/320", startApp: pkg, title: pkg)
    }

    private func launchSession(newDisplay: String?, startApp: String?, title: String) {
        do {
            let session = try sessions.makeSession(newDisplay: newDisplay, startApp: startApp)
            let controller = MirrorWindowController(session: session, title: title)
            mirrorControllers[session.options.scid] = controller
            controller.onClose = { [weak self] scid in
                self?.mirrorControllers[scid] = nil
                self?.rebuildMenu()
            }
            controller.showWindow(nil)
            rebuildMenu()
            Task { await session.start() }
        } catch {
            presentError(error)
        }
    }

    @objc private func ringPhone() {
        guard let companion else { companionNotReady("Ring My Phone"); return }
        Task { try? await companion.ringPhone() }
    }

    @objc private func mediaControl(_ sender: NSMenuItem) {
        guard let companion else { companionNotReady("Media controls"); return }
        guard let action = sender.representedObject as? String else { return }
        // Player name comes from the phone's now-playing packet; default player
        // selection is a roadmap item, so we target the active player by name
        // once media state is tracked. For now this is wired end-to-end on the
        // protocol side and exercised by CompanionTests.
        Task { try? await companion.mediaCommand(player: "", action: action) }
    }

    private func companionNotReady(_ feature: String) {
        let alert = NSAlert()
        alert.messageText = "\(feature) needs the companion link"
        alert.informativeText = """
        Notifications, media control, battery and Ring My Phone run over the \
        companion (KDE Connect) plane, not screen mirroring. Pair the phone with \
        the KDE Connect Android app and finish the encrypted-transport setup \
        (see docs/ROADMAP.md). The protocol layer is implemented; the pairing \
        transport is the remaining step.
        """
        alert.runModal()
    }

    @objc private func focusWindow(_ sender: NSMenuItem) {
        (sender.representedObject as? MirrorWindowController)?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        sessions.stopAll()
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func promptForPackage() -> String? {
        let alert = NSAlert()
        alert.messageText = "Open an app in its own window"
        alert.informativeText = "Enter the Android package name (e.g. org.videolan.vlc). "
            + "It will launch on a dedicated virtual display."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "com.example.app"
        alert.accessoryView = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not start session"
        alert.informativeText = String(describing: error)
        alert.runModal()
    }
}
