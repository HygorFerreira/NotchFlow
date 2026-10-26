# Atualizações dentro do aplicativo

O NotchFlow usa Sparkle 2.10.1 apenas na distribuição direta. O framework baixa um ZIP, verifica sua assinatura, instala o aplicativo e pode reiniciá-lo. O catálogo e as notas de versão também são assinados. A verificação ocorre a cada seis horas; o padrão é baixar em segundo plano e instalar ao encerrar. O menu e Ajustes → Sobre permitem verificar manualmente e configurar as opções automáticas.

O DMG serve para a primeira instalação. Quem está em uma versão anterior à 1.2.0 precisa instalar a versão com Sparkle uma vez. Tarefas e histórico ficam no diretório de dados existente. O app deve estar em Aplicativos, fora do volume somente leitura do DMG.

## Chave das atualizações

A chave Ed25519 é independente da assinatura paga da Apple. A chave pública está em `SUPublicEDKey` no Info.plist. A chave privada é guardada no Chaves, no serviço `https://sparkle-project.org`, conta `NotchFlow`. Não coloque a chave privada no código, no aplicativo, em uma release ou em logs. Preserve um backup seguro dessa chave: ela autentica as próximas atualizações dos apps já instalados.

Após resolver as dependências, as ferramentas oficiais ficam em `build/SourcePackages/artifacts/sparkle/Sparkle/bin/`. Se usar outro diretório de pacotes, ajuste `NOTCHFLOW_PACKAGES_DIR` ou `NOTCHFLOW_SPARKLE_BIN`.

Para consultar a chave pública existente:

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account NotchFlow -p
```

Para exportar uma cópia privada para um local seguro, execute você mesmo a ferramenta `generate_keys --account NotchFlow -x /local/seguro/chave`. O arquivo exportado é secreto. Uma nova chave aleatória não substitui a antiga nos apps já distribuídos.

## Preparar uma versão

1. Aumente `MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` nos targets do projeto. O Sparkle compara o número de build: ele precisa crescer em cada atualização.
2. Escreva `releases/<versão>.md` e atualize o changelog.
3. Execute as suítes relevantes e compile Debug, Release universal e NotchFlowAppStore.
4. Gere o instalador e o pacote de atualização:

```bash
bash scripts/create-dmg.sh
```

O script compila Apple Silicon e Intel, assina os componentes do Sparkle, gera o DMG, prepara um ZIP e usa `generate_appcast` para assinar o catálogo. A chave escolhida precisa corresponder ao Info.plist. A etapa falha se os arquivos de uma versão já estiverem preparados, evitando substituição acidental. Para repetir uma preparação ainda não publicada, remova ou mova conscientemente a pasta de saída correspondente antes de gerar novamente.

Sem `NOTCHFLOW_SIGN_IDENTITY`, o app usa assinatura ad-hoc e os entitlements `NotchFlow-Local.entitlements`, necessários para carregar o framework sem um Team ID. O macOS pode exigir autorização na primeira instalação. Esse pacote não é notarizado. Com Developer ID e perfil de notarização configurados, o mesmo script usa os entitlements de distribuição e notariza o aplicativo e o DMG.

Saídas:

- `build/NotchFlow-<versão>.dmg`: primeira instalação.
- `build/updates/v<versão>/NotchFlow-<versão>.zip`: atualização dentro do app.
- `build/updates/v<versão>/appcast.xml`: catálogo assinado com URL e assinatura do ZIP.
- `build/updates/v<versão>/SHA256SUMS`: checksums do ZIP e catálogo.

## Publicar

Faça commit e envie o código validado antes da publicação. Não reutilize uma tag ou número de build já distribuído. Crie uma release estável com tag numérica, incluindo ZIP e catálogo no mesmo envio. Por exemplo, para 1.2.0:

```bash
gh release create v1.2.0 \
  --repo HygorFerreira/NotchFlow \
  --target COMMIT_VALIDADO \
  --title 'NotchFlow 1.2.0' \
  --notes-file releases/1.2.0.md \
  --latest \
  build/NotchFlow-1.2.0.dmg \
  build/updates/v1.2.0/NotchFlow-1.2.0.zip \
  build/updates/v1.2.0/appcast.xml \
  build/updates/v1.2.0/SHA256SUMS
```

O endereço fixo `https://github.com/HygorFerreira/NotchFlow/releases/latest/download/appcast.xml` passa a apontar para o catálogo dessa release. O ZIP usa a URL da tag específica. Não edite o XML após assiná-lo: a assinatura deixaria de ser válida. Pré-releases e drafts não substituem a release estável nesse endereço.

Cada nova release deve conter seu catálogo assinado e um número de build maior. Um commit sozinho não publica atualização. A assinatura Ed25519 é verificada antes da extração; uma alteração no catálogo ou ZIP invalida o pacote.

## Validação

`bash scripts/test-updates.sh` verifica configuração de confiança, estado da interface, preferências, falhas, tentativas repetidas e isolamento do App Store. `scripts/validate-appcast.py` confere versão, build, sistema mínimo, tamanho, URL e presença da assinatura do pacote; `sign_update --verify` confere a assinatura criptográfica. `bash scripts/test-update-archive.sh App.app appcast.xml update.zip` valida as assinaturas com a chave pública embutida e confirma a rejeição de um ZIP e um catálogo alterados. Esse teste também é executado na preparação das atualizações.

A homologação completa exige duas versões reais, instaladas em uma pasta gravável: verificar, baixar, encerrar/instalar, reiniciar e conferir tarefas e foco. Faça também um teste com arquivo adulterado, que deve ser recusado. Não altere builds já distribuídos para simular outra versão.

O esquema **NotchFlowAppStore** usa outro Info.plist, entitlements próprios e nenhum produto Sparkle. Atualizações desse pacote continuam sob responsabilidade da loja.
