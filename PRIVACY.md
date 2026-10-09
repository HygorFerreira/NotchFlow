# Política de privacidade do NotchFlow

Atualizada em **8 de outubro de 2026**. Responsável pelo aplicativo: **Hygor Ferreira**.

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

Na configuração atual, a consulta de atualizações está desativada porque não há repositório de releases definido. Os dados da rotina não são enviados pela aplicação.

Caso um repositório seja configurado futuramente para distribuição direta, o verificador poderá consultar a API do GitHub para identificar versões novas. Essas requisições estarão sujeitas ao processamento de metadados de rede pelo serviço, como o endereço IP. A compilação com a condição `APPSTORE` desativa esse verificador; atualizações pela loja são administradas pela Apple.

## Backup e exclusão

Para fazer backup, encerre o app e copie a pasta de dados, incluindo o arquivo principal e suas cópias. Para localizar o arquivo usado pela instalação, utilize a ação de mostrar os dados no Finder, disponível nos ajustes.

Arrastar o aplicativo para a Lixeira não garante que os registros e as preferências sejam apagados. O script `scripts/wipe.sh` remove os caminhos locais descritos no [guia de uso](docs/USO.md); diretórios de contêiner e backups adicionais podem precisar de remoção separada.

## Contato

O canal público de suporte do NotchFlow ainda não foi configurado. Antes de uma publicação pública, esta política deve receber uma URL estável e um contato de suporte.
