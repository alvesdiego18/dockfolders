// O balão: painel sem borda ancorado ao ícone do Dock.
//
// Privacidade (validada em protótipo): sharingType = .none é definido na CRIAÇÃO da janela.
// Em macOS 26 o setter é recusado depois, então isto nunca é alternado em runtime.
// O build de debug libera a captura para permitir verificação visual da UI.

import AppKit

final class BalloonPanel: NSPanel {

    static let arrowHeight: CGFloat = 11
    static let arrowWidth: CGFloat = 20
    static let corner: CGFloat = 12
    static let minWidth: CGFloat = 240

    /// Duração da transição de redimensionamento (CONTEXT.md: ~0,2s com easing).
    /// Compartilhada com o balão para que a dissolução do conteúdo antigo termine junto.
    static let resizeDuration: TimeInterval = 0.22

    private(set) var currentWidth: CGFloat = 280

    /// Seta só aparece no modo preciso: no aproximado o erro horizontal medido é de
    /// 195pt, o que faria a seta apontar para outro app do Dock.
    private var showsArrow = false

    private let effect = NSVisualEffectView()
    private let shapeMask = CAShapeLayer()

    /// Fecha ao perder foco / ESC (Q7b).
    var onDismiss: (() -> Void)?

    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        #if DEBUG
        sharingType = .readOnly
        #else
        sharingType = .none
        #endif

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let host = NSView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.mask = shapeMask
        effect.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false

        host.addSubview(effect)
        effect.addSubview(content)
        contentView = host

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            effect.topAnchor.constraint(equalTo: host.topAnchor),
            effect.bottomAnchor.constraint(equalTo: host.bottomAnchor),

            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
        ])
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }

    override func cancelOperation(_ sender: Any?) {  // ESC
        onDismiss?()
    }

    /// Reposiciona ancorando a borda inferior no ícone do Dock.
    /// O balão cresce para cima: origin.y é fixo, só a altura muda (Q31).
    ///
    /// `concurrent` roda dentro da mesma animação de redimensionamento — é por onde o
    /// balão dissolve a foto do conteúdo antigo enquanto o accordion abre ou fecha.
    func present(contentWidth: CGFloat, contentHeight: CGFloat,
                 anchor: DockTileAnchor, animated: Bool,
                 concurrent: (() -> Void)? = nil) {
        showsArrow = (anchor.confidence == .precise)
        let total = contentHeight + (showsArrow ? Self.arrowHeight : 0)
        currentWidth = contentWidth

        var x = anchor.anchor.x - contentWidth / 2
        var y = anchor.anchor.y

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.anchor) })
            ?? NSScreen.main {
            let vf = screen.visibleFrame
            x = min(max(x, vf.minX + 8), vf.maxX - contentWidth - 8)
            y = min(y, vf.maxY - total - 8)
        }

        let target = NSRect(x: x, y: y, width: contentWidth, height: total)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = animated && isVisible && !reduceMotion

        if shouldAnimate {
            // Frame da janela, máscara dos cantos e conteúdo antigo animam juntos e com
            // o mesmo easing, para o balão crescer/encolher sem o conteúdo saltar.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.resizeDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                animator().setFrame(target, display: true)
                animateShape(to: total, duration: Self.resizeDuration)
                concurrent?()
            }
        } else {
            setFrame(target, display: true, animate: false)
            layoutShape(height: total)
            concurrent?()
        }

        orderFrontRegardless()
        makeKey()
    }

    /// Contorno do balão (retângulo arredondado + seta) para uma dada altura.
    private func shapePath(height: CGFloat) -> CGPath {
        let arrow = showsArrow ? Self.arrowHeight : 0
        let w = currentWidth
        let body = CGRect(x: 0, y: arrow, width: w, height: height - arrow)
        let p = CGMutablePath()
        p.addRoundedRect(in: body, cornerWidth: Self.corner, cornerHeight: Self.corner)
        if showsArrow {
            let mid = w / 2
            p.move(to: CGPoint(x: mid - Self.arrowWidth / 2, y: arrow + 1))
            p.addLine(to: CGPoint(x: mid, y: 0))
            p.addLine(to: CGPoint(x: mid + Self.arrowWidth / 2, y: arrow + 1))
            p.closeSubpath()
        }
        return p
    }

    private func layoutShape(height: CGFloat) {
        shapeMask.frame = CGRect(x: 0, y: 0, width: currentWidth, height: height)
        shapeMask.path = shapePath(height: height)
    }

    /// Interpola o contorno da máscara junto com o frame da janela — sem isto os
    /// cantos arredondados clipariam o conteúdo na altura antiga durante a transição.
    private func animateShape(to height: CGFloat, duration: TimeInterval) {
        let newPath = shapePath(height: height)

        let anim = CABasicAnimation(keyPath: "path")
        anim.fromValue = shapeMask.path
        anim.toValue = newPath
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.frame = CGRect(x: 0, y: 0, width: currentWidth, height: height)
        CATransaction.commit()

        shapeMask.add(anim, forKey: "path")
        shapeMask.path = newPath
    }

    /// Espaço reservado para a seta, para o conteúdo não invadi-la.
    var bottomInset: CGFloat { showsArrow ? Self.arrowHeight : 0 }
}
