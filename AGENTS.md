# Diretrizes para o Agente (DockFolders)

## Regra Obrigatória de Execução

- **Sempre ao final de cada alteração**:
  1. Compile o app:
     ```bash
     DEBUG=1 ./DockFolders/build.sh
     ```
  2. Encerre qualquer instância anterior em execução e abra a nova versão:
     ```bash
     killall DockFolders 2>/dev/null || true; sleep 0.5; open DockFolders/dist/DockFolders.app
     ```
  3. Valide se o processo está em execução via `pgrep -fl DockFolders`.

## Testes Automatizados

- Sempre que alterar o modelo de dados ou regras de negócio em `Store.swift`, execute os testes unitários:
  ```bash
  swiftc -O DockFolders/Sources/Store.swift DockFolders/Tests/main.swift -o /tmp/dockfolders_tests && /tmp/dockfolders_tests
  ```
