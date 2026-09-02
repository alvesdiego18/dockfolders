# DockFolders

App macOS nativo: um ícone no Dock que, ao ser clicado, abre um balão com pastas de
projeto agrupadas. Cada pasta abre no aplicativo escolhido para ela.

Este documento é o desenho acordado antes da implementação. Cada decisão abaixo foi
tomada explicitamente; as que divergiram da recomendação técnica estão registradas em
"Riscos aceitos".

## Stack

- Swift 6.2 / Xcode 26, macOS 26, arm64
- App `.regular` (obrigatório para ter ícone no Dock; `LSUIElement` some do Dock)
- Residente via login item, ícone fixado manualmente pelo usuário
- Build local: sem sandbox, sem notarização, sem conta de desenvolvedor

## Entrada

Clique no ícone do Dock, capturado por `applicationShouldHandleReopen(_:hasVisibleWindows:)`.
É a **única** porta de entrada: sem menu do Dock customizado, sem hotkey global.

## Painel

`NSPanel` sem borda com `NSVisualEffectView` material `.popover`, cantos arredondados,
seta ancorada ao ícone, sombra do sistema, claro/escuro automático.

**Posicionamento.** Accessibility API sobre o processo Dock, lendo `AXPosition`/`AXSize`
do tile correspondente. Fallback heurístico quando a permissão não foi concedida ou a árvore
AX mudou.

### Validado empiricamente (harness de protótipo, macOS 26.6.2 — descartado após validar)

Caminho preciso funciona. A árvore AX do Dock entrega 17 itens com títulos legíveis, e o tile
do app é localizável.

**O título do tile é o `CFBundleName`, não o `CFBundleDisplayName`.** O app se chama
"DockFolders Locator" no Finder e `DockFoldersLocator` na AX. Casar pelo display name falha
em silêncio.

**A heurística mede o Dock por `frame` menos `visibleFrame`, não por `tilesize`.** Medição real:
faixa do Dock = 55pt, `tilesize` configurado = 35. Calcular a partir do `tilesize` erraria em
20pt no caso mais simples; `visibleFrame` dá a espessura exata sem adivinhar.

**Erro da heurística é assimétrico** (medido contra o caminho preciso no mesmo instante):

| eixo | preciso | heurística | erro |
|---|---|---|---|
| X | 1155 | 960 | **195pt** |
| Y | 59 | 55 | 4pt |

A altura sai quase de graça; a posição horizontal do ícone é impossível de estimar sem AX —
195pt são cerca de dez ícones de distância.

**Sem permissão, a AX devolve zero itens** e o app cai no modo aproximado silenciosamente,
como previsto no onboarding sem prompt.

**Onboarding da permissão.** Sem prompt na primeira execução. O app roda em heurística e
mostra um aviso discreto e dispensável no rodapé ("posicionamento aproximado — ativar
precisão").

**Dispensa.** Fecha ao perder foco, com ESC, com novo clique no ícone (toggle) e ao abrir
uma pasta. `⌘`+clique abre a pasta e mantém o balão aberto.

**Seta.** Visível apenas no modo preciso. Em modo aproximado ela é ocultada e o balão vira um
painel flutuante — decisão tomada depois de medir que o erro horizontal da heurística é de
195pt, o que faria a seta apontar para outro aplicativo do Dock. Volta a aparecer sozinha
quando a permissão de Acessibilidade é concedida.

**Redimensionamento.** Cresce e encolhe **para cima**, com a borda inferior e a seta fixas.
Animado em ~0,22s com easing (`easeInEaseOut`): o frame da janela e o contorno da máscara
de cantos interpolam juntos. Ao abrir/fechar um grupo, uma foto do conteúdo anterior é
dissolvida por cima durante a mesma animação, para as linhas do accordion trocarem sem
salto. Respeita "Reduzir movimento". **Nunca tem ScrollView.**

## Privacidade

`sharingType = .none` incondicional em build de release: o painel é invisível para qualquer
captura de tela — janela isolada ou tela inteira, Meet, Teams, gravação, screenshot. Aplicado
pelo WindowServer, não por detecção de transmissão.

Em `#if DEBUG` a captura é liberada, para permitir verificação visual durante o
desenvolvimento. O binário de release é idêntico ao de proteção total.

### Validado empiricamente (protótipo, macOS 26.6.2 — descartado após validar)

Testado contra compartilhamento de tela real: a janela criada com `sharingType = .none`
**não aparece na transmissão**. Premissa confirmada.

**Restrição medida.** Em macOS 26, o setter de `sharingType` é **recusado** numa janela criada
como `.none`. Instrumentado em três pontos dentro do clique:

    toggle | antes=.none alvo=.readOnly apos-atribuicao=.none apos-reorder=.none

Atribuir `.readOnly` não surte efeito algum — a propriedade relê `.none` imediatamente após a
atribuição, antes de qualquer re-order. Não é atraso do WindowServer nem efeito de
`orderOut`/`orderFrontRegardless`: a mudança é simplesmente ignorada.

Reforçando a leitura: `NSWindowSharingType.readWrite` foi depreciado no macOS 15. A Apple trata
isso como propriedade de **criação** da janela, não como chave a ser girada depois.

Consequência de projeto: o app nunca alterna esse valor em runtime. `.none` é fixado na
construção da `NSPanel` e também aplicado à janela do balão de opções/aplicativos (`NSPopover`),
garantindo que tanto a lista de pastas quanto os atalhos de aplicativos vinculados fiquem invisíveis
a gravações e compartilhamentos de tela. A liberação para desenvolvimento visual é via flag de
ambiente `ENABLE_SCREEN_CAPTURE=1` sob `#if DEBUG`.

O ícone no Dock **permanece visível** em transmissões — é desenhado pelo processo Dock e
nenhuma API do app alcança isso. O que é sensível (nomes dos projetos e ferramentas) está protegido.

## Estrutura

Um nível só de hierarquia. O balão tem duas zonas, nesta ordem:

1. **Pastas avulsas** (topo)
2. **Grupos** (abaixo)

Arrastar reordena livremente *dentro* de cada zona, nunca entre elas.

### Grupos

Accordion **exclusivo**: abrir um grupo fecha os demais. É isso que garante o "sem scroll".

Cabeçalho do grupo:
- Nome à esquerda; duplo-clique edita inline
- Botão "abrir tudo" no canto direito: dispara cada pasta do grupo no seu app configurado
- Menu de contexto: *Renomear · Abrir tudo · Excluir grupo*

**"Abrir tudo" nunca empacota várias pastas numa única chamada ao sistema — uma por vez.**
Medido diretamente contra apps reais: dar duas pastas ao VS Code numa só chamada faz ele
tratar como pedido de *workspace multi-root* (os dois projetos caem juntos numa única
janela); o Android Studio, na mesma situação, ignora tudo além da primeira. O Xcode não se
importa, porque não tem esse conceito de mesclagem — mas empacotar quebrava os outros dois,
então a regra é uma pasta por chamada para todos. Entre duas aberturas seguidas do MESMO
app, há um intervalo mínimo de 0,9s (medido: menos que isso e o VS Code às vezes ainda trata
a segunda janela como reaproveitável, mesclando de novo); itens de apps diferentes saem em
sequência sem espera, já que a corrida só existe dentro do mesmo app.

Excluir um grupo **promove suas pastas a avulsas** — nada é destruído.
Grupos vazios são permitidos e normais (todo grupo nasce vazio).
O grupo aberto é persistido e sobrevive a reinício do Mac. **Ao reabrir o balão** (relançar
o app, ou clicar no ícone do Dock com o balão fechado) — nunca em cliques dentro de uma
sessão já aberta — o grupo que estava aberto pula para o topo da lista de grupos. Interagir
com o accordion enquanto o balão está visível não reordena nada; a reordenação acontece uma
vez, exatamente no instante da transição fechado→aberto.

### Orçamento de altura

Dois monitores 1920×1080 sem escala Retina (UI a 1:1). Descontando barra de menu, Dock e
margens: ~965pt úteis. Linha de pasta ~28pt, cabeçalho de grupo ~30pt.

Com accordion exclusivo, a altura máxima é *(todos os cabeçalhos) + (o maior grupo aberto)*.
15 grupos com um aberto de 6 pastas: ~618pt. Cabe sempre, por construção.

## Itens

Ícone da **abertura principal** à esquerda (`Opening.icon(for:)`) + nome da pasta + **até
duas** aberturas restantes como ícones à direita.

**Uma pasta tem várias formas de abrir** (Q33a). Cada abertura é um app e, opcionalmente, um
alvo específico dentro da pasta — o Xcode precisa do `.xcworkspace`/`.xcodeproj`, enquanto
Terminal e editores abrem a própria pasta. O alvo é **sempre escolhido à mão** (Q34b): sem
autodetecção.

**Abertura de Terminal aceita um comando** (opcional). Ao adicionar o Terminal como abertura,
um campo pede um comando de shell — o Terminal abre uma janela nova, entra na pasta e roda o
comando (ex.: `claude`). Em branco, só abre a pasta. Implementado via `do script` do
AppleScript, o que dispara a autorização "controlar o Terminal" na primeira vez — opt-in por
recurso, como a Acessibilidade. Pode haver mais de uma abertura de Terminal na mesma pasta
(uma sem comando, outra com `claude`, etc.), respeitando o teto de três.

- Clicar no **nome** abre com a **principal** (a primeira da lista); o ícone à esquerda a
  representa, então ela não se repete entre os ícones à direita
- Clicar num **ícone à direita** abre com aquela abertura
- Ícone sem rótulo, com **tooltip** no hover (app, e o arquivo quando há alvo)
- Máximo de três aberturas no total (Q35a): a principal à esquerda + até duas à direita
- Quando a principal é o **Finder**, o ícone é a pasta genérica do macOS
  (`NSWorkspace.icon(for: .folder)`), não o rosto do app Finder

**O nome da pasta nunca é truncado**: a largura do balão é **fixa**, calculada a partir da
linha mais larga possível — toda pasta (avulsa ou dentro de qualquer grupo, aberto ou não),
todo cabeçalho de grupo, incluindo os ícones de abertura — medida com o layout real das
linhas. Fixa de propósito: abrir ou fechar o accordion nunca muda a largura. Único teto é a
largura útil da tela.

Path que não resolve fica **esmaecido e não clicável** (volta sozinho quando o volume
reconecta).

Menu de contexto do item: *Configurar aberturas… · Remover do grupo · Remover*

As ações de abrir saíram do menu de contexto — são os ícones da linha, definidos por projeto.

## Adicionar e mover

Toda pasta **nasce avulsa**:
1. `NSOpenPanel` com `canChooseDirectories = true`, `canChooseFiles = false`
2. Dropdown de app: Finder + apps já usados no DockFolders ordenados por frequência + "Outro…"

> LaunchServices sugere praticamente só o Finder para diretórios — editores não se registram
> como handlers de pasta. Por isso o dropdown é alimentado por histórico de uso local.

Pasta vai para um grupo **por drag**:
- Soltar sobre o cabeçalho fechado insere no grupo
- Pairar ~0,7s sobre o cabeçalho expande (spring-loading), para escolher a posição exata

Sai do grupo arrastando para fora **ou** por *Remover do grupo* no menu de contexto.

## Rodapé

- `+` à esquerda, abre menu: *Adicionar pasta… / Criar grupo…*
- Engrenagem à direita: *Iniciar no login · Ativar posicionamento preciso · Sobre · Sair*
- Aviso de posicionamento aproximado, quando aplicável (dispensável)

Estado vazio: "Nenhuma pasta adicionada" centralizado + botão `Adicionar pasta`.

## Dados

`~/Library/Application Support/DockFolders/folders.json`

Paths em texto puro. Contém: pastas avulsas ordenadas, grupos ordenados com suas pastas,
a lista de aberturas de cada pasta, `openGroupID`, histórico de uso de apps.

O formato antigo de abridor único (`"opener"`) é migrado na leitura para a lista
(`"openers"`), sem perda de configuração.

## Escopo fechado

Apenas **pastas**. Não arquivos, não apps, não URLs. O valor é "abrir projeto no editor";
generalizar coloca o app contra Alfred/Raycast.

## Riscos aceitos

| Decisão | Consequência |
|---|---|
| Path puro em JSON | Renomear ou mover uma pasta quebra o item |
| Esmaecido sem distinguir a causa | Desconectar o SSD externo `/Volumes/Projetos` acinzenta a lista inteira sem explicar por quê; o conserto é editar o JSON |
| Só o clique no Dock | Sem rota alternativa se a árvore AX quebrar num update do macOS e a heurística errar |
| Seta sempre visível | Denuncia todo desalinhamento do modo heurístico |
| Sem escape hatch de captura | Impossível printar ou gravar o balão no app instalado |
| Toda pasta nasce avulsa | Popular um grupo é sempre dois passos; o drag vira infraestrutura crítica |
| Avulsas fixas no topo | Impossível pôr um grupo acima de uma pasta solta |

Nenhuma é bloqueante; todas são reversíveis.

## Ordem de construção

1. ✅ **Protótipo de validação de `sharingType = .none`** — premissa confirmada contra
   compartilhamento real de tela (harness descartado depois de validar; achados registrados
   acima, em "Privacidade").
2. ✅ **Posicionamento** (AX + fallback heurístico) — validado com um harness de medição
   (idem, descartado depois); módulo em `DockFolders/Sources/DockTileLocator.swift`.
3. ✅ **Modelo de dados e persistência** — `Sources/Store.swift`, com 17 asserções em
   `Tests/main.swift` cobrindo as regras estruturais.
4. ✅ **Lista, grupos, accordion** — `Sources/BalloonPanel.swift`, `BalloonContent.swift`,
   `Rows.swift`.
5. ✅ **Adicionar / drag / menus de contexto** — inclui spring-loading e renomear inline.
6. ✅ **Rodapé, login item, estado vazio, ícone** — ícone gerado a partir do ícone de pasta
   do próprio sistema (`Resources/AppIcon.icns`).

## Como construir

    ./DockFolders/build.sh            # release: sharingType = .none
    DEBUG=1 ./DockFolders/build.sh    # debug: captura liberada para verificação visual

Testes do modelo:

    swiftc -O DockFolders/Sources/Store.swift DockFolders/Tests/main.swift -o /tmp/t && /tmp/t
