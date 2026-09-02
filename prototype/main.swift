// Protótipo de validação: sharingType = .none realmente esconde a janela
// de uma transmissão de tela (Meet / Teams)?
//
// Duas janelas são exibidas simultaneamente:
//   CONTROLE  - sharingType padrão (.readOnly). DEVE aparecer na transmissão.
//   PROTEGIDA - sharingType .none.             NÃO DEVE aparecer na transmissão.
//
// A de controle é o que torna o teste conclusivo: sem ela, "não vi nada"
// também seria o resultado de compartilhar a tela errada.

import AppKit

// Painel sem borda precisa poder virar key, senão os botões não respondem.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var control: NSWindow!
    var protected: KeyablePanel!
    var statusLabel: NSTextField!

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        makeControlWindow()
        makeProtectedPanel()
        NSApp.activate(ignoringOtherApps: true)
        Self.appendLog("[\(Self.stamp())] === LAUNCH build=\(Self.buildID) pid=\(ProcessInfo.processInfo.processIdentifier) ===")
        logState("launch")
    }

    // MARK: janela de controle

    private func makeControlWindow() {
        control = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        control.title = "CONTROLE"
        control.level = .floating
        // sharingType fica no padrão (.readOnly) de propósito.

        let label = NSTextField(wrappingLabelWithString:
            "CONTROLE\n\nEsta janela DEVE aparecer na transmissão.\n"
            + "Se ela não aparecer, você está compartilhando a tela errada — "
            + "o teste não vale.")
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = control.contentView!
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        control.center()
        var f = control.frame
        f.origin.x -= 250
        control.setFrameOrigin(f.origin)
        control.makeKeyAndOrderFront(nil)
    }

    // MARK: painel protegido

    private func makeProtectedPanel() {
        protected = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 230),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // O ponto do protótipo.
        protected.sharingType = .none

        protected.isOpaque = false
        protected.backgroundColor = .clear
        protected.hasShadow = true
        protected.level = .floating
        protected.isMovableByWindowBackground = true
        protected.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Material do balão real, para já sentir a aparência final.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        protected.contentView = effect

        let title = NSTextField(wrappingLabelWithString:
            "PROTEGIDA\n\nEsta janela NÃO deve aparecer na transmissão.\n"
            + "Se aparecer, sharingType = .none falhou.")
        title.font = .systemFont(ofSize: 13)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Alternar ao vivo prova que a diferença vem de sharingType, e não de
        // outra particularidade da janela.
        let toggle = NSButton(title: "Alternar sharingType",
                              target: self,
                              action: #selector(toggleSharing))
        toggle.bezelStyle = .rounded
        toggle.translatesAutoresizingMaskIntoConstraints = false

        let quit = NSButton(title: "Sair", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        quit.translatesAutoresizingMaskIntoConstraints = false

        let buttons = NSStackView(views: [toggle, quit])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(title)
        effect.addSubview(statusLabel)
        effect.addSubview(buttons)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -20),
            title.topAnchor.constraint(equalTo: effect.topAnchor, constant: 24),

            statusLabel.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),

            buttons.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            buttons.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
        ])

        protected.center()
        var f = protected.frame
        f.origin.x += 250
        protected.setFrameOrigin(f.origin)
        protected.orderFrontRegardless()
        updateStatus()
    }

    @objc private func toggleSharing() {
        let antes = protected.sharingType
        let alvo: NSWindow.SharingType = (antes == NSWindow.SharingType.none) ? .readOnly : .none

        protected.sharingType = alvo
        let depoisDaAtribuicao = protected.sharingType

        protected.orderOut(nil)
        protected.orderFrontRegardless()
        let depoisDoReorder = protected.sharingType

        Self.appendLog("[\(Self.stamp())] toggle | antes=\(Self.name(antes))"
            + " alvo=\(Self.name(alvo))"
            + " apos-atribuicao=\(Self.name(depoisDaAtribuicao))"
            + " apos-reorder=\(Self.name(depoisDoReorder))")

        updateStatus()
    }

    private func updateStatus() {
        let none = protected.sharingType == NSWindow.SharingType.none
        statusLabel.stringValue = none
            ? "sharingType = .none  →  invisível na captura"
            : "sharingType = .readOnly  →  VISÍVEL na captura"
        statusLabel.textColor = none ? .systemGreen : .systemRed
    }

    // Fonte autoritativa: o próprio app lendo suas janelas. Não depende de
    // permissão de Gravação de Tela, ao contrário de CGWindowListCopyWindowInfo.
    private func logState(_ event: String) {
        let name = Self.name
        let line = "[\(Self.stamp())] \(event) | protegida=\(name(protected.sharingType))"
            + " | controle=\(name(control.sharingType))"
            + " | windowNumber protegida=\(protected.windowNumber)"
        print(line)
        Self.appendLog(line)
    }

    static func name(_ t: NSWindow.SharingType) -> String {
        switch t {
        case .none: return ".none"
        case .readOnly: return ".readOnly"
        @unknown default: return "?(\(t.rawValue))"
        }
    }

    static let buildID = "C3"

    static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    static let logURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("dockfolders-proto.log")

    static func appendLog(_ line: String) {
        let data = (line + "\n").data(using: .utf8)!
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
