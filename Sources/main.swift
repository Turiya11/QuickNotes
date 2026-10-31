// QuickNotes — draggable sticky notes that live on your macOS desktop.
// Notes persist to ~/Library/Application Support/QuickNotes/notes.json
// and come back exactly where you left them until you delete them.

import AppKit
import ServiceManagement

// MARK: - Model

struct Note: Codable {
    var id: UUID = UUID()
    var text: String = ""
    var x: Double
    var y: Double
    var width: Double = 240
    var height: Double = 220
    var color: Int = 0
}

struct NoteColor {
    let name: String
    let body: NSColor
    let header: NSColor
}

let palette: [NoteColor] = [
    NoteColor(name: "Yellow", body: NSColor(srgbRed: 1.00, green: 0.95, blue: 0.62, alpha: 1), header: NSColor(srgbRed: 0.98, green: 0.89, blue: 0.45, alpha: 1)),
    NoteColor(name: "Pink",   body: NSColor(srgbRed: 1.00, green: 0.82, blue: 0.86, alpha: 1), header: NSColor(srgbRed: 0.98, green: 0.71, blue: 0.77, alpha: 1)),
    NoteColor(name: "Blue",   body: NSColor(srgbRed: 0.80, green: 0.90, blue: 1.00, alpha: 1), header: NSColor(srgbRed: 0.67, green: 0.82, blue: 0.98, alpha: 1)),
    NoteColor(name: "Green",  body: NSColor(srgbRed: 0.82, green: 0.95, blue: 0.80, alpha: 1), header: NSColor(srgbRed: 0.69, green: 0.89, blue: 0.66, alpha: 1)),
    NoteColor(name: "Purple", body: NSColor(srgbRed: 0.89, green: 0.84, blue: 1.00, alpha: 1), header: NSColor(srgbRed: 0.80, green: 0.73, blue: 0.98, alpha: 1)),
    NoteColor(name: "Gray",   body: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1), header: NSColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1)),
]

// MARK: - Storage

final class NoteStore {
    static let shared = NoteStore()

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }()

    private var saveWork: DispatchWorkItem?

    func load() -> [Note] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Note].self, from: data)) ?? []
    }

    /// Debounced so typing doesn't hit the disk on every keystroke.
    func save(_ notes: [Note], immediately: Bool = false) {
        saveWork?.cancel()
        let work = DispatchWorkItem { [fileURL] in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(notes) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        saveWork = work
        if immediately {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }
}

// MARK: - Note window

/// Borderless windows can't become key by default, which would block typing.
final class NoteWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The header strip: dragging it moves the note.
final class HeaderView: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        bounds.fill()
    }
}

/// Buttons that respond to the first click even when the note isn't focused.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FirstMouseTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Bottom-right grip for resizing.
final class ResizeGrip: NSView {
    var onResizeEnd: (() -> Void)?
    private var startMouse: NSPoint = .zero
    private var startFrame: NSRect = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        for i in 1...3 {
            let o = CGFloat(i) * 4
            path.move(to: NSPoint(x: bounds.maxX - o, y: 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: o))
        }
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x
        let dy = now.y - startMouse.y
        let w = max(160, startFrame.width + dx)
        let h = max(120, startFrame.height - dy)
        // Keep the top-left corner pinned while resizing.
        window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - h, width: w, height: h), display: true)
    }

    override func mouseUp(with event: NSEvent) {
        onResizeEnd?()
    }
}

final class NoteController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    var note: Note
    let window: NoteWindow
    private let header = HeaderView()
    private let textView = FirstMouseTextView()
    private let scrollView = NSScrollView()
    private let grip = ResizeGrip()
    weak var app: AppController?

    init(note: Note, app: AppController) {
        self.note = note
        self.app = app
        window = NoteWindow(
            contentRect: NSRect(x: note.x, y: note.y, width: note.width, height: note.height),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        buildWindow()
        applyColor()
        applyLevel(floating: app.floatOnTop)
    }

    private func buildWindow() {
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.minSize = NSSize(width: 160, height: 120)
        window.delegate = self

        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        window.contentView = root

        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        let add = makeButton(symbol: "plus", tip: "New note", action: #selector(newNote))
        let colorBtn = makeButton(symbol: "paintpalette", tip: "Change color", action: #selector(cycleColor))
        let del = makeButton(symbol: "xmark", tip: "Delete note", action: #selector(deleteNote))
        let left = NSStackView(views: [add, colorBtn])
        left.spacing = 4
        left.translatesAutoresizingMaskIntoConstraints = false
        del.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(left)
        header.addSubview(del)

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor(white: 0.12, alpha: 1)
        textView.insertionPointColor = NSColor(white: 0.12, alpha: 1)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.string = note.text
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        grip.translatesAutoresizingMaskIntoConstraints = false
        grip.onResizeEnd = { [weak self] in self?.syncFrame() }
        root.addSubview(grip)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 28),

            left.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 6),
            left.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            del.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6),
            del.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),

            grip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            grip.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            grip.widthAnchor.constraint(equalToConstant: 16),
            grip.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func makeButton(symbol: String, tip: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        let b = FirstMouseButton(image: image ?? NSImage(), target: self, action: action)
        b.isBordered = false
        b.contentTintColor = NSColor(white: 0.25, alpha: 1)
        b.toolTip = tip
        b.widthAnchor.constraint(equalToConstant: 20).isActive = true
        b.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return b
    }

    func applyColor() {
        let c = palette[note.color % palette.count]
        window.contentView?.layer?.backgroundColor = c.body.cgColor
        header.fill = c.header
    }

    /// Desktop level sits just above the desktop icons, behind normal app windows.
    /// The note you're editing is lifted above everything so it's never hidden.
    func applyLevel(floating: Bool) {
        if floating || window.isKeyWindow {
            window.level = .floating
        } else {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    func show() {
        window.orderFrontRegardless()
    }

    func focus() {
        NSApp.activate(ignoringOtherApps: true)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    private func syncFrame() {
        let f = window.frame
        note.x = f.minX; note.y = f.minY
        note.width = f.width; note.height = f.height
        app?.noteChanged(self)
    }

    // MARK: Actions

    @objc private func newNote() {
        app?.createNote(near: window.frame)
    }

    @objc private func cycleColor() {
        note.color = (note.color + 1) % palette.count
        applyColor()
        app?.noteChanged(self)
    }

    @objc private func deleteNote() {
        if !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alert = NSAlert()
            alert.messageText = "Delete this note?"
            alert.informativeText = "This can't be undone."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        window.orderOut(nil)
        app?.remove(self)
    }

    // MARK: Delegates

    func windowDidBecomeKey(_ notification: Notification) { applyLevel(floating: app?.floatOnTop ?? false) }
    func windowDidResignKey(_ notification: Notification) { applyLevel(floating: app?.floatOnTop ?? false) }
    func windowDidMove(_ notification: Notification) { syncFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { syncFrame() }

    func textDidChange(_ notification: Notification) {
        note.text = textView.string
        app?.noteChanged(self)
    }
}

// MARK: - App

final class AppController: NSObject, NSApplicationDelegate {
    private var controllers: [NoteController] = []
    private var statusItem: NSStatusItem!
    private var floatItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    var floatOnTop: Bool {
        get { UserDefaults.standard.bool(forKey: "floatOnTop") }
        set { UserDefaults.standard.set(newValue, forKey: "floatOnTop") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        let saved = NoteStore.shared.load()
        if saved.isEmpty {
            createNote(near: nil, text: "Welcome to QuickNotes!\n\n• Drag the top bar to move me\n• Drag the corner to resize\n• 🎨 changes color, ✕ deletes\n• Menu bar icon → New Note")
        } else {
            for n in saved { add(NoteController(note: n, app: self)) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.save(controllers.map(\.note), immediately: true)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "QuickNotes")

        let menu = NSMenu()
        menu.addItem(withTitle: "New Note", action: #selector(newNoteFromMenu), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Show All Notes", action: #selector(showAll), keyEquivalent: "").target = self
        menu.addItem(.separator())
        floatItem = menu.addItem(withTitle: "Float Above Windows", action: #selector(toggleFloat), keyEquivalent: "")
        floatItem.target = self
        floatItem.state = floatOnTop ? .on : .off
        loginItem = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit QuickNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func add(_ c: NoteController) {
        controllers.append(c)
        c.show()
    }

    func createNote(near frame: NSRect?, text: String = "") {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = screen.midX - 120
        var y = screen.midY - 110
        if let frame {
            x = frame.minX + 30
            y = frame.minY - 30
        }
        let c = NoteController(note: Note(text: text, x: x, y: y, color: controllers.count % palette.count), app: self)
        add(c)
        c.focus()
        persist()
    }

    func noteChanged(_ c: NoteController) { persist() }

    func remove(_ c: NoteController) {
        controllers.removeAll { $0 === c }
        persist(immediately: true)
    }

    private func persist(immediately: Bool = false) {
        NoteStore.shared.save(controllers.map(\.note), immediately: immediately)
    }

    @objc private func newNoteFromMenu() { createNote(near: nil) }

    @objc private func showAll() {
        NSApp.activate(ignoringOtherApps: true)
        controllers.forEach { $0.window.orderFrontRegardless() }
    }

    @objc private func toggleFloat() {
        floatOnTop.toggle()
        floatItem.state = floatOnTop ? .on : .off
        controllers.forEach { $0.applyLevel(floating: floatOnTop) }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
app.run()
