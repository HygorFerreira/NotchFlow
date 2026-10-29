# Ferramentas e expansão do player

Prévias de SwiftUI com tarefas, notas, arquivos e letras fictícias, em português e inglês. Nenhuma conta ou biblioteca musical foi consultada para gerar estas imagens.

| Estado | Português | Inglês |
| --- | --- | --- |
| Paleta de comandos | [Abrir](pt-BR/command-palette.png) | [Abrir](en/command-palette.png) |
| Notas no notch | [Abrir](pt-BR/notch-tools-quick-notes.png) | [Abrir](en/notch-tools-quick-notes.png) |
| Notas na janela | [Abrir](pt-BR/tools-quick-notes.png) | [Abrir](en/tools-quick-notes.png) |
| Clipboard no notch | [Abrir](pt-BR/notch-tools-clipboard.png) | [Abrir](en/notch-tools-clipboard.png) |
| Arquivos no notch | [Abrir](pt-BR/notch-tools-file-shelf.png) | [Abrir](en/notch-tools-file-shelf.png) |
| Próximo compromisso | [Abrir](pt-BR/upcoming-event.png) | [Abrir](en/upcoming-event.png) |
| Player e letras | [Abrir](pt-BR/music-player.png) | [Abrir](en/music-player.png) |

Para reproduzir, compile Debug e execute com `-snapshot 1 -snapshotToolsOnly 1` ou `-snapshot 1 -snapshotMusicOnly 1`, acrescentando `-AppleLanguages '(pt-BR)'` ou `'(en)'`. A janela interativa isolada de ferramentas está disponível com `-preview 1 -previewTools 1`.

Validação: compilação Debug, Release e App Store; testes de persistência, produtividade, timer, música e ferramentas. O teste de clipboard usa uma área privada do pasteboard do macOS. As importações usam arquivos temporários e verificam que os originais permanecem intactos.

A interação de notas, criação de tarefa e busca no clipboard foi conferida em janela de demonstração. O fluxo com players reais, letras do serviço ainda requer validação na instalação do usuário.
