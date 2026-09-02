// Linhas do balão: pasta e cabeçalho de grupo.
//
// Alturas conforme o orçamento do CONTEXT.md: pasta 28pt, cabeçalho 30pt. É esse
// orçamento que faz o accordion exclusivo caber sem ScrollView.

import AppKit

extension NSPasteboard.PasteboardType {
    /// Arrasto interno: carrega só o UUID do item, nunca um caminho de arquivo.
    static let dockFoldersItem = NSPasteboard.PasteboardType("local.dockfolders.item")
}

final class ActionButton: NSButton {
    private var handler: (() -> Void)?

    convenience init(image: NSImage?, tooltip: String, handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.image = image
        self.imageScaling = .scaleProportionallyDown
        // Sem isto, o NSButton reserva espaço interno para um título mesmo com
        // title = "", o que desloca o ícone do centro real do botão — o quadro fica
        // centralizado, mas o desenho dentro dele não, e o nome parece desalinhado.
        self.imagePosition = .imageOnly
        self.toolTip = tooltip
        self.isBordered = false
        self.title = ""
        self.handler = handler
        self.target = self
        self.action = #selector(fire)
        self.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func fire() { handler?() }
}

class HoverRow: NSView {
    static var isDraggingActive = false

    var onClick: ((NSEvent) -> Void)?
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    var onMouseDown: (() -> Void)?
    var onDragStart: (() -> Void)?
    var isEnabled = true
    /// Início do arrasto; devolve o UUID a ser transportado.
    var dragItemID: UUID?

    private var tracking: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var isDragging = false
    var hovering = false { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true } }
    var isDropTarget = false { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with e: NSEvent) {
        guard !Self.isDraggingActive else { return }
        if isEnabled {
            hovering = true
            onMouseEnter?()
        }
    }

    override func mouseExited(with e: NSEvent) {
        hovering = false
        onMouseExit?()
    }

    override func mouseDown(with e: NSEvent) {
        isDragging = false
        mouseDownPoint = e.locationInWindow
        onMouseDown?()
        if e.clickCount == 2 { doubleClicked(e) }
    }

    override func mouseUp(with e: NSEvent) {
        guard isEnabled, !isDragging, !Self.isDraggingActive, e.clickCount == 1 else {
            isDragging = false
            return
        }
        onClick?(e)
    }

    override func mouseDragged(with e: NSEvent) {
        guard let id = dragItemID, let start = mouseDownPoint else { return }
        let dx = e.locationInWindow.x - start.x, dy = e.locationInWindow.y - start.y
        guard dx * dx + dy * dy > 16 else { return }   // limiar de 4pt

        isDragging = true
        Self.isDraggingActive = true
        onDragStart?()

        let pbItem = NSPasteboardItem()
        pbItem.setString(id.uuidString, forType: .dockFoldersItem)
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        dragItem.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [dragItem], event: e, source: self)
    }

    func doubleClicked(_ e: NSEvent) {}

    private func snapshot() -> NSImage {
        let img = NSImage(size: bounds.size)
        img.lockFocus()
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            rep.draw(in: bounds)
        }
        img.unlockFocus()
        img.size = bounds.size
        return img
    }

    override func draw(_ dirty: NSRect) {
        if isDropTarget {
            NSColor.controlAccentColor.withAlphaComponent(0.30).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
            NSColor.controlAccentColor.setStroke()
            let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5)
            p.lineWidth = 1.5
            p.stroke()
        } else if isSelected || hovering {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
    }
}

extension HoverRow: NSDraggingSource {
    func draggingSession(_ s: NSDraggingSession,
                         sourceOperationMaskFor ctx: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ s: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        Self.isDraggingActive = true
    }

    func draggingSession(_ s: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        Self.isDraggingActive = false
        DispatchQueue.main.async { [weak self] in
            self?.isDragging = false
        }
    }
}

final class FolderRow: HoverRow {
    static let height: CGFloat = 28

    private let primaryIcon = NSImageView()

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) != nil ? self : nil
    }

    init(item: FolderItem, indent: CGFloat = 0) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        dragItemID = item.id

        let available = item.isAvailable
        isEnabled = available

        primaryIcon.image = Opening.icon(for: item.primaryOpener) ?? NSWorkspace.shared.icon(for: .folder)
        primaryIcon.imageScaling = .scaleProportionallyDown
        primaryIcon.translatesAutoresizingMaskIntoConstraints = false

        // O nome nunca trunca: é ele que dita a largura do balão.
        let name = NSTextField(labelWithString: item.displayName)
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byClipping
        name.setContentCompressionResistancePriority(.required, for: .horizontal)
        name.setContentHuggingPriority(.required, for: .horizontal)
        name.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: nil)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        // Q10: path que não resolve fica esmaecido e não clicável.
        if !available {
            alphaValue = 0.4
            name.textColor = .secondaryLabelColor
            toolTip = "\(item.path) — não encontrada"
        } else {
            toolTip = item.path
        }

        addSubview(primaryIcon); addSubview(name); addSubview(chevron)
        NSLayoutConstraint.activate([
            primaryIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14 + indent),
            primaryIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            primaryIcon.widthAnchor.constraint(equalToConstant: 17),
            primaryIcon.heightAnchor.constraint(equalToConstant: 17),

            name.leadingAnchor.constraint(equalTo: primaryIcon.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 9),

            name.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
        ])
    }

    func updateIcon(for opener: Opener) {
        primaryIcon.image = Opening.icon(for: opener) ?? NSWorkspace.shared.icon(for: .folder)
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class GroupHeaderRow: HoverRow {
    static let height: CGFloat = 30

    var onOpenAll: (() -> Void)?
    var onRename: ((String) -> Void)?

    private let nameField = NSTextField()
    let groupID: UUID

    init(group: FolderGroup, isOpen: Bool) {
        self.groupID = group.id
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: isOpen ? "chevron.down" : "chevron.right",
                                accessibilityDescription: nil)
        chevron.contentTintColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        // Q32c: duplo-clique edita inline.
        nameField.stringValue = group.name
        nameField.font = .systemFont(ofSize: 13, weight: .semibold)
        nameField.isBordered = false
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.drawsBackground = false
        nameField.lineBreakMode = .byClipping
        nameField.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let count = NSTextField(labelWithString: "\(group.folders.count)")
        count.font = .systemFont(ofSize: 11)
        count.textColor = .tertiaryLabelColor
        count.translatesAutoresizingMaskIntoConstraints = false

        // Q25: botão no canto direito abre todas as pastas do grupo.
        let openAll = NSButton(image: NSImage(systemSymbolName: "square.stack",
                                              accessibilityDescription: "Abrir tudo")!,
                               target: self, action: #selector(openAllTapped))
        openAll.isBordered = false
        openAll.imagePosition = .imageOnly
        openAll.toolTip = "Abrir todas as pastas do grupo"
        openAll.isEnabled = !group.folders.isEmpty
        openAll.alphaValue = group.folders.isEmpty ? 0.3 : 1
        openAll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(chevron); addSubview(nameField); addSubview(count); addSubview(openAll)
        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 11),

            nameField.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 8),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),

            count.leadingAnchor.constraint(equalTo: nameField.trailingAnchor, constant: 6),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.trailingAnchor.constraint(lessThanOrEqualTo: openAll.leadingAnchor, constant: -10),

            openAll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            openAll.centerYAnchor.constraint(equalTo: centerYAnchor),
            openAll.widthAnchor.constraint(equalToConstant: 18),
        ])
    }

    @objc private func openAllTapped() { onOpenAll?() }

    override func doubleClicked(_ e: NSEvent) { beginRename() }

    func beginRename() {
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.drawsBackground = true
        nameField.isBordered = true
        window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    required init?(coder: NSCoder) { fatalError() }
}

extension GroupHeaderRow: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.drawsBackground = false
        nameField.isBordered = false
        let novo = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if !novo.isEmpty { onRename?(novo) }
    }
}
