# Política de privacidade do NotchFlow

Atualizada em **10 de outubro de 2026**. Responsável pelo aplicativo: **Hygor Ferreira**.

## Dados locais

O NotchFlow mantém no Mac suas tarefas, notas, projetos, etiquetas, sessões de foco, configurações, medicamentos cadastrados, registros de tomada e registros de água. O aplicativo não exige conta e não inclui publicidade, analytics ou rastreamento.

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

## Rede e atualizações

O acompanhamento de IA é opcional. Ao conectar Codex ou Claude Code, o NotchFlow lê a sessão existente na pasta selecionada ou no item de credenciais do Claude Code no app Chaves, conforme autorização do macOS. O token é usado somente em requisições HTTPS ao serviço correspondente (ChatGPT ou Anthropic) para consultar limites de consumo. Não é copiado para os arquivos de dados nem para as preferências do NotchFlow, e o aplicativo não altera nem renova essas credenciais.

As consultas ocorrem a cada dois minutos enquanto o app está aberto e ao retornar ao aplicativo. Os serviços recebem o token de autenticação, o identificador da conta quando necessário e metadados normais de rede, como o endereço IP. Tarefas, prompts e respostas não são enviados. Percentuais, horários de renovação, última leitura e permissões de pasta são guardados nas preferências locais para continuidade entre aberturas. Desativar o interruptor do serviço remove esses dados e interrompe novas consultas; o login na ferramenta de origem permanece ativo. Quando já autorizada pelo macOS, a leitura da sessão existente usa sua localização padrão automaticamente.

Na distribuição direta, o aplicativo consulta a API de releases do GitHub para o repositório `HygorFerreira/NotchFlow` ao iniciar e quando você solicita uma verificação nos ajustes. Os dados da rotina não são enviados pela aplicação.

Essas requisições estão sujeitas ao processamento de metadados de rede pelo GitHub, como o endereço IP. Ao escolher baixar uma atualização, o app abre a página da release no navegador. A compilação com a condição `APPSTORE` desativa esse verificador; atualizações pela loja são administradas pela Apple.

## Backup e exclusão

Para fazer backup, encerre o app e copie a pasta de dados, incluindo o arquivo principal e suas cópias. Para localizar o arquivo usado pela instalação, utilize a ação de mostrar os dados no Finder, disponível nos ajustes.

Arrastar o aplicativo para a Lixeira não garante que os registros e as preferências sejam apagados. O script `scripts/wipe.sh` remove os caminhos locais descritos no [guia de uso](docs/USO.md); diretórios de contêiner e backups adicionais podem precisar de remoção separada.

## Contato

O canal público de suporte do NotchFlow ainda não foi configurado. Antes de uma publicação pública, esta política deve receber uma URL estável e um contato de suporte.
