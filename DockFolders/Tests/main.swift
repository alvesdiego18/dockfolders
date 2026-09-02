// Verifica as regras estruturais do Store contra o que o CONTEXT.md decidiu.
import Foundation

var falhas = 0
func check(_ cond: Bool, _ what: String) {
    print((cond ? "  ok   " : "  FALHA") + "  \(what)")
    if !cond { falhas += 1 }
}

let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("dockfolders-test-\(UUID().uuidString)/folders.json")
let store = Store(url: tmp)

print("\n— pastas nascem avulsas (Q26c)")
let a = store.addLoose(path: "/Volumes/Projetos/Diego/dockfolders",
                       openers: [.app("com.microsoft.VSCode")])
let b = store.addLoose(path: "/Applications")
check(store.data.loose.count == 2, "duas avulsas")
check(store.data.groups.isEmpty, "nenhum grupo criado implicitamente")

print("\n— grupo nasce vazio e recebe por movimentação (Q27)")
let g = store.createGroup(name: "biscoito")
check(g.folders.isEmpty, "grupo criado vazio")
store.move(itemID: a.id, toGroup: g.id)
check(store.data.loose.count == 1, "item saiu das avulsas")
check(store.data.groups[0].folders.count == 1, "item entrou no grupo")

print("\n— accordion exclusivo (Q24a)")
let g2 = store.createGroup(name: "outro")
store.setOpenGroup(g.id)
check(store.data.openGroupID == g.id, "grupo aberto registrado")
store.setOpenGroup(g2.id)
check(store.data.openGroupID == g2.id, "abrir outro substitui, não acumula")
store.setOpenGroup(g2.id)
check(store.data.openGroupID == nil, "clicar no aberto fecha")

print("\n— excluir grupo promove as pastas a avulsas (Q27)")
store.setOpenGroup(g.id)
let antes = store.data.loose.count
store.deleteGroup(g.id)
check(store.data.loose.count == antes + 1, "pasta do grupo virou avulsa, não sumiu")
check(store.data.groups.count == 1, "grupo removido")
check(store.data.openGroupID == nil, "grupo aberto excluído limpa openGroupID")

print("\n— disponibilidade do path (Q10)")
let real = FolderItem(path: "/Applications")
let sumida = FolderItem(path: "/Volumes/Projetos/nao-existe-\(UUID().uuidString)")
let arquivo = FolderItem(path: "/etc/hosts")
check(real.isAvailable, "pasta existente disponível")
check(!sumida.isAvailable, "pasta inexistente indisponível")
check(!arquivo.isAvailable, "arquivo não conta como pasta (escopo é só pastas)")

print("\n— histórico de apps por frequência (Q9b)")
store.setOpeners([.app("com.microsoft.VSCode")], for: b.id)
store.setOpeners([.app("com.todesktop.230313mzl4w4u92")], for: b.id)
store.setOpeners([.app("com.microsoft.VSCode")], for: b.id)
check(store.appsByUsage().first == "com.microsoft.VSCode", "mais usado vem primeiro")

print("\n— round-trip em disco")
store.save()
let recarregado = Store(url: tmp)
check(recarregado.data == store.data, "estado idêntico após salvar e recarregar")

print("\n— múltiplas aberturas por pasta (Q33a/Q35a)")
store.setOpeners([.app("com.apple.dt.Xcode", target: "/tmp/p.xcworkspace"),
                  .app("com.microsoft.VSCode"),
                  .app("com.apple.Terminal")], for: b.id)
let multi = store.data.loose.first { $0.id == b.id }!
check(multi.openers.count == 3, "três aberturas guardadas")
check(multi.primaryOpener.bundleID == "com.apple.dt.Xcode", "a primeira é a principal")
check(multi.openers[0].targetPath == "/tmp/p.xcworkspace", "alvo específico preservado")
store.setOpeners([.finder, .finder, .finder, .finder], for: b.id)
check(store.data.loose.first { $0.id == b.id }!.openers.count == 4, "aberturas ilimitadas guardadas")

print("\n— adição direta a grupo e manipulação de openers")
let groupDireto = store.createGroup(name: "Direto")
let diretoItem = store.addFolder(path: "/Library", toGroup: groupDireto.id)
check(store.data.groups.first(where: { $0.id == groupDireto.id })?.folders.contains(where: { $0.id == diretoItem.id }) == true,
      "pasta adicionada diretamente ao grupo")
store.addOpener(.app("com.apple.Terminal"), to: diretoItem.id)
let loadedItem = store.findItem(diretoItem.id)!
check(loadedItem.openers.count == 2, "opener adicionado ao item")
store.reorderOpeners(for: diretoItem.id, fromIndex: 1, toIndex: 0)
check(store.findItem(diretoItem.id)!.openers.first?.bundleID == "com.apple.Terminal", "opener reordenado")
store.removeOpener(at: 0, for: diretoItem.id)
check(store.findItem(diretoItem.id)!.openers.first == .finder, "opener removido")

print("\n— comando de Terminal por abertura")
store.setOpeners([.app("com.apple.Terminal", command: "claude"),
                  .app("com.apple.Terminal")], for: b.id)
let term = store.data.loose.first { $0.id == b.id }!
check(term.openers[0].command == "claude", "comando guardado na abertura")
check(term.openers[1].command == nil, "abertura de Terminal sem comando fica nula")
store.save()
let termReload = Store(url: tmp)
check(termReload.data.loose.first { $0.id == b.id }!.openers[0].command == "claude",
      "comando sobrevive ao round-trip em disco")

print("\n— JSON sem a chave 'command' decodifica (compat)")
let noCmdURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("dockfolders-nocmd-\(UUID().uuidString)/folders.json")
try! FileManager.default.createDirectory(at: noCmdURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
try! """
{"version":1,"loose":[{"id":"\(UUID().uuidString)","path":"/Applications",
 "openers":[{"id":"\(UUID().uuidString)","bundleID":"com.apple.Terminal"}]}],
 "groups":[],"appUsage":{}}
""".data(using: .utf8)!.write(to: noCmdURL)
let noCmd = Store(url: noCmdURL)
check(noCmd.data.loose.first?.openers.first?.command == nil, "abertura antiga sem 'command' vira nil")

print("\n— migração do formato antigo (abridor único)")
let legacyURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("dockfolders-legacy-\(UUID().uuidString)/folders.json")
try! FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
let legacyJSON = """
{"version":1,"loose":[{"id":"\(UUID().uuidString)","path":"/Applications",
 "opener":{"app":{"bundleID":"com.microsoft.VSCode"}}}],
 "groups":[],"appUsage":{}}
"""
try! legacyJSON.data(using: .utf8)!.write(to: legacyURL)
let migrado = Store(url: legacyURL)
check(migrado.data.loose.count == 1, "item antigo carregado")
check(migrado.data.loose.first?.openers.first?.bundleID == "com.microsoft.VSCode",
      "abridor único virou lista de uma abertura")

print("\n— grupo aberto vai para o topo só ao reabrir o balão")
let s2 = Store(url: URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("dockfolders-order-\(UUID().uuidString)/folders.json"))
let gA = s2.createGroup(name: "A")
let gB = s2.createGroup(name: "B")
let gC = s2.createGroup(name: "C")
s2.setOpenGroup(gB.id)
check(s2.data.groups.map(\.name) == ["A", "B", "C"], "ordem intacta enquanto o balão segue aberto")
s2.promoteOpenGroupToFront()
check(s2.data.groups.map(\.name) == ["B", "A", "C"], "B foi para o topo ao reabrir")
s2.promoteOpenGroupToFront()
check(s2.data.groups.map(\.name) == ["B", "A", "C"], "já estava no topo: reabrir de novo não mexe")
s2.setOpenGroup(gB.id)  // fecha B (accordion exclusivo: clicar no aberto fecha)
check(s2.data.openGroupID == nil, "B fechado")
s2.promoteOpenGroupToFront()
check(s2.data.groups.map(\.name) == ["B", "A", "C"], "sem grupo aberto: reabrir não reordena")

print("\n— arquivo corrompido não é sobrescrito em silêncio")
try! "{ nao é json".data(using: .utf8)!.write(to: tmp)
let apos = Store(url: tmp)
check(apos.data.loose.isEmpty, "começa vazio após corrupção")
let dir = tmp.deletingLastPathComponent()
let backups = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
    .filter { $0.contains("corrupt") } ?? []
check(!backups.isEmpty, "original preservado como .corrupt-*")

print("\n" + (falhas == 0 ? "TODOS OS TESTES PASSARAM" : "\(falhas) FALHA(S)"))
exit(falhas == 0 ? 0 : 1)
