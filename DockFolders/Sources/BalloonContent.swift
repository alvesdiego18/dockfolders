// Conteúdo do balão: duas zonas (avulsas no topo, grupos abaixo) e rodapé.
// Sem ScrollView por decisão de projeto — o accordion exclusivo é o que mantém a
// altura dentro do orçamento da tela.
//
// O drag é infraestrutura, não conveniência: pela Q26c toda pasta nasce avulsa e
// arrastar é o único caminho para colocá-la num grupo.

import AppKit

final class BalloonContent: NSView {

    /// Para onde um item arrastado vai parar.
    private enum DropTarget {
        case looseAt(Int)
        case looseEnd
        case intoGroup(UUID)
        case groupFolderAt(UUID, Int)
    }

    private let store: Store
    private let stack = NSStackView()
    private var bottomInsetConstraint: NSLayoutConstraint!
    private var rowMap: [(view: NSView, target: DropTarget)] = []

    private var springTarget: UUID?
    private var springTimer: Timer?
    private var highlighted: HoverRow?

    private var optionsPopover: NSPopover?
    private var activeFolderID: UUID?
    private weak var activeRow: HoverRow?
    var onOpen: ((_ keepOpen: Bool) -> Void)?
    /// `concurrent`, quando presente, roda dentro da animação de redimensionamento do
    /// balão — usado pelo accordion para dissolver a foto do conteúdo anterior.
    var onNeedsResize: ((_ concurrent: (() -> Void)?) -> Void)?
    var onAddFolder: (() -> Void)?
    var onAddFolderToGroup: ((UUID) -> Void)?
    var onCreateGroup: (() -> Void)?
    var onToggleLoginItem: (() -> Void)?
    var onRequestPrecision: (() -> Void)?
    var onChangeOpener: ((FolderItem) -> Void)?
    var withModal: (((() -> Void) -> Void))?
    var isApproximate = false

    init(store: Store) {
        self.store = store
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 4, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        bottomInsetConstraint = stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            bottomInsetConstraint,
        ])

        registerForDraggedTypes([.dockFoldersItem])
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setBottomInset(_ inset: CGFloat) { bottomInsetConstraint.constant = -inset }

    var measuredHeight: CGFloat {
        stack.layoutSubtreeIfNeeded()
        return stack.fittingSize.height - bottomInsetConstraint.constant
    }

    /// Largura do balão: calculada a partir dos itens visíveis na lista.
    func measuredWidth(maxWidth: CGFloat) -> CGFloat {
        var widest: CGFloat = BalloonPanel.minWidth
        func consider(_ view: NSView) {
            view.layoutSubtreeIfNeeded()
            widest = max(widest, ceil(view.fittingSize.width))
        }
        let d = store.data
        for item in d.loose { consider(FolderRow(item: item, indent: 0)) }
        for g in d.groups {
            consider(GroupHeaderRow(group: g, isOpen: false))
            for item in g.folders { consider(FolderRow(item: item, indent: 16)) }
        }
        return min(widest, maxWidth)
    }

    // MARK: balão de opções de pasta

    func handleEscape() -> Bool {
        if optionsPopover?.isShown == true {
            closeOptionsPopover()
            return true
        }
        return false
    }

    func showFolderOptions(for item: FolderItem, relativeTo row: HoverRow) {
        if optionsPopover?.isShown == true && activeFolderID == item.id {
            closeOptionsPopover()
            return
        }
        closeOptionsPopover()

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self
        if let app = window?.appearance { pop.appearance = app }

        let optionsView = FolderOptionsView(folderID: item.id, store: store)
        optionsView.onOpen = { [weak self, weak pop] opener, keepOpen in
            Opening.open(item, with: opener)
            if !keepOpen {
                pop?.close()
                self?.closeOptionsPopover()
            }
            self?.onOpen?(keepOpen)
        }
        optionsView.onNeedsResize = { [weak pop, weak optionsView] in
            guard let pop, let optionsView else { return }
            pop.contentSize = optionsView.fittingSize
        }
        optionsView.withModal = self.withModal

        let vc = NSViewController()
        vc.view = optionsView
        pop.contentViewController = vc

        activeRow = row
        activeFolderID = item.id
        row.isSelected = true

        optionsPopover = pop
        pop.show(relativeTo: row.bounds, of: row, preferredEdge: .maxX)
    }

    func showFolderOptions(for itemID: UUID) {
        rebuild()
        onNeedsResize?(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let item = self.store.findItem(itemID),
                  let row = self.rowMap.compactMap({ $0.view as? FolderRow }).first(where: { $0.dragItemID == itemID }) else { return }
            self.showFolderOptions(for: item, relativeTo: row)
        }
    }

    func closeOptionsPopover() {
        activeRow?.isSelected = false
        activeRow = nil
        optionsPopover?.close()
        optionsPopover = nil
        activeFolderID = nil
    }

    // MARK: montagem

    func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowMap.removeAll()
        highlighted = nil

        let d = store.data
        if d.loose.isEmpty && d.groups.isEmpty {
            stack.addArrangedSubview(emptyState())
        } else {
            for (i, item) in d.loose.enumerated() {
                let row = folderRow(item, inGroup: nil)
                stack.addArrangedSubview(row)
                rowMap.append((row, .looseAt(i)))
            }
            if !d.loose.isEmpty && !d.groups.isEmpty {
                let sep = separator()
                stack.addArrangedSubview(sep)
                rowMap.append((sep, .looseEnd))
            }
            for g in d.groups {
                let isOpen = (d.openGroupID == g.id)
                let header = groupHeader(g, isOpen: isOpen)
                stack.addArrangedSubview(header)
                rowMap.append((header, .intoGroup(g.id)))
                if isOpen {
                    for (i, item) in g.folders.enumerated() {
                        let row = folderRow(item, inGroup: g.id)
                        stack.addArrangedSubview(row)
                        rowMap.append((row, .groupFolderAt(g.id, i)))
                    }
                }
            }
        }

        stack.addArrangedSubview(separator())
        if isApproximate { stack.addArrangedSubview(precisionNotice()) }
        stack.addArrangedSubview(footer())
        needsLayout = true
    }

    /// Fotografa o conteúdo atual numa camada por cima e devolve um bloco que a dissolve.
    /// O bloco roda dentro da animação de redimensionamento do balão, então as linhas
    /// que aparecem/somem no accordion trocam por baixo de um cross-dissolve — nunca
    /// saltam. Devolve `nil` quando ainda não há o que fotografar (primeira exibição).
    private func snapshotForCrossfade() -> (() -> Void)? {
        guard bounds.width > 1, bounds.height > 1,
              let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)

        let ghost = NSImageView()
        ghost.image = image
        ghost.imageScaling = .scaleNone
        ghost.imageAlignment = .alignTop
        ghost.wantsLayer = true
        ghost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ghost, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            ghost.topAnchor.constraint(equalTo: topAnchor),
            ghost.leadingAnchor.constraint(equalTo: leadingAnchor),
            ghost.trailingAnchor.constraint(equalTo: trailingAnchor),
            ghost.heightAnchor.constraint(equalToConstant: bounds.height),
        ])

        return { [weak ghost] in
            guard let ghost else { return }
            ghost.animator().alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + BalloonPanel.resizeDuration + 0.1) {
                ghost.removeFromSuperview()
            }
        }
    }

    // MARK: linhas

    private func folderRow(_ item: FolderItem, inGroup groupID: UUID?) -> HoverRow {
        let row = FolderRow(item: item, indent: groupID == nil ? 0 : 16)
        if activeFolderID == item.id {
            row.isSelected = true
            activeRow = row
        }
        row.onClick = { [weak self, weak row] _ in
            guard let self, let row else { return }
            self.showFolderOptions(for: item, relativeTo: row)
        }
        row.menu = itemMenu(item, inGroup: groupID)
        return row
    }

    private func groupHeader(_ g: FolderGroup, isOpen: Bool) -> HoverRow {
        let header = GroupHeaderRow(group: g, isOpen: isOpen)
        header.onClick = { [weak self] _ in
            guard let self else { return }
            self.closeOptionsPopover()
            let fade = self.snapshotForCrossfade()   // foto do estado atual
            self.store.setOpenGroup(g.id)            // accordion exclusivo
            self.onNeedsResize?(fade)                // rebuild + resize animam sob a foto
        }
        header.onOpenAll = { [weak self] in
            guard let self else { return }
            let folders = self.store.data.groups.first(where: { $0.id == g.id })?.folders ?? g.folders
            Opening.openAll(folders.filter(\.isAvailable).map { ($0, $0.primaryOpener) })
            self.onOpen?(false)
        }
        header.onRename = { [weak self] novo in
            self?.store.renameGroup(g.id, to: novo)
        }
        header.menu = groupMenu(g)
        return header
    }

    // MARK: menus de contexto

    private func itemMenu(_ item: FolderItem, inGroup groupID: UUID?) -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ block: @escaping () -> Void) {
            let mi = NSMenuItem(title: title, action: #selector(runBlock(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = block
            m.addItem(mi)
        }
        add("Abrir no Finder") {
            Opening.open(item, with: .finder)
        }
        if groupID != nil {
            add("Remover do grupo") { [weak self] in
                guard let self else { return }
                self.store.moveToLoose(itemID: item.id)
                self.rebuild(); self.onNeedsResize?(nil)
            }
        }
        m.addItem(.separator())
        add("Remover pasta") { [weak self] in
            guard let self else { return }
            self.store.remove(itemID: item.id)
            self.rebuild(); self.onNeedsResize?(nil)
        }
        return m
    }

    private func groupMenu(_ g: FolderGroup) -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ block: @escaping () -> Void) {
            let mi = NSMenuItem(title: title, action: #selector(runBlock(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = block
            m.addItem(mi)
        }
        add("Adicionar pasta a este grupo…") { [weak self] in
            self?.onAddFolderToGroup?(g.id)
        }
        add("Renomear") { [weak self] in
            guard let self else { return }
            let header = self.rowMap.compactMap { $0.view as? GroupHeaderRow }
                .first { $0.groupID == g.id }
            header?.beginRename()
        }
        add("Abrir tudo") { [weak self] in
            guard let self else { return }
            let folders = self.store.data.groups.first(where: { $0.id == g.id })?.folders ?? g.folders
            Opening.openAll(folders.filter(\.isAvailable).map { ($0, $0.primaryOpener) })
            self.onOpen?(false)
        }
        m.addItem(.separator())
        // Q27: excluir promove as pastas a avulsas; nada é destruído.
        add("Excluir grupo") { [weak self] in
            guard let self else { return }
            self.store.deleteGroup(g.id)
            self.rebuild(); self.onNeedsResize?(nil)
        }
        return m
    }

    @objc private func runBlock(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }

    // MARK: drag & drop

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        closeOptionsPopover()
        return .move
    }

    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        guard let hit = hitRow(for: s) else {
            clearHighlight(); return .move
        }

        highlight(hit.view as? HoverRow)

        // Spring-loading: pairar sobre um grupo fechado o expande (Q28a).
        if case let .intoGroup(gid) = hit.target, store.data.openGroupID != gid {
            if springTarget != gid {
                springTarget = gid
                springTimer?.invalidate()
                springTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                    guard let self, self.springTarget == gid else { return }
                    self.store.setOpenGroup(gid)
                    self.rebuild()
                    self.onNeedsResize?(nil)
                }
            }
        } else {
            springTarget = nil
            springTimer?.invalidate()
        }
        return .move
    }

    override func draggingExited(_ s: NSDraggingInfo?) {
        clearHighlight()
        springTarget = nil
        springTimer?.invalidate()
    }

    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        defer { clearHighlight(); springTimer?.invalidate(); springTarget = nil }

        guard let raw = s.draggingPasteboard.string(forType: .dockFoldersItem),
              let id = UUID(uuidString: raw) else { return false }

        let target = hitRow(for: s)?.target ?? .looseEnd

        switch target {
        case .looseAt(let i):            store.moveToLoose(itemID: id, at: i)
        case .looseEnd:                  store.moveToLoose(itemID: id)
        case .intoGroup(let gid):        store.move(itemID: id, toGroup: gid)
        case .groupFolderAt(let gid, let i): store.move(itemID: id, toGroup: gid, at: i)
        }
        rebuild()
        onNeedsResize?(nil)
        return true
    }

    /// As linhas são arranged subviews do stack, então o hit-test é feito em
    /// coordenadas do stack — um único caminho, sem conversões concorrentes.
    private func hitRow(for s: NSDraggingInfo) -> (view: NSView, target: DropTarget)? {
        let inStack = stack.convert(s.draggingLocation, from: nil)
        return rowMap.first { $0.view.frame.contains(inStack) }
    }

    private func highlight(_ row: HoverRow?) {
        guard highlighted !== row else { return }
        highlighted?.isDropTarget = false
        highlighted = row
        highlighted?.isDropTarget = true
    }

    private func clearHighlight() {
        highlighted?.isDropTarget = false
        highlighted = nil
    }

    // MARK: peças fixas

    private func separator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 9).isActive = true
        return v
    }

    private func emptyState() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Nenhuma pasta adicionada")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: "Adicionar pasta", target: self, action: #selector(addFolder))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label); container.addSubview(button)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 86),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10),
        ])
        return container
    }

    /// Faixa de status, não item de lista: alinhada à esquerda, junto ao rodapé.
    private func precisionNotice() -> NSView {
        let row = HoverRow()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.toolTip = "A seta só aparece com posicionamento preciso. Requer permissão de Acessibilidade."
        row.onClick = { [weak self] _ in self?.onRequestPrecision?() }

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle",
                             accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Posicionamento aproximado — ativar precisão")
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(icon); row.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 11),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12),
        ])
        return row
    }

    private func footer() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Adicionar")!,
                           target: self, action: #selector(showAddMenu(_:)))
        add.isBordered = false
        add.translatesAutoresizingMaskIntoConstraints = false

        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Opções")!,
                            target: self, action: #selector(showGearMenu(_:)))
        gear.isBordered = false
        gear.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(add); container.addSubview(gear)
        NSLayoutConstraint.activate([
            add.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            add.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            gear.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            gear.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    @objc private func addFolder() { onAddFolder?() }
    @objc private func requestPrecision() { onRequestPrecision?() }
    @objc private func createGroup() { onCreateGroup?() }
    @objc private func toggleLogin() { onToggleLoginItem?() }

    @objc private func showAddMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Adicionar pasta…", action: #selector(addFolder), keyEquivalent: "")
            .target = self

        if !store.data.groups.isEmpty {
            let groupSubmenu = NSMenu()
            for g in store.data.groups {
                let item = NSMenuItem(title: g.name, action: #selector(addGroupFolderAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = g.id
                groupSubmenu.addItem(item)
            }
            let groupItem = NSMenuItem(title: "Adicionar pasta ao grupo", action: nil, keyEquivalent: "")
            groupItem.submenu = groupSubmenu
            menu.addItem(groupItem)
        }

        menu.addItem(withTitle: "Criar grupo…", action: #selector(createGroup), keyEquivalent: "")
            .target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func addGroupFolderAction(_ sender: NSMenuItem) {
        guard let gid = sender.representedObject as? UUID else { return }
        onAddFolderToGroup?(gid)
    }

    @objc private func showGearMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let login = menu.addItem(withTitle: "Iniciar no login",
                                 action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        if isApproximate {
            menu.addItem(withTitle: "Ativar posicionamento preciso…",
                         action: #selector(requestPrecision), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }
}

extension BalloonContent: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        activeRow?.isSelected = false
        activeRow = nil
        optionsPopover = nil
        activeFolderID = nil
    }
}
