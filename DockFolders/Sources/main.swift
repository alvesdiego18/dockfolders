// DockFolders — ícone no Dock que abre um balão com pastas de projeto.

import AppKit
import ApplicationServices
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func toggle() {
        do {
            if isEnabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("login item: \(error.localizedDescription)")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = Store()
    private var panel: BalloonPanel!
    private var content: BalloonContent!
    /// Uma folha modal faz o painel perder o foco; sem isto ele se fecharia sozinho.
    private var isPresentingModal = false

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)

        content = BalloonContent(store: store)
        panel = BalloonPanel(content: content)
        panel.onDismiss = { [weak self] in self?.hide() }
        panel.onEscape = { [weak self] in self?.content.handleEscape() ?? false }

        content.onOpen = { [weak self] keepOpen in if !keepOpen { self?.hide() } }
        content.onNeedsResize = { [weak self] concurrent in
            self?.present(animated: true, concurrent: concurrent)
        }
        content.onAddFolder = { [weak self] in self?.addFolder() }
        content.onAddFolderToGroup = { [weak self] groupID in self?.addFolder(toGroup: groupID) }
        content.onCreateGroup = { [weak self] in self?.createGroup() }
        content.onToggleLoginItem = { LoginItem.toggle() }
        content.onRequestPrecision = { [weak self] in self?.requestAccessibility() }
        content.withModal = { [weak self] body in self?.withModal(body) ?? () }

        // O tile do Dock só existe depois que o app aparece nele.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.openBalloon()
        }
    }

    /// Clique no ícone do Dock com o app já rodando (Q6b + Q7b: toggle).
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if panel.isVisible { hide() } else { openBalloon() }
        return true
    }

    /// Transição de fechado → aberto: o único momento em que o grupo que ficou aberto
    /// pula para o topo da lista. Diferente de `present`, que também redesenha o balão
    /// já visível (abrir um grupo, adicionar pasta) — ali a ordem não deve mudar.
    private func openBalloon() {
        store.promoteOpenGroupToFront()
        present(animated: false)
    }

    // MARK: apresentação

    /// `concurrent` (vindo do accordion) roda dentro da animação de redimensionamento,
    /// dissolvendo a foto do conteúdo anterior enquanto o balão cresce ou encolhe.
    private func present(animated: Bool, concurrent: (() -> Void)? = nil) {
        let anchor = DockTileLocator.locate(appNames: ["DockFolders"])
        content.isApproximate = (anchor.confidence == .approximate)
        content.setBottomInset(anchor.confidence == .precise ? BalloonPanel.arrowHeight : 0)
        content.rebuild()
        content.layoutSubtreeIfNeeded()

        let screen = NSScreen.screens.first { $0.frame.contains(anchor.anchor) } ?? NSScreen.main
        let maxWidth = (screen?.visibleFrame.width ?? 900) - 40
        panel.present(contentWidth: content.measuredWidth(maxWidth: maxWidth),
                      contentHeight: content.measuredHeight,
                      anchor: anchor, animated: animated, concurrent: concurrent)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// O balão roda em `.popUpMenu`, acima de diálogos modais — se ficasse visível,
    /// esconderia a janela que o usuário precisa ver. Some enquanto o modal está aberto.
    private func withModal<T>(_ body: () -> T) -> T {
        isPresentingModal = true
        let wasVisible = panel.isVisible
        panel.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        let result = body()
        isPresentingModal = false
        if wasVisible { present(animated: false) }
        return result
    }

    private func hide() {
        guard !isPresentingModal else { return }
        content.closeOptionsPopover()
        panel.orderOut(nil)
    }

    // MARK: ações

    private func addFolder(toGroup groupID: UUID? = nil) {
        withModal {
            let open = NSOpenPanel()
            open.canChooseDirectories = true
            open.canChooseFiles = false          // escopo é só pastas
            open.allowsMultipleSelection = false
            open.prompt = "Adicionar"
            open.message = groupID != nil ? "Escolha uma pasta para adicionar ao grupo" : "Escolha uma pasta para adicionar"
            guard open.runModal() == .OK, let url = open.url else { return }

            // Nasce com Finder e Terminal e navega imediatamente para seus detalhes
            let item = store.addFolder(path: url.path, toGroup: groupID)
            DispatchQueue.main.async { [weak self] in
                self?.content.showFolderOptions(for: item.id)
            }
        }
    }

    private func createGroup() {
        withModal {
        let alert = NSAlert()
        alert.messageText = "Novo grupo"
        alert.informativeText = "O grupo nasce vazio; arraste pastas para dentro dele."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Nome do grupo"
        alert.accessoryView = field
        alert.addButton(withTitle: "Criar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.createGroup(name: name)
        }
    }

    private func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
