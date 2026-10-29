# Desenvolvimento do NotchFlow

## Ambiente

- macOS 14 ou superior para executar o aplicativo.
- Xcode 16.3 ou superior, com SDK de macOS e ferramentas de linha de comando.
- SwiftUI e AppKit; sem gerenciador externo de dependências para o app.
- Projeto e esquema: `NotchFlow`. Bundle ID atual: `dev.oprimo.NotchFlow`.

Execute os comandos abaixo na raiz do projeto. Confira a instalação ativa do Xcode com `xcode-select -p`; se necessário, selecione o Xcode completo nas configurações das ferramentas de linha de comando.

## Compilar e executar

```bash
open NotchFlow.xcodeproj
```

No Xcode, selecione NotchFlow, My Mac e sua equipe de assinatura quando necessário. Execute com `⌘R`.

Para compilar sem iniciar o app:

```bash
xcodebuild -project NotchFlow.xcodeproj -scheme NotchFlow   -configuration Debug -destination 'platform=macOS'   -derivedDataPath /tmp/notchflow-build CODE_SIGNING_ALLOWED=NO build
```

O produto fica em `/tmp/notchflow-build/Build/Products/Debug/NotchFlow.app`. Desativar assinatura serve para validação local; a distribuição exige assinatura apropriada.

Para compilar e abrir usando as configurações do projeto:

```bash
bash scripts/run.sh
bash scripts/run.sh release
```

O script encerra uma instância em execução antes de abrir o produto compilado.

## Estrutura

| Diretório | Responsabilidade |
| --- | --- |
| `NotchFlow/App/` | Inicialização, menu, janelas do notch, estado do painel, atualizações e snapshots. |
| `NotchFlow/Models/` | Modelos de rotina, métricas, resumo e Store com persistência JSON. |
| `NotchFlow/AI/` | Conexões de consumo do Codex/Claude, leitura autorizada de credenciais e painéis de limites da assinatura. |
| `NotchFlow/Focus/` | Timer, atalhos globais e notificações locais. |
| `NotchFlow/Music/` | Automação dos players, letras opcionais via LRCLIB e interfaces. |
| `NotchFlow/Tools/` | Paleta, clipboard em memória, importação de arquivos e interfaces de notas/ferramentas. |
| `NotchFlow/Notch/` | Painéis de atividade, saúde, máquina e apresentação do timer. |
| `NotchFlow/Tasks/` | Calendário, tarefas, captura rápida, formulários e resumo semanal. |
| `NotchFlow/Water/` | Painel e janela de hidratação. |
| `NotchFlow/Medications/` | Cadastro e acompanhamento de medicamentos. |
| `NotchFlow/Settings/` | Navegação, páginas e integração de abertura ao iniciar sessão. |
| `NotchFlow/Sync/` | Consulta e autorização do calendário com EventKit. |
| `NotchFlow/Design/` | Tema, componentes compartilhados e avisos de persistência. |
| `Tests/` | Verificações independentes dos modelos e persistência. |
| `scripts/` | Execução, testes, ícone, limpeza e distribuição. |
| `appstore/` | Exportação e materiais de apresentação para a loja. |

A pasta `NotchFlow/` usa `PBXFileSystemSynchronizedRootGroup`. Arquivos novos normalmente são detectados pelo Xcode sem alteração manual do projeto. Textos localizados ficam em `NotchFlow/Localizable.xcstrings`.

## Estado e persistência

`Store` é a fonte de dados da aplicação e opera no ator principal. O caminho padrão usa a pasta Application Support retornada pelo macOS, acrescida de `NotchFlow/data.json`; o sandbox pode redirecionar essa localização para o contêiner.

O Store mantém backup anterior e preserva arquivos danificados durante a recuperação. Mudanças nos modelos devem manter compatibilidade com arquivos que ainda não contenham campos novos. Testes e snapshots usam arquivos temporários próprios.

O timer calcula o restante com base no horário de término. Atalhos globais usam Carbon; calendários usam EventKit e notificações usam UserNotifications.

## Testes

`bash scripts/test-ai-usage.sh` valida leitura de limites, respostas parciais, datas, migração entre formatos do Claude, persistência sem tokens e estados de autenticação/restrição de requisições com rede simulada.

```bash
bash scripts/test-store.sh
bash scripts/test-productivity.sh
bash scripts/test-ai-usage.sh
bash scripts/test-focus.sh
bash scripts/test-music.sh
bash scripts/test-tools.sh
```

Esses scripts compilam executáveis Swift independentes; não dependem de um target de testes do Xcode. Cubra regras de negócio, migração, persistência e recuperação conforme a área alterada. Para mudanças visuais, faça a compilação e confira os fluxos reais e as prévias.

O teste do timer usa relógio controlado para conferir pausas, conclusão, edição de tarefas e limites de duração. O CI compila Debug, Release e a variante `APPSTORE`, além de executar as quatro suítes. Se `xcode-select` apontar para CommandLineTools, use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` antes do comando para selecionar o Xcode apenas naquela execução.

O teste de ferramentas usa um pasteboard privado (`NSPasteboard.withUniqueName`) e diretórios temporários. Precisa de acesso ao serviço de pasteboard do macOS; não lê nem substitui o clipboard geral. O CI deve rodar em uma sessão gráfica do macOS.

## Gerar imagens

Use `-snapshot 1 -snapshotToolsOnly 1` para gerar notas, clipboard e arquivos fictícios, paleta e compromisso compacto. O modo não monitora o clipboard geral. Para uma janela interativa isolada, use `-preview 1 -previewTools 1`.


Para revisar música, use `-snapshot 1 -snapshotMusicOnly 1`. Esse modo usa uma faixa fictícia, sem consultar os players nem persistir preferências de música, e gera player completo, compacto, prévia, foco simultâneo, lembrete e estado vazio. Execute com `-AppleLanguages '(pt-BR)'` e `'(en)'` para revisar os dois idiomas.

A integração de música usa `NSAppleEventDescriptor` em uma fila serial, com timeout de um segundo por evento. Os entitlements de todos os canais incluem os grupos de scripting de reprodução e leitura dos players, além de `NSAppleEventsUsageDescription`. Testes unitários simulam respostas; valide a autorização e os comandos com aplicativos reais em um build assinado antes de distribuir. A revisão da App Store continua dependendo da Apple.

Uma compilação Debug oferece o modo de snapshots, com dados de demonstração isolados:

```bash
/tmp/notchflow-build/Build/Products/Debug/NotchFlow.app/Contents/MacOS/NotchFlow   -snapshot 1 -AppleLanguages '(pt-BR)'
```

Para revisar apenas o guia de primeiros passos nas duas aparências, acrescente `-snapshotWelcomeOnly 1` ao comando de snapshots. Esse modo não altera a preferência de exibição do guia.

Para inglês, use `'(en)'`. O programa imprime o diretório de saída e encerra após renderizar. Copie as imagens antes da próxima execução, pois a pasta temporária de snapshots é recriada.

Para revisar o sistema visual completo com dados fictícios, acrescente `-snapshotVisualReview 1` ao comando. Esse modo gera as telas principais, todas as páginas de ajustes, detalhe de tarefa e captura rápida nas aparências clara e escura, além das cinco abas do notch e do timer compacto. As imagens são prévias reais de SwiftUI; confira também foco de teclado, popovers e redimensionamento no app.

Para conferir apenas as cinco abas do notch e o timer compacto, use `-snapshotNotchOnly 1` junto de `-snapshot 1`. Essas capturas incluem um fundo azul para distinguir a área da câmera dos cantos transparentes do painel.

Para compor imagens de apresentação, coloque as capturas em `appstore/screenshots/raw/pt-BR/` e `appstore/screenshots/raw/en/`, respectivamente, e execute:

```bash
swift appstore/screenshots/compose.swift
swift appstore/screenshots/compose.swift --readme
```

O primeiro comando gera as composições da loja; o segundo gera as imagens do README em `docs/images/` a partir das capturas em português. Para atualizar o ícone, altere e execute `scripts/generate-icon.swift`, em vez de editar cada PNG manualmente.

## Distribuição direta

O script de DMG depende da ferramenta `create-dmg`. Configure um certificado Developer ID e um perfil do `notarytool` para uma distribuição assinada e notarizada. As variáveis podem ser exportadas no terminal ou definidas em `.env.local`:

```bash
export NOTCHFLOW_SIGN_IDENTITY='Developer ID Application: Seu Nome (TEAMID)'
export NOTCHFLOW_NOTARY_PROFILE='nome-do-perfil'
bash scripts/create-dmg.sh
```

A saída inclui `build/NotchFlow-<versão>.dmg` e `build/updates/v<versão>/`, com ZIP, catálogo assinado e checksums. A geração do catálogo requer a chave do NotchFlow no Chaves; veja [ATUALIZACOES.md](ATUALIZACOES.md). Sem essas variáveis, o script pode gerar um pacote sem assinatura de distribuição ou sem notarização; gerar o arquivo não comprova que ele esteja pronto para distribuição.

## App Store

Antes de exportar, configure a equipe de assinatura no projeto e o `teamID` em `appstore/ExportOptions.plist` com sua conta. Cadastre o aplicativo no App Store Connect e revise identidade, permissões, URLs e materiais de loja.

```bash
bash scripts/appstore.sh
```

Esse comando recria `build/appstore/`, arquiva com a condição `APPSTORE` e exporta o pacote localmente. Para enviar uma versão preparada:

```bash
bash scripts/appstore.sh --upload
```

A opção `--upload` envia o build ao App Store Connect. As credenciais e os certificados são administrados pelo Xcode e não devem ser versionados. O esquema **NotchFlowAppStore** define `APPSTORE`, usa Info.plist e entitlements próprios e não liga nem incorpora o Sparkle. Não distribua um build do esquema NotchFlow com apenas a condição APPSTORE: use o target da loja para excluir o framework do pacote.

## Preparar uma versão

1. Atualize `MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` no projeto.
2. Execute a compilação, os testes e a revisão dos fluxos afetados.
3. Atualize o changelog, a política de privacidade quando aplicável e as imagens.
4. Configure as URLs de suporte e privacidade e revise [LISTING.md](../appstore/LISTING.md).
5. Valide assinatura, exportação e notarização conforme o canal escolhido.

O atualizador em `UpdateChecker.swift` usa o driver `SparkleUpdateDriver.swift` na distribuição direta. O Sparkle é fixado em 2.10.1 via Swift Package Manager e o lockfile é versionado. Catálogo e ZIP são assinados com Ed25519; as verificações automáticas ocorrem a cada seis horas e, por padrão, o app instala ao encerrar. Veja [ATUALIZACOES.md](ATUALIZACOES.md) para as chaves, validação e publicação das releases. O esquema **NotchFlowAppStore** não incorpora esse framework.
