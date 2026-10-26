# Revisão de estabilidade — 10/10/2026

Foram revisados os modelos, persistência, timer, agendamento de lembretes, calendário, conexões de IA, inicialização, textos localizados e configuração de distribuição. As alterações que já estavam no diretório foram preservadas. Esta revisão não substitui a homologação do pacote assinado em outra máquina.

## Correções desta revisão

- O editor de tarefas preserva tempo de foco, ordenação e metadados internos atualizados desde que o formulário foi aberto; normaliza título, notas e duração antes de salvar.
- Durações carregadas e iniciadas ficam entre 1 e 180 minutos, evitando overflow com valores extremos.
- Pausar e retomar mantém precisão de frações de segundo. Pausar depois do prazo conclui a sessão uma única vez.
- Encerrar normalmente o app registra o foco em andamento, respeitando o mínimo de um minuto. Isso não cobre encerramento forçado ou queda de energia.
- Arrastes com índices inválidos após mudanças na lista são ignorados.
- O cache de credenciais Claude considera a data de modificação do item no Chaves, pois a referência persistente pode continuar igual após a renovação.
- Respostas de IA com duração numérica extrema não causam conversão inválida para inteiro.
- Permissão de escrita no calendário não é interpretada como permissão para ler eventos.
- Textos de medicamentos em português foram completados. Snapshots não agendam notificações reais de demonstração.
- O CI agora inclui Debug, Release e APPSTORE, testes do timer e logs de build em caso de falha.

## Validação executada

| Verificação | Resultado |
| --- | --- |
| Persistência: backup, recuperação, proteção de leitura e nova tentativa de gravação | Passou |
| Produtividade: migração, recorrência, hidratação, lembretes, resumo e edição de rascunho | Passou |
| IA: parser, armazenamento sem tokens, autenticação e respostas HTTP simuladas | Passou |
| Timer: limites, pausas, conclusão, edição, desativação de tarefa e sessões curtas | Passou |
| Build Debug | Passou |
| Build Release universal — arm64 e x86_64 | Passou |
| Build APPSTORE universal — arm64 e x86_64 | Passou |
| Sintaxe dos scripts shell, arquivos plist e `git diff --check` | Passou |
| Execução do modo de snapshots em português | Concluiu sem falha |
| Inspeção visual das prévias de tarefas, edição, medicamentos e IA | Sem corte impeditivo nos layouts inspecionados |

Os builds foram feitos com `CODE_SIGNING_ALLOWED=NO`. O Xcode completo foi selecionado por `DEVELOPER_DIR`, sem mudar a configuração global da máquina. O aviso de extração de metadados AppIntents indica que o projeto não depende desse framework; não impediu os builds.

As conexões de IA foram testadas com credenciais fictícias e rede simulada. Renovação real no Chaves, concessão de acesso a pastas, notificações do sistema, abertura ao iniciar sessão e mudanças de tela/suspensão precisam de homologação interativa no app assinado. As prévias verificam apresentação, não todos os cliques e permissões.

## Pendências para publicação

1. Validar assinatura, entitlements, instalação e execução do pacote no canal escolhido; notarizar a distribuição direta ou exportar para a App Store.
2. Configurar URLs públicas de suporte e privacidade nos materiais da loja.
3. Publicar uma release estável para a distribuição direta, com tag numérica e DMG validado. Atualização em 26/10/2026: `HygorFerreira/NotchFlow` já é público, mas a lista pública de releases está vazia e `/releases/latest` retorna 404. O verificador já aponta para esse endereço e funciona sem autenticação quando houver uma release estável.
4. Conferir os fluxos de permissões e as conexões opcionais de IA com contas reais no pacote assinado, incluindo renovação de sessão.
5. Revisar capturas finais, número de build e dados no App Store Connect antes do envio.

Nenhum pacote foi publicado ou enviado à loja nesta revisão.
