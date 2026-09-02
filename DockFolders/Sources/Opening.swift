// Abertura de pastas e resolução de apps.

import AppKit
import UniformTypeIdentifiers

enum Opening {

    /// URL efetivamente aberta: o alvo específico do abridor, ou a própria pasta.
    static func targetURL(_ item: FolderItem, _ opener: Opener) -> URL {
        if let t = opener.targetPath, !t.isEmpty { return URL(fileURLWithPath: t) }
        return URL(fileURLWithPath: item.path)
    }

    static func open(_ item: FolderItem, with opener: Opener, completion: (() -> Void)? = nil) {
        let url = targetURL(item, opener)
        guard let bundleID = opener.bundleID else {
            NSWorkspace.shared.open(url)          // Finder
            completion?()
            return
        }
        guard let appURL = appURL(for: bundleID) else {
            NSWorkspace.shared.open(url)          // app sumiu: cai no Finder
            completion?()
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { completion?() }
        }
    }

    /// Intervalo mínimo entre duas aberturas seguidas do MESMO app, medido empiricamente
    /// contra o VS Code: menos que isso e a segunda pasta às vezes cai na mesma janela
    /// da primeira (o app ainda não tinha marcado a janela como "não mais vazia"); a
    /// partir daqui, duas janelas separadas de forma consistente.
    private static let sameAppGap: TimeInterval = 0.9

    /// Abre vários pares (pasta, abertura) de uma vez — "abrir tudo" de um grupo.
    ///
    /// **Uma chamada por pasta, nunca todas as URLs numa única chamada.** Medido
    /// diretamente: dar duas pastas ao VS Code numa só chamada faz ele tratar como
    /// pedido de *workspace multi-root* — os dois projetos caem juntos numa única
    /// janela, não em duas. O Android Studio, na mesma situação, simplesmente ignora
    /// tudo além da primeira URL. O Xcode é o único que não se importa, porque não tem
    /// esse conceito de mesclagem — mas empacotar para todos os apps quebrava os outros
    /// dois. Uma pasta por chamada é o que essas IDEs tratam como "abra este projeto".
    ///
    /// **Aberturas do mesmo app são encadeadas com um intervalo mínimo, não disparadas
    /// de uma vez.** Esperar só o `completionHandler` do `NSWorkspace.open` não basta —
    /// ele confirma que o app foi lançado/ativado, não que terminou de processar o
    /// pedido internamente; para o VS Code isso ainda deixava a segunda pasta cair na
    /// janela da primeira em vez de abrir uma nova. Itens de apps diferentes (uma pasta
    /// + um Terminal, por exemplo) não têm essa corrida — só um app por vez pode estar
    /// "com uma janela ainda vazia" — então saem em sequência sem espera.
    static func openAll(_ pairs: [(item: FolderItem, opener: Opener)]) {
        func step(_ index: Int) {
            guard index < pairs.count else { return }
            let (item, opener) = pairs[index]
            let sameAppAsNext = index + 1 < pairs.count && pairs[index + 1].opener.bundleID == opener.bundleID
                && opener.bundleID != nil
            open(item, with: opener) {
                if sameAppAsNext {
                    DispatchQueue.main.asyncAfter(deadline: .now() + sameAppGap) { step(index + 1) }
                } else {
                    step(index + 1)
                }
            }
        }
        step(0)
    }

    static func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func icon(for opener: Opener) -> NSImage? {
        guard let id = opener.bundleID else {
            // Finder: o ícone da pasta do macOS, não o rosto do app Finder.
            return NSWorkspace.shared.icon(for: .folder)
        }
        guard let u = appURL(for: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: u.path)
    }

    static func appName(for opener: Opener) -> String {
        guard let id = opener.bundleID else { return "Finder" }
        guard let u = appURL(for: id) else { return id }
        return FileManager.default.displayName(atPath: u.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    /// Texto do tooltip: só o app, ou "app — arquivo" quando há alvo específico (Q35).
    static func tooltip(for opener: Opener) -> String {
        let name = appName(for: opener)
        guard let t = opener.targetPath, !t.isEmpty else { return name }
        return "\(name) — \((t as NSString).lastPathComponent)"
    }
}
