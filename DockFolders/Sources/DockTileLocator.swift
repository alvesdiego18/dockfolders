// Localiza o tile do próprio app no Dock, para ancorar o balão.
//
// Caminho preciso: Accessibility API sobre o processo do Dock, lendo AXPosition/AXSize
// do AXDockItem correspondente. Exige permissão de Acessibilidade.
//
// Fallback: mede a faixa ocupada pelo Dock pela diferença entre `frame` e `visibleFrame`
// da tela. Isso dá a orientação e a espessura do Dock com precisão, mas não a posição
// horizontal do ícone — que é estimada no centro.

import AppKit
import ApplicationServices

struct DockTileAnchor {
    enum Confidence: String {
        case precise      // veio da AX: sabemos onde o ícone está
        case approximate  // veio da heurística: sabemos onde o Dock está
    }

    /// Ponto ao qual a seta do balão se ancora, em coordenadas AppKit
    /// (origem inferior-esquerda da tela principal).
    let anchor: CGPoint
    /// Retângulo do tile em coordenadas AppKit, quando conhecido.
    let tileRect: CGRect?
    let confidence: Confidence
    let detail: String
}

enum DockTileLocator {

    static func locate(appNames: [String]) -> DockTileAnchor {
        if AXIsProcessTrusted(), let precise = viaAccessibility(appNames: appNames) {
            return precise
        }
        return viaHeuristic(reason: AXIsProcessTrusted()
            ? "AX autorizada, mas o tile não foi encontrado na árvore"
            : "sem permissão de Acessibilidade")
    }

    /// Títulos de todos os itens do Dock. Diagnóstico: confirma o formato da árvore AX.
    static func dumpDockItemTitles() -> [String] {
        guard let axDock = dockElement() else { return [] }
        return allDockItems(under: axDock, depth: 0).compactMap { title(of: $0) }
    }

    // MARK: caminho preciso (Accessibility)

    private static func viaAccessibility(appNames: [String]) -> DockTileAnchor? {
        guard let axDock = dockElement() else { return nil }

        let items = allDockItems(under: axDock, depth: 0)
        guard let tile = items.first(where: { el in
            guard let t = title(of: el) else { return false }
            return appNames.contains(t)
        }) else { return nil }

        guard let pos = point(of: tile, kAXPositionAttribute),
              let size = size(of: tile, kAXSizeAttribute) else { return nil }

        // A AX reporta em coordenadas com origem no canto superior-esquerdo e Y crescendo
        // para baixo; AppKit usa origem inferior-esquerda. Converter pela altura da tela
        // de referência (a que tem origem em zero).
        let refHeight = referenceScreenHeight()
        let rect = CGRect(x: pos.x,
                          y: refHeight - (pos.y + size.height),
                          width: size.width,
                          height: size.height)

        return DockTileAnchor(
            anchor: CGPoint(x: rect.midX, y: rect.maxY),
            tileRect: rect,
            confidence: .precise,
            detail: "AX: tile em \(fmt(rect)) (AX cru: origem \(fmt(pos)), tamanho \(fmt(size)))"
        )
    }

    private static func dockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        return AXUIElementCreateApplication(dock.processIdentifier)
    }

    /// A árvore do Dock não tem forma documentada, então varremos em profundidade limitada
    /// em vez de assumir um caminho fixo.
    private static func allDockItems(under el: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < 4 else { return [] }
        guard let children = copy(el, kAXChildrenAttribute) as? [AXUIElement] else { return [] }

        var found: [AXUIElement] = []
        for child in children {
            if let role = copy(child, kAXRoleAttribute) as? String, role == "AXDockItem" {
                found.append(child)
            } else {
                found.append(contentsOf: allDockItems(under: child, depth: depth + 1))
            }
        }
        return found
    }

    // MARK: fallback heurístico

    private static func viaHeuristic(reason: String) -> DockTileAnchor {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame
        let vf = screen.visibleFrame

        // A faixa que o Dock ocupa é exatamente o que `visibleFrame` desconta.
        // Mais confiável que calcular a partir de `tilesize`, porque o macOS encolhe
        // os tiles quando o Dock está cheio e o tamanho efetivo não é exposto.
        let bottom = vf.minY - f.minY
        let left   = vf.minX - f.minX
        let right  = f.maxX - vf.maxX

        let orientation: String
        let anchor: CGPoint
        if bottom > left && bottom > right {
            orientation = "bottom (faixa de \(Int(bottom))pt)"
            anchor = CGPoint(x: f.midX, y: f.minY + bottom)
        } else if left >= right {
            orientation = "left (faixa de \(Int(left))pt)"
            anchor = CGPoint(x: f.minX + left, y: f.midY)
        } else {
            orientation = "right (faixa de \(Int(right))pt)"
            anchor = CGPoint(x: f.maxX - right, y: f.midY)
        }

        return DockTileAnchor(
            anchor: anchor,
            tileRect: nil,
            confidence: .approximate,
            detail: "heurística (\(reason)): Dock \(orientation); X estimado no centro"
        )
    }

    // MARK: utilitários AX

    private static func copy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func title(of el: AXUIElement) -> String? {
        copy(el, kAXTitleAttribute) as? String
    }

    private static func point(of el: AXUIElement, _ attr: String) -> CGPoint? {
        guard let v = copy(el, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        guard AXValueGetValue(v as! AXValue, .cgPoint, &p) else { return nil }
        return p
    }

    private static func size(of el: AXUIElement, _ attr: String) -> CGSize? {
        guard let v = copy(el, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        guard AXValueGetValue(v as! AXValue, .cgSize, &s) else { return nil }
        return s
    }

    /// Tela cuja origem é (0,0) — referência para converter coordenadas AX em AppKit.
    private static func referenceScreenHeight() -> CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]).frame.height
    }

    private static func fmt(_ r: CGRect) -> String {
        "(\(Int(r.origin.x)), \(Int(r.origin.y))) \(Int(r.width))×\(Int(r.height))"
    }
    private static func fmt(_ p: CGPoint) -> String { "(\(Int(p.x)), \(Int(p.y)))" }
    private static func fmt(_ s: CGSize) -> String { "\(Int(s.width))×\(Int(s.height))" }
}
