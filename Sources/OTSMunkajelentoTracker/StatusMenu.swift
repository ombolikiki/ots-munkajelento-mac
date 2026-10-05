import AppKit

/// Jobb kattintásra (vagy Ctrl+kattintásra) a menüsori ikonra felugró menü.
/// A SwiftUI MenuBarExtra ezt nem tudja, ezért az alkalmazás eseményfigyelőjével kapjuk el a kattintást.
final class StatusMenuController: NSObject {
    static let shared = StatusMenuController()

    private weak var model: AppModel?
    private var monitor: Any?

    func install(model: AppModel) {
        self.model = model
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self = self, let window = event.window, Self.isStatusItemWindow(window) else { return event }
            // bal kattintás: a szokásos lenyíló ablak; csak a jobb vagy a Ctrl+kattintás ad menüt
            if event.type == .leftMouseDown && !event.modifierFlags.contains(.control) { return event }
            self.showMenu(event: event, window: window)
            return nil
        }
    }

    /// A menüsori elem ablaka (a szövegmezők saját jobb klikkes menüjét ez nem érinti).
    static func isStatusItemWindow(_ window: NSWindow) -> Bool {
        window.className.contains("StatusBar")
    }

    // MARK: Menü

    final class ActionItem: NSMenuItem {
        var handler: (() -> Void)?
        @objc func run() { handler?() }
    }

    private func item(_ title: String, enabled: Bool = true, checked: Bool = false, key: String = "", _ handler: @escaping () -> Void) -> ActionItem {
        let it = ActionItem(title: title, action: #selector(ActionItem.run), keyEquivalent: key)
        it.target = it
        it.handler = handler
        it.isEnabled = enabled
        it.state = checked ? .on : .off
        return it
    }

    func buildMenu(statusButton: NSStatusBarButton? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard let m = model else { return menu }

        let open = item("Ablak megnyitása") { statusButton?.performClick(nil) }
        open.isEnabled = statusButton != nil
        menu.addItem(open)

        // futó időzítő / pomo kezelése
        if m.stopwatchRunning {
            menu.addItem(.separator())
            menu.addItem(item("Időzítő leállítása és mentése", enabled: m.fieldsComplete) { m.stopStopwatch() })
            menu.addItem(item("Időzítő elvetése") { m.discardStopwatch() })
        } else if m.pomodoroActive {
            menu.addItem(.separator())
            switch m.pomoPhase {
            case .work:
                menu.addItem(item("Pomo leállítása és mentése", enabled: m.fieldsComplete) { m.stopPomodoro() })
                menu.addItem(item("Pomo elvetése") { m.discardPomodoro() })
            case .shortBreak, .longBreak:
                menu.addItem(item("Szünet kihagyása") { m.skipPomodoroBreak() })
                menu.addItem(item("Pomodoro leállítása") { m.stopPomodoro() })
            case .idle:
                break
            }
        }

        menu.addItem(.separator())
        let panelOpen = PanelController.shared.isOpen
        menu.addItem(item(panelOpen ? "Leválasztott ablak előrehozása" : "Leválasztás külön ablakba") {
            PanelController.shared.show(model: m)
        })
        if panelOpen {
            menu.addItem(item("Leválasztott ablak bezárása") { PanelController.shared.close() })
        }
        let compact = UserDefaults.standard.bool(forKey: "compact")
        menu.addItem(item("Kompakt nézet", checked: compact || ContentView.smallScreen,
                          { UserDefaults.standard.set(!compact, forKey: "compact") }))

        // menüsori ikon választása
        let iconMenu = NSMenu()
        iconMenu.autoenablesItems = false
        let currentIcon = UserDefaults.standard.string(forKey: "menuIcon") ?? "adventist"
        for c in IconSets.main {
            iconMenu.addItem(item(c.label, checked: c.id == currentIcon) {
                UserDefaults.standard.set(c.id, forKey: "menuIcon")
            })
        }
        let iconItem = NSMenuItem(title: "Menüsori ikon", action: nil, keyEquivalent: "")
        iconItem.submenu = iconMenu
        menu.addItem(iconItem)

        menu.addItem(item("Adatfájl megjelenítése a Finderben") {
            NSWorkspace.shared.activateFileViewerSelecting([m.dataFileURL])
        })

        menu.addItem(.separator())
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "fejlesztői"
        let v = NSMenuItem(title: "\(AppModel.appName) \(version)", action: nil, keyEquivalent: "")
        v.isEnabled = false
        menu.addItem(v)
        menu.addItem(item("Kilépés", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    private func showMenu(event: NSEvent, window: NSWindow) {
        guard let view = window.contentView else { return }
        let button = Self.findStatusButton(in: view)
        let menu = buildMenu(statusButton: button)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private static func findStatusButton(in view: NSView) -> NSStatusBarButton? {
        if let b = view as? NSStatusBarButton { return b }
        for sub in view.subviews { if let b = findStatusButton(in: sub) { return b } }
        return nil
    }
}
