# Histórico de alterações do NotchFlow

Este arquivo registra os principais marcos do projeto. A versão atual é **1.3.0**, build **4**.

## 1.3.0 — 2026-10-29

- Mixer de áudio com volume e silenciamento por processo usando APIs públicas de áudio do macOS 14.2 ou superior, processamento local sem gravação, validação da saída e restauração do áudio ao desativar.

- Renovação visual das novas funções: navegação do notch com ícones e aba ativa, player com reprodução destacada e letras, ferramentas com editor de notas e estados vazios, área de arquivos demarcada, mixer e paleta de comandos com hierarquia consistente. Prévias em `output/refresh-review/`.

- Paleta de comandos global `⌃⌥K`, com busca em português/inglês, navegação por teclado, ações do aplicativo e início de foco por tarefa. Atalho configurável e indicação de conflito.
- Ferramentas no notch e em janela própria: notas com salvamento e backup no Store, criação de tarefas preservando o texto original, clipboard opcional em memória e arquivo de cópias para arrastar entre apps.
- Importação de arquivos em fila e por área temporária, sem modificar os originais, com limites de tamanho/quantidade e remoção para a Lixeira.
- Próximo compromisso no compacto com antecedência configurável e acesso a links de reunião, convivendo com timer, música e lembretes de rotina.
- Letras sincronizadas opcionais via LRCLIB, com tratamento de indisponibilidade, faixas instrumentais e letras sem marcações. Consultas usam sessão de rede efêmera.
- Testes de notas/persistência, clipboard privado, fila de arquivos, calendário, paleta, letras; prévias isoladas em `-snapshotToolsOnly 1`.

- Música no notch com seleção entre Spotify e Apple Music, ativação opcional e autorização de Automação do macOS. Usa Apple Events públicos e permissões de scripting específicas dos dois players.
- Aba Música com capa, faixa, artista, controles anterior/reproduzir/pausar/próxima e busca pela posição da faixa. Exibe estados de player fechado, sem faixa, acesso pendente e falha de leitura.
- Notch compacto com capa e indicador de reprodução; hover abre uma prévia com controles e acesso ao painel. Timer e tarefa continuam visíveis no modo padrão durante a música; lembretes permanecem em sua pílula separada.
- Testes de duração por player, progresso, pausa, dados inválidos e falhas de permissão; prévias isoladas de música, foco e lembretes em `-snapshotMusicOnly 1`.

## 1.2.0 — 2026-10-26

- Atualizador Sparkle 2.10.1 integrado: busca, download, validação Ed25519 e instalação pelo próprio app, com verificações a cada seis horas e instalação automática ao encerrar.
- Pacotes ZIP e catálogos assinados gerados junto do DMG; chave privada armazenada no Chaves, fora do repositório e do aplicativo.
- Opções de atualização nos Ajustes → Sobre e verificação manual no menu, sem abrir o navegador.
- Distribuição ad-hoc para amigos sem Developer ID, com os componentes do Sparkle assinados e permissão de biblioteca apenas nessa variante e em Debug.
- Target separado NotchFlowAppStore mantém o pacote da loja sem Sparkle ou permissões de instalação externa.
- Versão anterior à 1.2.0 exige uma instalação manual inicial para receber o atualizador.

- Guia opcional de primeiros passos exibido uma vez, com orientações sobre o notch, criação da primeira tarefa e atalhos; pode ser reaberto pelo menu ou em Ajustes → Geral. Disponível em português e inglês.
- Documentação de distribuição atualizada para o repositório público; consulta anônima confirmou a ausência de releases publicadas em 26/10/2026.

- Identificação atualizada de 1.0.0 (1) para 1.1.0 (2) para distinguir o pacote de teste com os novos recursos e visual. O empacotamento força as arquiteturas Apple Silicon e Intel.
- Notch recomposto a partir da referência minimalista: painel grafite abaixo da câmera, abas centralizadas com seleção clara, tarefas sem notas e controles extras visíveis apenas ao passar o mouse, ações em cartões e grade dos últimos sete dias com intervalos reais de foco. Timer compacto com progresso abaixo do título; filtros continuam disponíveis em um popover.
- Visual minimalista aplicado ao workspace, ajustes, tarefas, calendário, água, medicamentos, IA e resumo semanal: superfícies grafite e cinza adaptadas aos temas claro e escuro, seleções neutras, botões foscos e azul pontual para ações e progresso. Liquid Glass passa a ser desativado por padrão para preferências ainda não configuradas.
- Modo de revisão visual com dados fictícios (`-snapshot 1 -snapshotVisualReview 1`) para conferir as principais telas, formulários e abas do notch nas duas aparências.
- Notch com contorno neutro discreto, abas compactas e cartões de tarefas mais leves; a linha colorida aparece durante o foco quando a timeline está ativada. Mais espaço entre navegação e conteúdo, com animações da timeline respeitando Reduzir Movimento.

- Revisão de estabilidade: edição de tarefas preserva foco já registrado e ordenação; títulos, notas e durações são validados no Store.
- Timer preserva frações de segundo nas pausas, conclui ao pausar após o prazo e limita durações extremas sem overflow.
- Conexão Claude invalida o cache quando a credencial é atualizada no Chaves; leitura de limites de IA tolera durações numéricas extremas.
- Calendário exige acesso de leitura, sem tratar permissão de escrita como autorização para consultar eventos.
- Testes de regressão do timer e CI para Debug, Release e App Store.
- Sessões em andamento são registradas ao encerrar normalmente o app; arrastes com índices desatualizados são ignorados com segurança.
- Traduções em português dos lembretes e ações de medicamentos completadas; snapshots não agendam notificações de demonstração.

- Conexão de IA por interruptores, com aproveitamento do login existente, ações de entrar/trocar conta na ferramenta de origem e seleção de pastas apenas nas opções avançadas ou quando exigida pelo sandbox (2026-10-10).

- Aba IA e janela de consumo com conexão às sessões do Codex e Claude Code, indicadores dos limites da assinatura, renovação e atualização automática a cada dois minutos; leitura antiga e falhas identificadas, sem guardar tokens.

- Busca de atualizações restaurada pelas releases de `HygorFerreira/NotchFlow`, com verificação manual nos ajustes e aviso quando a consulta falha.
- Pílula de lembretes abaixo do notch para medicamentos e água, com registro rápido e intervalo de hidratação configurável.

### Identidade

- Nome do aplicativo, projeto Xcode, esquema, recursos e scripts padronizados como NotchFlow.
- Autoria e copyright identificados como Hygor Ferreira.
- Referências externas de distribuição removidas até a configuração dos canais do NotchFlow.

### Interface e experiência

- Navegação comum entre tarefas, medicamentos, água e resumo semanal.
- Componentes compartilhados para botões, campos, superfícies e barras de progresso.
- Melhor hierarquia visual, espaçamento e estados de interação.
- Formulários com conteúdo rolável e ações fixas; criação de tarefa em uma folha própria.
- Calendário de eventos recolhível para dar mais espaço à lista de tarefas.
- Ajustes organizados por rotina e aplicativo, com busca e rótulos acessíveis.
- Última aba do painel preservada durante a sessão do aplicativo.
- Liquid Glass opcional e transparência ajustável, com material translúcido nas versões anteriores ao macOS 26 e respeito a Reduzir Transparência.
- Calendário, cartões de tarefas e resumo do dia com contraste e destaque aprimorados; animações de arraste respeitam Reduzir Movimento.

### Rotina e acompanhamento

- Água com seleção de copo ou garrafa, capacidades independentes, unidades ml/L, meta diária, histórico, gráfico semanal e opção de desfazer.
- Validação de capacidade, incluindo números com vírgula ou ponto.
- Painel de uso da máquina com CPU e memória, atualizado enquanto visível.
- Cadastro de medicamentos, lembretes e registro de tomadas.
- Projetos, etiquetas, recorrência e filtros de tarefas.
- Captura rápida global e alertas de horário de início.
- Resumo semanal com metas, comparações e foco por tarefa.

### Persistência e documentação

- Backup da versão anterior dos dados, recuperação e avisos de falha de persistência.
- Testes independentes de persistência e de regras de produtividade e hidratação.
- Documentação reescrita em português, com guias de uso, desenvolvimento e contribuição.
- README com cinco imagens atualizadas em português, geradas com dados de demonstração e enquadramento revisado.
- Repositório privado do NotchFlow criado no GitHub.

## 1.0.0 - 2026-09-22

Marco histórico registrado na documentação do projeto. Não representa confirmação de disponibilidade pública do NotchFlow.

- Janela de ajustes com busca, escolha de tela, alertas e atalhos configuráveis.
- Interface em português do Brasil.
- Indicadores de foco diário, blocos concluídos e sequência de dias.
- Timer baseado no horário de término, com tratamento de suspensão e pausas.
- Ajustes na persistência, reabertura de janelas e apresentação do notch.
- Estrutura de compilação para distribuição direta e App Store.

## 0.0.2 - 2026-08-29

- Reordenação de tarefas por arraste.
- Ajustes no seletor de duração de foco e na rolagem das listas.
- Opção de abrir ao iniciar sessão.
- Melhorias na ordenação das tarefas e nos scripts de automação.

## 0.0.1 - 2026-08-29

- Estrutura inicial com SwiftUI e AppKit.
- Modelos de tarefas, sessões e configurações com persistência JSON.
- Painel do notch, timer, janela de tarefas e grade de atividade.
- Atalho global de foco e notificações locais.
- Integração de calendário somente para leitura.
- Projeto Xcode para macOS 14, scripts de execução e licença MIT.
