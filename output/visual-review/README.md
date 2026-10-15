# Revisão visual — NotchFlow

Capturas reais de SwiftUI com dados fictícios, nos temas claro e escuro. Os JPEGs de português ficam em `pt-BR/` e os de inglês em `en/`.

A [implementação revisada do notch](../notch-reference-implementation/notch-activity.jpeg) segue a composição da proposta minimalista. As capturas do notch em português já refletem essa revisão; as de inglês nesta galeria registram a etapa anterior.

| Tela | Escuro | Claro |
| --- | --- | --- |
| Tarefas e calendário | [JPEG](pt-BR/tasks-dark.jpeg) | [JPEG](pt-BR/tasks-light.jpeg) |
| Água | [JPEG](pt-BR/water-dark.jpeg) | [JPEG](pt-BR/water-light.jpeg) |
| Medicamentos | [JPEG](pt-BR/medications-dark.jpeg) | [JPEG](pt-BR/medications-light.jpeg) |
| Resumo semanal | [JPEG](pt-BR/summary-dark.jpeg) | [JPEG](pt-BR/summary-light.jpeg) |
| Consumo de IA | [JPEG](pt-BR/ai-dark.jpeg) | [JPEG](pt-BR/ai-light.jpeg) |
| Ajustes do notch | [JPEG](pt-BR/settings-notch-dark.jpeg) | [JPEG](pt-BR/settings-notch-light.jpeg) |
| Detalhe de tarefa | [JPEG](pt-BR/task-detail-dark.jpeg) | [JPEG](pt-BR/task-detail-light.jpeg) |
| Captura rápida | [JPEG](pt-BR/quick-capture-dark.jpeg) | [JPEG](pt-BR/quick-capture-light.jpeg) |

Notch: [Atividade](pt-BR/notch-activity.jpeg), [Saúde](pt-BR/notch-health.jpeg), [Máquina](pt-BR/notch-machine.jpeg), [Água](pt-BR/notch-water.jpeg), [IA](pt-BR/notch-ai.jpeg) e [timer](pt-BR/notch-focus.jpeg).

As pastas também incluem todas as páginas de ajustes. Para reproduzir, compile Debug e execute o app com `-snapshot 1 -snapshotVisualReview 1 -AppleLanguages '(pt-BR)'` (ou `'(en)'`). O app imprime a pasta temporária de saída e encerra; copie os arquivos antes da próxima execução.
