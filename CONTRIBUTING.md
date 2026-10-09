# Contribuir com o NotchFlow

O NotchFlow é desenvolvido por **Hygor Ferreira**. Antes de alterar o projeto, leia o [README](README.md) e o [guia de desenvolvimento](docs/DESENVOLVIMENTO.md).

## Preparar uma alteração

1. Execute o app localmente e reproduza o comportamento que deseja melhorar.
2. Mantenha cada alteração focada em um problema ou recurso.
3. Reutilize os componentes de `NotchFlow/Design/` para preservar a consistência visual.
4. Adicione textos à tabela `Localizable.xcstrings`, com português do Brasil e inglês.
5. Atualize a documentação quando mudar o uso, a persistência ou a distribuição.

## Validar

Compile o esquema NotchFlow em Debug e execute os testes relevantes:

```bash
bash scripts/test-store.sh
bash scripts/test-productivity.sh
```

Para interfaces, confira o fluxo afetado, tamanhos mínimos de janela, textos em ambos os idiomas, navegação por teclado e estados vazio, desativado e de erro. O modo de snapshots ajuda a revisar o layout, mas não substitui a interação com o app.

Para mudanças nos modelos, teste migração, persistência e recuperação quando forem afetadas. Use arquivos temporários; não inclua dados pessoais nos testes nem nas imagens.

## Registrar e apresentar

Se estiver trabalhando em um repositório Git, prefira commits como `feat(water): ...`, `fix(store): ...` ou `docs: ...`. Descreva o problema, o comportamento resultante e a validação realizada.

Registre mudanças ainda não publicadas na seção **Em desenvolvimento** do [CHANGELOG](CHANGELOG.md). Antes de uma versão, organize essa seção sob a versão e a data correspondentes.

Não inclua certificados, credenciais, perfis de assinatura ou `.env.local`. O arquivo `.xcodeproj` sincroniza a pasta `NotchFlow/`; novos arquivos de código normalmente são reconhecidos sem cadastro manual no projeto.
