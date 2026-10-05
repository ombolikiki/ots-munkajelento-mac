import SwiftUI
import AppKit

/// A leválasztott (külön, mozgatható) ablak. Ugyanazt a felületet és modellt használja, mint a menüsori lenyíló ablak.
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PanelController()

    @Published var isOpen = false
    /// Mindig legfelül marad-e (kitűzve).
    @Published var isPinned = true

    private var panel: NSPanel?
    var window: NSWindow? { panel }

    /// A menüsori lenyíló ablak (a ContentView jelenti be, amikor ablakba kerül).
    weak var menuWindow: NSWindow? {
        didSet {
            guard menuWindow !== oldValue else { return }
            visibilityObservation = menuWindow?.observe(\.isVisible, options: [.new]) { [weak self] window, change in
                guard change.newValue == true else { return }
                DispatchQueue.main.async { self?.menuWindowAppeared(window) }
            }
        }
    }
    private var visibilityObservation: NSKeyValueObservation?
    private var keyObserver: NSObjectProtocol?

    private func menuWindowAppeared(_ w: NSWindow) {
        guard isOpen, w === menuWindow, w.isVisible else { return }
        w.orderOut(nil)
        bringToFront()
    }

    override init() {
        super.init()
        // Ha van leválasztott ablak, a menüikonra kattintás azt hozza előre, a lenyíló ablak helyett.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self, let w = note.object as? NSWindow else { return }
            self.menuWindowAppeared(w)
        }
    }

    func bringToFront() {
        panel?.level = isPinned ? .floating : .normal
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static let panelName = "OTSMunkajelentoPanel"

    private var isCompactMode: Bool { UserDefaults.standard.bool(forKey: "compact") || ContentView.smallScreen }
    /// A leválasztott ablak legkisebb szélessége (a nézettől függ); ennél szélesebbre húzható, a tartalom követi.
    private var contentWidth: CGFloat { isCompactMode ? 340 : 440 }
    private var lastCompact = false
    private static func maxWidth(_ visible: NSRect) -> CGFloat { min(900, max(440, visible.width - 40)) }

    func show(model: AppModel) {
        if panel == nil {
            let hosting = NSHostingController(rootView: ContentView(detached: true).environmentObject(model))
            // Az ablak mérete nem követi a tartalmat (az a képernyőnél magasabbra nőve végtelen
            // elrendezési ciklust és összeomlást okozott), a tartalom görgethető.
            if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
            let p = NSPanel(contentViewController: hosting)
            p.styleMask = [.titled, .closable, .resizable]
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.delegate = self
            p.title = AppModel.appName
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let height = min(700, max(360, visible.height - 80))
            p.setContentSize(NSSize(width: contentWidth, height: height))
            applyWidthLimits(p)
            if !p.setFrameUsingName(Self.panelName) {
                p.setFrameTopLeftPoint(NSPoint(x: visible.maxX - p.frame.width - 24, y: visible.maxY - 12))
            }
            p.setFrameAutosaveName(Self.panelName)
            // visszaállított mentett méret esetén is érvényes szélesség (a megengedett tartományban) és a képernyőre férő magasság
            var size = p.contentRect(forFrameRect: p.frame).size
            size.width = min(max(size.width, contentWidth), Self.maxWidth(visible))
            size.height = min(max(size.height, 280), visible.height - 40)
            p.setContentSize(size)
            lastCompact = isCompactMode
            panel = p

            widthObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                // nem az elrendezési ciklusban, hanem utána módosítjuk az ablakot
                DispatchQueue.main.async { self?.syncWidth() }
            }
        }
        isOpen = true
        bringToFront()
    }

    private var widthObserver: NSObjectProtocol?

    /// Kompakt/normál nézet váltásakor az ablak szélessége az új nézet alapszélességére áll; egyébként a felhasználó által
    /// beállított szélességet nem bántjuk.
    private func syncWidth() {
        guard let p = panel else { return }
        let compactNow = isCompactMode
        guard compactNow != lastCompact else { return }
        lastCompact = compactNow
        applyWidthLimits(p)
        let current = p.contentRect(forFrameRect: p.frame).size
        p.setContentSize(NSSize(width: contentWidth, height: current.height))
    }

    private func applyWidthLimits(_ p: NSPanel) {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        p.contentMinSize = NSSize(width: contentWidth, height: 280)
        p.contentMaxSize = NSSize(width: Self.maxWidth(visible), height: max(400, visible.height - 40))
    }

    func close() {
        panel?.orderOut(nil)
        isOpen = false
    }

    func togglePin() {
        isPinned.toggle()
        panel?.level = isPinned ? .floating : .normal
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
    }
}

/// Megmondja, melyik ablakban van a nézet.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = TrackingView()
        v.onWindow = onWindow
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
