// Harness de medição do posicionamento do balão.
//
// Este app é .regular, então tem um tile próprio no Dock e pode localizar a si mesmo.
// Ele desenha um balão real (corpo + seta) com o ápice da seta exatamente no ponto
// calculado — se o ápice encostar no ícone, o posicionamento está correto.
//
// A captura de tela fica LIBERADA aqui de propósito: é o build de desenvolvimento
// previsto no CONTEXT.md, que permite verificar a UI por screenshot.

import AppKit
import ApplicationServices

let buildID = "L1"
let logURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("dockfolders-locator.log")

func log(_ line: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
    let out = "[\(f.string(from: Date()))] \(line)"
    print(out)
    let data = (out + "\n").data(using: .utf8)!
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(data); try? h.close()
    } else {
        try? data.write(to: logURL)
    }
}

/// Balão com seta apontando para baixo, ápice no centro da borda inferior.
final class BalloonView: NSView {
    static let arrowHeight: CGFloat = 12
    static let arrowWidth: CGFloat = 22
    static let corner: CGFloat = 12

    override var isFlipped: Bool { false }

    func shapePath() -> CGPath {
        let ah = Self.arrowHeight, aw = Self.arrowWidth, r = Self.corner
        let body = CGRect(x: 0, y: ah, width: bounds.width, height: bounds.height - ah)
        let p = CGMutablePath()
        p.addRoundedRect(in: body, cornerWidth: r, cornerHeight: r)
        let mid = bounds.midX
        p.move(to: CGPoint(x: mid - aw / 2, y: ah + 1))
        p.addLine(to: CGPoint(x: mid, y: 0))
        p.addLine(to: CGPoint(x: mid + aw / 2, y: ah + 1))
        p.closeSubpath()
        return p
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: KeyablePanel!
    var balloon: BalloonView!
    var effect: NSVisualEffectView!
    var info: NSTextField!

    let panelSize = NSSize(width: 300, height: 150)

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        try? FileManager.default.removeItem(at: logURL)
        log("=== LAUNCH build=\(buildID) pid=\(ProcessInfo.processInfo.processIdentifier) ===")
        log("AXIsProcessTrusted = \(AXIsProcessTrusted())")

        buildPanel()
        NSApp.activate(ignoringOtherApps: true)

        // O tile só existe depois que o app aparece no Dock.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.relocate() }
    }

    private func buildPanel() {
        panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: panelSize),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        balloon = BalloonView(frame: NSRect(origin: .zero, size: panelSize))
        effect = NSVisualEffectView(frame: balloon.bounds)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        balloon.addSubview(effect)
        panel.contentView = balloon
        applyMask()

        info = NSTextField(wrappingLabelWithString: "medindo…")
        info.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        info.translatesAutoresizingMaskIntoConstraints = false

        let relocateBtn = NSButton(title: "Medir de novo", target: self, action: #selector(relocate))
        let permBtn = NSButton(title: "Pedir Acessibilidade", target: self, action: #selector(askPermission))
        let quitBtn = NSButton(title: "Sair", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        [relocateBtn, permBtn, quitBtn].forEach { $0.bezelStyle = .rounded }

        let row = NSStackView(views: [relocateBtn, permBtn, quitBtn])
        row.orientation = .horizontal
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(info)
        effect.addSubview(row)
        NSLayoutConstraint.activate([
            info.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            info.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            info.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            row.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            row.bottomAnchor.constraint(equalTo: effect.bottomAnchor,
                                        constant: -(BalloonView.arrowHeight + 10)),
        ])

        panel.orderFrontRegardless()
    }

    private func applyMask() {
        let mask = CAShapeLayer()
        mask.path = balloon.shapePath()
        effect.layer?.mask = mask
    }

    @objc private func askPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        log("prompt de Acessibilidade: trusted=\(trusted)")
    }

    @objc private func relocate() {
        let titles = DockTileLocator.dumpDockItemTitles()
        log("itens do Dock (\(titles.count)): \(titles.joined(separator: " | "))")

        let names = ["DockFolders Locator", "DockFoldersLocator"]
        let a = DockTileLocator.locate(appNames: names)
        log("confiança=\(a.confidence.rawValue) ancora=(\(Int(a.anchor.x)), \(Int(a.anchor.y)))")
        log("  \(a.detail)")

        // Ápice da seta no ponto âncora.
        let origin = NSPoint(x: a.anchor.x - panelSize.width / 2, y: a.anchor.y)
        panel.setFrameOrigin(origin)
        applyMask()

        info.stringValue = """
        AX autorizada: \(AXIsProcessTrusted())
        confiança: \(a.confidence.rawValue)
        âncora: (\(Int(a.anchor.x)), \(Int(a.anchor.y)))
        itens no Dock: \(titles.count)
        """
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
