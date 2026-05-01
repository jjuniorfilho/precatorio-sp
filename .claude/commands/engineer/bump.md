Vamos preparar isso para um release aumentando o número da versão.

Siga estas regras para versionamento semântico x.y.z:

- x (Versão major): Incremente quando você fizer mudanças incompatíveis na API ou feature. Exemplos incluem:
Mudanças que quebram APIs públicas (ex.: remover ou renomear métodos).
Reescritas majors ou refatoração que alteram comportamento.
Mudanças que requerem que usuários atualizem seu código ou dependências para manter compatibilidade.
- y (Versão minor): Incremente quando você adicionar novas features ou melhorias de forma retrocompatível. Exemplos incluem:
Adicionando novos métodos, ponto de acessos, ou features.
Depreciar features (mas não removê-las ainda).
Melhorias que não quebram features existentes.
- z (Versão patch): Incremente quando você fizer correções de bugs retrocompatíveis ou pequenas atualizações. Exemplos incluem:
Corrigir bugs sem alterar feature pretendida.
Pequenas melhorias de performance.
Atualizações de documentação ou mudanças de metadata.

## Passo 0: Descobrir a versão atual (OBRIGATÓRIO)

NUNCA confie na versão que está no arquivo local. A fonte da verdade é o git:

1. Execute `git fetch --tags` para garantir que as tags remotas estão atualizadas.
2. Execute `git tag --sort=-v:refname | head -20` para listar as últimas tags.
3. Se o projeto for monorepo, filtre por prefixo (ex.: `git tag -l 'desktop-v*' --sort=-v:refname | head -5`).
4. A versão a ser incrementada é a da última tag relevante, NÃO a do arquivo local.
5. Se a versão do arquivo local estiver diferente da última tag, avise o usuário e use a da tag.

## Detecção automática do tipo de projeto

Detecte automaticamente o tipo de projeto e aplique o bump adequado:

### 1. Python (pyproject.toml)
- Altere a versão no `pyproject.toml`.
- Execute `uv sync --all-extras` para regenerar o lock file.

### 2. Node.js single app (package.json na raiz)
- Altere a versão no `package.json` da raiz.
- Se existir `package-lock.json`, execute `npm install --package-lock-only` para atualizar.

### 3. Monorepo Node.js (múltiplos package.json em apps/)
- Liste todos os `apps/*/package.json` que possuem campo `"version"`.
- Pergunte ao usuário QUAL app ele quer versionar (ou se quer todos).
- Altere a versão apenas no(s) `package.json` selecionado(s).

## Após o bump

1. Analise os commits desde a última tag para sugerir o tipo de bump (major/minor/patch).
2. Mostre a versão atual (da tag) e a versão sugerida. Pergunte ao usuário para confirmar.
3. Atualize a versão no(s) arquivo(s) do projeto para ficar em sincronia com a nova tag.
4. Após alterar a versão, pergunte ao usuário se deseja:
   - Criar um commit com a mensagem `chore: bump <app> version to x.y.z`
   - Criar uma git tag (ex.: `v1.0.1` ou `<app>-v1.0.1` para monorepos)
   - Fazer push do commit + tag para o remote (isso pode disparar workflows de release)

## Regras

- NUNCA faça push sem confirmação explícita do usuário.
- Em monorepos, prefixe a tag com o nome do app (ex.: `desktop-v1.0.1`) se houver mais de um app versionável. Se houver apenas um app versionável, use `v1.0.1` sem prefixo.
- Se existirem workflows de CI/CD que reagem a tags (ex.: `on: push: tags: ['v*']`), informe o usuário que o push da tag vai disparar o workflow.