# Política de privacidade do NotchFlow

Atualizada em **28 de outubro de 2026**. Responsável pelo aplicativo: **Hygor Ferreira**.

## Dados locais

O NotchFlow mantém no Mac suas tarefas, notas rápidas, notas de tarefas, projetos, etiquetas, sessões de foco, configurações, medicamentos cadastrados, registros de tomada e registros de água. O aplicativo não exige conta e não inclui publicidade, analytics ou rastreamento.

Esses registros são persistidos em `Application Support/NotchFlow/data.json`, no diretório de suporte disponibilizado pelo macOS. Em uma execução com sandbox, o caminho fica dentro do contêiner do aplicativo. Preferências auxiliares também podem ser armazenadas pelo macOS.

O mecanismo de persistência mantém uma cópia anterior em `data.json.backup`. Quando detecta um arquivo danificado, tenta recuperar os dados e preservar uma cópia do arquivo afetado. Essas cópias permanecem no Mac e devem ser consideradas ao excluir seus registros.

## Calendário

O acesso é opcional e depende de autorização do macOS. O aplicativo consulta eventos para exibi-los junto às tarefas. Não cria, edita ou exclui eventos e não envia o conteúdo do calendário a um servidor.

Você pode revogar o acesso em **Ajustes do Sistema > Privacidade e Segurança > Calendários**.

## Notificações

Alertas de tarefas, lembretes de medicamentos e avisos de término do foco são notificações locais, sujeitos às permissões e às configurações do macOS. Seu conteúdo pode aparecer na Central de Notificações ou na tela bloqueada, conforme as preferências do sistema.

Gerencie a permissão em **Ajustes do Sistema > Notificações > NotchFlow**.

## Uso da máquina

O painel consulta métricas do sistema para mostrar utilização de CPU e memória. A amostragem ocorre enquanto a área correspondente está visível. O aplicativo não envia essas métricas a um servidor.

## Mixer de áudio

O mixer é opcional e começa desativado a cada abertura. Ao ajustar uma fonte, usa Core Audio Taps para receber seu áudio, aplicar o volume e reproduzi-lo na saída selecionada pelo sistema, mediante autorização do macOS. Não acessa o microfone, não salva áudio e não o envia à rede. Nomes, identificadores dos processos e volumes ficam apenas em memória. Fechar o painel mantém os controles; desligar o mixer ou encerrar o aplicativo libera as fontes.

## Música

A integração é opcional e começa desativada. Ao ativá-la, o NotchFlow consulta apenas o player escolhido (Spotify ou Apple Music) por Apple Events, mediante autorização de Automação do macOS. Lê título, artista, identificador, capa, duração, estado e posição da faixa e envia comandos de reprodução solicitados por você. Não lê suas credenciais nem solicita login adicional.

As consultas ocorrem a cada dois segundos enquanto a integração está ativa e o player está aberto. O estado de ativação e a escolha de player ficam nas preferências locais; não há histórico de músicas no arquivo de dados. Metadados de reprodução permanecem em memória e são descartados ao desativar a integração. O Apple Music fornece a capa localmente quando disponível. Para Spotify, a interface busca a capa via HTTPS na URL informada pelo aplicativo; o servidor de imagens recebe os metadados normais da requisição, como endereço IP, e o sistema pode manter cache de rede.

Desative **Música no notch** para interromper as consultas. Você também pode revogar o acesso em **Ajustes do Sistema → Privacidade e Segurança → Automação**.

## Clipboard e arquivos temporários

O histórico de clipboard começa desativado e só consulta novas alterações após ser ativado. Até 30 cópias de texto ou PNG ficam em memória, sem histórico em disco. Desativar o recurso ou encerrar o app limpa a lista; a cópia atual do clipboard do macOS permanece no sistema. Itens sinalizados pelos aplicativos com os tipos confidencial, transitório ou automático são ignorados. Nem todo aplicativo sinaliza conteúdo sensível, portanto desative o histórico antes de copiar senhas ou outros segredos.

Arquivos arrastados para o notch ou escolhidos pelo seletor são copiados para `Application Support/NotchFlow/FileShelf`, dentro do contêiner quando há sandbox. Os originais não são alterados. As cópias persistem entre aberturas e podem ser arrastadas para outro app por sua ação. Removê-las as envia à Lixeira, quando permitido pelo macOS. A pasta de cópias também deve ser considerada ao fazer backup ou excluir dados.

## Letras sincronizadas

Letras são opcionais. Ao ativá-las, o app envia título, artista, álbum quando disponível e duração da faixa a `https://lrclib.net/api/get`. O serviço também recebe os metadados normais da requisição, como endereço IP. As respostas são mantidas em memória por uma sessão de rede efêmera e não são incluídas no arquivo de dados. A preferência de ativação é salva localmente. Desativar a opção cancela a consulta pendente.


## Rede e atualizações

O acompanhamento de IA é opcional. Ao conectar Codex ou Claude Code, o NotchFlow lê a sessão existente na pasta selecionada ou no item de credenciais do Claude Code no app Chaves, conforme autorização do macOS. O token é usado somente em requisições HTTPS ao serviço correspondente (ChatGPT ou Anthropic) para consultar limites de consumo. Não é copiado para os arquivos de dados nem para as preferências do NotchFlow, e o aplicativo não altera nem renova essas credenciais.

As consultas ocorrem a cada dois minutos enquanto o app está aberto e ao retornar ao aplicativo. Os serviços recebem o token de autenticação, o identificador da conta quando necessário e metadados normais de rede, como o endereço IP. Tarefas, prompts e respostas não são enviados. Percentuais, horários de renovação, última leitura e permissões de pasta são guardados nas preferências locais para continuidade entre aberturas. Desativar o interruptor do serviço remove esses dados e interrompe novas consultas; o login na ferramenta de origem permanece ativo. Quando já autorizada pelo macOS, a leitura da sessão existente usa sua localização padrão automaticamente.

Na distribuição direta, o Sparkle consulta por HTTPS um catálogo de atualizações assinado hospedado nas releases do repositório `HygorFerreira/NotchFlow`, no GitHub. As verificações automáticas ocorrem a cada seis horas e também podem ser iniciadas manualmente. Por padrão, o app baixa pacotes de atualização assinados e os instala ao encerrar. Verificações e instalação automática podem ser desativadas em Ajustes → Sobre. Os dados da rotina não são enviados.

O GitHub e sua infraestrutura de downloads recebem metadados normais da requisição, como endereço IP, versão do aplicativo e do sistema conforme o protocolo de atualização. A opção de perfil estatístico do sistema do Sparkle fica desativada. Catálogo, notas de versão e pacotes são autenticados com Ed25519 antes de serem utilizados. Downloads temporários e preferências do atualizador ficam no Mac. A compilação **NotchFlowAppStore** não inclui Sparkle; atualizações pela loja são administradas pela Apple.

## Backup e exclusão

Para fazer backup, encerre o app e copie a pasta de dados, incluindo o arquivo principal e suas cópias. Para localizar o arquivo usado pela instalação, utilize a ação de mostrar os dados no Finder, disponível nos ajustes.

Arrastar o aplicativo para a Lixeira não garante que os registros e as preferências sejam apagados. O script `scripts/wipe.sh` remove os caminhos locais descritos no [guia de uso](docs/USO.md); diretórios de contêiner e backups adicionais podem precisar de remoção separada.

## Contato

O canal público de suporte do NotchFlow ainda não foi configurado. Antes de uma publicação pública, esta política deve receber uma URL estável e um contato de suporte.
