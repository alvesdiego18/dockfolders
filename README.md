# DockFolders

Um ícone no Dock do Mac que abre um balão com atalhos para pastas de projeto. Cada
pasta pode ser aberta com até três aplicativos diferentes — a pasta em si, um
`.xcworkspace` no Xcode, o Terminal, o VS Code — com um clique.

## Funcionalidades

- **Ícone fixo no Dock.** Clicar abre um balão ancorado ao ícone; clicar de novo, ou
  apertar ESC, ou clicar fora, fecha.
- **Duas zonas.** Pastas soltas no topo, grupos de projeto abaixo. Um grupo pode
  reunir várias pastas do mesmo projeto (por exemplo, `App iOS`, `App Android` e o
  backend de um mesmo produto).
- **Accordion exclusivo.** Abrir um grupo fecha os demais — é o que garante que o
  balão nunca precise de barra de rolagem, não importa quantos grupos existam.
- **Até três formas de abrir cada pasta.** A principal abre ao clicar no nome; as
  demais aparecem como ícones à direita. Cada uma pode apontar para a pasta inteira
  ou para um arquivo específico dentro dela (o Xcode, por exemplo, precisa do
  `.xcworkspace`, não da pasta).
- **Atalho de Terminal.** Um botão dedicado adiciona o Terminal como abertura sem
  precisar navegar até `/Applications`.
- **Arrastar para organizar.** Pastas soltas viram parte de um grupo por drag &
  drop; pairar sobre um grupo fechado o expande sozinho (spring-loading, como no
  Finder).
- **Grupo mais usado sobe.** Ao reabrir o balão (não durante o uso — só na
  transição de fechado para aberto), o grupo que ficou aberto da última vez pula
  para o topo da lista.
- **Invisível em compartilhamento de tela.** O balão nunca aparece numa
  transmissão do Meet, do Teams ou numa gravação de tela — nem sequer no ícone do
  Dock, que continua visível, mas some tudo que está dentro do balão.

## Requisitos

- macOS 13 ou mais recente (testado em macOS 26)
- Xcode ou as Command Line Tools da Apple instaladas (para o `swiftc`)

## Instalação

### A partir de um `.dmg` já pronto

Se alguém te passou um `DockFolders-<versão>.dmg`, veja o `Leia-me.txt` dentro
dele — ele explica como liberar o app no Gatekeeper na primeira abertura (o app
não tem assinatura de uma conta de desenvolvedor Apple, então o macOS avisa antes
de abrir; isso é esperado, não um app corrompido).

### A partir do código-fonte

```
./DockFolders/build.sh
```

Gera `DockFolders/dist/DockFolders.app` (build de release, protegido contra
captura de tela) e `DockFolders/dist/DockFolders-<versão>.dmg` (pronto para
instalar em outro Mac). Para testar localmente sem gerar o `.dmg`:

```
DEBUG=1 ./DockFolders/build.sh
open DockFolders/dist/DockFolders.app
```

`DEBUG=1` também libera a captura de tela do balão — necessário para conferir a
interface por screenshot durante o desenvolvimento; o build sem essa flag é o
que efetivamente protege sua tela.

Depois de instalar, clique com o botão direito no ícone do Dock → **Opções →
Manter no Dock**, senão ele some quando o app for encerrado.

## Uso

- **Adicionar uma pasta:** botão `+` no rodapé → *Adicionar pasta…* → escolha a
  pasta → configure com quais apps ela abre.
- **Configurar aberturas:** clique com o botão direito numa pasta →
  *Configurar aberturas…*. A primeira da lista é a principal (a que o clique no
  nome dispara); as outras aparecem como ícones à direita, com tooltip ao passar
  o mouse.
- **Criar um grupo:** `+` → *Criar grupo…*. Ele nasce vazio — arraste pastas para
  dentro dele.
- **Abrir tudo de um grupo:** botão no canto direito do cabeçalho do grupo, abre
  cada pasta com sua abertura principal de uma vez.
- **Manter o balão aberto:** segure ⌘ ao clicar numa pasta.
- **Renomear um grupo:** duplo-clique no nome, ou pelo menu de contexto do
  cabeçalho.
- **Posicionamento preciso da seta:** conceda Acessibilidade ao DockFolders em
  Ajustes do Sistema → Privacidade e Segurança → Acessibilidade (o app pede isso
  sozinho ao clicar no aviso "posicionamento aproximado", quando aparece). Sem
  essa permissão o app funciona normalmente, só sem a seta apontando para o
  ícone.

## Onde ficam os dados

```
~/Library/Application Support/DockFolders/folders.json
```

Texto simples, editável à mão se precisar. Se o arquivo estiver corrompido, o
app preserva o original como `folders.json.corrupt-<timestamp>` em vez de
sobrescrever, e recomeça vazio.

## Arquitetura

| Arquivo | Responsabilidade |
|---|---|
| `Sources/main.swift` | Ciclo de vida do app, ações de menu, login item |
| `Sources/Store.swift` | Modelo de dados e persistência em JSON |
| `Sources/BalloonPanel.swift` | A janela do balão: forma, seta, `sharingType`, ancoragem |
| `Sources/BalloonContent.swift` | Layout do conteúdo, drag & drop, menus de contexto |
| `Sources/Rows.swift` | As linhas de pasta e de cabeçalho de grupo |
| `Sources/Opening.swift` | Abrir uma pasta com um app; resolução de ícones |
| `Sources/OpenerConfig.swift` | Janela de configuração das aberturas de uma pasta |
| `Sources/DockTileLocator.swift` | Localiza o ícone do app no Dock via Accessibility API |
| `Tests/main.swift` | Testes do `Store` (regras estruturais, persistência, migração) |

Rodar os testes do modelo:

```
swiftc -O DockFolders/Sources/Store.swift DockFolders/Tests/main.swift -o /tmp/dockfolders-tests
/tmp/dockfolders-tests
```

## Limitações conhecidas

| Situação | Comportamento |
|---|---|
| Pasta renomeada ou movida | O item para de resolver; fica esmaecido e não clicável |
| Volume externo desconectado | Toda pasta nele fica esmaecida, sem indicar a causa |
| Árvore de Acessibilidade do Dock muda num update do macOS | O app cai no modo de posicionamento aproximado, sem seta |
| App configurado como abertura foi desinstalado | A abertura cai para o Finder na hora de abrir |
| Build de release | Sem assinatura de Developer ID nem notarização — Gatekeeper avisa na primeira abertura em outro Mac |

## Design e decisões

O histórico completo de decisões de produto — o porquê de cada escolha, o que foi
medido empiricamente (posicionamento do Dock, comportamento do `sharingType`) e os
riscos aceitos conscientemente — está em [`CONTEXT.md`](CONTEXT.md).
