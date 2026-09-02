// View do balão de opções de uma pasta: exibe os aplicativos vinculados na horizontal
// e o botão de vincular novo aplicativo, sem scrollview.

import AppKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    static let openerIndex = NSPasteboard.PasteboardType("local.dockfolders.opener.index")
}

final class OpenerItemView: NSView, NSDraggingSource {

    let opener: Opener
    let index: Int
    var onOpen: ((_ isCommandPressed: Bool) -> Void)?
    var onMove: ((_ fromIndex: Int, _ toIndex: Int) -> Void)?
    var onConfigureFile: (() -> Void)?
    var onClearFile: (() -> Void)?
    var onConfigureCommand: (() -> Void)?
    var onRemove: (() -> Void)?

    private var tracking: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var isDragging = false

    var isHovering = false { didSet { needsDisplay = true } }
    var isDropTarget = false { didSet { needsDisplay = true } }

    init(opener: Opener, index: Int, isFolderAvailable: Bool) {
        self.opener = opener
        self.index = index
        super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        translatesAutoresizingMaskIntoConstraints = false

        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 44).isActive = true

        let tip = Opening.tooltip(for: opener)
        toolTip = index == 0 ? "\(tip) (Principal — abrir todos)" : tip
        registerForDraggedTypes([.openerIndex])

        let iconView = NSImageView()
        iconView.image = Opening.icon(for: opener)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        if !isFolderAvailable {
            alphaValue = 0.4
        }

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !isDragging else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        guard dx * dx + dy * dy > 16 else { return }

        isDragging = true
        let pbItem = NSPasteboardItem()
        pbItem.setString(String(index), forType: .openerIndex)
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        dragItem.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard !isDragging, event.clickCount == 1 else { return }
        let cmd = event.modifierFlags.contains(.command)
        onOpen?(cmd)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let name = Opening.appName(for: opener)

        let openItem = NSMenuItem(title: "Abrir com \(name)",
                                  action: #selector(contextOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let pickFileItem = NSMenuItem(title: opener.targetPath == nil ? "Selecionar arquivo específico…" : "Alterar arquivo específico…",
                                      action: #selector(contextConfigureFile), keyEquivalent: "")
        pickFileItem.target = self
        menu.addItem(pickFileItem)

        if opener.targetPath != nil {
            let clearFileItem = NSMenuItem(title: "Remover arquivo específico (abrir pasta)",
                                           action: #selector(contextClearFile), keyEquivalent: "")
            clearFileItem.target = self
            menu.addItem(clearFileItem)
        }

        if opener.bundleID == "com.apple.Terminal" {
            let cmdItem = NSMenuItem(title: "Configurar comando…",
                                     action: #selector(contextConfigureCommand), keyEquivalent: "")
            cmdItem.target = self
            menu.addItem(cmdItem)
        }

        menu.addItem(.separator())

        let removeItem = NSMenuItem(title: "Remover aplicativo",
                                    action: #selector(contextRemove), keyEquivalent: "")
        removeItem.target = self
        menu.addItem(removeItem)

        return menu
    }

    @objc private func contextOpen() { onOpen?(false) }
    @objc private func contextConfigureFile() { onConfigureFile?() }
    @objc private func contextClearFile() { onClearFile?() }
    @objc private func contextConfigureCommand() { onConfigureCommand?() }
    @objc private func contextRemove() { onRemove?() }

    // MARK: - Dragging Source

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    // MARK: - Dragging Destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let sourceStr = sender.draggingPasteboard.string(forType: .openerIndex),
              let sourceIdx = Int(sourceStr), sourceIdx != index else {
            return []
        }
        isDropTarget = true
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let sourceStr = sender.draggingPasteboard.string(forType: .openerIndex),
              let sourceIdx = Int(sourceStr), sourceIdx != index else {
            return []
        }
        isDropTarget = true
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard let sourceStr = sender.draggingPasteboard.string(forType: .openerIndex),
              let sourceIdx = Int(sourceStr) else {
            return false
        }
        onMove?(sourceIdx, index)
        return true
    }

    private func snapshot() -> NSImage {
        let img = NSImage(size: bounds.size)
        img.lockFocus()
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            rep.draw(in: bounds)
        }
        img.unlockFocus()
        img.size = bounds.size
        return img
    }

    override func draw(_ dirtyRect: NSRect) {
        if isDropTarget {
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
            NSColor.controlAccentColor.setStroke()
            let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
            p.lineWidth = 1.5
            p.stroke()
        } else if isHovering {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        } else if index == 0 {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
    }
}

final class OpenerAddButtonView: NSView {
    var onAdd: (() -> Void)?

    private var tracking: NSTrackingArea?
    var isHovering = false { didSet { needsDisplay = true } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 44).isActive = true
        toolTip = "Vincular novo aplicativo…"

        let plusIcon = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        plusIcon.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Adicionar aplicativo")?
            .withSymbolConfiguration(config)
        plusIcon.contentTintColor = .secondaryLabelColor
        plusIcon.imageScaling = .scaleProportionallyDown
        plusIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plusIcon)

        NSLayoutConstraint.activate([
            plusIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            plusIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            plusIcon.widthAnchor.constraint(equalToConstant: 24),
            plusIcon.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 1 else { return }
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onAdd?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovering {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        } else {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
    }
}

final class FolderOptionsView: NSView {

    private let store: Store
    let folderID: UUID

    var onOpen: ((_ opener: Opener, _ keepOpen: Bool) -> Void)?
    var onNeedsResize: (() -> Void)?
    var onChange: (() -> Void)?
    var withModal: (((() -> Void) -> Void))?

    private let stack = NSStackView()

    init(folderID: UUID, store: Store) {
        self.folderID = folderID
        self.store = store
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        setupViews()
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            let targetSharing: NSWindow.SharingType
            if let parentSharing = window.parent?.sharingType {
                targetSharing = parentSharing
            } else {
                #if DEBUG
                targetSharing = (ProcessInfo.processInfo.environment["ENABLE_SCREEN_CAPTURE"] == "1") ? .readOnly : .none
                #else
                targetSharing = .none
                #endif
            }
            window.sharingType = targetSharing
        }
    }

    private func setupViews() {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func rebuild() {
        guard let item = store.findItem(folderID) else { return }

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (i, opener) in item.openers.enumerated() {
            let opView = OpenerItemView(opener: opener, index: i, isFolderAvailable: item.isAvailable)
            opView.onOpen = { [weak self] keepOpen in
                self?.onOpen?(opener, keepOpen)
            }
            opView.onMove = { [weak self] fromIdx, toIdx in
                guard let self else { return }
                self.store.reorderOpeners(for: self.folderID, fromIndex: fromIdx, toIndex: toIdx)
                self.rebuild()
                self.onNeedsResize?()
                self.onChange?()
            }
            opView.onConfigureFile = { [weak self] in
                self?.pickTargetFile(for: i)
            }
            opView.onClearFile = { [weak self] in
                guard let self else { return }
                self.store.updateOpener(at: i, for: self.folderID) { $0.targetPath = nil }
                self.rebuild()
            }
            opView.onConfigureCommand = { [weak self] in
                self?.configureTerminalCommand(for: i)
            }
            opView.onRemove = { [weak self] in
                guard let self else { return }
                self.store.removeOpener(at: i, for: self.folderID)
                self.rebuild()
                self.onNeedsResize?()
                self.onChange?()
            }
            stack.addArrangedSubview(opView)
        }

        let addBtn = OpenerAddButtonView()
        addBtn.onAdd = { [weak self] in
            self?.promptAddApp()
        }
        stack.addArrangedSubview(addBtn)

        layoutSubtreeIfNeeded()
    }

    override var intrinsicContentSize: NSSize {
        stack.fittingSize
    }

    // MARK: - Ações de Modal

    private func runModalBlock(_ body: @escaping () -> Void) {
        if let withModal {
            withModal(body)
        } else {
            body()
        }
    }

    private func promptAddApp() {
        guard let item = store.findItem(folderID) else { return }

        runModalBlock { [weak self] in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.prompt = "Vincular"
            panel.message = "Selecione o aplicativo para vincular a “\(item.displayName)”"
            guard panel.runModal() == .OK, let url = panel.url else { return }

            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }

            let opener = Opener.app(bundleID)
            self.store.addOpener(opener, to: self.folderID)
            self.rebuild()
            self.onNeedsResize?()
            self.onChange?()
        }
    }

    private func pickTargetFile(for openerIndex: Int) {
        guard let item = store.findItem(folderID) else { return }

        runModalBlock { [weak self] in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.directoryURL = URL(fileURLWithPath: item.path)
            panel.prompt = "Selecionar"
            panel.message = "Escolha o arquivo específico a ser aberto por este aplicativo em “\(item.displayName)”"
            guard panel.runModal() == .OK, let url = panel.url else { return }

            self.store.updateOpener(at: openerIndex, for: self.folderID) {
                $0.targetPath = url.path
            }
            self.rebuild()
        }
    }

    private func configureTerminalCommand(for openerIndex: Int) {
        guard let item = store.findItem(folderID),
              openerIndex < item.openers.count else { return }
        let currentCmd = item.openers[openerIndex].command ?? ""

        runModalBlock { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Terminal"
            alert.informativeText = "Comando a ser executado pelo Terminal ao abrir (opcional). Deixe em branco para apenas entrar na pasta."
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.stringValue = currentCmd
            field.placeholderString = "ex.: claude"
            alert.accessoryView = field
            alert.addButton(withTitle: "Salvar")
            alert.addButton(withTitle: "Cancelar")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let cmd = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.store.updateOpener(at: openerIndex, for: self.folderID) {
                $0.command = cmd.isEmpty ? nil : cmd
            }
            self.rebuild()
        }
    }
}
