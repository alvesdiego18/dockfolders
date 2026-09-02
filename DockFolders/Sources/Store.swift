// Modelo de dados e persistência do DockFolders.
//
// Formato: JSON de paths em texto puro, conforme CONTEXT.md. Sem bookmarks — path
// renomeado ou volume desmontado deixa o item esmaecido, e o conserto é editar o arquivo.
//
// Regras estruturais aplicadas aqui, não na UI:
//   - um nível só: grupos contêm pastas, nunca outros grupos
//   - duas zonas: pastas avulsas no topo, grupos abaixo; reordenar nunca cruza zonas
//   - accordion exclusivo: no máximo um grupo aberto (`openGroupID`)
//   - excluir grupo promove suas pastas a avulsas; nada é destruído

import Foundation

// MARK: - Modelo

/// Uma forma de abrir o projeto. Uma pasta pode ter várias (Q33a).
///
/// `bundleID == nil` significa Finder. `targetPath` aponta para um arquivo específico
/// dentro da pasta — é o que o Xcode exige (`.xcworkspace`/`.xcodeproj`); nulo abre a
/// própria pasta. `command`, só para o Terminal, é um comando de shell rodado logo
/// depois do `cd` na pasta (ex.: `claude`); nulo apenas abre a pasta no Terminal.
struct Opener: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var bundleID: String?
    var targetPath: String?
    var command: String?

    static let finder = Opener(bundleID: nil, targetPath: nil)
    static let terminal = Opener(bundleID: "com.apple.Terminal", targetPath: nil)
    static let defaultOpeners: [Opener] = [.finder, .terminal]
    static func app(_ bundleID: String, target: String? = nil, command: String? = nil) -> Opener {
        Opener(bundleID: bundleID, targetPath: target, command: command)
    }
}

/// Formato antigo, quando cada pasta tinha um único abridor. Mantido só para migrar
/// o JSON existente sem perder configuração.
private enum LegacyOpener: Codable {
    case finder
    case app(bundleID: String)

    var migrated: Opener {
        switch self {
        case .finder: return .finder
        case .app(let id): return .app(id)
        }
    }
}

struct FolderItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var path: String
    var openers: [Opener] = Opener.defaultOpeners

    /// O primeiro da lista é o principal: é ele que o clique no nome dispara (Q33a).
    var primaryOpener: Opener { openers.first ?? .finder }

    var displayName: String { (path as NSString).lastPathComponent }

    enum CodingKeys: String, CodingKey { case id, path, openers, opener }

    init(id: UUID = UUID(), path: String, openers: [Opener] = Opener.defaultOpeners) {
        self.id = id; self.path = path; self.openers = openers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try c.decode(String.self, forKey: .path)
        if let list = try? c.decode([Opener].self, forKey: .openers) {
            openers = list.isEmpty ? [.finder] : list
        } else if let legacy = try? c.decode(LegacyOpener.self, forKey: .opener) {
            openers = [legacy.migrated]     // migração do formato de abridor único
        } else {
            openers = [.finder]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(path, forKey: .path)
        try c.encode(openers, forKey: .openers)
    }

    /// Q10: item que não resolve fica esmaecido e não clicável, sem distinguir a causa.
    var isAvailable: Bool {
        var isDir: ObjCBool = false
        let ok = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return ok && isDir.boolValue
    }
}

struct FolderGroup: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var folders: [FolderItem] = []
}

struct StoreData: Codable, Equatable {
    var version: Int = 1
    /// Zona superior. Toda pasta nasce aqui (Q26c).
    var loose: [FolderItem] = []
    /// Zona inferior.
    var groups: [FolderGroup] = []
    /// Accordion exclusivo: no máximo um aberto, lembrado entre sessões (Q30).
    var openGroupID: UUID?
    /// Alimenta o dropdown de apps por frequência — o LaunchServices praticamente
    /// só sugere o Finder para diretórios.
    var appUsage: [String: Int] = [:]
}

// MARK: - Persistência

final class Store {
    private(set) var data: StoreData
    let url: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DockFolders/folders.json")
    }

    init(url: URL = Store.defaultURL) {
        self.url = url
        self.data = Store.load(from: url)
    }

    private static func load(from url: URL) -> StoreData {
        guard let raw = try? Data(contentsOf: url) else { return StoreData() }
        guard let decoded = try? JSONDecoder().decode(StoreData.self, from: raw) else {
            // Arquivo ilegível: preserva o original em vez de sobrescrever silenciosamente.
            let backup = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: backup)
            return StoreData()
        }
        return decoded
    }

    func save() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(data) else { return }
        try? raw.write(to: url, options: .atomic)
    }

    // MARK: - Operações

    /// Toda pasta nasce avulsa (Q26c); ir para um grupo é sempre um segundo passo.
    @discardableResult
    func addLoose(path: String, openers: [Opener] = Opener.defaultOpeners) -> FolderItem {
        let item = FolderItem(path: path, openers: openers)
        data.loose.append(item)
        openers.forEach(recordUsage)
        save()
        return item
    }

    @discardableResult
    func createGroup(name: String) -> FolderGroup {
        let g = FolderGroup(name: name)
        data.groups.append(g)
        save()
        return g
    }

    func renameGroup(_ groupID: UUID, to name: String) {
        guard let i = data.groups.firstIndex(where: { $0.id == groupID }) else { return }
        data.groups[i].name = name
        save()
    }

    /// Excluir grupo promove as pastas a avulsas — nada é destruído (Q27).
    func deleteGroup(_ groupID: UUID) {
        guard let i = data.groups.firstIndex(where: { $0.id == groupID }) else { return }
        data.loose.append(contentsOf: data.groups[i].folders)
        data.groups.remove(at: i)
        if data.openGroupID == groupID { data.openGroupID = nil }
        save()
    }

    func move(itemID: UUID, toGroup groupID: UUID, at index: Int? = nil) {
        guard let item = detach(itemID) else { return }
        guard let g = data.groups.firstIndex(where: { $0.id == groupID }) else {
            data.loose.append(item); save(); return
        }
        let at = min(max(index ?? data.groups[g].folders.count, 0), data.groups[g].folders.count)
        data.groups[g].folders.insert(item, at: at)
        save()
    }

    func moveToLoose(itemID: UUID, at index: Int? = nil) {
        guard let item = detach(itemID) else { return }
        let at = min(max(index ?? data.loose.count, 0), data.loose.count)
        data.loose.insert(item, at: at)
        save()
    }

    func remove(itemID: UUID) {
        _ = detach(itemID)
        save()
    }

    @discardableResult
    func addFolder(path: String, toGroup groupID: UUID? = nil, openers: [Opener] = Opener.defaultOpeners) -> FolderItem {
        let item = FolderItem(path: path, openers: openers)
        if let groupID, let i = data.groups.firstIndex(where: { $0.id == groupID }) {
            data.groups[i].folders.append(item)
        } else {
            data.loose.append(item)
        }
        openers.forEach(recordUsage)
        save()
        return item
    }

    func setOpeners(_ openers: [Opener], for itemID: UUID) {
        mutateItem(itemID) { $0.openers = openers.isEmpty ? [.finder] : openers }
        openers.forEach(recordUsage)
        save()
    }

    func addOpener(_ opener: Opener, to itemID: UUID) {
        mutateItem(itemID) { $0.openers.append(opener) }
        recordUsage(opener)
        save()
    }

    func removeOpener(at index: Int, for itemID: UUID) {
        mutateItem(itemID) {
            guard index >= 0 && index < $0.openers.count else { return }
            $0.openers.remove(at: index)
            if $0.openers.isEmpty { $0.openers = [.finder] }
        }
        save()
    }

    func reorderOpeners(for itemID: UUID, fromIndex: Int, toIndex: Int) {
        mutateItem(itemID) {
            guard fromIndex >= 0 && fromIndex < $0.openers.count else { return }
            let opener = $0.openers.remove(at: fromIndex)
            let target = min(max(toIndex, 0), $0.openers.count)
            $0.openers.insert(opener, at: target)
        }
        save()
    }

    func updateOpener(at index: Int, for itemID: UUID, body: (inout Opener) -> Void) {
        mutateItem(itemID) {
            guard index >= 0 && index < $0.openers.count else { return }
            body(&$0.openers[index])
        }
        save()
    }

    func findItem(_ itemID: UUID) -> FolderItem? {
        if let item = data.loose.first(where: { $0.id == itemID }) { return item }
        for g in data.groups {
            if let item = g.folders.first(where: { $0.id == itemID }) { return item }
        }
        return nil
    }

    /// Accordion exclusivo: abrir um fecha os demais (Q24a).
    func setOpenGroup(_ groupID: UUID?) {
        data.openGroupID = (data.openGroupID == groupID) ? nil : groupID
        save()
    }

    /// O grupo que estava aberto vai para o topo — só no momento de reabrir o balão
    /// depois de ele ter sido fechado (relançar o app, ou clicar no Dock com o balão
    /// fechado), nunca enquanto o balão permanece aberto e você navega entre grupos.
    func promoteOpenGroupToFront() {
        guard let openID = data.openGroupID,
              let i = data.groups.firstIndex(where: { $0.id == openID }), i != 0 else { return }
        let g = data.groups.remove(at: i)
        data.groups.insert(g, at: 0)
        save()
    }

    /// Ordena o dropdown de apps por frequência de uso.
    func appsByUsage() -> [String] {
        data.appUsage.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    // MARK: - Internos

    private func recordUsage(_ opener: Opener) {
        guard let bundleID = opener.bundleID else { return }
        data.appUsage[bundleID, default: 0] += 1
    }

    /// Remove o item de onde quer que esteja e devolve.
    private func detach(_ itemID: UUID) -> FolderItem? {
        if let i = data.loose.firstIndex(where: { $0.id == itemID }) {
            return data.loose.remove(at: i)
        }
        for g in data.groups.indices {
            if let i = data.groups[g].folders.firstIndex(where: { $0.id == itemID }) {
                return data.groups[g].folders.remove(at: i)
            }
        }
        return nil
    }

    private func mutateItem(_ itemID: UUID, _ body: (inout FolderItem) -> Void) {
        if let i = data.loose.firstIndex(where: { $0.id == itemID }) {
            body(&data.loose[i]); return
        }
        for g in data.groups.indices {
            if let i = data.groups[g].folders.firstIndex(where: { $0.id == itemID }) {
                body(&data.groups[g].folders[i]); return
            }
        }
    }
}
