# Histórico de alterações do NotchFlow

Este arquivo registra os principais marcos do projeto. A seção **Em desenvolvimento** descreve mudanças presentes no código que ainda não possuem uma nova versão publicada. A versão configurada no projeto é **1.0.0**, build **1**.

## Em desenvolvimento - atualizado em 2026-10-09

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
