# Guia de uso do NotchFlow

## Abrir e navegar

O NotchFlow funciona pela barra de menus e pelo painel no topo da tela. Passe o mouse sobre o notch ou a pílula para expandi-lo. Use as abas **Atividade**, **Saúde**, **Máquina** e **Água** para consultar cada área.

O menu de ampulheta abre tarefas, captura rápida, medicamentos, água, resumo semanal e ajustes. As janelas principais também oferecem navegação entre essas áreas.

## Planejar tarefas

Na janela **Tarefas**, selecione uma data no calendário ou a lista de tarefas sem data. Crie uma atividade com `⌘N` e informe título, notas e duração de foco. Projeto, etiquetas, recorrência e horário de início são opcionais.

Clique no título para editar uma tarefa. Use o controle de conclusão para marcá-la e o botão de início para focar. As tarefas podem ser reordenadas por arraste. Os filtros de projeto e etiqueta também afetam o painel do notch e a seleção pelo atalho de foco.

Ao concluir uma tarefa recorrente, o app cria a próxima ocorrência. Datas já passadas são puladas. Para mudar as próximas repetições, edite a ocorrência seguinte. Desfazer e concluir novamente não deve gerar uma ocorrência duplicada.

A captura rápida (`⌘⇧N`) permite registrar uma tarefa enquanto outro aplicativo está aberto.

## Usar o foco

Inicie pelo botão da tarefa ou por `⌘⇧Espaço`. O atalho procura a primeira tarefa pendente de hoje que corresponda aos filtros. Quando não há uma tarefa elegível, inicia uma sessão sem tarefa com a duração dos ajustes. Acione novamente para parar.

O timer usa um horário de término para acompanhar a passagem do tempo mesmo quando o Mac é suspenso. Pausas não entram no tempo de foco. A duração de uma tarefa em andamento pode ser ajustada.

Em **Ajustes**, personalize a duração padrão, o estilo da linha, o modo mínimo, a tela e os alertas.

## Registrar água

1. Abra **Água** e escolha **Copo** ou **Garrafa**.
2. Expanda a personalização e configure a capacidade de cada recipiente e a meta diária.
3. Escolha ml ou L. Valores como `750` ml e `0,75` L representam a mesma capacidade.
4. Salve a configuração e registre cada recipiente consumido.

As capacidades válidas vão de **50 a 3.000 ml** e devem corresponder a mililitros inteiros. Copo e garrafa mantêm capacidades independentes. Alterar uma capacidade não modifica o volume de registros anteriores.

Consulte o histórico de hoje, desfaça registros incorretos e acompanhe o gráfico dos últimos sete dias. A meta é configurada pelo usuário.

## Medicamentos

Abra **Medicamentos**, adicione nome, dosagem e horários de lembrete. Ative ou desative os lembretes conforme necessário e use **Tomei** para registrar uma tomada. Permita notificações no macOS para receber os avisos.

## Uso da máquina

A aba **Máquina** mostra CPU e memória do sistema. A leitura é atualizada a cada dois segundos enquanto visível. A CPU pode aparecer inicialmente como indisponível até haver amostras suficientes. A memória apresentada inclui memória ativa, ligada ao sistema e comprimida.

## Calendário e resumo

Autorize o acesso ao calendário para visualizar eventos do dia na janela de tarefas. A seção de eventos pode ser expandida ou recolhida. O aplicativo apenas consulta os eventos.

O **Resumo semanal** reúne foco por dia e por tarefa, blocos e tarefas concluídos, comparação com a semana anterior e uma meta ajustável. Tarefas antigas sem data de conclusão conhecida não entram na contagem de conclusões. O tempo registrado permanece mesmo após a exclusão de uma tarefa.

## Backup e remoção

Nos ajustes, localize o arquivo de dados usando a ação de mostrar no Finder. Encerre o app antes de copiar a pasta `NotchFlow`, preservando `data.json`, `data.json.backup` e eventuais cópias de recuperação. Para restaurar, encerre o app e substitua os arquivos na mesma localização usada pela instalação.

Para remover os caminhos atendidos pelo script de limpeza:

```bash
bash scripts/wipe.sh
```

Esse comando pede confirmação e remove cópias instaladas em `/Applications` e `~/Applications`, produtos de compilação com o prefixo NotchFlow em DerivedData, dados em `~/Library/Application Support/NotchFlow`, preferências, caches e estado salvo. Ele não remove o código-fonte. A opção `-y` pula a confirmação.

O script não contempla a remoção explícita do contêiner de sandbox. Se a instalação armazenou dados em `~/Library/Containers/dev.oprimo.NotchFlow`, verifique esse diretório separadamente. Backups feitos em outros locais também permanecem.

## Resolver problemas

| Situação | Verificação |
| --- | --- |
| Não encontro a janela | Procure o ícone de ampulheta na barra de menus e escolha a área desejada. |
| Painel em outra tela | Confira a seleção de tela nos ajustes. |
| Atalho não funciona | Veja o status em Ajustes > Atalhos e possíveis conflitos com outros aplicativos. |
| Notificações não aparecem | Confira a permissão no macOS, os alertas no app e o modo Foco do sistema. |
| Calendário vazio | Confira a autorização e a data selecionada. |
| Não consigo salvar uma capacidade | Verifique o intervalo permitido, a unidade e o formato numérico. |
| Aviso sobre dados | Leia o aviso de persistência e preserve os arquivos antes de tentar uma recuperação. |

Consulte também a [política de privacidade](../PRIVACY.md).
