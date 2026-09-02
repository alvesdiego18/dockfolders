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

        content.onOpen = { [weak self] keepOpen in if !keepOpen { self?.hide() } }
        content.onNeedsResize = { [weak self] in self?.present(animated: true) }
        content.onAddFolder = { [weak self] in self?.addFolder() }
        content.onCreateGroup = { [weak self] in self?.createGroup() }
        content.onToggleLoginItem = { LoginItem.toggle() }
        content.onRequestPrecision = { [weak self] in self?.requestAccessibility() }
        content.onChangeOpener = { [weak self] item in self?.changeOpener(item) }

        // O tile do Dock só existe depois que o app aparece nele.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.present(animated: false)
        }
    }

    /// Clique no ícone do Dock com o app já rodando (Q6b + Q7b: toggle).
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if panel.isVisible { hide() } else { present(animated: false) }
        return true
    }

    // MARK: apresentação

    private func present(animated: Bool) {
        let anchor = DockTileLocator.locate(appNames: ["DockFolders"])
        content.isApproximate = (anchor.confidence == .approximate)
        content.setBottomInset(anchor.confidence == .precise ? BalloonPanel.arrowHeight : 0)
        content.rebuild()
        content.layoutSubtreeIfNeeded()

        let screen = NSScreen.screens.first { $0.frame.contains(anchor.anchor) } ?? NSScreen.main
        let maxWidth = (screen?.visibleFrame.width ?? 900) - 40
        panel.present(contentWidth: content.measuredWidth(maxWidth: maxWidth),
                      contentHeight: content.measuredHeight,
                      anchor: anchor, animated: animated)
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
        panel.orderOut(nil)
    }

    // MARK: ações

    private func addFolder() {
        withModal {
            let open = NSOpenPanel()
            open.canChooseDirectories = true
            open.canChooseFiles = false          // escopo é só pastas
            open.allowsMultipleSelection = false
            open.prompt = "Adicionar"
            guard open.runModal() == .OK, let url = open.url else { return }

            // Nasce com o Finder; as aberturas de verdade são configuradas em seguida.
            let item = store.addLoose(path: url.path)
            if let openers = OpenerConfigWindow.run(for: item) {
                store.setOpeners(openers, for: item.id)
            }
        }
    }

    private func changeOpener(_ item: FolderItem) {
        withModal {
            guard let openers = OpenerConfigWindow.run(for: item) else { return }
            store.setOpeners(openers, for: item.id)
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
