# Música no NotchFlow — revisão visual

Prévias reais de SwiftUI, com faixa e tarefas fictícias. A capa usa o estado de fallback; não foram consultadas contas ou bibliotecas musicais para gerar estas imagens.

| Estado | Português | Inglês |
| --- | --- | --- |
| Player completo | [Abrir](pt-BR/music-player.png) | [Abrir](en/music-player.png) |
| Compacto | [Abrir](pt-BR/music-compact.png) | [Abrir](en/music-compact.png) |
| Prévia ao passar o mouse | [Abrir](pt-BR/music-peek.png) | [Abrir](en/music-peek.png) |
| Música e timer | [Abrir](pt-BR/music-focus.png) | [Abrir](en/music-focus.png) |
| Música, timer e lembrete | [Abrir](pt-BR/music-focus-reminder.png) | [Abrir](en/music-focus-reminder.png) |
| Sem reprodução | [Abrir](pt-BR/music-empty.png) | [Abrir](en/music-empty.png) |

Reprodução: compile Debug e execute com `-snapshot 1 -snapshotMusicOnly 1 -AppleLanguages '(pt-BR)'` ou `'(en)'`. Esse modo não ativa o player real nem grava preferências de música.

A validação automatizada simula metadados dos players. Autorização de Automação, capa e comandos em players reais precisam de verificação em um build assinado com acesso concedido pelo macOS.
