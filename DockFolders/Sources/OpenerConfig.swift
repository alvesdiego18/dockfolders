// Janela de configuração das aberturas de uma pasta.
//
// Q34b: o alvo é sempre escolhido à mão — nada de autodetectar o .xcworkspace.
// Q35a: no máximo três aberturas.

import AppKit
import UniformTypeIdentifiers

final class OpenerConfigWindow: NSObject {

    private let item: FolderItem
    private var openers: [Opener]
    private let window: NSWindow
    private let list = NSStackView()
    private let addButton: NSButton
    private let terminalButton: NSButton
    private var confirmed = false

    static func run(for item: FolderItem) -> [Opener]? {
        let c = OpenerConfigWindow(item: item)
        return c.present()
    }

    private init(item: FolderItem) {
        self.item = item
        self.openers = item.openers
        self.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                               styleMask: [.titled], backing: .buffered, defer: false)
        self.addButton = NSButton(title: "Adicionar abertura…", target: nil, action: nil)
        self.terminalButton = NSButton(title: "Terminal", target: nil, action: nil)
        super.init()

        window.title = "Aberturas de “\(item.displayName)”"
        window.level = .modalPanel

        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 6
        list.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addOpener)
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false

        // Atalho: o Terminal sempre abre a pasta, então pula os dois diálogos
        // (escolher o app em /Applications, escolher pasta-ou-arquivo).
        terminalButton.target = self
        terminalButton.action = #selector(addTerminal)
        terminalButton.bezelStyle = .rounded
        terminalButton.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        terminalButton.imagePosition = .imageLeading
        terminalButton.translatesAutoresizingMaskIntoConstraints = false

        let done = NSButton(title: "Concluído", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString:
            "A primeira da lista é a principal: é ela que abre ao clicar no nome da pasta. "
            + "As demais ficam como ícones à direita.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let content = window.contentView!
        [list, addButton, terminalButton, done, hint].forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            list.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            list.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            addButton.topAnchor.constraint(equalTo: list.bottomAnchor, constant: 12),
            addButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            terminalButton.topAnchor.constraint(equalTo: list.bottomAnchor, constant: 12),
            terminalButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),

            hint.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 14),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            done.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        rebuild()
    }

    private func present() -> [Opener]? {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return confirmed ? (openers.isEmpty ? [.finder] : openers) : nil
    }

    @objc private func finish() {
        confirmed = true
        NSApp.stopModal()
    }

    private func rebuild() {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if openers.isEmpty {
            let empty = NSTextField(labelWithString: "Nenhuma abertura configurada.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            list.addArrangedSubview(empty)
        }
        for (i, opener) in openers.enumerated() {
            list.addArrangedSubview(row(for: opener, at: i))
        }
        addButton.isEnabled = openers.count < FolderItem.maxOpeners
        terminalButton.isEnabled = openers.count < FolderItem.maxOpeners
        window.setContentSize(NSSize(width: 420, height: 150 + CGFloat(max(openers.count, 1)) * 34))
    }

    @objc private func addTerminal() {
        guard Opening.appURL(for: "com.apple.Terminal") != nil else { return }

        // Comando opcional: o Terminal abre na pasta e, se houver comando, roda-o
        // logo depois (ex.: `claude`). Em branco, só abre a pasta.
        let alert = NSAlert()
        alert.messageText = "Terminal"
        alert.informativeText = "Comando para o Terminal rodar ao abrir (opcional). "
            + "Ex.: claude. Em branco, só abre a pasta no Terminal."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "claude"
        alert.accessoryView = field
        alert.addButton(withTitle: "Adicionar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let command = field.stringValue.trimmingCharacters(in: .whitespaces)
        openers.append(.app("com.apple.Terminal", command: command.isEmpty ? nil : command))
        rebuild()
    }

    private func row(for opener: Opener, at index: Int) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let icon = NSImageView()
        icon.image = Opening.icon(for: opener)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let detail: String
        if let cmd = opener.command, !cmd.isEmpty {
            detail = "$ \(cmd)"
        } else if let t = opener.targetPath, !t.isEmpty {
            detail = (t as NSString).lastPathComponent
        } else {
            detail = "a pasta"
        }
        let label = NSTextField(labelWithString: "\(Opening.appName(for: opener))  ·  \(detail)")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        if index == 0 {
            let badge = NSTextField(labelWithString: "principal")
            badge.font = .systemFont(ofSize: 10)
            badge.textColor = .tertiaryLabelColor
            badge.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -84),
                badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }

        let up = ActionButton(image: NSImage(systemSymbolName: "arrow.up",
                                             accessibilityDescription: "Subir"),
                              tooltip: "Tornar principal") { [weak self] in
            guard let self, index > 0 else { return }
            self.openers.swapAt(index, index - 1)
            self.rebuild()
        }
        up.isEnabled = index > 0

        let remove = ActionButton(image: NSImage(systemSymbolName: "minus.circle",
                                                 accessibilityDescription: "Remover"),
                                  tooltip: "Remover esta abertura") { [weak self] in
            guard let self else { return }
            self.openers.remove(at: index)
            self.rebuild()
        }

        container.addSubview(icon); container.addSubview(label)
        container.addSubview(up); container.addSubview(remove)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            up.trailingAnchor.constraint(equalTo: remove.leadingAnchor, constant: -8),
            up.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            up.widthAnchor.constraint(equalToConstant: 18),

            remove.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            remove.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            remove.widthAnchor.constraint(equalToConstant: 18),
        ])
        return container
    }

    // MARK: adicionar

    @objc private func addOpener() {
        guard let bundleID = pickApp() else { return }
        let target = pickTarget()          // nil = abre a própria pasta
        openers.append(.app(bundleID, target: target))
        rebuild()
    }

    private func pickApp() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Escolher"
        panel.message = "Qual aplicativo abre esta pasta?"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    /// Q34b: sempre manual. O Xcode precisa do .xcworkspace/.xcodeproj, não da pasta.
    private func pickTarget() -> String? {
        let alert = NSAlert()
        alert.messageText = "O que este aplicativo deve abrir?"
        alert.informativeText = "O Xcode precisa de um arquivo específico "
            + "(.xcworkspace ou .xcodeproj). Terminal e editores costumam abrir a pasta."
        alert.addButton(withTitle: "A pasta")
        alert.addButton(withTitle: "Escolher arquivo…")
        guard alert.runModal() == .alertSecondButtonReturn else { return nil }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false   // .xcodeproj é pacote: conta como arquivo
        panel.directoryURL = URL(fileURLWithPath: item.path)
        panel.prompt = "Escolher"
        panel.message = "Arquivo dentro de “\(item.displayName)”"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
